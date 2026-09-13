#!/bin/bash
set -euo pipefail

# ============================================================
# HOST: docker
# SCRIPT: Track Setup
#
# 1. Provisions the Okta user and serves the credentials page on :8080.
#    Does NOT mint the session token: S1 C1 does that so the magic
#    link is seconds old when the participant clicks it.
#
# 2. Syncs the docsify lab guide from GitHub and serves it on :8081.
#    Every .md file comes from googlecloudsecurity/agentic-soc-workshop,
#    so editing a page is a push plus a new session, with no track or
#    image rebuild. Each challenge tab points at its own hash route,
#    e.g. http://localhost:8081/#/s1c1-triage-agent
#
# Ports:
#   8080 - Credentials page
#   8081 - Lab guide (docsify)
#
# Instruqt secrets:
#   - okta_provision_token  (optional, falls back to inline default)
#   - github_token          (required once the docs repo is private)
#
# Instruqt agent variables set:
#   - USERNAME
#   - PASSWORD
#
# NO XTRACE. Do not add `set -x` to this script or re-enable it in any
# block below. The credentials section generates the participant password
# in-process; xtrace prints it to the Instruqt setup log, which is not a
# secret store. It would also leak the docs clone URL once that repo goes
# private and carries a token.
# ============================================================

until [ -f /opt/instruqt/bootstrap/host-bootstrap-completed ]; do sleep 1; done

WORKDIR=/root/.workshop
DOCS_ROOT=/root/instructions
DOCS_PORT=8081

DOCS_REPO="googlecloudsecurity/agentic-soc-workshop"
DOCS_REF="main"          # branch or tag only, see the clone note below
DOCS_PATH="docs"         # directory inside the repo, flat .md files
DOCSIFY_CDN="https://cdn.jsdelivr.net/npm/docsify@4.13.1"
COPYCODE_CDN="https://cdn.jsdelivr.net/npm/docsify-copy-code@3/dist/docsify-copy-code.min.js"

mkdir -p "$WORKDIR" /var/www/html "${DOCS_ROOT}/vendor"

echo '[SETUP] Installing dependencies...'
apt-get update -qq 2>/dev/null || true
for pkg in curl python3 git; do
  command -v "$pkg" &>/dev/null || apt-get install -y -qq "$pkg" 2>/dev/null || true
done

# ============================================================
# SECTION 1: Credentials
# ============================================================

# ---- Password generation ----
# head reads a fixed byte count and exits cleanly, so tr never takes
# a SIGPIPE. Piping /dev/urandom straight into tr under `set -o pipefail`
# is a race that can abort the whole script.
_rand_chars() { head -c 4096 /dev/urandom | LC_ALL=C tr -dc "$1"; }

generate_password() {
  local lower upper digit special rest
  lower=$(_rand_chars 'a-z');            lower=${lower:0:1}
  upper=$(_rand_chars 'A-Z');            upper=${upper:0:1}
  digit=$(_rand_chars '0-9');            digit=${digit:0:1}
  special=$(_rand_chars '!?%=');         special=${special:0:1}
  rest=$(_rand_chars 'A-Za-z0-9!?%=');   rest=${rest:0:12}
  printf '%s' "${lower}${upper}${digit}${special}${rest}" | fold -w1 | shuf | tr -d '\n'
}

USERNAME="${_SANDBOX_ID}@chronicle.team"
PASSWORD=$(generate_password)

echo "[SETUP] Username: ${USERNAME}"

# ---- Write shared library ----
# Constants and credentials (expanded), then functions (literal).
cat > "${WORKDIR}/env.sh" << ENVEOF
OKTA_PROVISION_URL="https://chronicle.workflows.okta.com/api/flo/d17f540697d1c51b3d2ee59be2b64668/invoke"
OKTA_PROVISION_TOKEN="\${okta_provision_token:-feda362ae7d79308e29d9a7ca88d6c0b3df11b468095113a85421e122cfe2f90}"
OKTA_BASE_URL="https://chronicle.okta.com"
SECOPS_URL="https://agentic.backstory.chronicle.security"
EMAIL_DOMAIN="chronicle.team"
WORKDIR="${WORKDIR}"
USERNAME="${USERNAME}"
PASSWORD="${PASSWORD}"
DOCS_ROOT="${DOCS_ROOT}"
DOCS_PORT="${DOCS_PORT}"
ENVEOF

cat >> "${WORKDIR}/env.sh" << 'ENVEOF'

