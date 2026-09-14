# Operation Shiny Hunter

## Agentic SOC workshop

---

## 10:42 UTC

A detection rule fires at Cymbal Investments.

An account belonging to a senior portfolio manager authenticates
successfully from Warsaw, Poland, a city it has never logged in from.
Fifty three seconds later, that same account enrolls a new multi-factor
authentication device. The device is an Android emulator.

Fifteen minutes after that, seven confidential documents leave the
company's Salesforce tenant in twenty-two seconds.

You are the Tier 1 analyst on shift. The alert is in your queue.

---

## Cymbal Investments

A mid-sized investment management firm headquartered in New York, roughly
$12B under management across institutional and high-net-worth clients.

That profile matters more than it looks. Everything in the document
repository is a regulated record. Trading strategies fall under SEC Rule
17a-4, financial statements under SOX, and the M&A material is textbook
MNPI. A data theft incident here is a disclosure event with a clock on it.

The security stack is unremarkable and modern. Okta for identity,
CrowdStrike on the endpoints, Wiz for cloud posture, Salesforce as the
document repository for Investment Operations, and Google SecOps tying the
logs together.

---

## The adversary

The tradecraft in front of you matches a ShinyHunters-branded cluster
tracked as **UNC6661**. Their pattern is consistent enough to recognise
from the first three events.

**They call you.** Not an email with a link. A phone call, from someone who
sounds like IT, who already knows your manager's name and your ticket
number.

**They relay in real time.** Their page forwards the typed credentials to
the real login page while the victim waits, along with the MFA code read
aloud over the phone. The session they walk away with is genuine.

**They enroll their own device.** Before doing anything noisy, they add a
factor they control, so losing the stolen session costs them nothing.

**They go straight for the documents.** No lateral movement, no endpoint
persistence beyond what the enrollment needed. They search for the words
"confidential" and "trading strategy", pull the results with a script, and
leave.

The whole sequence, first failed login to last document out the door, took
twenty-six minutes.

---

## The workshop

Three sections, each answering a different question.

### Section 1: what the product already does

Google SecOps ships with agentic capability that runs on every alert with
no configuration from you. The Triage Investigation Agent works the case
before you open it. Gemini lets you interrogate log sources in plain
language. Playbooks orchestrate the response and stop to ask you when a
decision needs a human.

You will work this incident using those capabilities, and you will find
something the automated triage did not.

### Section 2: what you can build on top of it

In-product agents are bounded by the product. Your identity provider, your
EDR, your cloud posture tool and your threat intelligence all sit outside
the SIEM, and something has to reach them.

Using the Google Agent Development Kit, you will build agents that do
exactly that, writing them in code-server and driving them through ADK
Web. You will find quickly that the tools you enable determine what an
agent can reach, and the instruction you write determines how well it
reasons about what it finds. That causal chain is the actual skill this
workshop teaches.

### Section 3: capture the flag

A set of challenges across the environment. You can work them by hand, or
point the agents you just built at them and let them do the searching.
Both are legitimate. One is faster.

---

## Before you begin

Your Google SecOps account and one-click login link are on the **SecOps
Login** tab. The username and password also stay in the instructions panel
on the left for the whole workshop.

The login link is single use and is reissued at the start of every
challenge, so always click the button on the current tab rather than one
you opened earlier.

---

> The attacker has had a long head start. Click **next** when you are ready
> to begin.
