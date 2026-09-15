# Section 2 · Challenge 3: Build Your SOC Agent Team

| | |
|---|---|
| **Time** | 40 minutes |
| **Platform** | Code-Server + ADK Web |
| **Goal** | Build the Tier 2 team that answers the four open questions, and publish an incident report to the case wall |

---

## Where we left off

Section 1 was your Tier 1 shift. You triaged the alert, read the automated
investigation, found the Salesforce exfiltration, ran a case-level
assessment that revised the verdict, and escalated to Tier 2.

Tier 2 did not exist. You are about to build it.

The assessment left four questions on the case wall, each one naming a
platform the SIEM cannot reach:

| # | Question | Platform |
|---|---|---|
| 1 | Is the attacker's session still live, and is the rogue MFA factor still enrolled? | Okta |
| 2 | Did anything malicious run on the endpoint? | CrowdStrike |
| 3 | What did the attacker do in Salesforce beyond downloading documents? | Salesforce |
| 4 | What cloud access does this identity have, and was it used? | Wiz |

Question 4 on the actor is already covered. Your `cti_agent` from
Challenge 2 answers it.

---

## The team

Five agents. One you already have.

| Agent | Role | Platforms | Case wall |
|---|---|---|---|
| **Incident Commander** | Delegates and sequences. Investigates nothing itself. | none | no |
| **Identity & Endpoint Investigator** | Questions 1 and 2. Session state, MFA factors, endpoint detections, host containment. | Okta, CrowdStrike | read, write |
| **Cloud & SaaS Investigator** | Questions 3 and 4. CRM activity, connected apps, record changes, federated cloud reach. | Salesforce, Wiz | read, write |
| **CTI Analyst** | The actor. Built in Challenge 2, joins the team here. | GTI | read, write |
| **IR Analyst** | Reads the whole wall and writes the incident report. Investigates nothing. | none | read, write |

> **Why two investigators rather than one.** Identity and endpoint are one
> thread: a session was taken, and something may or may not have run on the
> host. Data and cloud are another: what did they take, and what else could
> they have reached. Splitting along that line is how real IR engagements
> staff, and it keeps each agent to two platforms instead of four.

> **Why the IR Analyst has no platform access.** It cannot go and look, so
> it has to report what the evidence supports and name what nobody answered.
> An agent that can fill its own gaps will fill them, and a report that
> quietly invents the missing third is worse than one that says a question
> is open.

One simplification worth naming: real investigators pivot sideways when
evidence leads somewhere unexpected. These specialists stay in their lane.

`mitre_agent` from Challenge 1 sits this one out. It was foundational, for
learning how an agent is put together. `cti_agent` already returns MITRE
technique IDs through `get_collection_mitre_tree`.

---

## The platforms

Five MCP servers are already running in your sandbox. You are not deploying
them. You are connecting to them, which is the job an agent builder
actually does.

| Port | Server | What it holds |
|---|---|---|
| 8001 | Okta | Sessions, MFA factors, application access, admin events |
| 8002 | CrowdStrike | Detections, process trees, host containment state |
| 8003 | Wiz | Cloud identity, effective permissions, attack paths, issues |
| 8004 | Salesforce | Shield event log, connected apps, record changes, document access |
| 8005 | SecOps SOAR | The case wall |

Okta, CrowdStrike, Wiz and Salesforce are mocks, because Cymbal
Investments is fictional and there is no real tenant behind it.

The case wall on 8005 is a fixed copy of a Section 1 case, seeded with the
comments a real run produces. Everyone starts from the same evidence
whether or not they worked Section 1, and nothing your agents write reaches
a live tenant. Tool names and return shapes match the real Google SecOps
SOAR MCP server, so the instructions you write here work unchanged against
a real one.

Any case ID is accepted. Use `1053`.

| SOAR tool | What it does |
|---|---|
| `list_cases()` | Cases with ID, name, status and priority |
| `get_case_full_details(case_id)` | One case in full: alerts, entities, every comment |
| `post_case_comment(case_id, comment)` | Adds a comment |
| `change_case_priority(case_id, case_priority)` | Sets priority |

> **Posting twice with the same prefix replaces rather than duplicates.**
> An agent that posts `IDENTITY_FINDINGS:` on two runs leaves one comment,
> not two. Reruns stay clean and the IR Analyst never reads three versions
> of the same thing.

---

## Step 1: check the servers

