#!/usr/bin/env python3
"""Mock Wiz MCP server for the Agentic SOC Workshop.

Answers the cloud open question from the Operation Shiny Hunter case: what
could the compromised s.hudson identity reach in Google Cloud through its
federated access, and is there any sign the attacker used that path?

The honest answer here is a clean negative on usage plus real standing
exposure. That combination is the point. An identity that never touched
cloud during the incident can still represent a blast radius worth fixing
before the next one.

Run:  python3 wiz_mock.py          (SSE on 0.0.0.0:8003)
"""

import os

from mcp.server.fastmcp import FastMCP

PORT = int(os.environ.get("WIZ_MOCK_PORT", "8003"))

mcp = FastMCP("wiz-cloud-security", host="0.0.0.0", port=PORT)

VICTIM = "s.hudson@cymbal-investments.com"
ATTACKER_IP = "149.50.97.144"


@mcp.tool()
def get_cloud_identity(email: str) -> dict:
    """Look up a human identity in the cloud inventory and show how it
    federates in, what it is bound to, and how it has been used.

    Args:
        email: The corporate email address of the identity.
    """
    return {
        "email": email,
        "federation": {
            "provider": "Okta",
            "workforce_pool": "cymbal-workforce",
            "provider_id": "okta-saml",
            "binding": "Workforce Identity Federation to Google Cloud",
        },
        "principal": f"principal://iam.googleapis.com/locations/global/workforcePools/cymbal-workforce/subject/{email}",
        "groups": ["investment-operations", "reporting-readers"],
        "last_cloud_activity": "2026-02-19T16:22:04Z",
        "cloud_activity_during_incident": None,
        "note": (
            "No Google Cloud API activity recorded for this identity on "
            "2026-04-13. The federated path exists but was not exercised "
            "during the incident window."
        ),
    }


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
    return {
        "email": email,
        "bindings": [
            {
                "role": "roles/storage.objectViewer",
                "resource": "folders/cymbal-investment-ops",
                "granted_via": "group:investment-operations",
                "inherited_by_projects": [
                    "cymbal-invops-prod",
                    "cymbal-invops-analytics",
                    "cymbal-invops-archive",
                ],
                "note": "Folder-level grant. Applies to every bucket in three projects.",
            },
            {
                "role": "roles/bigquery.dataViewer",
                "resource": "projects/cymbal-invops-analytics",
                "granted_via": "group:reporting-readers",
                "datasets_in_scope": ["client_holdings", "trade_history", "fund_performance"],
            },
        ],
        "reachable_resources": {
            "storage_buckets": 14,
            "bigquery_datasets": 3,
            "objects_estimated": 412000,
        },
        "assessment": (
            "This identity has read access to client holdings and trade history "
            "in BigQuery and to every Cloud Storage bucket under the Investment "
            "Operations folder. None of it was accessed during the incident."
        ),
    }


@mcp.tool()
def list_identity_issues(email: str = "") -> dict:
    """List open Wiz issues affecting an identity: excessive permissions,
    stale credentials, missing controls.

    Args:
        email: Optional. Filter to one identity.
    """
    issues = [
        {
            "id": "WIZ-4471",
            "severity": "HIGH",
            "title": "Federated identity has folder-level storage read across production data",
            "subject": VICTIM,
            "detail": (
                "roles/storage.objectViewer granted at folders/cymbal-investment-ops "
                "via group:investment-operations. Scope exceeds the buckets this "
                "role is used against."
            ),
            "first_seen": "2025-08-14T00:00:00Z",
            "status": "OPEN",
        },
        {
            "id": "WIZ-4488",
            "severity": "MEDIUM",
            "title": "Service account key unused for over 180 days",
            "subject": "invops-report-runner@cymbal-invops-prod.iam.gserviceaccount.com",
            "detail": (
                "Key created 2025-06-02, last used 2025-09-30. The service account "
                "is impersonable by group:investment-operations."
            ),
            "first_seen": "2026-03-30T00:00:00Z",
            "status": "OPEN",
        },
        {
            "id": "WIZ-4502",
            "severity": "MEDIUM",
            "title": "Workforce pool provider has no session duration limit",
            "subject": "workforcePools/cymbal-workforce/providers/okta-saml",
            "detail": (
                "Sessions established through this provider inherit the default "
                "duration. A compromised identity provider session remains usable "
                "in Google Cloud for longer than necessary."
            ),
            "first_seen": "2026-01-11T00:00:00Z",
            "status": "OPEN",
        },
    ]
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
    return {
        "subject": email,
        "path_found": True,
        "exercised_during_incident": False,
        "steps": [
            {
                "step": 1,
                "description": "Okta session assumed via Workforce Identity Federation",
                "resource": "workforcePools/cymbal-workforce",
            },
            {
                "step": 2,
                "description": "Group membership grants folder-level storage read",
                "resource": "folders/cymbal-investment-ops",
            },
            {
                "step": 3,
                "description": "Impersonate service account reachable from that group",
                "resource": "invops-report-runner@cymbal-invops-prod.iam.gserviceaccount.com",
            },
            {
                "step": 4,
                "description": "Service account holds BigQuery read on client holdings",
                "resource": "projects/cymbal-invops-analytics/datasets/client_holdings",
            },
        ],
        "assessment": (
            "A four-step path exists from the compromised identity to client "
            "holdings data in BigQuery. Cloud audit logs show no activity from "
            "this identity on 2026-04-13, so the path was available but not "
            "taken. It remains open."
        ),
    }


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
        "count": 0,
        "entries": [],
        "note": (
            f"No Google Cloud audit log entries match. The attacker IP "
            f"{ATTACKER_IP} does not appear in cloud audit logs at any point."
        ),
    }


if __name__ == "__main__":
    mcp.run(transport="sse")
