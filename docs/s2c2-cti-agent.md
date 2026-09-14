# Section 2 · Challenge 2: CTI Agent with GTI

| | |
|---|---|
| **Time** | 25 minutes |
| **Platform** | Code-Server + ADK Web |
| **Goal** | Connect an agent to Google Threat Intelligence over MCP, and learn to tell a tool-grounded answer from a confident hallucination |

---

## Where we left off

Your MITRE agent has one tool, and that tool reaches the public internet.

That is not where your open questions live. Google Threat Intelligence,
your identity provider, your EDR, your cloud posture tool: none of them has
a built-in ADK tool, and none of them is searchable from a browser.

This challenge connects the first of them. You will build a CTI agent on
GTI, the same intelligence Mandiant analysts work from, and you will learn
the protocol every remaining tool in this workshop uses.

Build its instruction carefully. In Challenge 3 this agent becomes a
specialist your Incident Commander delegates to.

---

## What MCP is, and how gti_mcp works

**Model Context Protocol (MCP)** is an open standard that lets AI agents
connect to external tools and services. Challenge 1 used a built-in ADK
tool. From here, every tool your agents use comes from an MCP server.

**`gti_mcp` is a Python package** Google publishes on PyPI at
[pypi.org/project/gti-mcp](https://pypi.org/project/gti-mcp/), with source
at
[github.com/google/mcp-security](https://github.com/google/mcp-security/tree/main/server/gti/gti_mcp).
Each GTI tool is a Python function decorated with `@mcp.tool()`. The model
reads the function's docstring to work out what the tool does and when to
call it.

**`uvx` runs the package.** `uvx gti_mcp` fetches `gti_mcp` from PyPI and
executes it. uv caches it after the first run, so later calls are fast.
Your lab image has it pre-cached.

**ADK executes it.** When your agent receives a message, the ADK runtime
reads the `McpToolset` config in `agent.py`, launches `uvx gti_mcp` as a
subprocess, and passes `VT_APIKEY` through the `env` dict. ADK and
`gti_mcp` talk over stdio using the MCP protocol:

```
You send a message
  └── ADK starts uvx gti_mcp as a subprocess
      └── gti_mcp exposes its tool list over stdio
          └── ADK passes the tool list to Gemini
              └── Gemini decides which tool to call
                  └── ADK calls the tool via the MCP session
                      └── gti_mcp calls the GTI API using VT_APIKEY
                          └── result flows back to Gemini
                              └── Gemini synthesizes the response
```

`gti_mcp` is not a persistent server. It starts when a session begins and
terminates when it ends. The `StdioServerParameters` in your `agent.py` is
the configuration telling ADK what command to run and what environment to
give it.

---

## The GTI MCP tools

`gti_mcp` exposes over thirty tools. Your agent uses eight. The full
reference is at
[google.github.io/mcp-security/servers/gti_mcp.html](https://google.github.io/mcp-security/servers/gti_mcp.html).

| Tool | What it does |
|---|---|
| `get_ip_address_report` | Reputation, ASN, GTI verdict for an IP |
| `get_domain_report` | Analysis for a domain |
| `get_file_report` | Analysis for a file hash (MD5/SHA1/SHA256) |
| `search_threat_actors` | Search for threat actor collections by name |
| `get_collection_report` | Full profile for a threat actor, campaign, or malware family |
| `get_collection_mitre_tree` | MITRE ATT&CK techniques for a collection |
| `get_collection_timeline_events` | Curated timeline for a threat actor or campaign |
| `get_entities_related_to_a_collection` | Related entities for a collection |

> **Use exact tool names.** The model will happily invent
> plausible-sounding tools that do not exist. Your **Tools** instruction
> section must name the real ones.

---

## Step 1: Scaffold your agent

Use the ADK CLI to scaffold `cti_agent`, exactly as you did in
Challenge 1:

```bash
cd /root/agents
adk create cti_agent \
  --model gemini-3.5-flash \
  --project "$GOOGLE_CLOUD_PROJECT" \
  --region "$GOOGLE_CLOUD_LOCATION"
```

This creates `cti_agent/` with `agent.py`, `__init__.py`, and a
Vertex-configured `.env`.

The generated `agent.py` has no tools, and `adk create` cannot wire an MCP
toolset for you. Open `cti_agent/agent.py` in Code-Server and replace its
entire contents with this scaffold. The `description` and `instruction` are
deliberately empty. Filling them is Step 2.

```python
import os

from google.adk.agents.llm_agent import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import StdioConnectionParams
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
    description="",
    instruction="""
## Persona


## Goal


## Constraints


## Tools


## Format

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
    ],
)
```

Three things in that scaffold are worth understanding rather than copying
blindly.

> **`PATH` in the `env` dict.** ADK launches `uvx gti_mcp` as a subprocess
> with only the environment you hand it. Without `PATH`, the subprocess
> cannot find the `uvx` binary and the toolset never starts. `VT_APIKEY`
> authenticates the GTI API calls.

> **`tool_filter` restricts the toolset to eight tools.** Without it, ADK
> sends all thirty-plus GTI tool schemas to the model on every single
> request. That inflates every prompt and encourages the model to chain
> speculative pivots, which is the fastest way to exhaust your Vertex
> quota. Filtering is not cosmetic.

> **`args=["--with", "mcp<2", "gti_mcp"]` is load-bearing.** `gti_mcp`
> imports `mcp.server.fastmcp`, a module the MCP Python SDK removed in
> v2.0.0, and the package declares its `mcp` dependency with no upper
> bound. Without the pin, uv resolves to 2.x and the server dies at import.
> Read the failure-mode section at the end of this page, because you will
> meet this bug again.

---

## Step 2: Write the instruction

Write both the `description` and `instruction` fields.

**`description`** is one sentence. This is how your future Incident
Commander decides whether to delegate a task here, so make it specific
enough to tell this agent apart from `mitre_agent`. Naming the data source
and a representative capability works better than a generic label.

**`instruction`** uses the five elements. Answer these before you write.

**Persona.** What type of analyst is this? What dataset does it have that
`mitre_agent` does not?

**Goal.** Given an indicator or a threat actor name, what should it
produce? What does a complete, useful CTI response look like?

**Constraints.** Should it always query GTI, or only when it feels
uncertain? Should it ever make containment decisions? What should it do
when GTI returns nothing?

**Tools.** Reference the table above. What is the right sequence for
investigating an IP? For researching a threat actor by name?

**Format.** What should an IP response include? A hash? A threat actor
profile?

> A reference implementation is at the bottom of this page. Write your own
> first. The grader rewards specificity, and the reference is deliberately
> more verbose than you need.

Save with `Ctrl+S`.

---

## Step 3: Launch and test

```bash
cd /root/agents
adk web --host 0.0.0.0 --port 8000
```

Switch to the **ADK Web** tab and select `cti_agent`. All testing happens
here, not in the terminal.

The first message takes a few extra seconds while ADK launches the
`gti_mcp` subprocess. A full investigation runs roughly 30 seconds end to
end. That is normal. Do not refresh or open a second session, because that
doubles your load against a shared quota.

Start with the tool inventory:

```
What tools do you have available?
```

You should get back the eight tools from `GTI_TOOLS`. If you get a vague
answer with no tool names, your toolset failed to load. Skip to the
failure-mode section at the end of this page.

Then work the Cymbal Investments indicators:

```
Investigate this IP address: 149.50.97.144
```

```
What is the current threat profile for Shiny Hunters? Include recent campaigns and IOCs.
```

```
Investigate this hash: a3f8c2e1d4b5a6c7e8f9d0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1
```

```
Investigate 149.50.97.144 and pivot to any associated threat actors or campaigns in GTI.
```

That third one is a hash GTI has never seen. A good agent says so. A bad
agent invents a malware family.

---

## Step 4: Read the trace, then iterate

After each query, open the trace view. For the first time you will see a
multi-step agent loop:

- The model's **initial reasoning** about which GTI tool fits the input
- The **tool call** with the exact arguments passed to the MCP server
- The **GTI response** returned to the model
- Any **follow-up tool calls** where the agent pivots on results
- The **final synthesized response**

Read the timings too. Tool calls usually take under a second each. Nearly
all elapsed time is model generation, so if a run feels slow, the fix is
usually a tighter output format in your instruction, not fewer tools.

Now refine, using what you actually saw:

- Did the agent call a tool at all, or answer from training data?
- Did it use real tool names, or invent one?
- Did it pivot from the IP to an associated threat actor collection?
- Did it handle the unknown hash gracefully, without hallucinating a
  verdict?
- Did the response format match what a triaging analyst needs?

Stop the server, edit `agent.py`, restart, and start a **New Session** each
time. An old session replays stale tool state and will confuse your
results.

```bash
pkill -f "adk web"
cd /root/agents
adk web --host 0.0.0.0 --port 8000
```

---

## Step 5: Grade your agent

Open the **Grader** tab and click **Grade Challenge 2**.

As in Challenge 1, the score is feedback rather than a gate. Read the
per-dimension notes, tighten the part of your instruction they point at,
restart the agent, and grade again.

---

## When an agent looks healthy but has no tools

This is the single most important debugging lesson in the workshop, and it
is worth deliberately triggering once.

If the MCP server fails to start, ADK catches the error, logs it at
`WARNING`, and keeps going. The agent boots. It answers questions. It
sounds confident. It has zero tools and is answering entirely from training
data.

The tell in the ADK console:

```
WARNING - llm_agent.py:213 - Failed to get tools from toolset McpToolset:
Failed to create MCP session: Connection closed
```

The tell in the UI is subtler. Plausible answers, and no tool spans in the
trace.

The most common cause is the missing `mcp<2` pin. `gti_mcp` imports
`mcp.server.fastmcp`, which MCP Python SDK v2.0.0 deleted, and `gti-mcp`
declares `mcp` with no upper bound. When the SDK maintainers announced v2
they noted that the overwhelming majority of the ten thousand plus PyPI
packages depending on `mcp` had no upper bound and would all resolve to v2
the day it shipped. This is one of them.

You met a mild version of this in Challenge 1. An agent with no tools still
produced a confident answer about 2026 campaigns it had never seen. Here
the same failure is harder to spot, because the agent is supposed to have
tools and the answer is supposed to be about threat intelligence.

The lesson generalises past this one package. **A fluent answer is not
evidence that your tools are working.** Check the trace, not the prose.

---

## Challenge 2 complete

You have:

- Connected an agent to live Google Threat Intelligence through the
  official GTI MCP server
- Filtered the toolset so prompts stay small and tool selection stays
  focused
- Written an instruction naming exact GTI tool names
- Read a multi-step trace and told a tool-grounded answer apart from a
  hallucinated one

## Checkpoint

- [ ] `cti_agent/agent.py` has a specific `description` that differentiates
      it from `mitre_agent`
- [ ] Your instruction's **Tools** section references exact GTI MCP tool
      names
- [ ] Asking the agent what tools it has returns the eight filtered GTI
      tools
- [ ] The agent successfully queries GTI for `149.50.97.144`
- [ ] Multi-step GTI tool calls are visible in the trace view
- [ ] The agent reports the unknown hash as not found rather than inventing
      a verdict

---

## Next: challenge 3

You now have two specialists that work well on their own. A real incident
needs identity investigation, endpoint analysis, cloud exposure assessment,
and someone to pull it all together.

Next you build the rest of the team, connect them to the platforms your
case-level assessment said were needed, and put an Incident Commander in
front of them. Your `cti_agent` description is what decides whether the
right work gets routed here.

---

## Reference implementation

```python
import os

from google.adk.agents.llm_agent import Agent
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import StdioConnectionParams
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
        "GTI MCP server."
    ),
    instruction="""
## Persona
You are a Cyber Threat Intelligence (CTI) analyst at Cymbal Investments, a
financial services firm. You have direct access to Google Threat Intelligence
(GTI), powered by Mandiant and VirusTotal data. You specialize in investigating
indicators of compromise, profiling threat actors, and mapping adversary
activity to MITRE ATT&CK.

## Goal
When given an indicator (IP, domain, hash) or a threat actor name, query GTI to
retrieve current intelligence, assess severity, identify associated TTPs, and
return actionable context that directly informs triage and response decisions.

## Constraints
Always call a GTI tool before drawing any conclusion. Never answer an indicator
question from training knowledge alone, even when you recognize the indicator.

If GTI returns no results, state plainly that the indicator was not found in
GTI. Never invent a verdict, a malware family, or an attribution.

Do not chain more than three lookups in a single turn. Do not make containment
or remediation decisions. Your role is intelligence and assessment only.

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
    ],
)
```

---

## References

Product documentation and background reading for this challenge:

- [Model Context Protocol](https://modelcontextprotocol.io/)
- [MCP tools in ADK](https://google.github.io/adk-docs/tools/mcp-tools/)
- [Google MCP Security servers](https://github.com/google/mcp-security)
- [GTI MCP server tool reference](https://google.github.io/mcp-security/servers/gti_mcp.html)
- [gti-mcp on PyPI](https://pypi.org/project/gti-mcp/)
