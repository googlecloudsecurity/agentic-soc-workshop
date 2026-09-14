# agentic-soc-workshop

Lab content for the **Agentic SOC Workshop v3** on Instruqt.

Scenario: Operation Shiny Hunter — a ShinyHunters/UNC6661 vishing-assisted
account takeover at the fictional Cymbal Investments.

---

## Layout

```
docs/                  docsify lab guide — cloned into every sandbox at track start
  _sidebar.md          navigation
  overview.md          served at / via docsify homepage — the Section 0 briefing
  s1c1-triage-agent.md one file per challenge, filename == hash route
  ...
  ref-cheatsheet.md    reference page, linked from the sidebar
instruqt/              NOT served by docsify — version control for Instruqt config
  s0-assignment.md     Section 0 instructions pane
  s1-assignment.md     Section 1 instructions pane, identical for all five challenges
  scripts/
    setup-docker.sh    track setup, docker host
    s1-setup-docker.sh challenge setup, identical for all five Section 1 challenges
```

Only `docs/*.md` is copied into a sandbox. Anything outside `docs/` is never
served, which is why `instruqt/` is safe to keep in this repo.

---

## How content reaches a sandbox

The docker host's track setup performs a sparse, blobless, depth-1 clone of
`docs/` at track start and serves it with docsify on **port 8081**.

Editing a page is a push plus a new session. No track rebuild, no image
rebuild.

The credentials page runs separately on port 8080 on the same host. Do not
let anything else bind either port — both readiness checks in the setup
script test for a content marker rather than just a listening socket, so a
collision fails loudly rather than silently serving the wrong page.

---

## Filenames are a contract

Each challenge's **Lab Guide** tab deep-links to a hash route matching the
filename stem. Instruqt has no idea what is in this repo, so a rename here
gives a participant a blank content pane with no error anywhere.

| Challenge | Lab Guide tab path | File |
|---|---|---|
| Section 0 — Briefing | *(empty)* | `docs/overview.md` via docsify `homepage` |
| S1 C1 Triage Agent | `/#/s1c1-triage-agent` | `docs/s1c1-triage-agent.md` |
| S1 C2 Gemini in SecOps | `/#/s1c2-gemini-secops` | `docs/s1c2-gemini-secops.md` |
| S1 C3 Emerging Threats & Threat Hunt | `/#/s1c3-threat-hunt-agent` | `docs/s1c3-threat-hunt-agent.md` |
| S1 C4 Gemini in Playbooks | `/#/s1c4-gemini-playbooks` | `docs/s1c4-gemini-playbooks.md` |
| S1 C5 Detection Engineering Agent | `/#/s1c5-detection-engineering` | `docs/s1c5-detection-engineering.md` |
| S2 C1 Build Your First Agent | `/#/s2c1-first-agent` | `docs/s2c1-first-agent.md` |
| S2 C2 CTI Agent with GTI | `/#/s2c2-cti-agent` | `docs/s2c2-cti-agent.md` |
| S2 C3 Build Your SOC Agent Team | `/#/s2c3-agent-team` | `docs/s2c3-agent-team.md` |
| S3 Capture the Flag | `/#/s3-ctf` | `docs/s3-ctf.md` |

Track setup validates that every page linked from `_sidebar.md` exists and
prints `[DOCS] MISSING: <page>` if not. It **cannot** see the tab paths
above, so keep this table in sync by hand.

---

## Instruqt tab layout

Section 0 has one tab. All five Section 1 challenges use the same three, in
the same order — the assignment pane's `tab-0` / `tab-1` / `tab-2` buttons
are positional, so the order must not vary between challenges.

| # | Tab | Type | Host | Port |
|---|---|---|---|---|
| tab-0 | Lab Guide | Service | docker | 8081 |
| tab-1 | SecOps Login | Service | docker | 8080 |
| tab-2 | Google SecOps | External website | — | — |

Section 2 will need more tabs. Append them as tab-3 onward so 0–2 stay
stable and the Section 1 pane keeps working unchanged.

