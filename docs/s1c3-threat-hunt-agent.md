# Section 1 · Challenge 3: Emerging Threats and the Threat Hunt Agent

| | |
|---|---|
| **Time** | 15 minutes |
| **Platform** | Google SecOps SIEM, Emerging Threats Center + Threat Hunt agent |
| **Goal** | Find the campaign behind your incident in the Emerging Threats Center, assess what detection coverage you actually have, and see where autonomous hunting fits |

---

## Where we left off

The case wall has two things on it: TIN's automated triage of the
authentication chain, and your own discovery of the Salesforce
exfiltration.

Both describe one account, one day. That is the right scope for an
incident, and the wrong scope for the question a SOC lead asks next.

**Is this the only place this campaign has touched us?**

---

## Two capabilities, two time horizons

Google SecOps answers that question with two related capabilities, and the
difference between them matters.

| | Emerging Threats Center | Threat Hunt agent |
|---|---|---|
| Starts from | A curated GTI campaign | A hunting objective you set |
| Method | Indicator matching against your telemetry | Autonomous multi-step YARA-L 2.0 investigation |
| Output | IOC matches, detection matches, campaign-mapped rules | A dedicated case with an explicit determination and its evidence |
| Answers | Do this campaign's indicators appear in our data? | Is this behavior present, whether or not the indicators match? |

The Emerging Threats Center is a standing answer to "are we affected". The
Threat Hunt agent is a deep investigation you launch when you want proof
either way.

Only the Emerging Threats Center is available in this sandbox. Part 2 is
background on the other one.

---

## Part 1: find the campaign

**What you're doing.** Starting from curated campaign intelligence rather
than from a fired alert.

The Emerging Threats Center correlates GTI campaign intelligence against
your own environment in two ways. **IOC matches** search campaign
indicators across your telemetry. **Detection matches** surface the curated
rules mapped to that campaign, along with whether you actually have them
turned on.

**Task 1.1** — In Google SecOps, go to **Detections → Emerging Threats**.

**Task 1.2** — Search for the threat cluster behind your incident:

```
UNC6661
```

You will get several results, and they are not the same kind of thing.

Most are **intelligence reports**, marked with a document icon and an ID
like `26-10004420`. These are the written analysis: what the adversary
does, who they target, how the tradecraft works. Useful, but it is the same
information you could read on a public blog.

One result is a **campaign entry**, with a `CAMP.` identifier. That one is
different, and it is the one you want.

> **Check the associated actor before you open anything.** One of the
> results is a campaign run by **UNC6671**, a sibling cluster with the same
> tradecraft. They go after SharePoint and OneDrive with PowerShell rather
> than Salesforce. Close, and not your incident.

**Task 1.3** — Open the campaign entry and read the Google Threat
Intelligence summary. As you read, compare it against what TIN found in
your case:

- The initial access method and how the actor registered the MFA device
- Which cloud platforms the actor pivoted to
- The associated actors, and how the extortion arm is tracked separately
  from the intrusion cluster

**Task 1.4** — Now look at the panels on the right hand side. This is where
the campaign entry earns its place.

- **IOCs.** What does this report for your tenant?
- **Rules.** Read the count. Then open the **Disabled Rules** section
  below it.

Those disabled rules are curated detections that Google ships, already
mapped to this campaign. They exist in your tenant right now. Nobody has
switched them on.

Look at the **Rule Set** column for each one, then answer two questions for
yourself:

1. Which of these rules covers the part of the attack chain TIN actually
   caught in your case?
2. Which one describes real tradecraft for this campaign that this
   particular intrusion never used?

> **Coverage is not collection, and it is not availability either.** The
> platform collected the logs. Google wrote, vetted, and shipped the
> detections with the product. Nobody turned them on. That gap between what
> is available and what is enabled is invisible from the alert queue,
> because a rule that is off never produces an alert to tell you it is off.
> The campaign view is where it becomes visible.

---

## Part 2: the Threat Hunt agent

**What you're doing.** Reading, not clicking. The Threat Hunt agent is not
wired into this sandbox, so this part is background on a capability you
will meet in a real deployment.

