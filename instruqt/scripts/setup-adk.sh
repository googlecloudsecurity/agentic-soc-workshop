#!/bin/bash
set -euo pipefail

# ============================================================
# Instruqt Setup Script - Operation Shiny Hunter Workshop
# ADK VM (Ubuntu 24.04)
# Runs once at track start before any challenge is loaded.
#
# Ports on this host:
#   8000  ADK Web          (started by the participant, not here)
#   8080  code-server
#   8888  Grader           (written by challenge setup scripts)
#   8001  Okta MCP         (mock)
#   8002  CrowdStrike MCP  (mock)
#   8003  Wiz MCP          (mock, started by the S2 C3 challenge script)
#   8004  Salesforce MCP   (mock, started by the S2 C3 challenge script)
#   8005  SecOps SOAR MCP  (mock, started by the S2 C3 challenge script)
#
# Model: gemini-3.5-flash everywhere. Changing it means changing it in
# five places in this file: the export block, .bashrc, /etc/environment,
# .bash_profile, and the code-server terminal env in settings.json.
# ============================================================

# ---- Resolve Instruqt GCP ephemeral project credentials ----
# These variables are automatically injected by Instruqt when a GCP project
# named "google-cloud" is attached to the sandbox in config.yml
PROJECT_ID="${INSTRUQT_GCP_PROJECT_GOOGLE_CLOUD_PROJECT_ID}"
SA_KEY_B64="${INSTRUQT_GCP_PROJECT_GOOGLE_CLOUD_SERVICE_ACCOUNT_KEY}"
SA_EMAIL="${INSTRUQT_GCP_PROJECT_GOOGLE_CLOUD_SERVICE_ACCOUNT_EMAIL}"

echo "📋 Project: $PROJECT_ID"

# ---- GCP Auth ----
# Decode the base64-encoded service account key and activate it with gcloud.
# This authenticates the VM to the ephemeral GCP project so that Vertex AI
# calls (used by ADK agents) succeed without any manual login.
echo "$SA_KEY_B64" | base64 -d > /root/sa-key.json
gcloud auth activate-service-account "$SA_EMAIL" \
  --key-file=/root/sa-key.json \
  --project="$PROJECT_ID" 2>/dev/null

# ---- SecOps SA Key ----
# Write the SecOps (Chronicle) service account key from an Instruqt secret.
# This is a separate SA with access to the shared SecOps tenant used by
# the triage agent in later challenges.
echo "${siem_sa_json_agentic}" > /root/secops-sa-key.json
chmod 600 /root/secops-sa-key.json

# ---- Export environment variables for this script session ----
# These are needed immediately by tools run later in this script (e.g. uv, gcloud).
# They are also written to .bashrc and /etc/environment below for persistence.
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"
export GOOGLE_CLOUD_LOCATION="global"
export GOOGLE_GENAI_USE_VERTEXAI="true"
export GOOGLE_APPLICATION_CREDENTIALS="/root/sa-key.json"
export GEMINI_MODEL="gemini-3.5-flash"
export VT_APIKEY="${gti_enterprise_key}"
export CHRONICLE_PROJECT_ID="${siem_project_agentic}"
export CHRONICLE_CUSTOMER_ID="${siem_id_agentic}"
export CHRONICLE_REGION="us"
export SECOPS_SA_KEY_PATH="/root/secops-sa-key.json"
export SOAR_URL="${soar_url_agentic}"
export SOAR_APP_KEY="${soar_api_agentic}"

# ---- Persist env vars for interactive bash shells ----
# Appended to .bashrc so that every terminal a participant opens in
# code-server or the Instruqt terminal tab has the correct environment.
# Also activates the ADK virtual environment automatically on shell start.
cat >> /root/.bashrc << EOF
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"
export GOOGLE_CLOUD_LOCATION="global"
export GOOGLE_GENAI_USE_VERTEXAI="true"
export GOOGLE_APPLICATION_CREDENTIALS="/root/sa-key.json"
export GEMINI_MODEL="gemini-3.5-flash"
export VT_APIKEY="${gti_enterprise_key}"
export CHRONICLE_PROJECT_ID="${siem_project_agentic}"
export CHRONICLE_CUSTOMER_ID="${siem_id_agentic}"
export CHRONICLE_REGION="us"
export SECOPS_SA_KEY_PATH="/root/secops-sa-key.json"
export SOAR_URL="${soar_url_agentic}"
export SOAR_APP_KEY="${soar_api_agentic}"
source /root/adk-env/bin/activate
export PATH="/root/.local/bin:\$PATH"
EOF