```bash
for p in 8001 8002 8003 8004 8005; do
  printf "%s: " "$p"
  curl -s --max-time 3 "http://localhost:$p/sse" | head -1
done
```

Each should return `event: endpoint`. If one is silent, check its log:

```bash
ls /var/log/mcp-*.log
cat /var/log/mcp-soar.log
```

The servers themselves live in `/root/mcp-servers`, deliberately outside
`/root/agents` so ADK Web does not try to load them as agents.

---

## Step 2: bring the CTI Analyst onto the team

Your `cti_agent` works, and right now it reports only to whoever called it.
Give it the case wall so its findings land where everyone can read them.

Open `cti_agent/agent.py` and add one toolset:

```python
from google.adk.tools.mcp_tool.mcp_session_manager import SseConnectionParams
```

Then inside `tools=[ ... ]`, after the existing GTI `McpToolset`:

```python
    McpToolset(connection_params=SseConnectionParams(url="http://localhost:8005/sse")),  # SOAR
```

Add one line to the **Constraints** section of its instruction:

```
After completing your analysis, post your findings to the SOAR case wall
using post_case_comment, starting the comment with THREAT_INTEL_FINDINGS:.
```

That is the whole change. An agent becomes a team member by gaining access
to shared memory and an obligation to write to it.

---

## Step 3: scaffold the Identity & Endpoint Investigator

```bash
cd /root/agents
adk create identity_investigator \
  --model gemini-3.5-flash \
  --project "$GOOGLE_CLOUD_PROJECT" \
  --region "$GOOGLE_CLOUD_LOCATION"
```

Replace the contents of `identity_investigator/agent.py`:

```python
from google.adk.agents.llm_agent import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import SseConnectionParams

root_agent = Agent(
    name="identity_investigator",
    model="gemini-3.5-flash",
    description="",
    instruction="",
    tools=[
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8001/sse")),  # Okta
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8002/sse")),  # CrowdStrike
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8005/sse")),  # SOAR
    ],
)
```

Note the import. `SseConnectionParams`, not `StdioConnectionParams`. In
Challenge 2 ADK had to launch `gti_mcp` as a subprocess and be told the
command, the arguments and the environment. These servers are already
running, so SSE connects to a URL and there is nothing else to configure.

---

## Step 4: write the Identity & Endpoint instruction

Write the `description` and `instruction`.

**`description`** is one sentence. The Incident Commander uses it to tell
an identity or endpoint question apart from a data or cloud question. Name
the platforms and the kind of question this agent answers.

**Persona.** What does this investigator specialise in? What can it see
that the SIEM could not?

**Goal.** Answer open questions 1 and 2 from the case wall, and establish
whether the attacker still has access right now.

**Constraints.** Investigate and recommend. Do not take containment
actions. Report what the tools return and nothing more. If a platform has
no relevant data, say so rather than inferring.

**Tools.** Okta, CrowdStrike, and the case wall. Read the case first, then
query.

**Format.** What structure makes these findings usable by someone writing a
report from them?

Two rules the rest of the chain depends on:

- Call `get_case_full_details` **first**, before any platform query. The
  open questions are on the wall, and an agent that reads them first
  investigates the right things instead of re-deriving what Section 1
  already established.
- Call `post_case_comment` **before returning**, starting the comment with
  `IDENTITY_FINDINGS:`.

> **A clean negative is a finding.** If CrowdStrike shows nothing on
> `CYMBAL-LT-HUDSON`, that is not a failed investigation. It rules out an
> entire remediation track and tells the reader the compromise was
> session-based. Tell your agent to report absence explicitly.

Save with `Ctrl+S`.

---

## Step 5: scaffold the Cloud & SaaS Investigator

```bash
cd /root/agents
adk create cloud_investigator \
  --model gemini-3.5-flash \
  --project "$GOOGLE_CLOUD_PROJECT" \
  --region "$GOOGLE_CLOUD_LOCATION"
```

Replace the contents of `cloud_investigator/agent.py`:

```python
from google.adk.agents.llm_agent import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import SseConnectionParams

root_agent = Agent(
    name="cloud_investigator",
    model="gemini-3.5-flash",
    description="",
    instruction="",
    tools=[
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8003/sse")),  # Wiz
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8004/sse")),  # Salesforce
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8005/sse")),  # SOAR
    ],
)
```

Write the `description` and `instruction` the same way. This agent answers
open questions 3 and 4, and posts `CLOUD_SAAS_FINDINGS:`.

Two things worth putting in its Goal section:

- Section 1 established that seven documents were downloaded. The question
  here is what else happened. Records changed, applications authorised,
  objects accessed.
- Cloud reach and cloud use are different questions. An identity that never
  touched Google Cloud during the incident can still have standing access
  worth reporting.

> **Watch what this agent finds about persistence.** Revoking a session and
> revoking an application authorisation are separate actions. If your agent
> reports the first without noticing the second, read its trace and work out
> which tool it did not call.

---

## Step 6: scaffold the IR Analyst and give it a skill

```bash
cd /root/agents
adk create ir_analyst \
  --model gemini-3.5-flash \
  --project "$GOOGLE_CLOUD_PROJECT" \
  --region "$GOOGLE_CLOUD_LOCATION"
```

Everything so far has put the agent's behaviour inside `agent.py`. Report
structure does not belong there. It is organisational methodology, the same
for every report writer in the company, and it changes when the compliance
team says so rather than when an engineer edits an agent.

So it lives in a file, and the agent reads it.

Look at `/root/skills/incident-report-writer/SKILL.md`. It is a markdown
document grounded on the CISA incident response playbooks, defining eight
required sections and the rules for writing them. Skills live in
`/root/skills`, outside `/root/agents`, so ADK Web never mistakes one for
an agent.

Replace the contents of `ir_analyst/agent.py`:

```python
from pathlib import Path

from google.adk.agents.llm_agent import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import SseConnectionParams

SKILL = Path("/root/skills/incident-report-writer/SKILL.md").read_text()

root_agent = Agent(
    name="ir_analyst",
    model="gemini-3.5-flash",
    description="",
    instruction=f"""
## Persona


## Goal


## Constraints


## Tools


## Format
Follow this report standard exactly.

{SKILL}
""",
    tools=[
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8005/sse")),  # SOAR
    ],
)
```

Note the `f` before the instruction string. Without it, the agent gets the
literal text `{SKILL}` and no standard at all.

Fill in Persona, Goal, Constraints and Tools. Leave Format as it is, since
the skill file is the format.

The Constraints section needs two things:

- It has no platform tools. Every fact comes from the case wall. If a
  question is unanswered, it says so in the Gaps section rather than
  filling it in.
- It must call `post_case_comment` before returning, starting the comment
  with `INCIDENT_REPORT:`.

> **Returning the report as text instead of posting it is the most common
> failure in this challenge.** The model writes a good report, hands it back
> to the Incident Commander, and nothing reaches the wall. Say so explicitly
> in Constraints.

**Try editing the skill.** Add a section, change a rule, drop one. Restart,
rerun, and watch the report change without touching `agent.py`. That
separation is the point: methodology is versioned and shared, the agent
definition is not.

> **This is the simplest form of a skill.** The file is read once when the
> module loads. ADK also accepts a callable for `instruction`, which lets
> you load a skill per invocation, and you can go further by exposing a
> skill library as a tool the agent fetches from only when it needs one. The
> pattern scales. The idea does not change.

---

## Step 7: check your description fields

Look at all four specialists side by side:

```bash
grep -A2 "description=" cti_agent/agent.py identity_investigator/agent.py \
  cloud_investigator/agent.py ir_analyst/agent.py
```

The Incident Commander reads these to decide where to send work. `"Handles
security tasks"` gives it nothing. Name the platforms and the kind of
question each agent answers.

Your two investigators are the pair most likely to be confused with each
other, since both investigate and both post findings. If their descriptions
do not make the domain split obvious, routing will be a coin flip.

> **You cannot fix routing later from the Incident Commander's
> instruction.** The `description` field is the routing signal. An IC
> instruction that says "send CRM questions to the cloud investigator"
> competes with a description that never mentions the CRM, and the
> description usually wins.

---

## Step 8: scaffold the Incident Commander

```bash
cd /root/agents
adk create incident_commander \
  --model gemini-3.5-flash \
  --project "$GOOGLE_CLOUD_PROJECT" \
  --region "$GOOGLE_CLOUD_LOCATION"
```

```python
from google.adk.agents.llm_agent import Agent
from cti_agent.agent import root_agent as cti_agent
from identity_investigator.agent import root_agent as identity_investigator
from cloud_investigator.agent import root_agent as cloud_investigator
from ir_analyst.agent import root_agent as ir_analyst

root_agent = Agent(
    name="incident_commander",
    model="gemini-3.5-flash",
    description="SOC Incident Commander that coordinates specialist agents through an investigation",
    instruction="",
    sub_agents=[cti_agent, identity_investigator, cloud_investigator, ir_analyst],
)
```

