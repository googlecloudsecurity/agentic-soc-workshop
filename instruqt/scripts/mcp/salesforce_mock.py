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
_EVENTS = _seed["events"]
_DOCS = _seed["documents"]
_DOCS_NOTE = _seed["documents_note"]
_APPS = _seed["connected_apps"]
_MODS = _seed["record_modifications"]
_MODS_NOTE = _seed["record_modifications_note"]

mcp = FastMCP("salesforce-event-monitoring", host="0.0.0.0", port=PORT)


@mcp.tool()
def search_event_log(source_ip: str = "", event_type: str = "") -> dict:
    """Search the Salesforce Shield event log for this user.

    Repeated events of the same kind are returned as one row with a time
    range and a count. Event types present: Login,
    ConnectedAppAuthorization, LightningPageView, ContentDocumentLink,
    ApiEvent.

    Args:
        source_ip: Filter to one source IP address.
        event_type: Filter to one event type.
    """
    rows = _EVENTS
    if source_ip:
        rows = [r for r in rows if r.get("source_ip") == source_ip]
    if event_type:
        rows = [r for r in rows if r.get("event_type", "").lower() == event_type.lower()]
    return {"user": _ORG["victim"], "count": len(rows), "events": rows}


@mcp.tool()
def list_connected_apps() -> dict:
    """List OAuth connected apps authorized for this user, with who
    authorized each, from what IP, and whether the refresh token is valid.

    A connected app authorized during an attacker session is a persistence
    mechanism. Its refresh token survives session revocation and password
    resets, so revoking the app is a separate containment action from
    terminating sessions in the identity provider.
    """
    return {"count": len(_APPS), "connected_apps": _APPS}


@mcp.tool()
def get_record_modifications(user: str = "") -> dict:
    """List create, update and delete operations on Salesforce records
    during the incident window.

    Establishes whether an incident involved data integrity impact or was
    read-only theft. The two require different notification and recovery
    decisions.

    Args:
        user: Optional. The username or email to check.
    """
    return {
        "user": user or _ORG["victim"],
        "count": len(_MODS),
        "modifications": _MODS,
        "note": _MODS_NOTE,
    }


@mcp.tool()
def get_document_access() -> dict:
    """List the documents accessed or downloaded, with their timestamps and
    file types.

    The user agent and auth method for these downloads are in the note.
    A script pulling files in bulk on an OAuth token is a different event
    from a person reading a document in a browser session.
    """
    return {
        "count": len(_DOCS),
        "documents": _DOCS,
        "note": _DOCS_NOTE,
        "classification": _ORG["classification_note"],
    }


if __name__ == "__main__":
    mcp.run(transport="sse")
