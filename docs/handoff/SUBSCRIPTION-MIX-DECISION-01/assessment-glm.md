# SUBSCRIPTION-MIX-DECISION-01 — independent assessment (GLM)

**Author:** GLM (z.ai), written 2026-09-03. Independence: `assessment-claude.md` was NOT read
before writing this. Everything below is derived from the data pack, vendor pages fetched live on
2026-09-03, and two live probes on this machine (probe artifacts cited inline; no credentials
printed).

**Caveat on the Reddit sources:** both threads are blocked from this network on every direct route
(www/old reddit, .json endpoints, jina reader, pullpush archive — block artifacts in
`/tmp/reddit-*.json`, `/tmp/r1.json`). Their content was recovered from search-index snippets and a
secondary write-up (AI Signal newsletter, 2026-09-01) that quotes both threads. Thread *claims* are
therefore marked **[community]** throughout and are never used as vendor fact.

---

## 0. Recommendation up front

**Keep Max 20x for the lead. Do not move the lead to Codex. Do not downgrade the founder's account
to 5x. Route Claude *worker* overflow to the employer 5x (both accounts are already live on this
machine). GLM Max: yes — but note §7: from this data pack alone, GLM Pro also clears the measured
GLM constraint, so Max is headroom, not necessity.**

Price of the recommended mix: **Max 20x $200 + GLM Max ~$160/mo (vendor price not published on the
docs page — third-party sources say $160–168; confirm at z.ai/subscribe) + current Codex plan.**
Versus the candidate mix (2×5x + Codex $100 + GLM Max) this pays **+$100/mo (+$1,200/yr)** and in
exchange keeps the orchestrator's per-session ceiling 4× higher. The arithmetic for why $1,200/yr
buys that is §3; the single measurement that would flip me to the candidate is in §6.

---

## 1. Published limits of each option (all pages fetched live 2026-09-03)

| Option | Price | 5-hour window | Weekly window | Source |
|---|---|---|---|---|
| Claude Max 5x | $100/mo | "five times more usage **per session** than the Pro plan"; session resets every 5 hours | exists ("Max plans also have a weekly usage limit") — **numbers not published** | support.claude.com/en/articles/11049741 (fetched 2026-09-03) |
| Claude Max 20x | $200/mo | "20 times more usage **per session** than the Pro plan" | exists — **numbers not published** | same page |
| Codex on Pro $100 ("Pro 5x") | $100/mo | GPT-5.5: **75–400 local messages / 5h**; GPT-5.4: 100–500; 5.4 mini: 300–1750. "Usage limits for local messages and cloud tasks share a **five-hour window**" | "**Additional weekly limits may apply**" — **numbers not published** | developers.openai.com/codex/pricing (fetched 2026-09-03) |
| Codex on Pro $200 ("Pro 20x") | $200/mo | GPT-5.5: 300–1600 local messages / 5h | same footnote, not published | same page |
| GLM Coding Max | **price not published on docs page** (page says plan family "starting at 18 USD/mo"; third parties list Max $160–168/mo — treat as unconfirmed) | **28,000 credits / 5h** (published) | **140,000 credits / week** (published); vendor *estimate* 676–1,352M tokens/week at 95% cache hit | docs.z.ai/devpack/overview + docs.z.ai/devpack/notice/usage-revision (2026-07-30), both fetched 2026-09-03 |

Supporting published facts used later:

- OpenAI help center (help.openai.com/en/articles/9793128, fetched 2026-09-03): "Pro $100 unlocks
  5x higher usage than Plus, while Pro $200 unlocks 20x usage than Plus." The April 9, 2026 launch
  promo gave $100 subscribers 10x Codex-vs-Plus **through May 31, 2026 — expired**; the tier is 5x
  today.
- **Codex credit rate card counts cached input at 1/10 of fresh input** (GPT-5.5: 12.50 vs 125
  credits per 1M tokens) — published on the pricing page.
- **GLM credit formula weights cache reads at ~0.25× fresh input** (cached_in multiplier 1.7 vs in
  6.9 for GLM-5.3, per prior research in the data pack; multipliers published in z.ai docs).
