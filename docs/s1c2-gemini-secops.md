# Section 1 · Challenge 2: Gemini in SecOps

| | |
|---|---|
| **Time** | 15 minutes |
| **Platform** | Google SecOps SIEM + SOAR |
| **Goal** | Use Gemini to uncover the Salesforce exfiltration the triage search never reached, then approve the findings onto the case wall |

---

## Where we left off

The case wall has `TIN_INVESTIGATION:` on it: the authentication chain, the
MFA manipulation, the GTI verdict.

What it does not have is any account of what data left the environment.

Look back at the search in TIN's trail that concluded the activity was
isolated to one account:

```
principal.ip = "149.50.97.144"
```

A sound query for the question it was asking. Did this IP touch anyone
else? But it matches on one specific field, and different log sources
populate different fields. A search built around `principal.ip` returns
whatever log types put the address there, and silently returns nothing from
the ones that do not.

TIN did not miss the exfiltration so much as never search a shape of data
that would contain it. That is not a flaw to work around. It is why
interactive analysis exists, and why the trail shows you every query.

---

## Part 1: query for the exfiltration

**Task 1.1** — In the **Google SecOps** tab, open the **Gemini** chat
interface (the sparkle icon, or the Ask Gemini bar).

**Task 1.2** — Send this prompt:

```
Show me Salesforce events where principal.ip is 149.50.97.144 from the past month
```

> **Why this wording.** TIN already confirmed the attacker IP, so you are
> following a known thread into a new log source. The explicit time range
> matters. Without it, Gemini's default 24-hour window may miss the events
> entirely depending on when they were ingested.
>
> If Gemini comes back empty, drop the field name and just ask for
> Salesforce events involving `149.50.97.144`. Naming a field constrains the
> query Gemini builds, and this is exactly the situation where that
> constraint can work against you.

What you should see:

- 5 document searches at 11:03 to 11:05 UTC, keywords `confidential`,
  `internal`, `trading strategy`, `portfolio`, `proposal`
- 7 file downloads at 11:08:03 to 11:08:25 UTC, user agent
  `python-requests/2.31.0`
- 1 POST to the Salesforce Aura endpoint at 11:20 UTC

**Task 1.3** — Ask a follow-up:

```
What is the significance of python-requests as a user agent
for these Salesforce file downloads?
```

The core of the answer is that `python-requests` is a programmatic HTTP
library, not a browser. Something scripted these downloads, which makes
this automated bulk exfiltration rather than a user reading documents.

Gemini will usually go further. Look for it to cover some of:

- **Automation and mass exfiltration.** Legitimate Salesforce use comes from
  browser user agents. A scripted client is a common way to pull many
  records at once.
- **Downloader and malware patterns.** Scripted Python clients are a
  recognised tooling pattern in data theft operations.
- **Evasion.** Custom scripts bypass client-side controls and avoid
  producing the telemetry a human session would.

> **Ask it something it cannot answer, too.** Gemini will tell you what a
> user agent implies. It cannot tell you whether that session is still open
> right now, or what ran on the endpoint. Hold that thought. It is the whole
> of Challenge 4.

---

## Part 2: confirm the exfiltrated documents

Gemini's summary will not list the file names directly. They sit in the
parsed event fields, so you need to drill in.

**Task 2.1** — Run this UDM search. Note that it uses `ip`, not
`principal.ip`. `ip` is an alias that matches the address wherever the
parser put it:

```
extracted.fields.key = "DocumentTitle"
metadata.log_type = "SALESFORCE"
ip = "149.50.97.144"
```

**Task 2.2** — Confirm all seven documents:

```
Q4_Investment_Report_Confidential.pdf
Client_Portfolio_2026_Internal.xlsx
Trading_Strategy_Confidential_2026.docx
Board_Deck_Internal_Jan2026.pptx
M&A_Proposal_Confidential_Draft.pdf
Investor_Relations_Q4_Confidential.pdf
Fund_Performance_Internal_YTD.xlsx
```

> These are financial and M&A documents. Their exfiltration carries
> regulatory exposure under SEC Rule 17a-4, SOX, and MNPI rules. Your agents
> in Section 2 will need to cite them by name.

---

## Part 3: approve the findings onto the case wall

**What you're doing:** getting your discovery onto the case record, where
the case-level assessment in Challenge 4 and the agents you build in
Section 2 will read it.

A second pending action is waiting on your case, holding a written summary
of exactly what you just found. It appeared as soon as you approved the
triage findings in Challenge 1.

**Task 3.1** — Return to your case, open **Pending Actions**, and click
**Respond** on **Approve Gemini in SecOps Investigation?**

> If you do not see it, click the **refresh** icon next to the case header.
> The case view does not poll for changes on its own.

**Task 3.2** — Select **Approve**, then click **Done**.

**Task 3.3** — Find the new `GEMINI_FINDINGS:` comment on the case wall and
expand it with **View More**. Check it against what you found: the five
search keywords, the seven document names, the `python-requests` user
agent, and the Aura endpoint POST.

**Task 3.4** — Confirm both comments are now on the wall:

1. `TIN_INVESTIGATION:`, posted after your approval in Challenge 1
2. `GEMINI_FINDINGS:`, the Salesforce exfiltration you just confirmed

> **Why this is a pending action rather than a free-text box.** Everything
> downstream reads this comment: the case-level assessment in Challenge 4,
> and your agents in Section 2. Approving a prepared summary means everyone
> reaches Challenge 4 with the same evidence on the wall, however their
> queries went.
>
> Nothing stops you adding your own comment alongside it. If you found
> something the prepared summary does not mention, write it up and post it,
> then watch what the assessment in Challenge 4 makes of it. The case wall
> is shared memory, and what you put there changes what comes next.

---

## The teaching moment

TIN runs structured automated searches optimised for triage speed, and
shows you every one of them. Gemini lets you ask a natural language
question that crosses a log source boundary the automated search never
covered.

Neither replaces the other. What connects them is an analyst who read the
queries closely enough to notice which shape of data had not been looked
at, and the case wall, where both sets of findings end up.

---

## Challenge 2 complete

You have:

- Discovered the Salesforce exfiltration with Gemini
- Drilled into parsed events to confirm all 7 document names
- Approved `GEMINI_FINDINGS:` onto the case wall

---

## Next: challenge 3

You know what happened to this account, and what left the building. Next:
is this campaign active anywhere else in the environment?

---

## References

Product documentation and background reading for this challenge:

- [Gemini in Google SecOps overview](https://docs.cloud.google.com/chronicle/docs/secops/gemini-secops)
- [Generate UDM search queries with Gemini](https://docs.cloud.google.com/chronicle/docs/investigation/generate-udm-search-queries-gemini)
