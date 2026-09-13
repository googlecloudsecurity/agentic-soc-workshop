#!/bin/bash
set -uo pipefail

# ============================================================
# HOST: docker
# SCRIPT: Section 1 challenge setup - refresh the SecOps magic link
#
# Use this VERBATIM as the docker setup script for all five:
#   S1 C1: Triage Agent
#   S1 C2: Gemini in SecOps
#   S1 C3: Emerging Threats & Threat Hunt
#   S1 C4: Gemini in Playbooks
#   S1 C5: Detection Engineering Agent
#
# Nothing in here is challenge-specific. The provisioning retry that used
# to live only in the first challenge now sits inside refresh_magic_link,
# so a participant who skips ahead recovers the same way as one who starts
# at C1.
#
# The Okta session token behind the launch button is single use and
# expires in about five minutes. Without this, someone reaching C4 clicks
# a button that has been dead for half an hour.
#
# No `set -e`. A failed mint is fail-soft: the username and password in
# the instructions pane still work, so the challenge must not abort. The
# two things that DO abort are handled explicitly below.
# ============================================================

WORKDIR=/root/.workshop

if [[ ! -f "${WORKDIR}/env.sh" ]]; then
  echo "[LINK] ERROR: ${WORKDIR}/env.sh missing. Did track setup run?"
  exit 1
fi

# shellcheck source=/dev/null
source "${WORKDIR}/env.sh"

# Non-zero here means the Okta account does not exist and could not be
# created. The participant has no way in, so fail loudly rather than
# letting them discover it at the login screen.
refresh_magic_link || {
  echo '[LINK] ERROR: no SecOps account for this sandbox. Flag this to the proctor.'
  exit 1
}

# refresh_magic_link tolerates a down credentials page with `|| true`,
# because for it the link is the point. For the challenge it is not: the
# page is the only fallback when a mint fails, so re-check and fail here.
ensure_creds_server || {
  echo '[LINK] ERROR: credentials page not responding on 8080'
  tail -10 /var/log/creds-server.log 2>/dev/null || true
  exit 1
}

echo '[LINK] Challenge ready'
echo "[LINK]   Username : ${USERNAME}"
echo "[LINK]   SecOps   : ${SECOPS_URL}"
