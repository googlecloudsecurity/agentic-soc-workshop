#!/usr/bin/env python3
"""Mock Google SecOps SOAR MCP server for the Agentic SOC Workshop.

Serves a fixed copy of the Operation Shiny Hunter case wall over SSE so
that every participant's agents start from identical evidence, whether or
not they completed Section 1. Nothing here touches a live tenant.

Tool names and return shapes mirror the real secops-soar MCP server
(https://google.github.io/mcp-security/servers/secops_soar_mcp.html) so
agent instructions written against this mock work unchanged against a real
SOAR instance.

Any case_id is accepted and resolves to the same seeded case.

Run:  python3 soar_mock.py        (SSE on 0.0.0.0:8005)
"""

import os
from datetime import datetime, timezone

from mcp.server.fastmcp import FastMCP

PORT = int(os.environ.get("SOAR_MOCK_PORT", "8005"))

mcp = FastMCP("secops-soar-mock", host="0.0.0.0", port=PORT)

CASE_ID = 1053
CASE_NAME = "Case 1053 - Critical Priority (workshop copy)"

# Comments seeded verbatim from a real Section 1 run, oldest first.
_COMMENTS = [
    {
        "id": 56001,
        "author": "Automation",
        "timestamp": "2026-04-13T11:41:58Z",
        "text": """TIN_INVESTIGATION:

Alert: GOOGLECHRONICLE_RULE_SHINYHUNTERS_POST_AUTH_MFA_MANIPULATION

Verdict: False Positive
Confidence: High Confidence

Summary:
The Okta account for user s.hudson was flagged for potential post-vishing
account takeover (ShinyHunters style). The activity involved a series of
failed login attempts from IP 149.50.97.144 followed by a successful
authentication and the immediate activation of a new Okta MFA factor
(Passkey) using an Android emulator environment.

Analysis of the indicator 149.50.97.144 confirms a suspicious verdict.
Broad SIEM searches targeting the specific Android emulator user agent
('com.okta.android.auth/8.19.0 okta-sdk-kotlin/2.3.0 Android/16
Genymobile/Phone') and the source IP 149.50.97.144 across the surrounding
six-day period confirmed the malicious activity was highly localized and
isolated to the compromised account of s.hudson. No evidence of lateral
movement or targeting of other internal accounts by this actor was
identified.

Status: STATUS_COMPLETED_SUCCESS""",
    },
    {
        "id": 56002,
        "author": "Automation",
        "timestamp": "2026-04-13T11:50:58Z",
        "text": """GEMINI_FINDINGS:

Source: Gemini interactive investigation, analyst-initiated
Query: All Salesforce events from 149.50.97.144 within the past month

Salesforce Exfiltration Discovered:
- Document searches by s.hudson (attacker session) at 11:03-11:05 UTC
  Search keywords: confidential, internal, trading strategy, portfolio, proposal
- 7 documents downloaded 11:08:03-11:08:25 UTC
  User agent: python-requests/2.31.0 (scripted bulk download, not a browser)

  Files:
    Q4_Investment_Report_Confidential.pdf
    Client_Portfolio_2026_Internal.xlsx
    Trading_Strategy_Confidential_2026.docx
    Board_Deck_Internal_Jan2026.pptx
    M&A_Proposal_Confidential_Draft.pdf
    Investor_Relations_Q4_Confidential.pdf
    Fund_Performance_Internal_YTD.xlsx

- POST to Salesforce Aura endpoint at 11:20 UTC (likely data staging)

Assessment: Automated bulk exfiltration of financial and M&A documents.
Regulatory exposure: SEC Rule 17a-4 (trading records), SOX (financial
records), MNPI.""",
    },
    {
        "id": 56003,
        "author": "Automation",
        "timestamp": "2026-04-13T11:51:47Z",
        "text": """EVIDENCE ASSESSMENT

Verdict assessment: revise
Recommended priority: Critical
Evidence sufficiency: partial
Ready to escalate: True

WHY
The initial automated triage verdict of 'False Positive' was based solely
on the Okta activity and a lack of lateral movement within the identity
provider. Subsequent investigation, documented in the 'GEMINI_FINDINGS'
comment, revealed confirmed data exfiltration from Salesforce. This
included searches for sensitive keywords and the download of seven
confidential financial and M&A documents. This direct evidence of data
loss and regulatory exposure supersedes the initial assessment.

OPEN QUESTIONS - not answerable from the SIEM
1. What is the current status of the Passkey MFA factor for s.hudson's
   Okta account, and have all active sessions originating from
   149.50.97.144 been terminated?
Needs: Okta
Why: To ensure immediate revocation of the attacker's access and prevent
any further use of the compromised MFA factor or existing sessions.

2. Is there any evidence of malicious activity on CYMBAL-LT-HUDSON that
   facilitated the initial credential compromise or provided persistent
   access?
Needs: CrowdStrike
Why: Determining the initial compromise vector and endpoint status is
crucial for remediating compromised assets and understanding whether the
attacker has a broader foothold.

3. Within Salesforce, did the attacker perform any actions beyond
   searching and downloading documents, such as modifying records,
   authorizing connected applications, or accessing other objects?
Needs: Salesforce
Why: This determines the full extent of data loss and whether any
persistent access mechanism was established inside the CRM itself.

4. What cloud resources could the compromised s.hudson identity reach
   through its federated access, and is there evidence the attacker used
   that path?
Needs: Wiz
Why: Federated identity extends the blast radius beyond SaaS. Standing
exposure must be assessed even where no cloud activity occurred.""",
    },
    {
        "id": 56004,
        "author": "Automation",
        "timestamp": "2026-04-13T11:53:24Z",
        "text": """ESCALATED TO TIER 2

Escalation approved by the analyst. The case-level assessment reviewed the
full case wall, including findings added after the initial triage ran, and
recommended Critical priority.

Open questions remain that cannot be answered from SIEM telemetry. They
require live platform access. See the EVIDENCE ASSESSMENT comment above
for the full list and the reasoning behind each one.""",
    },
]

