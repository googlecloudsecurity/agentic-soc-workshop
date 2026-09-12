# Section 1 · Challenge 3 — Emerging Threats & Threat Hunt Agent

| | |
|---|---|
| **Time** | 15 minutes |
| **Platform** | Google SecOps SIEM — Emerging Threats Center + Threat Hunt agent |
| **Goal** | Find the campaign behind your incident in the Emerging Threats Center, then review the results of an autonomous threat hunt across the environment |

> 🚧 **Under construction.** This challenge is still being built and is not
> part of today's session. Feel free to read through it, but you can skip
> straight to the next challenge whenever you like — nothing later in the
> workshop depends on it.

---

## Where We Left Off

The case wall has two things on it: TIN's automated triage of the
authentication chain, and your own discovery of the Salesforce
exfiltration.

Both describe *one account, one day*. That is the right scope for an
incident, and the wrong scope for the question a SOC lead asks next:

**Is this the only place this campaign has touched us?**

---

## Two Capabilities, Two Time Horizons

Google SecOps answers that question with two related capabilities, and the
difference between them matters.

| | Emerging Threats Center | Threat Hunt agent |
|---|---|---|
| Starts from | A curated GTI campaign | A campaign, actor, malware family, or MITRE TTP you select |
| Looks back | 12 months of telemetry for IOC matches | Up to 30 days of telemetry |
| Runtime | Immediate — the matching is already done | 60–90 minutes, autonomous, in the background |
| Output | IOC matches, detection matches, campaign-mapped rules | A dedicated case with an explicit verdict and evidence |

The Emerging Threats Center is a standing answer to "are we affected." The
Threat Hunt agent is a deep multi-stage investigation you launch when you
want proof either way.

---

## Part 1 — Find the Campaign

**What you're doing:** starting from curated campaign intelligence rather
than from a fired alert.

The Emerging Threats Center correlates GTI campaign intelligence against
your own environment in two ways: **IOC matches**, where campaign
indicators are searched across your telemetry, and **detection matches**,
where curated rules mapped to that campaign have fired.

**Task 1.1** — In Google SecOps, go to **Detections → Emerging Threats**.

**Task 1.2** — Find the campaign matching your incident.

> 🚧 **TODO — fill in during build:** the exact campaign name as it appears
> in the ETC feed for this tenant, and how to find it (search term, or its
> position in the prioritised feed).

**Task 1.3** — Open the campaign detail view and read the writeup. Note:

- The TTPs attributed to the campaign, and how they compare to what TIN
  found in your case
- Whether the campaign detail names infrastructure you already have —
  the MEVSPACE ASN, the attacker IP, the phishing domain

**Task 1.4** — Review the two match types.

> 🚧 **TODO — fill in during build:** what IOC matches and detection matches
> actually return in this tenant, and which of them tie back to your case.

> 💡 **Why this is a different starting point:** an alert tells you
> something fired. A campaign view tells you what an adversary group is
> doing across the industry, and then shows you which parts of it are
> already present in your data. The first is reactive by construction. The
> second lets you act on intelligence before anything fires.

---

## Part 2 — Review the Threat Hunt

**What you're doing:** reading the output of an autonomous hunt that was
launched against this campaign before the workshop began.

A hunt runs for 60 to 90 minutes. You are not going to watch one finish
inside a 15 minute challenge, so one has been run for you — which is also
how this works in practice. You launch a hunt, you go and do something
else, and you come back to a case.

**Task 2.1** — Open **Case Management** and find the case prefixed
**Threat Hunt for**. Hunts create their own dedicated case, tagged
`Threat Hunt`, separate from your incident case.

**Task 2.2** — Read the verdict. The agent returns an explicit answer, not
a pile of search results.

**Task 2.3** — Open the execution detail and work through how it got there:

- The multi-step hunt plan the agent generated
- The rationale for each step
- The underlying **YARA-L 2.0 queries** it actually ran
- The extracted entity summaries — IPs, hostnames, command lines, hashes

> 💡 **The transparency is the point.** An agent that returns a verdict you
> cannot audit is not usable in a SOC. Read the queries. You are checking
> whether you agree with how it looked, not just what it found.

**Task 2.4** — Compare the hunt's scope to your case.

> 🚧 **TODO — fill in during build:** what the pre-run hunt actually found,
> and whether it is complementary to the incident (a second affected user,
> an earlier failed attempt) or a clean negative.

> 💡 **A clean negative is a real result.** Most hunts come back empty, and
> that is exactly why hunting is expensive for humans and cheap for agents.
> "We looked across 30 days of telemetry and this campaign touched one
> account" is an answer a CISO can act on.

---

## Challenge 3 Complete ✅

| Done | Task |
|---|---|
| ✅ | Found the campaign behind your incident in the Emerging Threats Center |
| ✅ | Reviewed IOC matches and detection matches against your own telemetry |
| ✅ | Read the Threat Hunt agent's verdict and its underlying queries |
| ✅ | Compared campaign-wide scope against your single-incident scope |

---

## → Challenge 4

You have the incident, the campaign, and the environment-wide picture.
Next: the response side, and where Gemini fits inside a SOAR playbook.

---

## References

Product documentation and background reading for this challenge:

- [Emerging Threats Center overview](https://docs.cloud.google.com/chronicle/docs/detection/emerging-threats)
- [Emerging Threats Center detailed view](https://docs.cloud.google.com/chronicle/docs/detection/emerging-threats-detailed-view)
- [Introducing the Emerging Threats Center in Google Security Operations](https://cloud.google.com/blog/products/identity-security/introducing-the-emerging-threats-center-in-google-security-operations) — Google Cloud blog
- [Introducing the Emerging Threat Center](https://security.googlecloudcommunity.com/news-announcements-9/introducing-the-emerging-threats-center-in-google-security-operations-6281) — Google Cloud Security Community
- [Emerging Threat Center video walkthrough](https://security.googlecloudcommunity.com/videos-74/introducing-the-emerging-threat-center-active-threat-intel-for-google-secops-6280) — Google Cloud Security Community
- [Emerging Threats Center overview](https://www.youtube.com/watch?v=3fdjAZFTeAI) — YouTube
- [Threat Hunt agent documentation](https://docs.cloud.google.com/chronicle/docs/detection/threat-hunt-agent)
- [Announcing Public Preview of the Threat Hunt agent](https://security.googlecloudcommunity.com/community-blog-42/announcing-public-preview-of-the-google-security-operations-threat-hunt-agent-8099) — Google Cloud Security Community
