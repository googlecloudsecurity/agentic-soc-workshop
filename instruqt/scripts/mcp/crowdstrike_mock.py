#!/usr/bin/env python3
"""Mock CrowdStrike Falcon MCP server for the Agentic SOC Workshop.

Answers the endpoint open question from the Operation Shiny Hunter case:
did anything malicious run on CYMBAL-LT-HUDSON, and is the host contained?

The answer is no, and that is the finding. The compromise was
session-based: the attacker relayed credentials and MFA in real time and
worked entirely from their own infrastructure. The endpoint was never
touched, so EDR was never going to catch it. Ruling that out closes an
entire remediation track.

The only detection in the environment is a low-severity DNS resolution on a
different host three days earlier, which is where the phishing infrastructure
first shows up.

Scenario data lives in crowdstrike_seed.json next to this file.

Run:  python3 crowdstrike_mock.py  (SSE on 0.0.0.0:8002)

Env:
  CROWDSTRIKE_MOCK_PORT   listen port, default 8002
  CROWDSTRIKE_MOCK_SEED   path to the seed file
"""

import json
import os
from pathlib import Path

try:
    from mcp.server.fastmcp import FastMCP
except ImportError:
    from fastmcp import FastMCP

PORT = int(os.environ.get("CROWDSTRIKE_MOCK_PORT", "8002"))
SEED_PATH = Path(
    os.environ.get(
        "CROWDSTRIKE_MOCK_SEED", Path(__file__).parent / "crowdstrike_seed.json"
    )
)

_seed = json.loads(SEED_PATH.read_text(encoding="utf-8"))
_HOSTS = _seed["hosts"]
_DETECTIONS = _seed["detections"]
_TREES = _seed["process_trees"]
_NO_DET_NOTE = _seed["no_detections_note"]

mcp = FastMCP("crowdstrike-edr", host="0.0.0.0", port=PORT)


@mcp.tool()
def list_detections(hostname: str = "", severity: str = "", username: str = "") -> dict:
    """List CrowdStrike endpoint detections, optionally filtered.

    An empty result for a host is a finding, not a failed query. It rules
    out endpoint-based compromise and points the investigation elsewhere.

    Args:
        hostname: Filter to one host.
        severity: Filter to Critical, High, Medium, Low or Informational.
        username: Filter to one username or email.
    """
    rows = _DETECTIONS
    if hostname:
        rows = [d for d in rows if hostname.upper() in d.get("hostname", "").upper()]
    if severity:
        rows = [d for d in rows if d.get("severity", "").lower() == severity.lower()]
    if username:
        rows = [
            d
            for d in rows
            if username.lower() in d.get("username", "").lower()
            or username.lower() in d.get("user_email", "").lower()
        ]
    result = {"total": len(rows), "detections": rows}
    if not rows:
        result["note"] = _NO_DET_NOTE
    return result


@mcp.tool()
def get_detection_details(detection_id: str) -> dict:
    """Get full details for one detection, including the process that
    triggered it and whether the pattern was blocked or detected only.

    Args:
        detection_id: The detection ID from list_detections.
    """
    for d in _DETECTIONS:
        if d.get("detection_id") == detection_id:
            return d
    return {
        "error": f"Detection {detection_id} not found",
        "available_detection_ids": [d["detection_id"] for d in _DETECTIONS],
    }


@mcp.tool()
def get_host_info(hostname: str) -> dict:
    """Get host details: platform, OS, assigned user, sensor health,
    containment status and observed IP addresses.

    Containment status answers whether anyone has acted. Sensor health
    answers whether an empty detection list is trustworthy.

    Args:
        hostname: The hostname, for example CYMBAL-LT-HUDSON.
    """
    host = _HOSTS.get(hostname.upper()) or next(
        (v for k, v in _HOSTS.items() if k.upper() == hostname.upper()), None
    )
    if not host:
        return {
            "error": f"Host {hostname} not found",
            "available_hosts": list(_HOSTS.keys()),
        }
    return host


@mcp.tool()
def get_process_tree(hostname: str) -> dict:
    """Get the process execution tree for a host during the incident window.

    Look for scripting interpreters, browser automation flags, binaries
    dropped to temporary directories, and anything spawned by a browser.
    Their absence is as informative as their presence.

    Args:
        hostname: The hostname, for example CYMBAL-LT-HUDSON.
    """
    tree = _TREES.get(hostname.upper()) or next(
        (v for k, v in _TREES.items() if k.upper() == hostname.upper()), None
    )
    if not tree:
        return {
            "error": f"No process tree recorded for {hostname}",
            "available_hosts": list(_TREES.keys()),
        }
    return tree


if __name__ == "__main__":
    mcp.run(transport="sse")
