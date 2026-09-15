# Section 1 · Challenge 4: Gemini in Playbooks

| | |
|---|---|
| **Time** | 15 minutes |
| **Platform** | Google SecOps SOAR + Vertex AI |
| **Goal** | Attach and run a case-level playbook that uses Vertex AI to reassess the case, then escalate it to Tier 2 |

---

## Where we left off

The case wall now holds two sets of findings:

- `TIN_INVESTIGATION:`, the automated triage, which returned **False
  Positive** with high confidence
- `GEMINI_FINDINGS:`, your discovery of the Salesforce exfiltration, seven
  confidential documents pulled by a script

Read side by side, those two comments do not agree. One says nothing
happened. The other describes a data breach.

Nobody has resolved that yet. That is this challenge.

---

## Two kinds of playbook

You have already met one. Back in Challenge 1, a pending action appeared
asking you to approve TIN's findings. You did not create that. It came from
an **alert-level playbook** named `Update Case`, attached automatically the
moment the alert arrived.

Alert-level automation runs on every alert, with no human deciding it
should. That is the right scope for the things you always want done: set an
SLA, name the case, run triage, ask for approval before writing findings to
the record.

A **case-level playbook** is different. It runs against the whole case
rather than a single alert, so it can reason over everything that has
accumulated, including comments an analyst added hours after the alert
fired. And you attach it deliberately, when a case has built up enough
context to be worth a second look.

That is the playbook you are about to run.

---

## Part 1: read the playbook before you run it

**What you're doing:** understanding what the automation will do before you
let it touch your case. A playbook that writes to the case record and
changes its priority deserves a read-through first.

**Task 1.1** — In your case, open the **Playbooks** tab. It will show
`Playbooks (0)`. No case-level playbook is attached yet.

**Task 1.2** — Click the **+** button to attach a playbook manually, and
look at what is offered. You want **Assess Evidence Gaps**.

Do not add it yet. First, understand what it contains.

**Task 1.3** — The playbook runs six steps in sequence:

| # | Step | What it does |
|---|---|---|
| 1 | Get Case Details | Pulls the case, including every comment on the wall |
| 2 | VertexAI · Execute Prompt | Sends that evidence to Gemini on Vertex AI with a custom prompt |
| 3 | Case Comment | Writes the assessment back to the case wall |
| 4 | Change Priority | Sets the case priority |
| 5 | Change Case Name | Renames the case to match |
| 6 | Escalate to Tier 2? | Asks you to decide |

Step 2 is the one worth dwelling on.

> **This is a different kind of AI from Challenge 2.** Gemini in SecOps is
> conversational. You ask, it answers, you read. Here the model sits inside
> a workflow. Nobody reads its output directly; the playbook does. That
> makes prose the wrong shape for the answer. The prompt asks Vertex AI to
> return **structured JSON** against a fixed schema, so named fields can
> drive the steps that follow. A priority value feeds the Change Priority
> action. A boolean frames the escalation question. A formatted block
> becomes the case comment.
>
> That is the difference between AI you talk to and AI you wire in.

**Task 1.4** — Look at what the prompt actually asks for. The schema
defines six fields:

```
verdict_assessment        concur | revise | insufficient_evidence
verdict_rationale         why, in prose
recommended_priority      Critical | High | Medium | Low | Informative
evidence_sufficiency      sufficient | partial | insufficient
ready_to_escalate         true | false
open_questions            four questions, each with the platform that
                          could answer it and why it matters
```

Note what is not there. No incident report. No MITRE mapping. No
containment plan. The prompt asks a narrower question: given everything on
this case wall, what is still unknown, and who should be holding this case?

> **The prompt is the control surface.** Every constraint in it shapes what
> comes back, including a rule that every open question must be answerable
> by a specific platform that is not the SIEM. That one line is why the
> output is an agenda rather than a wish list.

---

## Part 2: attach and run

**Task 2.1** — Back on the **Playbooks** tab, click **+**, select
**Assess Evidence Gaps**, and click **Add**.

The playbook starts immediately.

**Task 2.2** — Return to the **Overview** tab and watch the case wall. The
assessment takes 15 to 30 seconds to appear. Vertex AI is reading roughly
10,000 tokens of case evidence before it answers.

**Task 2.3** — Find the `EVIDENCE ASSESSMENT` comment and expand it with
**View More**. Read the whole thing.

You should see something close to this:

```
EVIDENCE ASSESSMENT

Verdict assessment: revise
Recommended priority: Critical
Evidence sufficiency: partial
Ready to escalate: True
```

followed by the reasoning, then four numbered open questions, each naming
the platform that could answer it.

> **The case header will look stale.** The title and priority chip at the
> top of the case do not update on their own. Click the **refresh** icon
> next to the case header and the title becomes
> `Case NNNN - Critical Priority`.

---

## Part 3: read what it concluded