# Provision the Okta user. Returns non-zero on failure without exiting
# the caller, so a flaky tenant cannot block the ADK challenges.
provision_user() {
  local response code
  response=$(curl -s -w '\n%{http_code}' --max-time 60 --retry 2 --retry-delay 5 \
    -X POST "${OKTA_PROVISION_URL}?clientToken=${OKTA_PROVISION_TOKEN}" \
    -H 'Content-Type: application/json' \
    --data "{
      \"First Name\": \"SecOps\",
      \"Last Name\": \"${_SANDBOX_ID}\",
      \"Email\": \"${USERNAME}\",
      \"Password\": \"${PASSWORD}\"
    }") || return 1
  code=$(printf '%s' "$response" | tail -1)
  [[ "$code" -ge 200 && "$code" -lt 300 ]] || { echo "[OKTA] provision HTTP ${code}" >&2; return 1; }
  return 0
}

# Authenticate and echo a fresh magic URL on stdout.
# The session token is single use and expires in about five minutes,
# so call this immediately before the participant needs it.
mint_magic_url() {
  local response token
  response=$(curl -s --max-time 30 --retry 2 --retry-delay 3 \
    -X POST "${OKTA_BASE_URL}/api/v1/authn" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    --data "{
      \"username\": \"${USERNAME}\",
      \"password\": \"${PASSWORD}\",
      \"options\": {\"multiOptionalFactorEnroll\": false, \"warnBeforePasswordExpired\": false}
    }") || return 1
  token=$(printf '%s' "$response" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("sessionToken",""))' 2>/dev/null) || return 1
  [[ -n "$token" ]] || return 1
  printf 'https://login.%s/login/sessionCookieRedirect?token=%s&redirectUrl=%s\n' \
    "$EMAIL_DOMAIN" "$token" "$SECOPS_URL"
}

