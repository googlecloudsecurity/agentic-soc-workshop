#!/usr/bin/env python3
"""Mock Salesforce Event Monitoring MCP server for the Agentic SOC Workshop.

Answers the Salesforce open question from the Operation Shiny Hunter case:
what did the attacker do inside the CRM beyond searching and downloading
documents?

Shaped after Salesforce Shield Event Monitoring, which is how a real SOC
would query this: an event log of Login, ConnectedAppAuthorization,
LightningPageView, ContentDocumentLink and ApiEvent records, plus connected
app and record-change views.

Scenario data lives in salesforce_seed.json next to this file.

Run:  python3 salesforce_mock.py   (SSE on 0.0.0.0:8004)

Env:
  SALESFORCE_MOCK_PORT   listen port, default 8004
  SALESFORCE_MOCK_SEED   path to the seed file, default ./salesforce_seed.json
"""

import json
import os
from pathlib import Path

try:
    from mcp.server.fastmcp import FastMCP
except ImportError:
    from fastmcp import FastMCP

PORT = int(os.environ.get("SALESFORCE_MOCK_PORT", "8004"))
SEED_PATH = Path(
    os.environ.get(
        "SALESFORCE_MOCK_SEED", Path(__file__).parent / "salesforce_seed.json"
    )
)

_seed = json.loads(SEED_PATH.read_text(encoding="utf-8"))
_ORG = _seed["org"]
_EVENTS = sorted(_seed["events"], key=lambda r: r["timestamp"])
_APPS = _seed["connected_apps"]
_MODS = _seed["record_modifications"]
_MODS_NOTE = _seed["record_modifications_note"]

mcp = FastMCP("salesforce-event-monitoring", host="0.0.0.0", port=PORT)


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
    apps = _APPS
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
    rows = [m for m in _MODS if user.lower() in m.get("user", "").lower()]
    return {
        "user": user,
        "since": since,
        "count": len(rows),
        "modifications": rows,
        "note": _MODS_NOTE if not rows else "",
    }


@mcp.tool()
def get_document_access(document_id: str = "", user: str = "") -> dict:
    """Show which documents were accessed or downloaded, by whom, and with
    what client.

    The user agent distinguishes a person reading a document in a browser
    from a script pulling files in bulk. The auth method distinguishes a
    logged-in session from an OAuth token.

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
        "classification_note": _ORG["classification_note"],
    }


if __name__ == "__main__":
    mcp.run(transport="sse")