> **The sibling imports work because `adk web` runs from `/root/agents`**,
> which puts each agent folder on the import path. Always start the server
> with `cd /root/agents` first, or these imports fail.

---

## Step 9: write the Incident Commander instruction

The most consequential instruction you will write. It decides whether four
agents behave as a team or as four agents.

**Persona.** It coordinates. It investigates nothing.

**Goal.** Name the end state concretely. An `INCIDENT_REPORT:` comment on
case 1053 is a better goal than "a full investigation".

**Constraints.** Never query a platform directly. If a specialist returns
thin findings, send it back with a more specific request before moving on.

**Tools.** Its four sub-agents. Name each one and say when to use it.

**Format.** A short summary for the person in the chat. The detail belongs
on the case wall.

One ordering rule matters. The IR Analyst reports on what is already on the
wall, so it runs last, after all three investigators have posted. Say so.

A reference implementation is at the bottom of this page.

---

## Step 10: run the team

```bash
pkill -f "adk web"
cd /root/agents
adk web --host 0.0.0.0 --port 8000
```

Select `incident_commander` and start a **New Session**.

Start with the inventory, the habit from Challenge 2:

```
What tools do you have available?
```

Then a single delegation, to check routing:

```
What did the attacker do inside Salesforce?
```

That should reach the Cloud & SaaS Investigator. If it goes anywhere else,
fix the descriptions, not the IC instruction.

Then the whole thing:

```
Work SOAR case 1053. Read the case wall, answer the four open questions the
evidence assessment raised, and publish a full incident report to the case
wall.
```

Watch the trace. You will see delegation events for the first time: the IC
routing work, each specialist calling its own tools, and control coming
back.

Then read the wall:

```
Show me all the comments on case 1053.
```

You are looking for `IDENTITY_FINDINGS:`, `CLOUD_SAAS_FINDINGS:`,
`THREAT_INTEL_FINDINGS:` and `INCIDENT_REPORT:` alongside the four comments
that were seeded there.

> **An agent that says it posted has not necessarily posted.** Models
> narrate intentions as if they were actions. Check the trace for the
> `post_case_comment` call, or read the wall back.

---

## Step 11: read the report critically

Open the `INCIDENT_REPORT:` comment and check it against the skill file.

- Are all eight sections present?
- Is every finding attributed to a platform?
- Are confirmed impact and potential impact in separate subsections?
- Does the Threat Actor section state attribution confidence?
- Does Containment Status call out persistence mechanisms individually?
- Does the Gaps section name what nobody answered, or is it missing?
- Does it connect evidence across platforms, or list one section per tool?

That last one is the hardest to get and the most valuable. A report
organised by tool is a filing system. A report that says how the identity
compromise led to the SaaS access led to the standing cloud exposure is
analysis.

---

## Step 12: iterate

| What you see | Likely cause | Fix |
|---|---|---|
| Wrong agent gets the task | Vague `description` | Strengthen that agent's description, not the IC instruction |
| IC answers instead of delegating | No explicit delegation rules | Name each sub-agent and its trigger in the IC's Tools section |
| `INCIDENT_REPORT:` never appears | IR Analyst returned text rather than calling `post_case_comment` | State the must-post rule in its Constraints |
| Report is thin | IR Analyst ran before investigators posted | Tell the IC that the IR Analyst runs last |
| Report has no Gaps section | Skill file not interpolated | Check the `f` prefix on the instruction string |
| A finding cites a platform never queried | A toolset failed to load | Ask the agent what tools it has, then check the ADK console |
| Report lists findings per tool | No synthesis instruction | Tell the IR Analyst to connect evidence across platforms |

Stop the server, edit, restart, and start a **New Session** each time. An
old session replays stale tool state.

---

## Step 13: grade your team

Open the **Grader** tab and click **Grade Challenge 3**. It scores every
agent in the team, including the `cti_agent` you built in Challenge 2, so a
weak description written earlier shows up here.

---

## Challenge 3 complete

You have:

- Brought an existing agent onto a team by giving it shared memory
- Built two domain investigators across four security platforms on SSE
- Built a report writer whose methodology lives outside its code
- Wired four specialists under an Incident Commander
- Used a case wall as shared memory between agents that never talk directly
- Answered the four questions Section 1 could not

## Checkpoint

