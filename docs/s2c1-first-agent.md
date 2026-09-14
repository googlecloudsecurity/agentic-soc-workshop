# Section 2 · Challenge 1: Build Your First Agent

| | |
|---|---|
| **Time** | 20 minutes |
| **Platform** | code-server + ADK Web |
| **Goal** | Scaffold an agent with the ADK CLI, write its instruction, give it a tool, and see the difference a tool makes |

---

## Where we left off

Your case is escalated to Tier 2 with four open questions on the wall.
Every one of them names a platform outside the SIEM: Okta, CrowdStrike,
Wiz, Google Threat Intelligence.

Tier 2 does not exist yet. You are about to build it.

Not in this challenge, though. Before you wire an agent into four security
platforms, you need to know what an agent actually is, and the fastest way
to learn that is to build one with a single tool and watch what changes
when you add it.

So this challenge builds a MITRE ATT&CK assistant. Nothing to do with your
case. Everything to do with the mechanics you will use for the rest of the
workshop.

---

## Your workspace

Section 2 swaps the tab set. Google SecOps steps back for the whole
section, and returns in Section 3 for the CTF. Three new tabs take its
place:

| Tab | What it is |
|---|---|
| **Code-Server** | A browser VS Code. Your agents live in `/root/agents` |
| **ADK Web** | The ADK developer UI. Chat with your agent and read its trace |
| **Grader** | Scores your agent |

All terminal commands run in the Code-Server tab's built-in terminal.

> **ADK Web will not load yet.** Nothing is listening on that port until you
> start the server yourself in Step 3. A connection error on that tab before
> then is expected.

---

## Step 1: Scaffold the agent

ADK ships with a CLI that scaffolds a new agent for you. Run this from the
`agents` workspace:

```bash
cd /root/agents
adk create mitre_agent \
  --model gemini-3.5-flash \
  --project "$GOOGLE_CLOUD_PROJECT" \
  --region "$GOOGLE_CLOUD_LOCATION"
```

What the flags do:

| Flag | What it does |
|---|---|
| `--model` | Sets the model for the root agent |
| `--project` | The GCP project to use, already exported in every terminal |
| `--region` | The Vertex location, `global` in this environment |

Passing `--project` and `--region` tells `adk create` to use **Vertex AI**
as the backend and writes those values into the generated `.env`, with no
interactive prompts. Run `adk create mitre_agent` with no flags and it
walks you through the same choices interactively.

> **Where the inference actually runs.** `$GOOGLE_CLOUD_PROJECT` is an
> ephemeral GCP project created for your sandbox and destroyed when it ends.
> Every model call your agents make in Section 2 bills to that project and
> dies with it. The platform allows a fixed list of models through this
> path, so if you want to try a different one, pick from the supported list
> linked at the bottom of this page. A model that is not on it will fail at
> the first call rather than at startup.

This creates a `mitre_agent/` folder with three files:

| File | What it does |
|---|---|
| `agent.py` | The agent definition: model, name, description, and instruction |
| `__init__.py` | Makes the folder a Python package so ADK can discover the agent |
| `.env` | Points ADK at Vertex AI and your GCP project |

Open `mitre_agent/agent.py` in Code-Server. The CLI generated a bare
`root_agent` with a placeholder instruction and **no tools**. Your agent
has four fields:

| Field | What it does |
|---|---|
| `instruction` | The system prompt. Defines everything the agent says and does |
| `model` | Which LLM powers the agent |
| `name` | Identifier used when agents delegate to each other |
| `description` | One sentence other agents read to decide whether to route here |

> **Why the variable is named `root_agent`.** ADK and the workshop grader
> both load your agent by looking for exactly this name. Keep it as
> `root_agent`.

---

## Step 2: Write the instruction

Replace the placeholder instruction with a real one using these five
elements. Also update the `description` to something specific, like
`"MITRE ATT&CK knowledge assistant for SOC analysts"`.

```python
instruction="""
## Persona
You are a [role] at [organization] with expertise in [domain].

## Goal
Help [audience] [accomplish what] by [how].

## Constraints
[What the agent must never do or fabricate.]

## Tools
[When and how to use available tools.]

## Format
When given a technique ID, always include:
- Technique name and tactic
- What the adversary is doing
- Detection opportunities
""",
```

Save with `Ctrl+S`.

> Write your own first. A reference implementation is at the bottom of this
> page, and it is deliberately more verbose than you need.

---

## Step 3: Launch and test

```bash
cd /root/agents
adk web --host 0.0.0.0 --port 8000
```

Switch to the **ADK Web** tab, select `mitre_agent`, and start a **New
Session**.

Try:

```
What is T1078?
```

```
An analyst saw mimikatz.exe on a workstation. What MITRE techniques apply?
```

Then run this one and **note the response**. You will run it again in
Step 5:

```
What are the most recent Shiny Hunters campaigns in 2026 and what TTPs did they use?
```

