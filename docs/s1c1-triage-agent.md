# Section 1 · Challenge 1: triage agent

| | |
|---|---|
| **Time** | 15 minutes |
| **Platform** | Google SecOps SIEM + SOAR |
| **Goal** | Read the Triage Agent's investigation and the queries behind it, form your own view on the verdict, and post the findings to the case wall |

---

## What the triage agent is

**TIN (the Triage Investigation Agent)** is an agentic capability built into
Google SecOps SIEM. When an alert fires, it automatically:

- Searches across the SIEM, not just the events in the alert
- Queries Google Threat Intelligence live for IOC enrichment
- Correlates findings into a structured investigation
- Shows every query it ran, so you can audit how it reached its verdict

In under two minutes it pulls in tens of events across multiple log
sources, retrieves live GTI attribution on the attacker IP, and prepares a
complete investigation summary with every query shown in full. A human
analyst doing this by hand takes 20 to 40 minutes.

This is not a demo feature. It runs in production SecOps environments
today.

---

## Part 1: open the case and note your case ID

**Task 1.1** — Open the **Google SecOps** tab and go to Cases. Log in if
prompted.

**Task 1.2** — Find your case. It is named in the format:

```
Case [CASE ID] - [PRIORITY] Priority
```

For example: **Case 1053 - High Priority**. Something set that name
automatically the moment the alert arrived. You will find out what in
Challenge 4.

**Task 1.3** — Note the numeric ID at the start of the case name.

> **Write this number down.** You will need it in Section 2 to tell your
> agents which SOAR case to read and write to.

**Task 1.4** — Click the case to open it.

---

## Part 2: read the TIN investigation

> **Why TIN sees more than the case summary.** SOAR generated the Gemini
> case summary from the alert events it ingested. TIN ran its own searches
> across the SIEM and pulled in considerably more.
>
> | | Case Summary | TIN Investigation |
> |---|---|---|
> | Evidence base | The alert events | Its own SIEM searches, ~31 events |
> | Threat intel | References a verdict | Ran a live GTI query |
> | Scope | This alert | Checked whether other accounts were hit |

**Task 2.1** — Read the **Gemini Summary** panel at the top of the case.
Three columns: what happened, why it matters, and what to do next. Note the
verdict badge at the top of the panel.

**Task 2.2** — Click **View Investigation** to open TIN's step-by-step
trail.

You can filter the timeline by tool type: GTI lookups, SIEM searches,
context fetches. Work through each step and read both the finding and the
query that produced it. TIN shows every search it ran in full, and you can
re-run any of them.

Things worth stopping on:

- **The GTI lookup** on `149.50.97.144`. Read the verdict carefully, and
  note that GTI records when a verdict has recently changed.
- **The historical login search.** What baseline did TIN have to compare
  against? The answer shapes how much weight the geographic anomaly can
  carry.
- **The prior alert for this identity.** TIN found one, closed by a human
  with a root cause that is not what you would expect. Read how TIN handled
  that.
- **The IP search**, `principal.ip = "149.50.97.144"` across a six-day
  window, returning ~31 events. This is the search that concluded the
  activity was isolated to one account.
- **The user agent search** for `Genymobile/Phone`. Look at what it
  returned, then look at the query.

> **Read the queries, not just the findings.** The user agent search is the
> one to sit with. The emulator string is the centrepiece of this alert, and
> yet that search came back empty, because it was scoped to
> `metadata.event_type = "USER_LOGIN"` and the MFA factor activation is not
> a login event.
>
> Nothing is wrong with the query. It is well-formed and the assumption
> behind it is reasonable. But scope determines findings, and the only way
> to know what an automated search did not look at is to read it. This is
> why the trail is shown to you rather than just the conclusion.

**Task 2.3** — Note the key facts. Your agents in Section 2 read these
directly from the case wall, so TIN's investigation is their starting
point.

```
Victim:          s.hudson@cymbal-investments.com (Saul Hudson)
Attacker IP:     149.50.97.144 (Warsaw, Poland)
Enrolled factor: Okta Passkey, Android emulator
                 com.okta.android.auth/... Android/16 Genymobile/Phone
Pattern:         failed logins, successful auth, immediate MFA enrollment
Scope:           isolated to s.hudson, no other accounts targeted by this IP
```

> **What is missing.** TIN pulled ~31 events and ran a live GTI query
> automatically, in under two minutes. But there is no Salesforce data
> exfiltration in any of it. Look again at the IP search that found those 31
> events and ask what it would have matched. That is Challenge 2.

---

## Part 3: decide, then post to the case wall

> **This step has consequences.** If you decline, or let the action time out
> after 10 minutes, TIN's findings never reach the case wall. In Section 2
> your agents will read the case wall and find nothing from TIN, and the
> Incident Commander will have no triage context to cite.
>
> This is intentional. Every decision in the investigation chain has
> downstream consequences.

**Task 3.1** — In the investigation view, find the prompt: **Do you agree
with the verdict?**

This is the human-in-the-loop moment, and it is a real question. Before you
answer it, weigh what you have read:

- What verdict and confidence did TIN return?
- Does the Gemini Summary panel characterise the incident the same way?
- Which of the two had more evidence in front of it?
- From the evidence you have read, the failed login sequence, the
  successful authentication, the immediate enrollment of an MFA factor from
  an Android emulator, what would you have concluded?

> **Disagreeing is a valid answer.** The prompt is not there for decoration.
> An analyst who rubber-stamps an automated verdict adds nothing to the
> chain. An analyst who reads the evidence, forms their own view, and
> records where it differs is doing the job. Your feedback is also how the
> product learns what your environment actually looks like.

**Task 3.2** — Close the investigation panel and return to the case. Find
**Pending Actions** and click **Respond** on **Approve Triage Agent
Investigation**.

**Task 3.3** — Select **Approve**, then click **Done**. A
`TIN_INVESTIGATION:` comment appears on the case wall with TIN's verdict,
confidence, summary, and next steps.

> If the comment does not appear, click the **refresh** icon next to the
> case header. The case view does not poll for changes on its own. Worth
> remembering for the rest of this section.

> **Approving is a separate decision from agreeing.** It posts TIN's work to
> the record so your agents can build on it in Section 2. An investigation
> worth building on does not have to be an investigation you agree with.

---

## Challenge 1 complete

You have:

- Found your case and noted your Case ID
- Read TIN's investigation trail, including the queries it ran
- Formed your own view and answered the verdict prompt
- Approved posting `TIN_INVESTIGATION:` to the case wall

---

## Next: challenge 2

TIN answered what happened to the account. It did not answer what left the
building. Next you will use Gemini in Google SecOps to follow the attacker
into a log source TIN's search scope never covered.

---

## References

Product documentation and background reading for this challenge:

- [Triage Investigation Agent](https://docs.cloud.google.com/chronicle/docs/secops/triage-investigation-agent)