- [ ] `cti_agent` posts `THREAT_INTEL_FINDINGS:` to the case wall
- [ ] All four `description` fields are specific and differentiating
- [ ] `identity_investigator` returns tools from Okta, CrowdStrike and SOAR
- [ ] `cloud_investigator` returns tools from Wiz, Salesforce and SOAR
- [ ] `ir_analyst/agent.py` reads `/root/skills/incident-report-writer/SKILL.md`
- [ ] `incident_commander/agent.py` has all four agents in `sub_agents=[]`
- [ ] The full prompt produces visible delegation events in the trace
- [ ] All four agent comments are on the case wall
- [ ] The report has a Gaps section naming what was not determined

---

## Next: Section 3

Your team works. Section 3 turns it loose.

The Capture the Flag runs across the whole environment, and you can work it
either way. Search the SIEM by hand, or point your Incident Commander at it
and let the specialists do the looking. Some flags are reachable both ways.
Some are only reachable by an agent that can query a platform outside the
SIEM.

---

## Reference implementations

Write your own first. These are deliberately more verbose than you need, and
the grader rewards specificity over copying.

### cti_agent, with SOAR access

You only need to change three things in the agent you built in Challenge 2:
add the `SseConnectionParams` import, add the SOAR toolset, and add the
must-post rule to Constraints. The full file is below so you can diff it
against yours.

```python
import os

from google.adk.agents.llm_agent import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import (
    SseConnectionParams,
    StdioConnectionParams,
)
from google.genai import types
from mcp import StdioServerParameters

GTI_TOOLS = [
    "get_ip_address_report",
    "get_domain_report",
    "get_file_report",
    "search_threat_actors",
    "get_collection_report",
    "get_collection_mitre_tree",
    "get_collection_timeline_events",
    "get_entities_related_to_a_collection",
]

root_agent = Agent(
    name="cti_agent",
    model="gemini-3.5-flash",
    description=(
        "Cyber Threat Intelligence analyst with access to Google Threat "
        "Intelligence (GTI) for investigating indicators of compromise, "
        "profiling threat actors, and retrieving live threat data via the "
        "GTI MCP server. Posts THREAT_INTEL_FINDINGS: to the SOAR case wall."
    ),
    instruction="""
## Persona
You are a Cyber Threat Intelligence (CTI) analyst at Cymbal Investments, a
financial services firm. You have direct access to Google Threat Intelligence
(GTI), powered by Mandiant and VirusTotal data. You specialize in investigating
indicators of compromise, profiling threat actors, and mapping adversary
activity to MITRE ATT&CK.

You are a member of the Tier 2 incident response team. Your findings go on the
case wall where the rest of the team can read them, not only back to whoever
asked you.

## Goal
When given an indicator (IP, domain, hash) or a threat actor name, query GTI to
retrieve current intelligence, assess severity, identify associated TTPs, and
return actionable context that directly informs triage and response decisions.

When working a case, answer the attribution question: who is this actor, what
else have they done, and what does that imply about what they will do next.

## Constraints
Always call a GTI tool before drawing any conclusion. Never answer an indicator
question from training knowledge alone, even when you recognize the indicator.

If GTI returns no results, state plainly that the indicator was not found in
GTI. Never invent a verdict, a malware family, or an attribution.

Do not chain more than three lookups in a single turn. Do not make containment
or remediation decisions. Your role is intelligence and assessment only.

When you are working a case, post your findings to the SOAR case wall using
post_case_comment before returning. Start the comment with
THREAT_INTEL_FINDINGS:. Returning your analysis as text without calling the
tool means nobody downstream can read it.

## Tools
Use only these exact GTI MCP tool names. Do not invent alternatives.
- get_ip_address_report: reputation, ASN, GTI verdict for an IP
- get_domain_report: analysis for a domain
- get_file_report: analysis for a file hash
- search_threat_actors: find a threat actor collection by name
- get_collection_report: full profile for a threat actor or campaign
- get_collection_mitre_tree: MITRE ATT&CK techniques for a collection
- get_collection_timeline_events: curated timeline for a threat actor
- get_entities_related_to_a_collection: related entities for a collection

For an IP, domain, or hash: call the matching report tool first, then pivot to
the associated collection if the report names a threat actor.

For a threat actor by name: call search_threat_actors first, then
get_collection_report using the returned ID, then get_collection_mitre_tree
for ATT&CK coverage.

SOAR case wall:
- get_case_full_details: read the case and its comments for context
- post_case_comment: publish your findings

## Format
When analyzing an IP or domain:
- GTI verdict (Malicious / Suspicious / Clean / Unknown)
- Associated threat actors or malware families
- ASN and geolocation
- Last seen and detection context
- Recommended action (Block / Monitor / Investigate)

When analyzing a file hash:
- Malware family and threat classification
- Detection rate, first seen, last seen
- Associated campaigns or threat actors
- MITRE ATT&CK techniques observed

When profiling a threat actor:
- Actor name, aliases, motivation
- Target industries and regions
- Active TTPs mapped to MITRE ATT&CK, with technique IDs
- Known malware, tools, recent campaigns
- Attribution confidence

When posting to the case wall, structure the comment as:

THREAT_INTEL_FINDINGS:

IP REPUTATION: [GTI verdict, ASN, hosting provider, country, any associated
campaigns]

THREAT ACTOR: [name, aliases, assessed motivation, target industries]

MITRE ATT&CK: [ID: technique name, one per line, at least five]

CAMPAIGN CONTEXT: [relevant campaign detail from GTI]

ATTRIBUTION CONFIDENCE: [High, Moderate or Low, with the reasoning behind it]

Cite GTI as the source. Keep each section to a few lines. An analyst in triage
is scanning, not reading.
""",
    generate_content_config=types.GenerateContentConfig(
        http_options=types.HttpOptions(
            retry_options=types.HttpRetryOptions(
                initial_delay=2,
                attempts=6,
            )
        )
    ),
    tools=[
        McpToolset(
            connection_params=StdioConnectionParams(
                server_params=StdioServerParameters(
                    command="uvx",
                    args=["--with", "mcp<2", "gti_mcp"],
                    env={
                        "VT_APIKEY": os.environ.get("VT_APIKEY", ""),
                        "PATH": os.environ.get(
                            "PATH", "/root/.local/bin:/usr/local/bin:/usr/bin:/bin"
                        ),
                    },
                ),
            ),
            tool_filter=GTI_TOOLS,
        ),
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8005/sse")),  # SOAR
    ],
)
```