If responses feel generic, stop the server with `Ctrl+C`, tighten your
instruction, restart, and start a **New Session**. Iteration is the skill
this workshop is really teaching.

---

## Step 4: Read the trace

Click any event in the left panel. You will see the full request sent to
the model, including your instruction, and the response that came back.

Now look at what is not there. No tool calls. The agent answered the Shiny
Hunters question entirely from training data, with a knowledge cutoff, and
it cannot reach anything that happened in 2026.

It still gave you an answer. That is worth sitting with.

> **Fluency is not evidence.** A model with no tools produces confident,
> well-structured, plausible text about events it has never seen. The only
> way to know whether an answer is grounded is to look at whether a tool
> ran. You will meet this again in Challenge 2, in a nastier form.

---

## Step 5: Add a tool

Stop the server. In `mitre_agent/agent.py`, add the import at the top and
the `tools` argument at the bottom of the `Agent(...)` call. Leave your
instruction exactly as you wrote it.

Add this import:

```python
from google.adk.tools import google_search
```

And add this line inside `Agent(...)`, after `instruction`:

```python
    tools=[google_search],
```

Then update the **Tools** section of your instruction:

```
Use Google Search for current threat intelligence and recent campaigns.
Always search before answering questions about recent threat actor activity.
```

Save. Restart the server and start a **New Session**:

```bash
cd /root/agents
adk web --host 0.0.0.0 --port 8000
```

Run the same Shiny Hunters prompt. Compare the answer against the one you
noted in Step 3, then open the trace. This time there is a tool call to
`google_search` and results flowing back into the model.

> **This is the shift from a knowledge agent to an action agent.** Nothing
> about the model changed. You added one line, and the agent went from
> recalling to retrieving.

---

## Step 6: Grade your agent

Open the **Grader** tab and click **Grade Challenge 1**. The grader runs
your agent against a set of test prompts and scores it across five
dimensions: instruction quality, tool configuration, MITRE response,
analytical depth, and live intelligence.

You get a score out of 100 with specific feedback on each dimension. The
grader takes around 30 seconds, because it runs your agent live rather than
reading your file.

> The score is feedback, not a gate. Read the per-dimension notes, refine
> your instruction or tools, restart the agent, and grade again. Most people
> gain the most on their second attempt.

---

## Challenge 1 complete

You have:

- Scaffolded an agent with `adk create` on Vertex AI
- Written an instruction with all five elements: Persona, Goal, Constraints,
  Tools, Format
- Added `google_search` as your first tool
- Read a trace and told a grounded answer apart from a recalled one
- Graded your agent

## Checkpoint

- [ ] Instruction has all five elements
- [ ] Agent answers `What is T1078?` with structured output
- [ ] `tools=[google_search]` is in `agent.py`
- [ ] The Shiny Hunters prompt returns 2026 results after adding search
- [ ] A `google_search` tool call is visible in the trace view
- [ ] You graded your agent in the Grader tab

---

## Next: challenge 2

Google Search reaches the public internet. Your four open questions need
something else: Google Threat Intelligence, your identity provider, your
EDR, your cloud posture tool. None of those have a built-in ADK tool.

Next you will connect one of them over MCP, and find out what happens when
that connection quietly fails.

---

## Reference implementation

```python
from google.adk.agents.llm_agent import Agent
from google.adk.tools import google_search

root_agent = Agent(
    name="mitre_agent",
    model="gemini-3.5-flash",
    description="MITRE ATT&CK knowledge assistant for SOC analysts",
    instruction="""
## Persona
You are a MITRE ATT&CK expert assistant for SOC analysts. You have deep
knowledge of adversary tactics, techniques, and procedures (TTPs) and
think like a senior threat intelligence analyst.

## Goal
Help SOC analysts rapidly understand threats, interpret technique IDs,
profile threat actors, and identify detection opportunities.

## Constraints
Stay focused on cybersecurity. Do not speculate about attribution beyond
what evidence supports. Never fabricate technique IDs or campaign details.

## Tools
Use Google Search for current threat intelligence and recent campaigns.
Always search before answering questions about recent threat actor activity.

## Format
For a technique ID, always provide:
- Technique name and parent tactic
- What the adversary is doing in plain language
- Common tools or malware associated with it
- Key detection opportunities
- Relevant data sources

For a threat actor, provide:
- Overview and motivation
- Known TTPs with MITRE ATT&CK IDs
- Target industries and regions
- Notable recent campaigns

Be concise. Lead with the most important information.""",
    tools=[google_search],
)
```

---

## References

Product documentation and background reading for this challenge:

- [Agent Development Kit documentation](https://google.github.io/adk-docs/)
- [ADK quickstart](https://google.github.io/adk-docs/get-started/quickstart/)
- [Built-in tools: Google Search](https://google.github.io/adk-docs/tools/built-in-tools/)
- [Supported AI models on Instruqt](https://docs.instruqt.com/ai-capabilities/connect-ai-models)
- [MITRE ATT&CK](https://attack.mitre.org/)
