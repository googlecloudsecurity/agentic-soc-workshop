# Section 1 · Challenge 1 — Triage Agent

| | |
|---|---|
| **Time** | 15 minutes |
| **Platform** | Google SecOps SIEM + SOAR |
| **Goal** | Review what the Triage Agent found automatically, approve its findings to the case wall, and note your Case ID |

---

## What the Triage Agent Is

**TIN (the Triage Investigation Agent)** is an agentic capability built into
Google SecOps SIEM. When an alert fires, it automatically:

- Searches all Google SecOps log sources, not just the alert events
- Queries Google Threat Intelligence live for IOC enrichment
- Correlates findings into a structured investigation
- Waits for analyst approval before writing to the SOAR case wall

In under two minutes it can correlate 31 events across multiple log
sources, retrieve live GTI attribution on the attacker IP, and prepare a
complete investigation summary. A human analyst doing this by hand takes
20 to 40 minutes.

This is not a demo feature. It runs in production SecOps environments
today.

---

## Part 1 — Open the Case and Note Your Case ID

**Task 1.1** — Open the **Google SecOps** tab and go to Cases. Log in if
prompted.

**Task 1.2** — Find your case. It is named in the format:

```
[CASE ID] - True Positive - High Confidence
```

For example: **214 - True Positive - High Confidence**. The name was set
automatically by the playbook using TIN's verdict and confidence.

**Task 1.3** — Note the numeric ID at the start of the case name.

> 📋 **Write this number down.** You will need it in Section 2 to tell your
> agents which SOAR case to read and write to.

**Task 1.4** — Click the case to open it.

---

## Part 2 — Read the TIN Investigation

> **Why TIN sees more than the Gemini case summary:** the case summary was
> generated from the 6 alert events SOAR ingested. TIN ran full searches
> across all log sources and found 31.
>
> | | Case Summary | TIN Investigation |
> |---|---|---|
> | Evidence base | 6 alert events | 31 events, all log sources |
> | GTI enrichment | References a verdict | Ran a live GTI query |
> | Geo baseline | Mentions Netherlands | Confirmed 30-day login history |

**Task 2.1** — Read the **Gemini Summary** panel at the top of the case. It
covers the attacker IP verdict, the credential stuffing pattern, three
behaviour anomalies, and the MITRE techniques the alert surfaced.

**Task 2.2** — Click **View Investigation →** to open TIN's step-by-step
trail. Work through each step and notice how the picture was built:

- **GTI query** on `149.50.97.144` — malicious verdict, Mandiant campaign
  association (UNC6661)
- **30-day login history** — consistent Netherlands logins. Warsaw is new
- **31 events from the attacker IP** — MFA activation, Okta logins, an SSO
  burst across 8 applications
- **Recent login events** — failure loop 10:42 to 10:51 UTC, success at
  10:52:14, MFA activation at 10:53:07
- **Scope check** — only s.hudson affected, no lateral movement

**Task 2.3** — Note the key facts. Your agents in Section 2 read these
directly from the case wall, so TIN's investigation is their starting
point.

```
Victim:          s.hudson@cymbal-investments.com (Saul Hudson)
Attacker IP:     149.50.97.144 (Warsaw, Poland — MEVSPACE ASN 201814)
GTI verdict:     Malicious — Mandiant campaign association (UNC6661)
Enrolled device: Genymobile/Phone (Android emulator, isEmulator=true)
MFA factor ID:   mfa9genymobile00001
```

> ✅ TIN traced 31 events and ran a live GTI query automatically. But notice
> what it did **not** find: the Salesforce data exfiltration. That is in a
> different log source, and it is what you will uncover in Challenge 2.

---

## Part 3 — Approve Posting TIN's Investigation to the Case Wall

> ⚠️ **This step has consequences.** If you click **No** or let the action
> time out after 10 minutes, TIN's findings are never written to the case
> wall. In Section 2 your agents will read the case wall and find nothing
> from TIN, and the Incident Commander will have no triage context to cite.
>
> This is intentional. Every decision in the investigation chain has
> downstream consequences.

**Task 3.1** — In the SOAR case, go to **Pending Actions**. You will see a
manual task: **Post TIN Investigation to Case Wall?**

**Task 3.2** — Review TIN's findings before deciding:

- **Verdict:** True Positive — a confirmed incident, not a false positive
- **Confidence:** High
- **Summary:** the full attack narrative including credential stuffing, MFA
  manipulation, and the SSO burst
- **GTI verdict:** attacker IP confirmed malicious, UNC6661 association

**Task 3.3** — Click **Approve**. A `TIN_INVESTIGATION:` comment appears on
the case wall with TIN's full verdict, confidence, summary, and next steps.

> 💡 **The human-in-the-loop pattern:** in a real SOC an analyst reviews
> automated findings before they become part of the official record. TIN did
> the work. You validate it. Approve is an endorsement, not a rubber stamp.

---

## Challenge 1 Complete ✅

| Done | Task |
|---|---|
| ✅ | Found your case and noted your Case ID |
| ✅ | Read TIN's investigation trail |
| ✅ | Approved posting `TIN_INVESTIGATION:` to the case wall |

---

## → Challenge 2

TIN answered *what happened to the account*. It did not answer *what left
the building*. Next you will use Gemini in Google SecOps to follow the
attacker into a log source TIN's search scope never covered.