# ---- Persist env vars for all system sessions ----
# /etc/environment is read by PAM for all login sessions including
# non-interactive ones, ensuring ADK web and background processes
# also have the correct GCP project and credentials.
cat >> /etc/environment << EOF
GOOGLE_CLOUD_PROJECT="$PROJECT_ID"
GOOGLE_CLOUD_LOCATION="global"
GOOGLE_GENAI_USE_VERTEXAI="true"
GOOGLE_APPLICATION_CREDENTIALS="/root/sa-key.json"
GEMINI_MODEL="gemini-3.5-flash"
VT_APIKEY="${gti_enterprise_key}"
CHRONICLE_PROJECT_ID="${siem_project_agentic}"
CHRONICLE_CUSTOMER_ID="${siem_id_agentic}"
CHRONICLE_REGION="us"
SECOPS_SA_KEY_PATH="/root/secops-sa-key.json"
SOAR_URL="${soar_url_agentic}"
SOAR_APP_KEY="${soar_api_agentic}"
EOF

# ---- Persist env vars and workspace directory for login shells ----
# code-server terminals launch as --login bash shells, which source
# .bash_profile instead of .bashrc. Sourcing .bashrc from .bash_profile
# ensures all env vars (including secrets written to .bashrc) are available
# in every terminal without needing to manually source anything.
cat >> /root/.bash_profile << EOF
[[ -f /root/.bashrc ]] && source /root/.bashrc
cd /root/agents
source /root/adk-env/bin/activate
export PATH="/root/.local/bin:\$PATH"
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"
export GOOGLE_CLOUD_LOCATION="global"
export GOOGLE_GENAI_USE_VERTEXAI="true"
export GOOGLE_APPLICATION_CREDENTIALS="/root/sa-key.json"
export GEMINI_MODEL="gemini-3.5-flash"
EOF

# ---- Install uv ----
# uv is a fast Python package manager written in Rust.
# Used to create the virtual environment and install ADK packages
# significantly faster than pip.
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="/root/.local/bin:$PATH"

# ---- Create ADK virtual environment and install packages ----
# uv creates venvs natively in Rust and does NOT use python3's venv module,
# so no apt-get is required here. The previous python3-venv install cost
# ~2 minutes of track start time and was never needed.
# The fallback exists only in case a future base image changes something
# uv depends on.
echo "🐍 Creating ADK virtual environment..."
if ! uv venv /root/adk-env 2>/dev/null; then
  echo "uv venv failed, falling back to python3-venv..."
  apt-get update -qq
  apt-get install -y -qq python3-venv > /dev/null 2>&1
  uv venv /root/adk-env
fi

source /root/adk-env/bin/activate

# google-adk: the Agent Development Kit framework
# fastmcp:    used by the mock MCP servers in later challenges. The mocks
#             try `mcp.server.fastmcp` first and fall back to `fastmcp`, so
#             either package satisfies them.
uv pip install "google-adk==2.4.0" "fastmcp==3.4.2" aiohttp google-cloud-aiplatform

# ---- Warm the GTI MCP cache in the background ----
# gti-mcp declares an unbounded `mcp` dependency. MCP Python SDK 2.0 removed
# mcp.server.fastmcp, so an unpinned `uvx gti_mcp` resolves to 2.x and the
# server dies on import, leaving the agent silently toolless.
#
# This pre-resolves using the EXACT invocation Challenge 2 participants use,
# so their first agent start is a cache hit rather than a cold download.
# Backgrounded so it never blocks track start: Challenge 0 and Challenge 1
# give it 30+ minutes of cover before anyone needs it.
echo "🔥 Warming gti_mcp cache in background..."
nohup bash -c '
  timeout 300 uvx --with "mcp<2" gti_mcp < /dev/null > /var/log/gti-cache-warm.log 2>&1
  touch /root/.gti-cache-warm-done
' > /dev/null 2>&1 &