---

## The magic link

The Okta session token behind the SecOps Login button is single use and
expires in about five minutes. Every Section 1 challenge therefore runs
`instruqt/scripts/s1-setup-docker.sh`, which calls `refresh_magic_link` to
mint a new one and re-render the page.

Nothing challenge-specific lives in that script. The provisioning retry sits
inside `refresh_magic_link` rather than in the first challenge, so a
participant or proctor who skips ahead recovers the same way as one who
starts at C1.

Credentials themselves (username and password) are stable for the life of
the sandbox and live in the instructions pane. The link lives only on the
SecOps Login tab — one source for the thing that expires.

---

## Going private

Track setup reads a GitHub PAT from the Instruqt track secret named
**`github_token`**.

Instruqt substitutes secret placeholders into the script body at run time.
They are **not** environment variables — `printenv GITHUB_TOKEN` returns
empty and the clone silently stays anonymous, which only breaks once the
repo is private. Use the `${github_token}` substitution form.

Token scope: classic tokens need `repo`; fine-grained tokens need
Contents: Read-only on this repository.

---

## Models

Every agent in Section 2 runs on **`gemini-3.5-flash`** through Vertex AI in
the sandbox's ephemeral GCP project. Standardise on that string everywhere:
lab guides, reference implementations, and the `GEMINI_MODEL` export in the
adk host's track setup.

Instruqt allows only a fixed list of models through a connected cloud
account. Anything not on that list fails at the first inference call, not at
startup. Check it before offering participants an alternative:
https://docs.instruqt.com/ai-capabilities/connect-ai-models

OpenRouter is **not** used in this workshop. Vertex through the ephemeral
project is the only inference path.

Grader judge models are a separate decision from agent models and do not
have to match.

---

## Writing style

Pages follow a fixed shape:

1. Summary table: Time, Platform, Goal
2. "Where we left off", what is already on the SOAR case wall
3. What the capability is and why it matters, before any clicking
4. Numbered Parts containing numbered Tasks (Section 1) or numbered Steps
   (Section 2)
5. Completion list, then a Checkpoint list for build challenges
6. One-line narrative handoff to the next challenge
7. References, product documentation

Prose follows the `unslop` rules. The ones that bite most often:

- **No em dashes.** Use a period or a comma, or restructure the sentence.
- **Sentence case headings**, with proper nouns still capitalised. "Part 2:
  review the Threat Hunt", not "Part 2: Review The Threat Hunt".
- **No decorative emojis.** Callouts use a bold lead-in that ends in a
  period, then the detail: `> **Read the queries, not just the findings.**`
- **Active voice.** Name the actor rather than writing "the logs were
  collected".
- **Cut filler and hedging.** "It is important to note that" goes entirely.

The callouts explaining *why* a query is worded a particular way are the
most valuable lines on any page. Callouts flagging decisions with downstream
consequences are the second most valuable.

Avoid asserting values that the product recalculates: campaign rule counts,
IOC match state, verdicts. Tell participants what to read, not what they
will find.

---

## Known open items

- `s1c3` Part 2 needs a pre-run Threat Hunt before it can be completed.
  Hunts run 60 to 90 minutes, so it can never be run live inside the
  challenge.
- `s1c5`, `s2c2`, `s2c3` and `s3-ctf` are stubs.
- Section 2 needs a decision on the SOAR case wall: mock MCP server on port
  8004 versus the real SOAR MCP. Affects continuity from Section 1, grading
  determinism, and whether participants can skip Section 1.
- The Section 2 grader runs agents live, which is slow. Static analysis of
  `agent.py` would be faster. `s2c1` Step 6 describes live grading and would
  need updating.
- `ref-cheatsheet.md` needs a scope decision: if it lists scenario IOCs it
  becomes a CTF answer key served to every participant.
- CTF flags fall into tiers by which path can reach them: SIEM-answerable by
  both hand and agent, platform-answerable by agents only, GTI by both. Tag
  every candidate flag with its tier before building the CTF.
