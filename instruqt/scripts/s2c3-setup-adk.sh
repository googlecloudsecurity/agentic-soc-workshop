#!/bin/bash
#
# HOST: adk
# SCRIPT: Section 2 Challenge 3 setup
#
# Starts the three new mock MCP servers the agent team connects to and
# stages the incident report skill. Idempotent: safe to rerun.
#
# Conventions match the existing Okta and CrowdStrike mocks:
#   - servers live in /root/mcp-servers, NOT /root/agents
#     (/root/agents is the ADK Web workspace; anything in there gets
#      scanned as an agent)
#   - /root/mcp-servers/.adkignore belts-and-braces that
#   - run under the ADK venv interpreter, not system python3
#   - skills live in /root/skills/<name>/SKILL.md, outside the workspace
#
# Port map, all five started by this script:
#   8001  Okta
#   8002  CrowdStrike
#   8003  Wiz
#   8004  Salesforce
#   8005  SecOps SOAR
#
set -eo pipefail

MCP_DIR="/root/mcp-servers"
SKILLS_DIR="/root/skills"
VENV_PY="/root/adk-env/bin/python3"
REPO_RAW="https://raw.githubusercontent.com/googlecloudsecurity/agentic-soc-workshop/main"

log() { printf '[s2c3] %s\n' "$*"; }

mkdir -p "${MCP_DIR}" "${SKILLS_DIR}/incident-report-writer" /var/log

# ADK Web scans for agent packages. Keep it out of the mock directory.
touch "${MCP_DIR}/.adkignore"

[ -x "${VENV_PY}" ] || { log "ERROR: ${VENV_PY} not found"; exit 1; }

# --- FastMCP availability ---------------------------------------------------
# The mocks import mcp.server.fastmcp and fall back to fastmcp, so either
# package satisfies them. Check before starting anything.
if ! "${VENV_PY}" -c 'import mcp.server.fastmcp' 2>/dev/null \
   && ! "${VENV_PY}" -c 'import fastmcp' 2>/dev/null; then
  log "no FastMCP in adk-env, installing"
  /root/.local/bin/uv pip install --python "${VENV_PY}" "fastmcp==3.4.2" --quiet 2>&1 | tail -2 || true
fi
"${VENV_PY}" -c 'import mcp.server.fastmcp' 2>/dev/null && log "using mcp.server.fastmcp"
"${VENV_PY}" -c 'import fastmcp' 2>/dev/null && log "using fastmcp"

# --- fetch servers, seeds and skill -----------------------------------------
# Each mock is a server plus a JSON seed, so a scenario change is a data
# diff rather than a code diff. Repo is public: no token needed.
fetch() {
  local src="$1" dest="$2"
  curl -fsSL --retry 3 --retry-delay 2 --max-time 30 -o "${dest}" "${src}" || {
    log "ERROR: could not fetch $(basename "${dest}")"
    return 1
  }
  log "fetched $(basename "${dest}")"
}

for m in okta crowdstrike wiz salesforce soar; do
  fetch "${REPO_RAW}/instruqt/scripts/mcp/${m}_mock.py"  "${MCP_DIR}/${m}_mock.py"  || exit 1
  fetch "${REPO_RAW}/instruqt/scripts/mcp/${m}_seed.json" "${MCP_DIR}/${m}_seed.json" || exit 1
done

fetch "${REPO_RAW}/skills/incident-report-writer/SKILL.md" \
      "${SKILLS_DIR}/incident-report-writer/SKILL.md" || exit 1

# --- start servers ----------------------------------------------------------
# /sse is a long-lived stream. curl connects, receives the endpoint event,
# then waits for more and gets killed by --max-time, exiting 28. That is
# expected, so the exit code is deliberately ignored and only the body is
# tested. Do not add `|| return 1` here, and do not pipe to grep either:
# grep exits on first match, curl takes SIGPIPE, and pipefail reports
# failure even though the marker was found.
serving() {
  local body
  body=$(curl -s --max-time 2 "http://localhost:$1/sse" 2>/dev/null || true)
  [[ "${body}" == *"event:"* ]]
}

start_mock() {
  local name="$1" port="$2" script="${MCP_DIR}/$1_mock.py"
  if serving "${port}"; then
    log "${name}: already serving on ${port}"
    return 0
  fi
  if [ ! -s "${script}" ]; then
    log "${name}: ERROR script missing at ${script}"
    return 0
  fi
  log "${name}: starting on ${port}"
  nohup "${VENV_PY}" "${script}" >>"/var/log/mcp-${name}.log" 2>&1 &
}

start_mock okta        8001
start_mock crowdstrike 8002
start_mock wiz         8003
start_mock salesforce  8004
start_mock soar        8005

# --- readiness --------------------------------------------------------------
log "waiting for MCP servers"
FAILED=0
for entry in "okta:8001" "crowdstrike:8002" "wiz:8003" "salesforce:8004" "soar:8005"; do
  name="${entry%%:*}"; port="${entry##*:}"
  ready=0
  for _ in $(seq 1 15); do
    if serving "${port}"; then ready=1; break; fi
    sleep 1
  done
  if [ "${ready}" -eq 1 ]; then
    log "${name} (${port}): ready"
  else
    log "${name} (${port}): NOT SERVING"
    tail -15 "/var/log/mcp-${name}.log" 2>/dev/null | sed 's/^/    /' || true
    FAILED=1
  fi
done

[ "${FAILED}" -eq 0 ] && log "setup complete" || log "setup complete with errors"
exit 0
