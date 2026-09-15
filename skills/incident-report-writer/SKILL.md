---
name: incident-report-writer
description: Structures and formats security incident reports for executive and technical audiences. Grounded on the CISA incident response playbooks and NIST SP 800-61.
metadata:
  author: agentic-soc-workshop
  version: "2.0"
  source: CISA Federal Government Cybersecurity Incident and Vulnerability Response Playbooks
---

# Incident report writing

CISA's incident response playbook structures response around the NIST SP
800-61 lifecycle: preparation, detection and analysis, containment,
eradication and recovery, and post-incident activity. Cymbal Investments is
not a federal agency, so the reporting obligations differ. The structure
does not.

Write the report in these sections, in this order.

## 1. Summary

Four to six sentences. What happened, to whom, when, and what was lost.
Written so an executive who reads nothing else comes away correct rather
than merely reassured.

State the incident status plainly: ongoing, contained, or eradicated. Do
not write "under investigation" if the evidence supports something
stronger.

## 2. Detection and analysis

How the incident was detected, and what the investigation established.

- The detection source and the time it fired
- The confirmed attack chain in order, with UTC timestamps
- The evidence supporting each step, and the platform it came from
- Where an earlier automated assessment was revised, and on what evidence

Attribute every claim to a source. "Okta shows the session was created at
10:52:14" beats "the attacker logged in". A reader must be able to tell
observed fact from inference.

## 3. Scope and impact

What the adversary reached, and what that means.

- Accounts, hosts, applications and data confirmed affected
- Data exfiltrated, named specifically, with its classification
- Systems and data reachable but not accessed, stated as such
- Regulatory exposure, naming the specific obligation

Keep confirmed impact and potential impact in separate subsections.
Conflating them is the most common failure in incident reporting, and it
drives both over-notification and under-notification.

## 4. Threat actor

- Actor name and aliases
- Assessed motivation
- MITRE ATT&CK technique IDs observed in this incident, with names
- Attribution confidence: high, moderate or low, with the reasoning

Attribution confidence is not optional. A named actor with no stated
confidence reads as fact when it is a judgement.

## 5. Containment status

What has been done, what is outstanding, and what is still exposed.

For each containment action: the action, whether it is complete, and who
performed it. For each outstanding item: what it is, why it matters, and
how urgent.

Call out persistence mechanisms individually. A revoked session does not
revoke an OAuth refresh token, and a report that treats "access revoked" as
one line hides that.

## 6. Recommended actions

Ordered by urgency, not by category. Each recommendation states the action,
the system it applies to, and what it prevents.

Separate immediate containment from eradication from longer-term hardening.
CISA treats these as distinct phases for a reason: hardening before
eradication is complete leaves the adversary inside while you tune
controls.

## 7. Evidence and indicators

A table of indicators: type, value, and where it was observed. IP
addresses, user agents, document names, application identifiers,
hostnames.

This section exists to be copied into a detection rule or a block list.
Keep it free of prose.

## 8. Gaps

What could not be determined, and what would be needed to determine it.

A report with no gaps section is either incomplete or dishonest. If every
question was answered, say so explicitly rather than omitting the section.

---

## Writing rules

**Cite the source for every finding.** Name the platform. A report the
reader cannot verify is a report the reader has to trust.

**Synthesise across sources rather than listing per platform.** A section
per tool is a filing system, not an analysis. Connect the identity evidence
to the SaaS evidence to the cloud exposure, and say what the connection
means.

**Never fabricate.** No invented IOCs, timestamps, technique IDs,
hostnames or record counts. If a detail is not in the evidence, it does not
go in the report.

**Say when something did not happen.** "No endpoint detections on
CYMBAL-LT-HUDSON" is a finding. It rules out an entire remediation track
and tells the reader the compromise was session-based.

**Use UTC throughout**, and write times in ISO 8601.

**Keep the summary free of jargon.** Everything below it can be technical.

**Post the report** to the SOAR case wall with a comment beginning
`INCIDENT_REPORT:`.

---

## Reference

CISA, Federal Government Cybersecurity Incident and Vulnerability Response
Playbooks (August 2024 revision).
https://www.cisa.gov/resources-tools/resources/federal-government-cybersecurity-incident-and-vulnerability-response-playbooks

NIST SP 800-61, Computer Security Incident Handling Guide.
