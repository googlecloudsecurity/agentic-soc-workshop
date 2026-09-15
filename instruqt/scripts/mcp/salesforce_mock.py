#!/usr/bin/env python3
"""Mock Salesforce Event Monitoring MCP server for the Agentic SOC Workshop.

Answers the Salesforce open question from the Operation Shiny Hunter case:
what did the attacker do inside the CRM beyond searching and downloading
documents?

Shaped after Salesforce Shield Event Monitoring, which is how a real SOC
would query this: an event log of Login, ContentDocument, ApiEvent and
LightningPageView records, plus connected app and record-change views.

Run:  python3 salesforce_mock.py   (SSE on 0.0.0.0:8004)
"""

import os

from mcp.server.fastmcp import FastMCP

PORT = int(os.environ.get("SALESFORCE_MOCK_PORT", "8004"))

mcp = FastMCP("salesforce-event-monitoring", host="0.0.0.0", port=PORT)

ATTACKER_IP = "149.50.97.144"
LEGIT_IP = "96.6.127.53"
VICTIM = "s.hudson@cymbal-investments.com"
VICTIM_ID = "005hudson0000001"

SCRIPTED_UA = "python-requests/2.31.0"
BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/133.0.0.0 Safari/537.36"

DOCUMENTS = [
    ("069hudson-doc-001", "Q4_Investment_Report_Confidential.pdf", "pdf", "11:08:03"),
    ("069hudson-doc-002", "Client_Portfolio_2026_Internal.xlsx", "xlsx", "11:08:07"),
    ("069hudson-doc-003", "Trading_Strategy_Confidential_2026.docx", "docx", "11:08:11"),
    ("069hudson-doc-004", "Board_Deck_Internal_Jan2026.pptx", "pptx", "11:08:14"),
    ("069hudson-doc-005", "M&A_Proposal_Confidential_Draft.pdf", "pdf", "11:08:18"),
    ("069hudson-doc-006", "Investor_Relations_Q4_Confidential.pdf", "pdf", "11:08:21"),
    ("069hudson-doc-007", "Fund_Performance_Internal_YTD.xlsx", "xlsx", "11:08:25"),
]

SEARCH_TERMS = [
    ("11:03:12", "confidential"),
    ("11:03:48", "internal"),
    ("11:04:21", "trading strategy"),
    ("11:04:55", "portfolio"),
    ("11:05:19", "proposal"),
]


def _events() -> list[dict]:
    rows: list[dict] = []

    rows.append(
        {
            "timestamp": "2026-04-13T10:54:08Z",
            "event_type": "Login",
            "user": VICTIM,
            "user_id": VICTIM_ID,
            "source_ip": ATTACKER_IP,
            "user_agent": BROWSER_UA,
            "login_type": "SAML Sso",
            "status": "Success",
            "session_id": "sfdc-attacker-001",
            "detail": "Federated login via Okta SSO",
        }
    )
    rows.append(
        {
            "timestamp": "2026-04-13T10:54:41Z",
            "event_type": "ConnectedAppAuthorization",
            "user": VICTIM,
            "user_id": VICTIM_ID,
            "source_ip": ATTACKER_IP,
            "user_agent": BROWSER_UA,
            "app_name": "Cymbal Data Sync",
            "consumer_key": "3MVG9n_HvETGhr3B_cymbaldatasync",
            "scopes": ["api", "refresh_token", "offline_access"],
            "status": "Success",
            "detail": (
                "First authorization of this connected app for this user. "
                "Refresh token issued, valid until revoked."
            ),
        }
    )

    for ts, term in SEARCH_TERMS:
        rows.append(
            {
                "timestamp": f"2026-04-13T{ts}Z",
                "event_type": "LightningPageView",
                "user": VICTIM,
                "user_id": VICTIM_ID,
                "source_ip": ATTACKER_IP,
                "user_agent": BROWSER_UA,
                "page": "Search Results",
                "search_term": term,
                "session_id": "sfdc-attacker-001",
            }
        )

    for doc_id, title, filetype, ts in DOCUMENTS:
        rows.append(
            {
                "timestamp": f"2026-04-13T{ts}Z",
                "event_type": "ContentDocumentLink",
                "operation": "Download",
                "user": VICTIM,
                "user_id": VICTIM_ID,
                "source_ip": ATTACKER_IP,
                "user_agent": SCRIPTED_UA,
                "document_id": doc_id,
                "document_title": title,
                "file_type": filetype,
                "auth_method": "OAuth refresh token (Cymbal Data Sync)",
            }
        )

    rows.append(
        {
            "timestamp": "2026-04-13T11:20:14Z",
            "event_type": "ApiEvent",
            "operation": "POST",
            "user": VICTIM,
            "user_id": VICTIM_ID,
            "source_ip": ATTACKER_IP,
            "user_agent": SCRIPTED_UA,
            "endpoint": "/aura?r=1&aura.ApexAction.execute",
            "objects_queried": ["Account", "Contact"],
            "rows_returned": 301,
            "detail": (
                "Bulk record retrieval through the Aura Apex action endpoint. "
                "Returned 301 Account and Contact records including client "
                "names, account values and primary contact email addresses."
            ),
        }
    )

    rows.append(
        {
            "timestamp": "2026-04-13T09:12:33Z",
            "event_type": "Login",
            "user": VICTIM,
            "user_id": VICTIM_ID,
            "source_ip": LEGIT_IP,
            "user_agent": BROWSER_UA,
            "login_type": "SAML Sso",
            "status": "Success",
            "session_id": "sfdc-hudson-legit-044",
            "detail": "Routine login, corporate VPN egress",
        }
    )

    return sorted(rows, key=lambda r: r["timestamp"])


