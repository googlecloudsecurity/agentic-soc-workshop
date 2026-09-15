#!/usr/bin/env bash
#
# Section 2 Challenge 3 setup, adk host.
#
# Starts the five mock MCP servers the agent team connects to and stages
# the skills directory participants edit. Idempotent: safe to rerun, and
# safe if the track-level setup already started some of the servers.
#
# Port map:
#   8001  Okta
#   8002  CrowdStrike
#   8003  Wiz
#   8004  Salesforce
#   8005  SecOps SOAR
#
set -Eeuo pipefail

AGENTS_DIR="/root/agents"
MCP_DIR="${AGENTS_DIR}/mcp"
SKILLS_DIR="${AGENTS_DIR}/skills"
REPO_RAW="https://raw.githubusercontent.com/googlecloudsecurity/agentic-soc-workshop/main"

log() { printf '[s2c3] %s\n' "$*"; }
fail() { printf '[s2c3] ERROR: %s\n' "$*" >&2; exit 1; }

mkdir -p "${MCP_DIR}" "${SKILLS_DIR}" /var/log

# --- dependencies -----------------------------------------------------------
# mcp<2 is load-bearing. The mocks import mcp.server.fastmcp, which the MCP
# Python SDK removed in v2.0.0, and nothing pins it for us.
log "ensuring FastMCP is available"
if ! python3 -c 'import mcp.server.fastmcp' 2>/dev/null; then
  uv pip install --system "mcp<2" >/dev/null 2>&1 \
    || pip3 install --break-system-packages "mcp<2" >/dev/null 2>&1 \
    || fail "could not install mcp<2"
fi
python3 -c 'import mcp.server.fastmcp' 2>/dev/null \
  || fail "mcp.server.fastmcp still not importable"

# --- fetch mock servers and skills -----------------------------------------
fetch() {
  local src="$1" dest="$2"
  if [[ -s "${dest}" ]]; then
    log "already present: $(basename "${dest}")"
    return 0
  fi
  curl -fsSL --retry 3 --retry-delay 2 --max-time 30 -o "${dest}" "${src}" \
    || fail "could not fetch $(basename "${dest}")"
  log "fetched $(basename "${dest}")"
}

for m in wiz_mock salesforce_mock soar_mock; do
  fetch "${REPO_RAW}/instruqt/scripts/mcp/${m}.py" "${MCP_DIR}/${m}.py"
done

fetch "${REPO_RAW}/agents/skills/incident-report.md" "${SKILLS_DIR}/incident-report.md"

# --- start servers ----------------------------------------------------------
# systemd is not PID 1 on this host, so nohup rather than unit files.
start_mock() {
  local name="$1" script="$2" port="$3"

  if curl -s --max-time 2 "http://localhost:${port}/sse" | head -1 | grep -q 'event:'; then
    log "${name} already serving on ${port}"
    return 0
  fi

  if [[ ! -s "${script}" ]]; then
    log "WARNING: ${name} script missing at ${script}, skipping"
    return 0
  fi

  log "starting ${name} on ${port}"
  nohup python3 "${script}" >>"/var/log/mcp-${name}.log" 2>&1 &
}

start_mock wiz        "${MCP_DIR}/wiz_mock.py"        8003
start_mock salesforce "${MCP_DIR}/salesforce_mock.py" 8004
start_mock soar       "${MCP_DIR}/soar_mock.py"       8005

# --- readiness --------------------------------------------------------------
log "waiting for MCP servers"
for port in 8001 8002 8003 8004 8005; do
  ready=0
  for _ in $(seq 1 30); do
    if curl -s --max-time 2 "http://localhost:${port}/sse" | head -1 | grep -q 'event:'; then
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "${ready}" -eq 1 ]]; then
    log "port ${port}: ready"
  else
    log "WARNING: port ${port} not serving. Check /var/log/mcp-*.log"
  fi
done

log "setup complete"
