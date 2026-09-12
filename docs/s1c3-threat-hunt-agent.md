# Section 1 · Challenge 3 — Emerging Threats & Threat Hunt Agent

> 🚧 **Coming soon.** This challenge is in development and is not part of
> today's session. Here is what it will cover.

---

## The Question This Challenge Answers

You have worked one alert to ground truth. The account is compromised, the
documents are gone, and the case wall has the evidence.

That leaves a harder question, and it is the one a SOC lead asks next:

**Is this the only place in the environment this campaign has touched?**

One confirmed incident is a starting point, not a conclusion. The
indicators you now hold — an ASN, a phishing domain, an enrollment pattern,
a user agent — are a hunting hypothesis. Somewhere in the last ninety days
of logs there may be an earlier attempt that failed, a second user who got
the same call, or a factor enrolled from the same emulator fingerprint that
nobody flagged.

---

## What It Will Cover

- Working from curated emerging threat intelligence rather than a fired
  alert, and turning a campaign writeup into something you can actually
  search for
- Pivoting the indicators from your case into hypotheses that span log
  sources and time ranges an alert never covers
- Using an agent to carry the hunt — running the iterations, chasing the
  negative results, and surfacing only what merits an analyst's attention
- Deciding what a hunt finding becomes: a new detection, a case, or a
  documented negative that is worth keeping

---

## Why It Sits Here

Challenges 1 and 2 were reactive. Something fired, and you responded. This
challenge is the first proactive one, and it is where the economics of
agentic security change: hunting is expensive because most hypotheses come
back empty, and an agent that can run twenty empty hunts overnight changes
what is worth hypothesising in the first place.

---

> Click **next** in the instructions panel to continue.