**What you're doing:** checking the model's reasoning rather than accepting
its answer. Same discipline as Challenge 1, where you read TIN's queries
rather than just its verdict.

**Task 3.1** — Read the **WHY** section.

The assessment had access to something the triage agent never did: your
`GEMINI_FINDINGS:` comment, posted after triage had already finished and
closed. Confirmed bulk exfiltration of seven regulated documents changes
the picture, and the assessment says so.

> **Neither assessment was wrong for the evidence it had.** TIN searched
> what it was scoped to search and reported accurately on it. The
> case-level assessment ran later, against a case wall that had grown. The
> difference is scope and timing, not competence, and it is exactly the
> reason a case-level playbook exists as a separate thing from an
> alert-level one.

**Task 3.2** — Read the four open questions and the platform named against
each.

Look at what they have in common. Not one of them can be answered from the
SIEM. Live session state, endpoint process trees, cloud exposure, actor
attribution, all of it lives in systems outside Google SecOps.

<details>
<summary><strong>"Why doesn't the SIEM already have this?"</strong></summary>

A fair question, and the answer is not that something is misconfigured.

**A SIEM stores events; these questions ask about state.** Okta logs record
that a session was created at 10:52:14. They do not record whether that
session is still open right now. A log is a record of something that
happened. Session state, enrolled factors and containment status are live
properties that change after the log was written and are never re-emitted.

**Not everything generates a log.** An S3 bucket ACL, a Salesforce OAuth
scope, an unreviewed connected app. These are configuration, not activity.
Nothing gets logged until someone touches them, and by then the exposure
has already existed for months.

**Some data is deliberately not ingested.** Full endpoint process telemetry
is enormous. Most organisations forward detections and selected events, not
every process launch on every host, because the ingestion cost is real and
the value of the long tail is low until an incident makes one branch of it
interesting.

**And some of it is not yours.** Threat actor attribution, campaign
infrastructure, ASN reputation. That comes from an intelligence provider
who sees the rest of the world. Your telemetry cannot tell you about
attacks on other organisations.

The SIEM answers what happened in my environment. That is a large and
useful question, and it is not the only one.

</details>

---

## Part 4: decide

**What you're doing:** the second human-in-the-loop gate in this workshop.
The first, in Challenge 1, decided what went into the record. This one
decides who owns the case.

**Task 4.1** — In the case, find **Pending Actions** and click **Respond**
on **Escalate to Tier 2?**

**Task 4.2** — Before answering, note the case is currently assigned to
**@Tier1**, which is you. Escalating hands it to Tier 2.

**Task 4.3** — Select **Yes**, then **Done**.

**Task 4.4** — Confirm what changed on the case wall:

- `ESCALATED TO TIER 2` comment posted
- Case assigned to **@Tier2**
- Assignee chip at the top of the case now reads `@Tier2`

> **Three of the four fields drove something.** The priority value set the
> case priority and the case name. The boolean framed the escalation. The
> formatted questions became the comment. Only `evidence_sufficiency` was
> purely informational, and in a production build it would gate the branch,
> so that a case with insufficient evidence never reaches the escalation
> prompt at all.
>
> None of that is possible with prose output. You cannot route on a
> paragraph.

---

## Challenge 4 complete

You have:

- Read a case-level playbook before running it
- Attached and ran it against your case
- Read the assessment and the reasoning behind the revised verdict
- Identified four questions the SIEM cannot answer
- Escalated the case to Tier 2

---

## The big picture

Three different uses of AI, three different shapes.

**The Triage Agent** ran automatically on the alert, with no configuration
from you, and showed its working.

**Gemini in SecOps** answered your questions in the moment, in plain
language, across a log source boundary the automated search never covered.

**Vertex AI in a playbook** did something neither of those can. It produced
an answer designed to be consumed by software. Named fields, fixed enums,
predictable structure, feeding a priority change, a rename, an assignment
and an escalation prompt without a human retyping anything.

The prompt was the entire control surface. The tools you give a model
determine what it can reach. The instructions you write determine how well
it reasons about what it finds. That relationship is the whole of
Section 2.

---

## Next: challenge 5

The case is with Tier 2 and four questions are open. Before you build the
team that answers them, one more agent is worth knowing about: the one
whose job is making sure this fires the next time.

---

## References

Product documentation and background reading for this challenge:

- [Vertex AI integration for Google SecOps SOAR](https://docs.cloud.google.com/chronicle/docs/soar/marketplace-integrations/vertex-ai)
- [Working with case playbooks](https://docs.cloud.google.com/chronicle/docs/soar/respond/working-with-playbooks/case-playbooks)
- [Google SecOps gets a Vertex AI boost](https://security.googlecloudcommunity.com/news-announcements-9/google-secops-gets-a-vertex-ai-boost-5291#M144), Google Cloud Security Community