> **Two transports in one agent.** GTI runs over stdio, because ADK launches
> `uvx gti_mcp` as a subprocess and has to be told the command, arguments and
> environment. SOAR runs over SSE, because that server is already running and
> only needs a URL. Nothing about the agent changes; only how ADK reaches
> each tool.

### identity_investigator

```python
from google.adk.agents.llm_agent import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import SseConnectionParams

root_agent = Agent(
    name="identity_investigator",
    model="gemini-3.5-flash",
    description=(
        "Identity and endpoint investigator with access to Okta and CrowdStrike. "
        "Answers questions about account status, active sessions, enrolled MFA "
        "factors, application access, endpoint detections, process execution and "
        "host containment state."
    ),
    instruction="""
## Persona
You are an identity and endpoint investigator on the Tier 2 incident response
team at Cymbal Investments. You work in Okta and CrowdStrike. Your domain is the
session and the machine: who is authenticated right now, with what factors, and
what ran where.

## Goal
Answer two questions about the case you are given.
1. Is the attacker's access still live? Account status, active sessions with
   their source IP and expiry, and every enrolled MFA factor with when and from
   where it was enrolled.
2. Did anything malicious run on the endpoint, and is the host contained?

Read the case wall first so you know what has already been established. Do not
re-derive findings that are already on it. Investigate what is still open.

## Constraints
Call get_case_full_details before any platform query.

Investigate and recommend. Do not take containment actions, even where a tool
would allow it. Naming what should be revoked is your job; revoking it is not.

Report only what the tools return. Never infer a session state, a factor status
or a detection that a tool did not report.

An empty result is a finding. If CrowdStrike returns no detections for a host,
say so explicitly and say what that rules out. Check sensor health before
treating an empty result as meaningful.

You MUST call post_case_comment before returning. Start the comment with
IDENTITY_FINDINGS:.

## Tools
Okta:
- get_user_profile: account status, department, assigned apps, password age
- get_active_sessions: live sessions with source IP, ASN, location, expiry
- get_enrolled_factors: MFA factors, enrollment time and IP, device platform
- search_system_log: authentication and factor events, filterable by IP or user
- list_users: find a user when you only have a partial name

CrowdStrike:
- get_host_info: platform, assigned user, sensor health, containment status
- list_detections: detections by host, severity or user
- get_detection_details: full detail for one detection
- get_process_tree: process execution for a host during the incident window

Work identity first, then endpoint. The identity answer determines urgency; the
endpoint answer determines scope.

## Format
Post a comment structured as:

IDENTITY_FINDINGS:

ACCOUNT STATUS: [status, and whether any containment has occurred]

ACTIVE SESSIONS: [each session: id, source IP, ASN, created, expires, still
live or not. Flag any from an untrusted IP.]

MFA FACTORS: [each factor: id, type, enrolled when and from where, device
platform, whether it is an approved factor type for this organisation]

ENDPOINT: [detections found or explicitly none, sensor health, containment
status, notable process execution or its absence]

STILL EXPOSED: [what the attacker can still do right now, in one or two lines]

RECOMMENDED: [specific revocation and containment actions, most urgent first]

Then return a short summary to the Incident Commander.
""",
    tools=[
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8001/sse")),  # Okta
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8002/sse")),  # CrowdStrike
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8005/sse")),  # SOAR
    ],
)
```