# ---- Create grader directory ----
# The grader server files are written by individual challenge setup scripts.
# This just ensures the directory exists at track start.
mkdir -p /root/grader

# ---- Create agents workspace directory ----
# This is the root workspace that code-server opens and where participants
# will run adk create to scaffold their agents during challenges.
mkdir -p /root/agents

# ---- Create mock MCP server directory ----
# Mocks live OUTSIDE /root/agents. Anything inside the ADK Web workspace
# gets scanned as an agent package. The .adkignore is belt and braces.
# The S2 C3 challenge script fetches the servers and seeds into here.
mkdir -p /root/mcp-servers
touch /root/mcp-servers/.adkignore

# ---- Write Cymbal Investments org knowledge skill ----
# Pre-built skill loaded by participants in Challenge 1.
# Lives at /root/skills/ — outside /root/agents/ so ADK Web never
# discovers it as an agent.
echo "Writing cymbal-org-knowledge skill..."
mkdir -p /root/skills/cymbal-org-knowledge/references

cat > /root/skills/cymbal-org-knowledge/SKILL.md << 'SKILL_EOF'
---
name: cymbal-org-knowledge
description: Provides organizational context about Cymbal Investments — the company, its business, security stack, and key personnel. Use when investigating Cymbal Investments incidents, analyzing alerts from their environment, or when the user mentions Cymbal, s.hudson, or any Cymbal Investments user or system.
license: Apache-2.0
metadata:
  author: agentic-soc-workshop
  version: "1.1"
  scenario: Operation Shiny Hunter
---

# Cymbal Investments — Organizational Knowledge

## Who is Cymbal Investments?

Cymbal Investments is a mid-sized financial services firm headquartered in New York,
operating in investment management and portfolio advisory services. The firm manages
approximately $12B AUM across institutional and high-net-worth client segments.

**Regulatory environment:** SEC Rule 17a-4, SOX, and MNPI obligations apply. Any
incident involving trading strategies, M&A activity, or client portfolios must be
treated as a potential regulatory disclosure event.

---

## Security Stack

| Platform       | Role                              | Scope                        |
|----------------|-----------------------------------|------------------------------|
| Okta           | Identity and SSO                  | All SaaS apps, 847 users     |
| CrowdStrike    | EDR                               | All Windows/macOS endpoints  |
| Wiz            | Cloud security posture            | Google Cloud, Salesforce     |
| Google SecOps  | SIEM (Chronicle)                  | All log sources              |
| Google SOAR    | Case management and response      | SOC workflow                 |
| Salesforce     | CRM and document repository       | Finance and client ops       |

**Key SaaS apps connected via Okta SSO:** Salesforce, SharePoint, Slack, Google Drive,
DocuSign, Workday, Zoom, GitHub.

---

## Key Personnel

| Name            | Email                                   | Role                            |
|-----------------|-----------------------------------------|---------------------------------|
| Saul Hudson     | s.hudson@cymbal-investments.com         | Senior Portfolio Manager        |
| Gordon Sumner   | g.sumner@cymbal-investments.com         | IT Systems Administrator / Okta Admin |
| Paul Hewson     | p.hewson@cymbal-investments.com         | Head of Investment Operations   |

---

## Environment Details

**Endpoints:** All endpoints are Windows 11 or macOS, managed via CrowdStrike.
Hostname convention: CYMBAL-LT-{LASTNAME} for laptops.

**Identity:** Okta is the single identity provider. All SaaS access is via Okta SSO.
MFA is enforced for all users. Approved factor types: YubiKey hardware tokens and
Okta Verify (mobile app on corporate-approved devices).

**Cloud:** Google Cloud is the primary cloud platform. Users federate in from Okta
through Workforce Identity Federation to the cymbal-workforce pool, so cloud access
follows Okta group membership rather than separate cloud credentials. Salesforce is
the primary document and CRM repository for Investment Operations.

**Network:** Corporate egress IP range: 96.6.127.0/24. Employees in Europe may
appear from Amsterdam (96.6.127.x) when connected to corporate VPN.
SKILL_EOF

cat > /root/skills/cymbal-org-knowledge/references/investigation-methodology.md << 'REF_EOF'
# Cymbal Investments — SOC Investigation Methodology

