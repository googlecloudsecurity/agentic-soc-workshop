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

Scenario data lives in soar_seed.json next to this file. Comments agents
post are held in memory only, so a restart returns the wall to its seeded
state.

Run:  python3 soar_mock.py        (SSE on 0.0.0.0:8005)

Env:
  SOAR_MOCK_PORT   listen port, default 8005
  SOAR_MOCK_SEED   path to the seed file, default ./soar_seed.json
"""

import copy
import json
import os
from datetime import datetime, timezone
from pathlib import Path

# The v2 track ran mocks under mcp-env with google-adk 1.x, where
# mcp.server.fastmcp exists. MCP Python SDK 2.0 removed that module, and the
# v3 adk-env pins fastmcp 3.x separately. Try both so the mock runs under
# either environment.
try:
    from mcp.server.fastmcp import FastMCP
except ImportError:
    from fastmcp import FastMCP

PORT = int(os.environ.get("SOAR_MOCK_PORT", "8005"))
SEED_PATH = Path(
    os.environ.get("SOAR_MOCK_SEED", Path(__file__).parent / "soar_seed.json")
)

_seed = json.loads(SEED_PATH.read_text(encoding="utf-8"))
_CASE = copy.deepcopy(_seed["case"])
_COMMENTS = copy.deepcopy(_seed["comments"])
_NEXT_ID = [max((c["id"] for c in _COMMENTS), default=56000) + 100]

mcp = FastMCP("secops-soar-mock", host="0.0.0.0", port=PORT)


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