_EVENTS = _events()


@mcp.tool()
def search_event_log(
    source_ip: str = "",
    user: str = "",
    event_type: str = "",
) -> dict:
    """Search the Salesforce Shield event log.

    Every argument is an optional filter. Omit them all to return the full
    log. Event types present in this org: Login, ConnectedAppAuthorization,
    LightningPageView, ContentDocumentLink, ApiEvent.

    Args:
        source_ip: Filter to one source IP address.
        user: Filter to one username or email.
        event_type: Filter to one event type.
    """
    rows = _EVENTS
    if source_ip:
        rows = [r for r in rows if r.get("source_ip") == source_ip]
    if user:
        rows = [r for r in rows if user.lower() in r.get("user", "").lower()]
    if event_type:
        rows = [r for r in rows if r.get("event_type", "").lower() == event_type.lower()]
    return {"count": len(rows), "events": rows}


@mcp.tool()
def list_connected_apps(user: str = "") -> dict:
    """List OAuth connected apps authorized in this Salesforce org, with the
    user who authorized each one and whether its refresh token is still
    valid.

    A connected app authorized during an attacker session is a persistence
    mechanism. Its refresh token survives session revocation and password
    resets, so revoking the app is a separate containment action from
    terminating sessions in the identity provider.

    Args:
        user: Optional. Filter to apps authorized by one user.
    """
    apps = [
        {
            "app_name": "Cymbal Data Sync",
            "consumer_key": "3MVG9n_HvETGhr3B_cymbaldatasync",
            "authorized_by": VICTIM,
            "authorized_at": "2026-04-13T10:54:41Z",
            "authorized_from_ip": ATTACKER_IP,
            "scopes": ["api", "refresh_token", "offline_access"],
            "refresh_token_status": "VALID",
            "last_used": "2026-04-13T11:20:14Z",
            "publisher": "Unverified",
            "note": (
                "Not present in the Cymbal approved application inventory. "
                "First and only authorization is from the attacker IP."
            ),
        },
        {
            "app_name": "Salesforce for Outlook",
            "consumer_key": "3MVG9n_HvETGhr3B_sfdcoutlook",
            "authorized_by": VICTIM,
            "authorized_at": "2025-11-02T14:08:12Z",
            "authorized_from_ip": LEGIT_IP,
            "scopes": ["api", "refresh_token"],
            "refresh_token_status": "VALID",
            "last_used": "2026-04-13T08:44:02Z",
            "publisher": "Salesforce",
            "note": "Standard corporate deployment.",
        },
    ]
    if user:
        apps = [a for a in apps if user.lower() in a["authorized_by"].lower()]
    return {"count": len(apps), "connected_apps": apps}


@mcp.tool()
def get_record_modifications(user: str, since: str = "2026-04-13T00:00:00Z") -> dict:
    """List create, update and delete operations on Salesforce records by a
    user since a given time.

    Use this to establish whether an incident involved data integrity
    impact or was read-only theft. The two require different notification
    and recovery decisions.

    Args:
        user: The username or email to check.
        since: ISO 8601 timestamp. Defaults to the start of 2026-04-13.
    """
    return {
        "user": user,
        "since": since,
        "count": 0,
        "modifications": [],
        "note": (
            "No create, update or delete operations recorded for this user in "
            "the window. All observed activity was read and export only."
        ),
    }


@mcp.tool()
def get_document_access(document_id: str = "", user: str = "") -> dict:
    """Show which documents were accessed or downloaded, by whom, and with
    what client.

    The user agent distinguishes a person reading a document in a browser
    from a script pulling files in bulk.

    Args:
        document_id: Optional. Filter to one ContentDocument ID.
        user: Optional. Filter to one username or email.
    """
    rows = [r for r in _EVENTS if r.get("event_type") == "ContentDocumentLink"]
    if document_id:
        rows = [r for r in rows if r.get("document_id") == document_id]
    if user:
        rows = [r for r in rows if user.lower() in r.get("user", "").lower()]
    return {
        "count": len(rows),
        "documents": rows,
        "classification_note": (
            "All seven documents carry Confidential or Internal classification "
            "labels in the Cymbal document taxonomy."
        ),
    }


if __name__ == "__main__":
    mcp.run(transport="sse")