_CASE = {
    "id": CASE_ID,
    "identifier": f"SEC-{CASE_ID}",
    "name": CASE_NAME,
    "description": "Workshop copy. Agent writes do not reach a live tenant.",
    "priority": "Critical",
    "status": "In Progress",
    "stage": "Incident",
    "assignedUser": "@Tier2",
    "creationTime": "2026-04-13T11:23:29Z",
    "modificationTime": "2026-04-13T11:53:24Z",
    "alerts": [
        {
            "id": 34801,
            "name": "GOOGLECHRONICLE_RULE_SHINYHUNTERS_POST_AUTH_MFA_MANIPULATION",
            "severity": "Medium",
            "riskScore": 75,
            "count": 6,
            "creationTime": "2026-04-13T11:24:00Z",
        }
    ],
    "entities": [
        {"identifier": "149.50.97.144", "entityType": "IP Address", "isSuspicious": True},
        {
            "identifier": "S.HUDSON@CYMBAL-INVESTMENTS.COM",
            "entityType": "User",
            "isSuspicious": False,
        },
        {"identifier": "CYMBAL-LT-HUDSON", "entityType": "Hostname", "isSuspicious": False},
    ],
    "tags": ["shinyhunters", "account-takeover", "data-exfiltration"],
}

_NEXT_ID = [56100]


def _prefix(text: str) -> str:
    """First token of the first line, used as the upsert key."""
    stripped = text.strip()
    if not stripped:
        return ""
    first = stripped.splitlines()[0].strip()
    return first.split()[0].rstrip(":").upper() if first else ""


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


@mcp.tool()
def list_cases() -> list[dict]:
    """List available cases in the SOAR platform.

    Returns each case with its ID, name, priority, status and assignee. Use
    get_case_full_details to read a specific case and its comments.
    """
    return [
        {
            "id": _CASE["id"],
            "identifier": _CASE["identifier"],
            "name": _CASE["name"],
            "description": _CASE["description"],
            "priority": _CASE["priority"],
            "status": _CASE["status"],
            "assignedUser": _CASE["assignedUser"],
            "creationTime": _CASE["creationTime"],
        }
    ]


@mcp.tool()
def get_case_full_details(case_id: str) -> dict:
    """Retrieve full details for a single case: metadata, alerts, entities
    and every comment on the case wall, oldest first.

    Read every comment before drawing conclusions. Earlier comments hold
    the triage findings and the open questions this investigation exists to
    answer.

    Args:
        case_id: The ID of the case, for example "1053".
    """
    case = dict(_CASE)
    case["comments"] = [dict(c) for c in _COMMENTS]
    return case


@mcp.tool()
def post_case_comment(case_id: str, comment: str) -> dict:
    """Add a comment to a case wall.

    Start the comment with an uppercase prefix naming what it is, for
    example "IDENTITY_FINDINGS:" or "INCIDENT_REPORT:". Posting again with
    the same prefix replaces the earlier comment rather than duplicating
    it, so a rerun stays clean.

    Args:
        case_id: The ID of the case, for example "1053".
        comment: The full comment text.
    """
    key = _prefix(comment)
    timestamp = _now()

    for existing in _COMMENTS:
        if key and existing["author"] == "agent" and _prefix(existing["text"]) == key:
            existing["text"] = comment
            existing["timestamp"] = timestamp
            return {
                "success": True,
                "comment_id": existing["id"],
                "timestamp": timestamp,
                "author": existing["author"],
                "replaced": True,
            }

    _NEXT_ID[0] += 1
    entry = {
        "id": _NEXT_ID[0],
        "author": "agent",
        "timestamp": timestamp,
        "text": comment,
    }
    _COMMENTS.append(entry)
    return {
        "success": True,
        "comment_id": entry["id"],
        "timestamp": timestamp,
        "author": "agent",
        "replaced": False,
    }


@mcp.tool()
def change_case_priority(case_id: str, case_priority: str) -> dict:
    """Change the priority of a case.

    Args:
        case_id: The ID of the case, for example "1053".
        case_priority: One of PriorityInfo, PriorityLow, PriorityMedium,
            PriorityHigh, PriorityCritical.
    """
    allowed = {
        "PriorityInfo": "Informative",
        "PriorityLow": "Low",
        "PriorityMedium": "Medium",
        "PriorityHigh": "High",
        "PriorityCritical": "Critical",
    }
    if case_priority not in allowed:
        return {
            "success": False,
            "error": f"Invalid priority. Use one of: {', '.join(allowed)}",
        }
    previous = _CASE["priority"]
    _CASE["priority"] = allowed[case_priority]
    return {
        "success": True,
        "case_id": _CASE["id"],
        "previous_priority": previous,
        "new_priority": _CASE["priority"],
        "timestamp": _now(),
    }


if __name__ == "__main__":
    mcp.run(transport="sse")
