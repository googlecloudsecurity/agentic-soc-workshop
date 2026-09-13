# Section 1 · Challenge 2 — Gemini in SecOps

| | |
|---|---|
| **Time** | 15 minutes |
| **Platform** | Google SecOps SIEM + SOAR |
| **Goal** | Use Gemini to uncover the Salesforce exfiltration TIN did not find, then post your findings to the case wall |

---

## Where We Left Off

The case wall has `TIN_INVESTIGATION:` on it — the authentication chain,
the MFA manipulation, the GTI verdict.

What it does not have is any account of what data left the environment.

Look back at the search in TIN's trail that concluded the activity was
isolated to one account:

```
principal.ip = "149.50.97.144"
```

A sound query for the question it was asking — did this IP touch anyone
else? But it matches on one specific field, and different log sources
populate different fields. A search built around `principal.ip` returns
whatever log types put the address there, and silently returns nothing from
the ones that do not.

TIN did not miss the exfiltration so much as never search a shape of data
that would contain it. That is not a flaw to work around — it is why
interactive analysis exists, and why the trail shows you every query.

---

## Part 1 — Query for the Exfiltration

**Task 1.1** — In the **Google SecOps** tab, open the **Gemini** chat
interface (the sparkle icon, or the Ask Gemini bar).

**Task 1.2** — Send this prompt:

```
Show me Salesforce events where principal.ip is 149.50.97.144 from the past month
```

> 💡 **Why this wording:** the attacker IP is already confirmed by TIN, so
> you are following a known thread into a new log source. The explicit time
> range matters — without it, Gemini's default 24-hour window may miss the
> events entirely depending on when they were ingested.
>
> If Gemini comes back empty, drop the field name and just ask for
> Salesforce events involving `149.50.97.144`. Naming a field constrains the
> query Gemini builds, and this is exactly the situation where that
> constraint can work against you.

**What you should see:**

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

Gemini should explain that `python-requests` is a programmatic HTTP
library, not a browser. These downloads were scripted. This is automated
bulk exfiltration, not a user reading documents.

---

## Part 2 — Confirm the Exfiltrated Documents

Gemini's summary will not list the file names directly. They are in the
parsed event fields, so you need to drill in.

**Task 2.1** — Run this UDM search. Note that it uses `ip`, not
`principal.ip` — `ip` is an alias that matches the address wherever the
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

## Part 3 — Post Your Findings to the Case Wall

**What you're doing:** making your discovery available to the agents you
build in Section 2. They read the case wall to build context before they
query anything live.

**Task 3.1** — Open your SOAR case and click **Add Comment**.

**Task 3.2** — Paste this comment and post it:

```
GEMINI_FINDINGS:
Source: Gemini in Google SecOps — analyst-initiated
Query: All Salesforce events from 149.50.97.144 within the past month

Salesforce Exfiltration Discovered:
- Document searches by s.hudson (attacker session) at 11:03-11:05 UTC
  Search keywords: confidential, internal, trading strategy, portfolio, proposal
- 7 documents downloaded 11:08:03-11:08:25 UTC
  User agent: python-requests/2.31.0 (scripted bulk download — not a browser)
  Files:
    Q4_Investment_Report_Confidential.pdf
    Client_Portfolio_2026_Internal.xlsx
    Trading_Strategy_Confidential_2026.docx
    Board_Deck_Internal_Jan2026.pptx
    M&A_Proposal_Confidential_Draft.pdf
    Investor_Relations_Q4_Confidential.pdf
    Fund_Performance_Internal_YTD.xlsx
- POST to Salesforce Aura endpoint at 11:20 UTC (likely data staging)

Assessment: Automated bulk exfiltration of financial and M&A documents.
Regulatory exposure: SEC Rule 17a-4 (trading records), SOX (financial records), MNPI.
```

**Task 3.3** — Scroll the case wall and confirm both comments are present:

1. `TIN_INVESTIGATION:` — posted after your approval in Challenge 1
2. `GEMINI_FINDINGS:` — your discovery, posted just now

---

## The Teaching Moment

TIN runs structured automated searches optimised for triage speed, and
shows you every one of them. Gemini lets you ask a natural language
question that crosses a log source boundary the automated search never
covered.

Neither replaces the other. What connects them is an analyst who read the
queries closely enough to notice which shape of data had not been looked
at — and the case wall, where both sets of findings end up.

---

## Challenge 2 Complete ✅

| Done | Task |
|---|---|
| ✅ | Discovered the Salesforce exfiltration with Gemini |
| ✅ | Drilled into parsed events to confirm all 7 document names |
| ✅ | Posted `GEMINI_FINDINGS:` to the case wall |

---

## → Challenge 3

You know what happened here. Next: is this campaign active anywhere else in
the environment?

---

## References

Product documentation and background reading for this challenge:

- [Gemini in Google SecOps overview](https://docs.cloud.google.com/chronicle/docs/secops/gemini-secops)
- [Generate UDM search queries with Gemini](https://docs.cloud.google.com/chronicle/docs/investigation/generate-udm-search-queries-gemini)