## Platform Investigation Sequence

### 1. Identity (Okta) — Always First

| Check                | Tool                  | What to look for                                        |
|----------------------|-----------------------|---------------------------------------------------------|
| Account status       | get_user_profile      | ACTIVE or SUSPENDED?                                    |
| Active sessions      | get_active_sessions   | Sessions from unexpected IPs or geo-locations           |
| Enrolled MFA factors | get_enrolled_factors  | Factor types, enrollment dates, device platforms        |
| Assigned apps        | get_user_profile      | Which Okta SSO apps the user has access to              |

**Normal baseline for Cymbal Investments:**
- Employees typically authenticate from New York or Amsterdam (corporate VPN: 96.6.127.0/24)
- Approved MFA factors: YubiKey hardware tokens and Okta Verify on corporate devices
- Business hours: 08:00-20:00 ET. Activity outside these hours warrants review.

### 2. Endpoint (CrowdStrike) — Second

| Check           | Tool                  | What to look for                                        |
|-----------------|-----------------------|---------------------------------------------------------|
| Detections      | list_detections       | HIGH or CRITICAL severity on the user host              |
| Process tree    | get_process_tree      | Suspicious parent-child relationships                   |
| Host info       | get_host_info         | Containment status, OS version, assigned user           |

**Cymbal endpoint naming:** CYMBAL-LT-{LASTNAME} for employee laptops.

An absence of detections is a finding, not a dead end. A session-based
compromise never touches the endpoint, so a clean host rules out an entire
remediation track.

### 3. SaaS (Salesforce) — Third

| Check                | Tool                      | What to look for                                     |
|----------------------|---------------------------|------------------------------------------------------|
| Event log            | search_event_log          | Logins, page views, API calls by IP or user          |
| Document access      | get_document_access       | What was downloaded, with which client               |
| Connected apps       | list_connected_apps       | OAuth apps authorized, and by whom, and from where   |
| Record changes       | get_record_modifications  | Whether data was altered or only read                |

**Why connected apps matter:** an OAuth app authorized during an attacker
session survives session revocation and password resets. Revoking the app is
a separate containment action from terminating sessions in Okta.

### 4. Cloud (Wiz) — Fourth

| Check                  | Tool                        | What to look for                                   |
|------------------------|-----------------------------|----------------------------------------------------|
| Identity federation    | get_cloud_identity          | How the user federates in, and last cloud activity |
| Effective permissions  | get_effective_permissions   | Inherited folder-level grants, BigQuery datasets   |
| Open issues            | list_identity_issues        | Excessive permissions, stale keys, missing limits  |
| Attack path            | get_attack_path             | Chain from compromised identity to sensitive data  |
| Cloud audit activity   | search_cloud_audit_logs     | Whether the attacker IP appears in cloud at all    |

**Cymbal cloud context:** Google Cloud access is federated from Okta, so a
compromised Okta identity carries its cloud reach with it. Reach and use are
different questions. An identity that never touched cloud during an incident
can still hold standing access worth reporting.

## Escalation Criteria

Escalate immediately to L2 if any of the following are confirmed:
- Active session from a non-corporate IP with no VPN
- MFA factor enrolled outside of IT provisioning workflow
- Salesforce document access in bulk or via automation
- An OAuth connected app authorized from an untrusted IP, with a valid refresh token
- A federated identity with a live attack path to regulated data in BigQuery or Cloud Storage
- Any finding tagged with regulatory data types (trading, M&A, client portfolios)
REF_EOF

echo "  cymbal-org-knowledge skill written to /root/skills/"

# ---- Install code-server ----
# code-server runs VS Code in the browser, providing participants with a
# familiar IDE experience inside the Instruqt lab without leaving the browser.
curl -fsSL https://code-server.dev/install.sh | sh

# ---- Configure code-server ----
# Disable authentication (Instruqt handles access control at the tab level)
# and bind to all interfaces so the Instruqt service tab can reach port 8080.
mkdir -p /root/.config/code-server
cat > /root/.config/code-server/config.yaml << 'EOF'
bind-addr: 0.0.0.0:8080
auth: none
cert: false
EOF