# Render the credentials page. Arg 1 is the magic URL, empty for none.
write_creds_page() {
  local magic_url="${1:-}" button
  if [[ -n "$magic_url" ]]; then
    button="<a href=\"${magic_url}\" target=\"_blank\" class=\"btn\">🚀 Launch Google SecOps</a>
    <div class=\"hint\">One-time link. If it has expired, sign in at
    <a href=\"${SECOPS_URL}\">${SECOPS_URL}</a> with the credentials above.</div>"
  else
    button="<div class=\"hint\">Sign in at <a href=\"${SECOPS_URL}\">${SECOPS_URL}</a>
    with the credentials above.</div>"
  fi
  cat > /var/www/html/index.html << CREDHTML
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Operation Shiny Hunter - Your Credentials</title>
<style>
  body { font-family: 'Google Sans', sans-serif; background: #0f1117; color: #e8eaed; margin: 0; padding: 40px; }
  .card { background: #1e2029; border-radius: 12px; padding: 32px; max-width: 600px; margin: 0 auto; }
  h1 { color: #4285f4; font-size: 1.4em; margin-top: 0; }
  .cred { background: #2a2d3a; border-radius: 8px; padding: 16px; margin: 12px 0; }
  .label { color: #9aa0a6; font-size: 0.8em; text-transform: uppercase; letter-spacing: 0.1em; }
  .value { font-family: monospace; font-size: 1.1em; color: #e8eaed; margin-top: 4px; word-break: break-all; }
  .btn { display: inline-block; background: #4285f4; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; font-weight: 500; margin-top: 16px; }
  .btn:hover { background: #3367d6; }
  .hint { color: #9aa0a6; font-size: 0.85em; margin-top: 16px; line-height: 1.5; }
  .hint a { color: #8ab4f8; }
  .meta { color: #9aa0a6; font-size: 0.8em; margin-top: 24px; }
</style>
</head>
<body>
<div class="card">
  <h1>🔐 Your SecOps Credentials</h1>
  <div class="cred">
    <div class="label">Username</div>
    <div class="value">${USERNAME}</div>
  </div>
  <div class="cred">
    <div class="label">Password</div>
    <div class="value">${PASSWORD}</div>
  </div>
  <div class="cred">
    <div class="label">SecOps URL</div>
    <div class="value">${SECOPS_URL}</div>
  </div>
  ${button}
  <div class="meta">Link minted: $(date -u '+%Y-%m-%d %H:%M UTC') · Sandbox: ${_SANDBOX_ID}</div>
</div>
</body>
</html>
CREDHTML
}

# Probe a local port and test the response body for a marker string.
# Deliberately not `curl ... | grep -q`: grep exits on first match, curl
# takes SIGPIPE, and under `set -o pipefail` the pipeline reports failure
# even though the marker was found.
_serving_marker() {
  local port="$1" marker="$2" body
  body=$(curl -sf --max-time 3 "http://localhost:${port}/" 2>/dev/null) || return 1
  [[ "$body" == *"$marker"* ]]
}

# Start the credentials page if it is not already answering.
# Checks for the page's own marker rather than "anything on 8080", so a
# different service holding the port is reported as a failure instead of
# silently passing as the credentials page.
ensure_creds_server() {
  _serving_marker 8080 'Your SecOps Credentials' && return 0
  nohup python3 -m http.server 8080 --directory /var/www/html \
    > /var/log/creds-server.log 2>&1 &
  echo $! > "${WORKDIR}/creds-server.pid"
  local i
  for i in $(seq 1 15); do
    _serving_marker 8080 'Your SecOps Credentials' && return 0
    sleep 1
  done
  return 1
}

# Make sure the Okta user exists, retrying provisioning if track setup
# could not complete it.
#
# Lives here rather than in the first challenge's script so that ANY
# challenge can recover. With no challenge 0 in the track, a proctor or
# tester who skips straight to S1 C4 would otherwise hit a mint against
# an account that was never created.
#
# Returns non-zero only when the account genuinely does not exist.
ensure_provisioned() {
  [[ -f "${WORKDIR}/provisioned" ]] && return 0
  echo '[LINK] user not provisioned at track start, retrying...'
  if provision_user; then
    touch "${WORKDIR}/provisioned"
    echo '[LINK] provisioned, waiting for account activation...'
    sleep 10
    return 0
  fi
  echo '[LINK] ERROR: provisioning failed'
  return 1
}

# Mint a fresh magic link, re-render the credentials page, and republish
# the MAGIC_URL agent variable.
#
# Call this from EVERY section 1 challenge's docker setup script. The Okta
# session token is single use and expires in about five minutes, so a link
# minted at S1 C1 is dead by the time anyone reaches S1 C4. The page on the
# SecOps Login tab is the single source for this value; the instructions
# pane carries only USERNAME and PASSWORD, which are stable for the life
# of the sandbox.
#
# Return values are deliberately asymmetric:
#   0 - link minted, or mint failed but the account exists so the
#       username and password in the pane still work. Degraded, not broken.
#   1 - no account at all. The caller should fail the challenge loudly
#       so a proctor sees it rather than a participant discovering it.
refresh_magic_link() {
  local url="" attempt
  if ! ensure_provisioned; then
    write_creds_page ""
    agent variable set MAGIC_URL ""
    ensure_creds_server || true
    return 1
  fi
  for attempt in 1 2 3; do
    url=$(mint_magic_url) && break
    url=""
    sleep 3
  done
  write_creds_page "$url"
  agent variable set MAGIC_URL "$url"
  ensure_creds_server || true
  if [[ -n "$url" ]]; then
    echo "[LINK] magic link refreshed"
  else
    echo "[LINK] WARNING: mint failed, credentials page shows manual login only"
  fi
  return 0
}

# Start the docsify lab guide if it is not already answering.
ensure_docs_server() {
  _serving_marker "${DOCS_PORT}" 'Agentic SOC Workshop' && return 0
  nohup python3 -m http.server "${DOCS_PORT}" --directory "${DOCS_ROOT}" \
    > /var/log/docs-server.log 2>&1 &
  echo $! > "${WORKDIR}/docs-server.pid"
  local i
  for i in $(seq 1 15); do
    _serving_marker "${DOCS_PORT}" 'Agentic SOC Workshop' && return 0
    sleep 1
  done
  return 1
}
ENVEOF

# shellcheck source=/dev/null
source "${WORKDIR}/env.sh"

# ---- Store credentials for the assignment body ----
agent variable set USERNAME "${USERNAME}"
agent variable set PASSWORD "${PASSWORD}"

# ---- Provision ----
echo '[SETUP] Calling Okta provisioning workflow...'
if provision_user; then
  touch "${WORKDIR}/provisioned"
  echo '[SETUP] User provisioned. Waiting for account activation...'
  sleep 10
else
  echo '[SETUP] WARNING: provisioning failed. S1 C1 will retry.'
fi

# ---- Serve credentials page (no magic link yet) ----
write_creds_page ""
ensure_creds_server && \
  echo '[SETUP] Credentials page live on port 8080' || \
  echo '[SETUP] WARNING: credentials page not responding'

# ============================================================
# SECTION 2: Lab guide (docsify)
#
# Runs after the credentials page is live so a slow GitHub or jsdelivr
# cannot delay the thing S1 C1 depends on.
# ============================================================

# ---- Vendor assets ----
# Local copies rather than CDN links, so the guide still renders if
# jsdelivr is slow or blocked during the event. Every fetch is guarded:
# this script also provisions credentials, and an unguarded curl under
# `set -e` would take the whole track setup down with it.
VENDOR_OK=1
fetch_vendor() {
  curl -fsSL --max-time 30 --retry 2 --retry-delay 2 "$1" -o "$2" 2>/dev/null || {
    echo "[DOCS] vendor fetch failed: $1"
    VENDOR_OK=0
  }
}

fetch_vendor "${DOCSIFY_CDN}/lib/docsify.min.js"        "${DOCS_ROOT}/vendor/docsify.min.js"
fetch_vendor "${DOCSIFY_CDN}/lib/themes/dark.css"       "${DOCS_ROOT}/vendor/dark.css"
fetch_vendor "${DOCSIFY_CDN}/lib/plugins/search.min.js" "${DOCS_ROOT}/vendor/search.min.js"
fetch_vendor "${COPYCODE_CDN}"                          "${DOCS_ROOT}/vendor/copy-code.min.js"

# ---- Content, synced from GitHub ----
# Sparse, blobless, depth 1: one request for the whole directory rather
# than one Contents API call per page, so cost does not grow with pages.
#
# DOCS_REF must be a branch or tag. `--branch` does not accept a commit
# SHA. To pin a frozen delivery to a SHA, replace the clone with:
#   git init /tmp/docsrc && git -C /tmp/docsrc remote add origin "$URL"
#   git -C /tmp/docsrc fetch --depth 1 origin "$SHA"
#   git -C /tmp/docsrc checkout FETCH_HEAD
#
# The clone URL carries a token once the repo goes private. This script
# runs without xtrace, so it is never echoed. Do not add `set -x`.
#
# DOCS_TOKEN comes from an Instruqt track secret. Instruqt substitutes the
# placeholder into this script's text at run time, exactly as it does for
# soar_url_agentic in the Vertex setup script. Do NOT read it with
# printenv: track secrets are not exported as environment variables, so
# that returns empty and the clone silently stays anonymous, which only
# breaks once the repo goes private.
#
# Name the secret `github_token` in the track's secret list. If the secret
# does not exist, Instruqt leaves the placeholder unsubstituted and the
# line below fails under `set -u`, which is the loud failure you want.
#
# PAT scope: classic tokens need `repo`; fine-grained tokens need
# Contents: Read-only on googlecloudsecurity/agentic-soc-workshop.
DOCS_TOKEN="${github_token}"
DOCS_CLONE_URL="https://github.com/${DOCS_REPO}.git"
if [ -n "${DOCS_TOKEN}" ]; then
  # GitHub accepts any username when the password is a PAT. x-access-token
  # is the conventional placeholder and works for both PATs and GitHub App
  # installation tokens.
  DOCS_CLONE_URL="https://x-access-token:${DOCS_TOKEN}@github.com/${DOCS_REPO}.git"
fi

DOCS_OK=0
rm -rf /tmp/docsrc
if git clone --quiet --depth 1 --filter=blob:none --sparse \
     --branch "${DOCS_REF}" "${DOCS_CLONE_URL}" /tmp/docsrc 2>/tmp/docs-clone.err; then
  if git -C /tmp/docsrc sparse-checkout set "${DOCS_PATH}" 2>>/tmp/docs-clone.err; then
    DOCS_OK=1
  fi
fi
unset DOCS_TOKEN DOCS_CLONE_URL

if [ "${DOCS_OK}" -eq 1 ] && [ -d "/tmp/docsrc/${DOCS_PATH}" ]; then
  # Guard the glob: with set -e, a cp that matches nothing kills track setup.
  if ls /tmp/docsrc/"${DOCS_PATH}"/*.md >/dev/null 2>&1; then
    cp /tmp/docsrc/"${DOCS_PATH}"/*.md "${DOCS_ROOT}/"
    echo "[DOCS] synced $(ls -1 "${DOCS_ROOT}"/*.md | wc -l | tr -d ' ') pages from ${DOCS_REPO}@${DOCS_REF}"
    echo "[DOCS] commit $(git -C /tmp/docsrc rev-parse --short HEAD)"
  else
    echo "[DOCS] ##### NO .md FILES IN ${DOCS_PATH} #####"
    DOCS_OK=0
  fi
fi
rm -rf /tmp/docsrc

if [ "${DOCS_OK}" -eq 0 ]; then
  echo "[DOCS] ##### CONTENT FETCH FAILED - serving a stub #####"
  # Strip any user:token@ from the git error text before it reaches the
  # Instruqt log. git usually redacts credentials in its own messages, but
  # "usually" is not a guarantee worth betting a PAT on.
  sed -n '1,20p' /tmp/docs-clone.err 2>/dev/null | sed -E 's#//[^/@]*@#//***@#g' || true
  cat > "${DOCS_ROOT}/overview.md" <<'STUBEOF'
# Lab guide unavailable

The lab content could not be fetched at track start. Tell your instructor,
and use the challenge panel on the left to continue in the meantime.
STUBEOF
  cat > "${DOCS_ROOT}/_sidebar.md" <<'STUBEOF'
- [Start here](/)
STUBEOF
fi

# Fail loudly if the sidebar points at a page that did not come down. Cheap,
# and it turns a silent 404 mid-workshop into a visible setup-log error.
# The grep is guarded: it exits 1 on no match, which under pipefail would
# abort the command substitution.
#
# NOTE: this validates sidebar links only. It cannot see the hash routes in
# the Instruqt tab configuration — keep the table in README.md in sync.
if [ -f "${DOCS_ROOT}/_sidebar.md" ]; then
  MISSING=0
  SIDEBAR_PAGES=$(grep -oE '\(([A-Za-z0-9._/-]+)\.md\)' "${DOCS_ROOT}/_sidebar.md" \
    | tr -d '()' | sort -u || true)
  for PAGE in ${SIDEBAR_PAGES}; do
    [ -f "${DOCS_ROOT}/${PAGE}" ] || { echo "[DOCS] MISSING: ${PAGE}"; MISSING=1; }
  done
  [ "${MISSING}" -eq 0 ] && echo "[DOCS] all sidebar links resolve"
fi

# ---- Shell ----
# No README.md and no per-challenge cp: `homepage` serves overview.md
# at '/', and challenges deep-link with a hash route.
cat > "${DOCS_ROOT}/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Agentic SOC Workshop</title>
  <link rel="stylesheet" href="vendor/dark.css">
  <style>
    /* Taken from Instruqt's own CSS variables on <body>, not guessed. */
    :root {
      --iq-bg:     #131824;
      --iq-panel:  #1E2637;
      --iq-border: rgba(255,255,255,.10);
      --iq-text:   #FFFFFF;
      --iq-muted:  #D4D4D4;
      --iq-accent: #0F9E6E;
      --iq-link:   #3DD9A0;
      --iq-code:   #1E2637;

      --iq-ok:     #0F9E6E;  --iq-ok-bg:     #1A3335;
      --iq-warn:   #FF8F28;  --iq-warn-bg:   #6F3E11;
      --iq-danger: #CB020C;  --iq-danger-bg: #6F1111;

      --iq-mono: "JetBrains Mono", "Courier Prime", "Courier New", Courier, monospace;
      --theme-color: var(--iq-accent);
    }

    body, .content, .markdown-section { background: var(--iq-bg); color: var(--iq-text); }
    .sidebar { background: var(--iq-panel); border-right: 1px solid var(--iq-border); }
    .sidebar .app-name-link { color: var(--iq-text); }

    .sidebar ul li a { color: var(--iq-muted); }
    .sidebar ul li a:hover,
    .sidebar ul li.active > a,
    .sidebar ul li a.active { color: var(--iq-link); font-weight: 600; }
    .sidebar-nav > ul > li > strong,
    .sidebar-nav > ul > li > p {
      color: var(--iq-muted); text-transform: uppercase;
      font-size: 11px; letter-spacing: .08em;
    }

    .markdown-section { max-width: 860px; padding: 24px 32px; }
    /* Docsify's language label sits exactly where the copy button goes. */
    .markdown-section pre[data-lang]::after { display: none; }
    .markdown-section h1,
    .markdown-section h2,
    .markdown-section h3 { color: var(--iq-text); }
    .markdown-section h2 { border-bottom: 1px solid var(--iq-border); padding-bottom: 6px; }
    .markdown-section a { color: var(--iq-link); text-decoration: none; }
    .markdown-section a:hover { text-decoration: underline; }
    .markdown-section strong { color: var(--iq-text); }

    .markdown-section code,
    .markdown-section pre { background: var(--iq-code); }
    .markdown-section code,
    .markdown-section pre > code { font-family: var(--iq-mono); }
    .markdown-section code { color: var(--iq-link); border-radius: 3px; }
    .markdown-section pre { border: 1px solid var(--iq-border); border-radius: 6px; }
    .markdown-section pre > code { font-size: 13px; line-height: 1.5; color: var(--iq-text); }

    /* Agent prompts are written as blockquotes, so this one earns its keep. */
    .markdown-section blockquote {
      border-left: 4px solid var(--iq-link);
      background: rgba(15, 158, 110, .12);
      color: var(--iq-text); padding: 10px 16px; margin: 16px 0;
    }

    .markdown-section table th,
    .markdown-section table td { border-color: var(--iq-border); }
    .markdown-section tr { background: transparent; border-top-color: var(--iq-border); }
    .markdown-section tr:nth-child(2n) { background: rgba(255,255,255,.02); }

    .search input {
      background: var(--iq-code); color: var(--iq-text);
      border: 1px solid var(--iq-border); border-radius: 4px;
    }
    .search .results-panel { background: var(--iq-panel); }
    .search p, .search h2 { color: var(--iq-text); }

    .tip, .warn, .danger {
      padding: 12px 16px; margin: 16px 0; border-radius: 4px;
      border-left: 4px solid;
    }
    .tip    { border-color: var(--iq-ok);     background: var(--iq-ok-bg); }
    .warn   { border-color: var(--iq-warn);   background: var(--iq-warn-bg); }
    .danger { border-color: var(--iq-danger); background: var(--iq-danger-bg); }

    .docsify-copy-code-button {
      background: var(--iq-accent) !important;
      color: #fff !important;
      font-size: 11px !important;
      border-radius: 3px !important;
      opacity: .85;
    }
    .docsify-copy-code-button:hover { opacity: 1; }
    .sidebar-toggle { background: transparent; }
    .sidebar-toggle span { background-color: var(--iq-muted); }
  </style>
</head>
<body>
  <div id="app">Loading...</div>
  <script>
    window.$docsify = {
      name: 'Agentic SOC Workshop', repo: false,
      // overview.md serves at '/', so nothing is copied over README.md and
      // each challenge tab can deep-link with a hash route instead.
      homepage: 'overview.md',
      loadSidebar: true, subMaxLevel: 2, auto2top: true,
      search: { placeholder: 'Search', noData: 'No matches', depth: 3 },
      copyCode: { buttonText: 'Copy', errorText: 'Failed', successText: 'Copied' },
      // Start with the sidebar collapsed so the instructions get the full
      // width of a narrow Instruqt tab. The toggle button still expands it.
      plugins: [
        function (hook) {
          hook.mounted(function () { document.body.classList.add('close'); });
        }
      ]
    };
  </script>
  <script src="vendor/docsify.min.js"></script>
  <script src="vendor/search.min.js"></script>
  <script src="vendor/copy-code.min.js"></script>
</body>
</html>
HTMLEOF

# If any vendor asset failed to download, point every asset at the CDN.
# All or nothing on purpose: a page half-served from an empty local file
# is harder to diagnose than a page that simply needs network.
if [ "${VENDOR_OK}" -eq 0 ]; then
  echo "[DOCS] one or more vendor assets missing, falling back to CDN"
  sed -i \
    -e "s#vendor/dark.css#${DOCSIFY_CDN}/lib/themes/dark.css#" \
    -e "s#vendor/docsify.min.js#${DOCSIFY_CDN}/lib/docsify.min.js#" \
    -e "s#vendor/search.min.js#${DOCSIFY_CDN}/lib/plugins/search.min.js#" \
    -e "s#vendor/copy-code.min.js#${COPYCODE_CDN}#" \
    "${DOCS_ROOT}/index.html"
fi

# ---- Serve it ----
# Same nohup pattern as the credentials page rather than a systemd unit:
# systemd is not reliably PID 1 on an Instruqt docker host.
ensure_docs_server && \
  echo "[SETUP] Lab guide live on port ${DOCS_PORT}" || \
  { echo "[SETUP] WARNING: lab guide not responding on ${DOCS_PORT}"; \
    tail -10 /var/log/docs-server.log 2>/dev/null || true; }

echo '[SETUP] docker host setup complete'
echo "[SETUP]   Credentials page : port 8080"
echo "[SETUP]   Lab guide        : port ${DOCS_PORT}"
echo "[SETUP]   Username         : ${USERNAME}"
