#!/usr/bin/env python3
"""Mock Okta MCP server for the Agentic SOC Workshop.

Answers the identity open question from the Operation Shiny Hunter case: is
the attacker's session still live, and is the rogue MFA factor still
enrolled?

The answer to both is yes. Section 1 confirmed what happened in the logs.
Nothing has been revoked, because nobody has done it yet.

Scenario data lives in okta_seed.json next to this file.

Run:  python3 okta_mock.py         (SSE on 0.0.0.0:8001)

Env:
  OKTA_MOCK_PORT   listen port, default 8001
  OKTA_MOCK_SEED   path to the seed file, default ./okta_seed.json
"""

import json
import os
from pathlib import Path

try:
    from mcp.server.fastmcp import FastMCP
except ImportError:
    from fastmcp import FastMCP

PORT = int(os.environ.get("OKTA_MOCK_PORT", "8001"))
SEED_PATH = Path(os.environ.get("OKTA_MOCK_SEED", Path(__file__).parent / "okta_seed.json"))

_seed = json.loads(SEED_PATH.read_text(encoding="utf-8"))
_USERS = _seed["users"]
_LOG = sorted(_seed["system_log"], key=lambda r: r["timestamp"])

mcp = FastMCP("okta-iam", host="0.0.0.0", port=PORT)


def _find(email: str):
    if not email:
        return None
    return _USERS.get(email) or next(
        (v for k, v in _USERS.items() if k.lower() == email.lower()), None
    )


def _not_found(email: str) -> dict:
    return {
        "error": f"User {email} not found in Okta",
        "available_users": list(_USERS.keys()),
    }


@mcp.tool()
def list_users(query: str = "") -> dict:
    """List Okta users, optionally filtered by name or email.

    Args:
        query: Optional substring to match against email or display name.
    """
    out = []
    for email, u in _USERS.items():
        profile = u.get("profile", {})
        if (
            not query
            or query.lower() in email.lower()
            or query.lower() in profile.get("displayName", "").lower()
        ):
            out.append(
                {
                    "email": email,
                    "id": u.get("id"),
                    "name": profile.get("displayName"),
                    "title": profile.get("title"),
                    "status": u.get("status"),
                    "lastLogin": u.get("lastLogin"),
                }
            )
    return {"total": len(out), "users": out}


@mcp.tool()
def get_user_profile(user_email: str) -> dict:
    """Get an Okta user profile: status, department, assigned applications,
    and when the password was last changed.

    Account status matters for containment. An ACTIVE account after a
    confirmed compromise means no containment action has been taken.

    Args:
        user_email: The user's email address.
    """
    user = _find(user_email)
    if not user:
        return _not_found(user_email)
    return {
        "email": user_email,
        "id": user.get("id"),
        "status": user.get("status"),
        "profile": user.get("profile", {}),
        "created": user.get("created"),
        "lastLogin": user.get("lastLogin"),
        "passwordChanged": user.get("passwordChanged"),
        "assigned_apps": user.get("assigned_apps", []),
        "note": user.get("note", ""),
    }


@mcp.tool()
def get_active_sessions(user_email: str) -> dict:
    """List active Okta sessions for a user, with source IP, ASN, location
    and whether each is flagged suspicious.

    A session created during an incident and never revoked is live access
    the attacker still holds. Check the expiry, not just the creation time.

    Args:
        user_email: The user's email address.
    """
    user = _find(user_email)
    if not user:
        return _not_found(user_email)
    sessions = user.get("active_sessions", [])
    suspicious = [s for s in sessions if s.get("suspicious")]
    return {
        "user": user_email,
        "total": len(sessions),
        "suspicious_count": len(suspicious),
        "sessions": sessions,
    }


@mcp.tool()
def get_enrolled_factors(user_email: str) -> dict:
    """List enrolled MFA factors for a user, with enrollment time, the IP it
    was enrolled from, device platform, and whether the device is an
    emulator.

    A factor enrolled from an untrusted IP during an incident is attacker
    persistence. It survives a password reset.

    Args:
        user_email: The user's email address.
    """
    user = _find(user_email)
    if not user:
        return _not_found(user_email)
    factors = user.get("enrolled_factors", [])
    suspicious = [f for f in factors if f.get("suspicious")]
    return {
        "user": user_email,
        "total": len(factors),
        "suspicious_count": len(suspicious),
        "factors": factors,
    }


@mcp.tool()
def search_system_log(
    source_ip: str = "",
    actor: str = "",
    event_type: str = "",
) -> dict:
    """Search the Okta system log.

    Every argument is an optional filter. Omit them all to return the full
    log. Event types present: user.session.start,
    user.mfa.factor.activate, user.authentication.sso.

    Args:
        source_ip: Filter to one source IP address.
        actor: Filter to one user email.
        event_type: Filter to one event type.
    """
    rows = _LOG
    if source_ip:
        rows = [r for r in rows if r.get("source_ip") == source_ip]
    if actor:
        rows = [r for r in rows if actor.lower() in r.get("actor", "").lower()]
    if event_type:
        rows = [r for r in rows if r.get("event_type", "").lower() == event_type.lower()]
    return {"count": len(rows), "events": rows}


if __name__ == "__main__":
    mcp.run(transport="sse")