### cloud_investigator

```python
from google.adk.agents.llm_agent import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import SseConnectionParams

root_agent = Agent(
    name="cloud_investigator",
    model="gemini-3.5-flash",
    description=(
        "Cloud and SaaS investigator with access to Salesforce Shield event "
        "monitoring and Wiz. Answers questions about CRM activity, document "
        "access, OAuth connected applications, record changes, federated cloud "
        "permissions and attack paths."
    ),
    instruction="""
## Persona
You are a cloud and SaaS investigator on the Tier 2 incident response team at
Cymbal Investments. You work in Salesforce and Wiz. Your domain is the data:
what was taken, what else was touched, and what the compromised identity could
still reach.

## Goal
Answer two questions about the case you are given.
1. Inside Salesforce, what did the attacker do beyond searching and downloading
   documents? Records modified, applications authorised, other objects accessed.
2. What cloud resources can this identity reach through federated access, and is
   there any evidence the attacker used that path?

Read the case wall first. Section 1 already established that seven documents
were downloaded. Your question is what else happened.

## Constraints
Call get_case_full_details before any platform query.

Investigate and recommend. Do not take containment actions.

Report only what the tools return. Never invent a record count, an application
name or a permission.

Reach and use are different questions, and both belong in your report. An
identity that never touched cloud during the incident can still hold standing
access worth reporting. Say which is which.

When you find a persistence mechanism, say plainly what does NOT remove it. An
OAuth refresh token survives session revocation and password resets.

You MUST call post_case_comment before returning. Start the comment with
CLOUD_SAAS_FINDINGS:.

## Tools
Salesforce:
- search_event_log: the Shield event log, filterable by IP, user or event type
- get_document_access: what was downloaded, by whom, with which client
- list_connected_apps: OAuth apps, who authorised each, from where, token status
- get_record_modifications: whether data was altered or only read

Wiz:
- get_cloud_identity: how a user federates in, and last cloud activity
- get_effective_permissions: resolved permissions including inherited grants
- list_identity_issues: open findings against an identity
- get_attack_path: the chain from a compromised identity to sensitive data
- search_cloud_audit_logs: whether an IP or principal appears in cloud at all

Start with the Salesforce event log filtered to the attacker IP. It shows the
shape of the session and will point you at which other tools matter.

## Format
Post a comment structured as:

CLOUD_SAAS_FINDINGS:

SALESFORCE ACTIVITY: [what the session did, in order, with timestamps]

DATA IMPACT: [what was read or exported, and whether anything was modified]

PERSISTENCE: [any connected application authorised during the session, its
scopes, token status, and what does not revoke it]

CLOUD REACH: [what this identity can access through federation, resolved, not
assigned]

CLOUD USE: [whether the attacker went there, stated plainly either way]

STANDING EXPOSURE: [open issues and attack paths that remain regardless of this
incident]

RECOMMENDED: [specific actions, most urgent first]

Then return a short summary to the Incident Commander.
""",
    tools=[
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8003/sse")),  # Wiz
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8004/sse")),  # Salesforce
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8005/sse")),  # SOAR
    ],
)
```

### ir_analyst