# ---- Configure VS Code user settings ----
# These settings are applied globally for the root user in code-server:
# - Disables workspace trust prompt (unnecessary in a controlled lab environment)
# - Injects GCP env vars into every terminal opened in code-server
# - Sets the terminal to open as a login shell so .bash_profile is sourced
#   (which sources .bashrc and activates the venv automatically)
# - Opens a terminal panel on startup instead of the welcome tab
# - Sets the Python interpreter to the ADK venv for IntelliSense
# - Disables AI chat features (note: code-server bug #7540 means the
#   chat panel may still appear despite these settings — this is cosmetic
#   and does not affect functionality; the panel can be collapsed)
mkdir -p /root/.local/share/code-server/User
cat > /root/.local/share/code-server/User/settings.json << EOF
{
  "security.workspace.trust.enabled": false,
  "workbench.secondarySideBar.visible": false,
  "terminal.integrated.env.linux": {
    "GOOGLE_CLOUD_PROJECT": "$PROJECT_ID",
    "GOOGLE_CLOUD_LOCATION": "global",
    "GOOGLE_GENAI_USE_VERTEXAI": "true",
    "GOOGLE_APPLICATION_CREDENTIALS": "/root/sa-key.json",
    "GEMINI_MODEL": "gemini-3.5-flash",
    "VIRTUAL_ENV": "/root/adk-env",
    "PATH": "/root/adk-env/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  },
  "terminal.integrated.defaultProfile.linux": "bash",
  "terminal.integrated.profiles.linux": {
    "bash": {
      "path": "/bin/bash",
      "args": ["--login"],
      "env": {
        "CDPATH": "/root/agents"
      }
    }
  },
  "terminal.integrated.cwd": "/root/agents",
  "terminal.integrated.defaultLocation": "editor",
  "workbench.colorTheme": "Default Dark Modern",
  "workbench.startupEditor": "terminal",
  "editor.fontSize": 14,
  "editor.formatOnSave": true,
  "python.defaultInterpreterPath": "/root/adk-env/bin/python3",
  "python.pythonPath": "/root/adk-env/bin/python3",
  "chat.commandCenter.enabled": false,
  "inlineChat.enabled": false,
  "workbench.tips.enabled": false,
  "chat.editor.enabled": false,
  "chat.suggestions.enabled": false,
  "github.copilot.enable": {
    "*": false
  },
  "workbench.activityBar.compact": true,
  "chat.disabled": true,
  "chat.disableAIFeatures": true,
  "chat.aiGeneratedWorkspaceName.enabled": false
}
EOF

# ---- Install VS Code Python extension ----
# Provides syntax highlighting, IntelliSense, and linting for Python files.
# The || true prevents track setup from dying if the marketplace is
# unreachable — this line previously had no guard despite the comment.
code-server --install-extension ms-python.python || true
code-server --uninstall-extension vscode.chat --force 2>/dev/null || true

# ---- Configure code-server systemd service ----
# Override the default systemd unit to pass /root/agents as the workspace root.
# This opens the file explorer rooted at /root/agents, hiding system files
# and other directories that participants don't need to see.
# The ExecStart line is cleared first (required by systemd drop-in syntax)
# before setting the new command.
mkdir -p /etc/systemd/system/code-server@root.service.d
cat > /etc/systemd/system/code-server@root.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/code-server --config /root/.config/code-server/config.yaml /root/agents
EOF

systemctl daemon-reload
systemctl enable --now code-server@root

# ---- Wait for code-server to be ready ----
# Poll port 8080 until it responds. The Instruqt challenge tab will fail
# to load if code-server isn't up before the participant sees it.
# Exit with an error and print service logs if it doesn't start within 60s.
TIMEOUT=60
ELAPSED=0
until curl -s http://localhost:8080 > /dev/null 2>&1; do
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: code-server failed to start"
    journalctl -u code-server@root --no-pager -n 20
    exit 1
  fi
  echo "Waiting for code-server... (${ELAPSED}s)"
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

echo "✅ Done - Project: $PROJECT_ID"
echo "   Workspace: /root/agents"
echo "   Mock MCP dir: /root/mcp-servers"
echo "   code-server: http://adk:8080"
echo "   Model: gemini-3.5-flash"
echo "   gti_mcp cache warming in background (marker: /root/.gti-cache-warm-done)"