It matters here because it answers the question Part 1 raised at a
different scale. The Emerging Threats Center tells you whether campaign
indicators match your telemetry. A hunt goes looking for the behavior
even where no indicator matches.

### What it is

The Threat Hunt agent is an autonomous capability powered by Gemini and
grounded in three things: Google Threat Intelligence, Mandiant frontline
expertise, and the MITRE ATT&CK framework. It automates proactive threat
hunting across historical security telemetry.

You give it a hunting objective. It plans the hunt, writes and runs
**YARA-L 2.0** queries against your historical data, reviews what comes
back, and decides what to look at next. At the end it issues a
**determination**, a final verdict such as Substantial Evidence, Evidence
Found, or Threat Not Found.

### Why that is different from a search

A search answers the question you asked. A hunt decides which questions to
ask.

Hunting is the most expensive thing a SOC does with its time, because most
hunts find nothing. That is not failure. "We looked across our historical
telemetry for this actor's behavior and found no evidence" is an answer a
CISO can act on, and it is worth having. But paying a senior analyst to
produce it over and over is why hunting is the first thing to get dropped
when the queue is full.

An agent that hunts autonomously changes that arithmetic. The cost of a
clean negative drops far enough that you can afford to ask the question
routinely rather than only after an incident.

### How it connects to Part 1

The campaign entry you just read is an integration point for the agent.
That is also why, during public preview, the Threat Hunt agent is limited
to Enterprise Plus: the Emerging Threats integration heavily invokes Google
Threat Intelligence.

It also needs the enhanced Case Management experience enabled, because a
hunt produces its own case rather than attaching to an existing one. The
hunt is an investigation in its own right, with its own evidence and its own
verdict.

> **Read the queries, not just the determination.** Same discipline as
> Challenge 1. The agent shows the YARA-L it ran and the reasoning behind
> each step. A verdict you cannot audit is not usable in a SOC, and the only
> way to know what a hunt did not look at is to read what it did.

> **Both of these are Public Preview** and covered by pre-GA terms.
> Availability, licensing and behaviour may have changed since this guide
> was written. Check the product documentation linked at the bottom of this
> page before quoting any of it to a customer.

---

## Challenge 3 complete

You have:

- Found the campaign behind your incident in the Emerging Threats Center
- Told an intelligence report apart from a campaign entry, and UNC6661 from
  UNC6671
- Read the campaign's coverage panel and found curated rules shipped but
  disabled
- Understood where the Threat Hunt agent fits alongside campaign coverage

---

## Next: challenge 4

You have the incident, the campaign, and the environment-wide picture. Two
assessments of this case now sit on the wall and they do not agree with
each other. Next: a playbook that reads both and decides who should be
holding this case.

---

## References

Product documentation and background reading for this challenge:

- [Emerging Threats Center overview](https://docs.cloud.google.com/chronicle/docs/detection/emerging-threats)
- [Emerging Threats Center detailed view](https://docs.cloud.google.com/chronicle/docs/detection/emerging-threats-detailed-view)
- [Introducing the Emerging Threats Center in Google Security Operations](https://cloud.google.com/blog/products/identity-security/introducing-the-emerging-threats-center-in-google-security-operations), Google Cloud blog
- [Introducing the Emerging Threat Center](https://security.googlecloudcommunity.com/news-announcements-9/introducing-the-emerging-threats-center-in-google-security-operations-6281), Google Cloud Security Community
- [Emerging Threat Center video walkthrough](https://security.googlecloudcommunity.com/videos-74/introducing-the-emerging-threat-center-active-threat-intel-for-google-secops-6280), Google Cloud Security Community
- [Emerging Threats Center overview](https://www.youtube.com/watch?v=3fdjAZFTeAI), YouTube
- [Threat Hunt agent documentation](https://docs.cloud.google.com/chronicle/docs/detection/threat-hunt-agent)
- [Announcing Public Preview of the Threat Hunt agent](https://security.googlecloudcommunity.com/community-blog-42/announcing-public-preview-of-the-google-security-operations-threat-hunt-agent-8099), Google Cloud Security Community