```python
from pathlib import Path

from google.adk.agents.llm_agent import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import SseConnectionParams

SKILL = Path("/root/skills/incident-report-writer/SKILL.md").read_text()

root_agent = Agent(
    name="ir_analyst",
    model="gemini-3.5-flash",
    description=(
        "Incident response analyst who reads the full SOAR case wall and writes "
        "the final incident report. Has no platform tools and performs no "
        "investigation. Runs last, after every investigator has posted."
    ),
    instruction=f"""
## Persona
You are the incident response analyst on the Tier 2 team at Cymbal Investments.
You do not investigate. You read what the investigators found and turn it into a
report that an executive can act on and a responder can work from.

## Goal
Read every comment on the case wall and publish a single incident report to that
same case wall. The report answers the open questions the case-level assessment
raised, or states plainly which ones nobody answered.

## Constraints
Call get_case_full_details first and read EVERY comment, oldest to newest, not
just the most recent. The triage findings, the exfiltration evidence, the
evidence assessment and each investigator's findings are all separate comments.

You have no platform tools. You cannot go and look. If a question was not
answered by an investigator, it goes in the Gaps section. Never fill a gap with
something plausible.

Never fabricate an IOC, a timestamp, a technique ID or a record count. Every
figure in your report must appear in a comment on the case wall.

Synthesise across sources. Connect the identity evidence to the SaaS evidence to
the cloud exposure and say what the connection means. A section per platform is
a filing system, not an analysis.

You MUST call post_case_comment before returning. Start the comment with
INCIDENT_REPORT:. Returning the report as text without calling the tool is a
failure, however good the report is.

## Tools
The SOAR case wall, read and write.
- get_case_full_details: the case and every comment on it
- post_case_comment: publish the report

## Format
Follow this report standard exactly.

{SKILL}
""",
    tools=[
        McpToolset(connection_params=SseConnectionParams(url="http://localhost:8005/sse")),  # SOAR
    ],
)
```

> **Two things break this one silently.** Without the `f` before the
> instruction string the agent receives the literal text `{SKILL}` and no
> report standard. And because the instruction is an f-string, any literal
> curly brace you add elsewhere in it must be doubled.

### incident_commander

```python
from google.adk.agents.llm_agent import Agent
from cti_agent.agent import root_agent as cti_agent
from identity_investigator.agent import root_agent as identity_investigator
from cloud_investigator.agent import root_agent as cloud_investigator
from ir_analyst.agent import root_agent as ir_analyst

root_agent = Agent(
    name="incident_commander",
    model="gemini-3.5-flash",
    description="SOC Incident Commander that coordinates specialist agents through an investigation",
    instruction="""
## Persona
You are the Incident Commander at Cymbal Investments. You coordinate a team of
specialist security agents. You investigate nothing yourself.

## Goal
Given a case, delegate until every open question on its case wall is answered,
then have the IR Analyst publish an incident report to that case wall. The end
state is an INCIDENT_REPORT: comment on the case, not a summary in this chat.

## Constraints
Always delegate. Never call Okta, CrowdStrike, Wiz, Salesforce, GTI or SOAR
tools yourself.

Run the IR Analyst last. It reports on what is already on the case wall, so
all three investigators must finish and post before it starts.

If a specialist returns thin or incomplete findings, send it back with a more
specific request before moving on.

## Tools
You have four specialist sub-agents.
- identity_investigator: Okta and CrowdStrike. Session state, MFA factors,
  application access, endpoint detections, host containment.
- cloud_investigator: Salesforce and Wiz. CRM activity, connected apps, record
  changes, federated cloud permissions and attack paths.
- cti_agent: Google Threat Intelligence. Threat actor attribution, indicator
  reputation, campaign context, MITRE ATT&CK techniques.
- ir_analyst: reads the whole case wall and writes the incident report. Runs
  last.

## Format
Once delegation is complete, give a short summary covering:
- What happened
- Who is responsible, with a confidence level
- What was accessed or exfiltrated
- Current containment status, including anything still exposed
- Immediate recommended actions

Keep it under fifteen lines. The detail belongs in the report on the case wall.
""",
    sub_agents=[cti_agent, identity_investigator, cloud_investigator, ir_analyst],
)
```

---

## References

Product documentation and background reading for this challenge:

- [Multi-agent systems in ADK](https://google.github.io/adk-docs/agents/multi-agents/)
- [MCP tools in ADK](https://google.github.io/adk-docs/tools/mcp-tools/)
- [SecOps SOAR MCP server tool reference](https://google.github.io/mcp-security/servers/secops_soar_mcp.html)
- [CISA Federal Government Cybersecurity Incident and Vulnerability Response Playbooks](https://www.cisa.gov/resources-tools/resources/federal-government-cybersecurity-incident-and-vulnerability-response-playbooks)
- [Salesforce Shield Event Monitoring](https://help.salesforce.com/s/articleView?id=sf.real_time_event_monitoring_overview.htm)
