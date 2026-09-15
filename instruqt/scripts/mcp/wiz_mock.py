#!/usr/bin/env python3
"""Mock Wiz MCP server for the Agentic SOC Workshop.

Answers the cloud open question from the Operation Shiny Hunter case: what
could the compromised s.hudson identity reach in Google Cloud through its
federated access, and is there any sign the attacker used that path?

The honest answer here is a clean negative on usage plus real standing
exposure. That combination is the point. An identity that never touched
cloud during the incident can still represent a blast radius worth fixing
before the next one.

Scenario data lives in wiz_seed.json next to this file.

Run:  python3 wiz_mock.py          (SSE on 0.0.0.0:8003)

Env:
  WIZ_MOCK_PORT   listen port, default 8003
  WIZ_MOCK_SEED   path to the seed file, default ./wiz_seed.json
"""

import json
import os
from pathlib import Path

try:
    from mcp.server.fastmcp import FastMCP
except ImportError:
    from fastmcp import FastMCP

PORT = int(os.environ.get("WIZ_MOCK_PORT", "8003"))
SEED_PATH = Path(os.environ.get("WIZ_MOCK_SEED", Path(__file__).parent / "wiz_seed.json"))

_seed = json.loads(SEED_PATH.read_text(encoding="utf-8"))
_IDENTITY = _seed["identity"]
_PERMS = _seed["effective_permissions"]
_ISSUES = _seed["issues"]
_PATH = _seed["attack_path"]
_AUDIT = _seed["audit_logs"]

mcp = FastMCP("wiz-cloud-security", host="0.0.0.0", port=PORT)


@mcp.tool()
def get_cloud_identity(email: str) -> dict:
    """Look up a human identity in the cloud inventory and show how it
    federates in, what it is bound to, and how it has been used.

    Args:
        email: The corporate email address of the identity.
    """
    if email.lower() != _IDENTITY["email"].lower():
        return {"email": email, "found": False, "note": "Identity not in the cloud inventory."}
    return dict(_IDENTITY)


@mcp.tool()
def get_effective_permissions(email: str) -> dict:
    """Show what a federated identity can actually reach in Google Cloud
    once group membership and inherited bindings are resolved.

    Effective permissions differ from assigned roles. A role granted at the
    folder level applies to every project beneath it, which is how an
    identity ends up with far more reach than anyone intended.

    Args:
        email: The corporate email address of the identity.
    """
    if email.lower() != _IDENTITY["email"].lower():
        return {"email": email, "found": False, "bindings": []}
    result = {"email": _IDENTITY["email"]}
    result.update(_PERMS)
    return result


@mcp.tool()
def list_identity_issues(email: str = "") -> dict:
    """List open Wiz issues affecting an identity: excessive permissions,
    stale credentials, missing controls.

    Args:
        email: Optional. Filter to one identity.
    """
    issues = _ISSUES
    if email:
        issues = [i for i in issues if email.lower() in i["subject"].lower()]
    return {"count": len(issues), "issues": issues}


@mcp.tool()
def get_attack_path(email: str) -> dict:
    """Trace the attack path from a compromised identity to the most
    sensitive resource it could reach.

    An attack path is a chain, not a single finding. It shows what an
    attacker holding this identity could do next if they chose to.

    Args:
        email: The corporate email address of the compromised identity.
    """
    if email.lower() != _IDENTITY["email"].lower():
        return {"subject": email, "path_found": False, "steps": []}
    result = {"subject": _IDENTITY["email"]}
    result.update(_PATH)
    return result


@mcp.tool()
def search_cloud_audit_logs(source_ip: str = "", principal: str = "") -> dict:
    """Search Google Cloud audit logs for activity by IP or principal.

    Args:
        source_ip: Optional. Filter to one source IP address.
        principal: Optional. Filter to one principal or email.
    """
    return {
        "source_ip": source_ip,
        "principal": principal,
        "count": len(_AUDIT["entries"]),
        "entries": _AUDIT["entries"],
        "note": _AUDIT["note"],
    }


if __name__ == "__main__":
    mcp.run(transport="sse")
