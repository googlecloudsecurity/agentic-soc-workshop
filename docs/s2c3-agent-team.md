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

Look at `/root/agents/skills/incident-report.md`. It is a markdown document
grounded on the CISA incident response playbooks, defining eight required
sections and the rules for writing them.

Replace the contents of `ir_analyst/agent.py`:

```python
from pathlib import Path

from google.adk.agents.llm_agent import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import SseConnectionParams

SKILL = (Path(__file__).parent.parent / "skills" / "incident-report.md").read_text()

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
- [ ] `ir_analyst/agent.py` reads `skills/incident-report.md`
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

## Reference: Incident Commander instruction

```python
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
```

---

## References

Product documentation and background reading for this challenge:

- [Multi-agent systems in ADK](https://google.github.io/adk-docs/agents/multi-agents/)
- [MCP tools in ADK](https://google.github.io/adk-docs/tools/mcp-tools/)
- [SecOps SOAR MCP server tool reference](https://google.github.io/mcp-security/servers/secops_soar_mcp.html)
- [CISA Federal Government Cybersecurity Incident and Vulnerability Response Playbooks](https://www.cisa.gov/resources-tools/resources/federal-government-cybersecurity-incident-and-vulnerability-response-playbooks)
- [Salesforce Shield Event Monitoring](https://help.salesforce.com/s/articleView?id=sf.real_time_event_monitoring_overview.htm)
