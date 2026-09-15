# Section 1 · Challenge 5: Detection Engineering Agent

| | |
|---|---|
| **Time** | 10 minutes |
| **Platform** | Google SecOps, Detection Engineering agent |
| **Goal** | Understand how detection coverage gets built and validated, and why this agent works differently from every other one in Section 1 |

---

## Where we left off

The case is with Tier 2 and four questions are open. Before you build the
team that answers them, there is one more thing this incident should have
produced.

Go back to Challenge 3 for a moment. The campaign entry listed curated
rules mapped to UNC6661, and some of them were disabled. Nobody turned them
on, and nobody knew, because a rule that is off never produces an alert to
tell you it is off.

That is a coverage gap. This challenge is about the agent whose whole job
is finding and closing them.

---

## Reading, not clicking

This one is background. The Detection Engineering agent is not wired into
this sandbox, and there is a good reason for that which turns out to be the
most interesting thing about it.

Every agent you have met so far lives inside the product. The Triage agent
runs on an alert in the SIEM. Gemini answers in a panel. The playbook runs
Vertex AI inside SOAR.

The Detection Engineering agent does not work that way. It is exposed as a
set of **Model Context Protocol (MCP) tools**, operated by a compatible AI
client such as Google Antigravity or Claude Code. You do not open a page in
SecOps and click a button. You connect a client to the Google SecOps MCP
server and work with the agent from there.

> **That is the bridge to Section 2.** An MCP server exposing security
> tooling, driven by an agent you configure, is exactly what you are about
> to build. The difference is that you will be writing the client, and here
> Google wrote the server.

---

## What it does

The agent closes the loop between intelligence and detection.

**Threat intelligence extraction.** It reads CTI reports and emerging threat
advisories and extracts granular behavioural procedures and tactics from
them, turning prose into structured **Threat Detection Opportunities**
(TDOs). That is the step that normally takes a detection engineer an
afternoon of reading.

**Rule authoring.** From those TDOs it drafts **YARA-L 2.0** detection
rules, the same language the Threat Hunt agent uses for queries and the
same language your curated rules are written in.

**Event simulation.** This is the part with no manual equivalent. An
embedded simulation harness generates synthetic, schema-valid UDM events
reflecting the exact adversary procedures, and pushes them through your
live ingestion pipeline. The rule is validated end to end, from
normalisation through to whether it actually fires, in a production-safe
way.

**Coverage evaluation.** The result is a full-funnel answer: not "does this
rule look right" but "did a realistic attack sequence trigger it in our
environment".

---

## Why simulation is the hard part

Writing a detection rule is not difficult. Knowing whether it works is.

The normal way to find out is to wait for the attack. Failing that, you
reason about your rule against your understanding of your parsers and hope
both are correct. Plenty of rules that look right never fire, because the
field they match on is not populated by the log source that would carry the
event.

You saw a version of that in Challenge 1. The Triage agent searched for the
emulator user agent and got nothing back, because the search was scoped to
`USER_LOGIN` and an MFA activation is not a login. The query was
well-formed and the assumption behind it was reasonable. It still did not
match.

A rule can be wrong in exactly the same way, and nothing tells you until an
incident does.

> **Synthetic events are visible if you ask for them.** Because simulated
> telemetry flows through the real pipeline, SecOps keeps it separate by
> default. There is a setting under Settings, User Preferences, Synthetic
> Data Visibility that shows synthetic test data alongside real events.

---

## Where it fits

Four agents, four different jobs, across one incident.

| Agent | Question it answers |
|---|---|
| Triage and Investigation | Is this alert real, and what happened? |
| Threat Hunt | Is this behaviour anywhere in our telemetry, indicator match or not? |
| Detection Engineering | Would we catch this next time, and can we prove it? |
| The team you build in Section 2 | What do the platforms outside the SIEM know? |

The first three ship with the product. The fourth is the one nobody can
build for you, because it depends on which tools your organisation runs.

> **Public preview.** The Detection Engineering agent is available in public
> preview for Google SecOps Enterprise and Enterprise Plus tiers, and an
> administrator has to enable the Preview Features opt-in in the console.
> Pre-GA terms apply, so availability and behaviour may have changed since
> this guide was written. Check the documentation below before quoting any
> of it to a customer.

---

## Challenge 5 complete

You have:

- Understood how detection coverage gaps form and why they stay invisible
- Seen how CTI reports become structured detection opportunities
- Understood why event simulation answers a question rule review cannot
- Met the first Google security agent that runs through MCP rather than in
  the product UI

---

## Next: Section 2

Section 1 was your Tier 1 shift, and it is over. You triaged the alert,
found what the automated search did not reach, reassessed the case, and
escalated it to Tier 2.

Tier 2 does not exist yet.

Four questions are open on that case wall, and every one of them names a
platform outside the SIEM. Now you build the agents that can reach them.

---

## References

Product documentation and background reading for this challenge:

- [Evaluate threat coverage with the Detection Engineering Agent](https://docs.cloud.google.com/chronicle/docs/secops/agentic-detection-engineering)
- [Google SecOps release notes](https://docs.cloud.google.com/chronicle/docs/secops/release-notes)
- [Announcing Public Preview of the Detection Engineering Agent](https://security.googlecloudcommunity.com/community-blog-42/announcing-public-preview-of-the-google-security-operations-detection-engineering-agent-8178), Google Cloud Security Community
- [Agentic SOC](https://cloud.google.com/solutions/security/agentic-soc), Google Cloud
- [Google MCP Security servers](https://github.com/google/mcp-security)