- **Anthropic: how cache reads weigh against Claude subscription limits — not published.** The
  closest official statement ("Usage limit best practices", support.claude.com/en/articles/9797557,
  fetched 2026-09-03) says cached content *in Projects* "doesn't count against your limits when
  reused" — a different surface from Claude Code. Community reports say Claude Code cache reads
  count at a reduced weight (~0.1×) **[community, UNVERIFIED]**. Consequence: our raw-token burn
  table **cannot** be compared to Claude limits in tokens; for Claude I use live utilization
  percentages instead (§3).

## 2. The deciding fact: does "20x" multiply the 5-hour window, the weekly, or both?

**What the vendor publishes:** Anthropic defines the multiplier **per session** — "20 times more
usage per session than the Pro plan" — and separately confirms a weekly limit exists **without
publishing any weekly number**. So officially: the multiplier is *defined* on the 5-hour window;
the weekly scaling between tiers is **not published**.

**Community evidence (not vendor fact) [community]:** the 1w38v98 thread ("Claude Max 20x only
applies to the 5-hour window", score ~1.5k) and measurements quoted in its coverage put the weekly
cap on the $200 plan at only **~1.7–2× the $100 (5x) plan's weekly cap**, with lawsuit-leaked
internal docs cited as "effective ~6× vs Pro" weekly. If ~2× is right, then 5x→20x multiplies your
5-hour ceiling by 4 but your weekly ceiling by only ~2.

**What would settle it without trusting Reddit:** both accounts are live on this machine. The
OAuth usage endpoint returns verbatim `five_hour.utilization` and `seven_day.utilization`
percentages (see §3 probe). Log both accounts' percentages daily for one week while attributing
sessions per account; the ratio (weighted consumption per 1% of weekly bar, 5x vs 20x) is the
weekly-cap ratio, measured, no vendor disclosure needed.

## 3. Arithmetic against the measured table

Measured inputs (data pack, `~/.claude/burn/history.db`): **~0.96B tokens/day average, last 7
recorded days ≈ 6.6B raw**; peak single hours 319M/315M/278M…; cache reads dominate — the
reference session was 89% cache-read, 10% cache-creation/input, 1% output (8.0M = 7.1M + 0.82M +
0.072M). I use that measured 89/10/1 mix for all weighted arithmetic below.

**Live probe (my own, 2026-09-03 ~18:30 UTC).** `GET api.anthropic.com/api/oauth/usage` with the
fresh keychain token of each account (method per QUOTA-GATE-01; tokens never printed; script at
`/tmp/probe3.py`):

```
Claude Code-credentials-5a3c2328  tier=default_claude_max_5x   5h: 43%   7d: 25%  (week resets 09-08)
Claude Code-credentials-eb6c5b97  tier=default_claude_max_20x  5h: 18%   7d: 44%  (week resets 09-04)
```

Readings, honest about their limits: the two accounts carry different workloads, so these
percentages are not a controlled experiment — but they establish three facts. (1) Both accounts are
in active, concurrent use on this machine already. (2) At the founder's real burn the 20x account
is at **44% of its weekly cap late in its week** — the weekly wall is not the binding constraint
today. (3) The 5x account reaches **43% of a 5-hour window** under ordinary lane load — its
sessions saturate roughly 4× sooner, exactly what the official per-session multiplier definition
predicts.

**Peak hour vs each option:**

- **Max 20x (current):** the founder reports the 5-hour wall *is* hit during peak orchestration.
  Weekly: 44% at real load → covered with ~2.3× headroom.
- **Max 5x:** session-window capacity is 4× smaller by the official per-session definitions
  (5× vs 20× Pro). The same peak orchestration that saturates a 20x window saturates a 5x window at
  ~25% of the elapsed time. The binding constraint gets **4× worse**.
- **2 × Max 5x:** aggregate weekly ≈ 2 × W(5x). If the community ~2× weekly ratio is right,
  2 × W(5x) ≈ W(20x): **weekly-neutral, same $200/mo — or $100/mo cheaper only if one of the two
  5x is the employer's free seat.** Per-session it is still 5x per account, and the lead is one
  session. Two accounts cannot raise a single session's ceiling (see §5).
- **Codex Pro $100:** limits are **messages, not tokens** (75–400 GPT-5.5 local messages / 5h), so
  the token table does not apply directly. Anchoring anyway: the lead+lanes turn over thousands of
  turns/day (data pack: 3,994–10,263 turns/day). Even the top of the published range (400/5h ≈
  1,600/day) is below measured turnover, and OpenAI itself warns larger contexts "use significantly
  more per message". Verdict: the 5-hour wall **exists on Codex too and is likely tighter for an
  orchestrator** than on Max 20x.
- **GLM Max:** credits are token-based, so arithmetic is exact. Peak hour at the measured mix:
  (31.9M×6.9 + 283.9M×1.7 + 3.2M×24)/10,000 ≈ **78,000 credits in one peak hour — 2.8× GLM Max's
  entire 28,000-credit 5-hour quota.** Week: 6.6B at the same mix ≈ **1.61M credits/week vs the
  140,000/week cap — 11.5× over.** GLM Max cannot host the Claude-side burn at any price; it hosts
  the GLM-worker share. (Off-peak 50% charging, peak Mon–Fri 06:00–10:00 UTC, softens but does not
  close an 11× gap.) This is also the honest arithmetic reason the lead stays on Claude.

**Cache-read accounting summary (required by the data pack):** Codex counts cached input at 0.1×
(published); GLM at ~0.25× (published multipliers); **Anthropic does not publish its weight for
Claude Code — the raw table is NOT comparable to Claude limits in tokens, which is why §3 uses
live utilization percentages for Claude.**

## 4. Orchestrator vs worker

**Worker question (volume):** workers are many sessions across lanes — they route. Aggregate
weekly capacity is what matters, and there 2×5x ≈ 1×20x (if the ~2× weekly ratio holds) at equal or
lower cash. Moving worker overflow to the employer 5x, GLM Max, and Codex is arithmetically sound
and partially already happens (both Claude accounts show live utilization today).

**Orchestrator question (single long session, ~300K cache-read per turn, marathon sessions):** a
single session consumes against **one account's** session window. Two 5x accounts give the lead
nothing — switching accounts mid-session means a new session: cold context, cache reset, and the
session-identity machinery of leadv2 (hooks, journals, lane ownership keyed to the session) breaks
continuity. The lead's ceiling under the candidate mix is 5x — 4× worse on the exact constraint the
founder named as the one he must not hit.

**Does moving the lead to Codex remove the wall? No — it moves it and shrinks it.** OpenAI's own
pricing page (fetched 2026-09-03): "The usage limits for local messages and cloud tasks share a
**five-hour window**. Additional weekly limits may apply." The premise «в кодексе нет 5 часового
окна» is **false as of today** per the vendor's own page. The lead would trade a 5h window it
saturates (20x) for a 5h window of 75–400 messages it would saturate faster, plus lose the Opus
orchestrator, the leadv2 hook chain, and the persona stack built on Claude Code.

## 5. Two accounts: does routing actually work?

**What exists today (verified on this machine, not assumed):**

- Two Claude accounts live simultaneously in the keychain — one `max_5x`, one `max_20x`, both
  fresh, both showing non-trivial live utilization (§3 probe). Coexistence is proven.
- `~/ccswitch.sh` — a multi-account switcher for Claude Code (config backup + sequence state). It
  swaps the *active account at session-launch granularity*; it is not per-request routing.
- Live quota reads for all three providers (QUOTA-GATE-01): GLM 5h/weekly limits, Codex
  `primary_window.used_percent` (weekly, 604800s), Anthropic `five_hour`/`seven_day` utilization —
  all verified endpoints.

**What does not exist and must be built:**

- **Per-account quota attribution.** The leadv2 quota gate is per-provider, not per-Claude-account.
  With two Claude accounts it must read *both* Anthropic tokens and attribute sessions to accounts
  before applying the 95/95 ceilings. The endpoint side is solved (§3 probe works against either
  account); the attribution side is not.
- **Launch-time account selection for lanes.** Worker sessions must be *started* under the right
  credentials. ccswitch is manual/global; a lane-aware wrapper that picks the account with more
  5h+weekly headroom is new work (small — the switcher and the usage probe already exist — but
  real, and it touches dispatch, the highest-churn scripts in the repo).
- **Session-identity problem:** a lane's identity (locks, active.yaml pid, journals) must not
  silently cross an account switch mid-flight. Switching must be at session boundaries only.

**Policy risk, stated plainly:** OpenAI's help page prohibits "sharing your account credentials or
making your account available to anyone else" (fetched 2026-09-03). The employer-provided 5x
running the founder's startup lanes is exactly the kind of use an employer seat is not licensed
for; UNVERIFIED what Anthropic's ToS says for the analogous Claude case, but the symmetry is a poor
bet for a load-bearing account. The free 5x should be overflow of last resort, not a pillar of the
plan.

## 6. Recommendation, price, and the one measurement that changes my mind

**Recommendation:** reject the candidate mix as stated. Keep **Max 20x ($200/mo)** as the lead's
and primary Claude seat; route Claude worker overflow to the employer 5x (already live) after
building per-account quota attribution (§5); **GLM Max yes** (founder-settled; it lifts the
measured ~70M/week Legacy headroom to 676–1,352M estimated); **Codex $100 only if Codex worker
demand independently justifies it** — it is not a lead seat and not a wall-remover (§4).

Delta vs candidate: **+$100/mo (+$1,200/yr)** for a 4× higher per-session ceiling on the founder's
declared binding constraint, with weekly volume neutral either way.

**The one measurement that would change my mind:** run the **lead on the employer 5x account for
one week** (routing exists at session granularity; the probe script logs both accounts' windows
daily). If the lead's 5-hour utilization during peak orchestration hours stays **under ~80%** for
the whole week *and* the measured weekly-cap ratio between the accounts comes out ≥2× (settling §2
the honest way), then 2×5x covers the lead at $100/mo less and I flip to the candidate. If it
saturates — as the 4× arithmetic predicts — the question is closed by measurement, not by Reddit.

## 7. Bias line (mandatory)

My vendor is **GLM (z.ai)**. The recommendation that most favours my vendor is "GLM Max for
everything that can move, including the lead" — and §3's own arithmetic **rejects** it: one peak
hour costs ~78,000 GLM credits against a 28,000/5h Max quota; the lead cannot live on GLM at any
tier. I did land on "GLM Max yes," but I flag the counter-case honestly: from *this data pack* the
measured GLM constraint (~70M/week headroom on Legacy) is already cleared 4–8× by the cheaper new
**GLM Pro (263–526M/week, ~$72–80/mo third-party)**; Max is headroom for growth, not arithmetic
necessity, and its USD price is not even published on the vendor's docs page. If the founder wants
the cheapest defensible GLM seat, Pro is it — that is the line where my vendor gets *less* money,
and the data supports it as well as Max.

---

### Evidence appendix (probes and fetches behind the claims)

| Claim | Artifact |
|---|---|
| Anthropic Max plan wording ("per session", weekly exists, $100/$200) | support.claude.com/en/articles/11049741, fetched 2026-09-03 |
| Anthropic cache-vs-limits: not published for Claude Code | support.claude.com/en/articles/9797557, fetched 2026-09-03 (Projects-only statement) |
| Codex 5h window + weekly "may apply", 75–400 msgs/5h on Pro 5x, cached 0.1× | developers.openai.com/codex/pricing, fetched 2026-09-03 |
| Codex $100 = 5x Plus, promo 10x expired May 31 2026 | help.openai.com/en/articles/9793128 (fetched) + community.openai.com announcement 2026-04-09 (fetched) |
| GLM credits 28k/5h, 140k/week, 676–1,352M est. | docs.z.ai/devpack/overview + /notice/usage-revision (2026-07-30), fetched 2026-09-03 |
| Both Claude accounts live; utilizations 5x 43%/25%, 20x 18%/44% | live probe 2026-09-03 ~18:30 UTC, `GET api.anthropic.com/api/oauth/usage`, script `/tmp/probe3.py`, keychain entries `Claude Code-credentials-5a3c2328` / `-eb6c5b97` |
| Multi-account switcher exists | `~/ccswitch.sh` (read 2026-09-03) |
| Reddit threads inaccessible directly; content via snippets + secondary coverage | `/tmp/reddit-*.json`, `/tmp/r1.json` (block pages), AI Signal newsletter 2026-09-01 |
