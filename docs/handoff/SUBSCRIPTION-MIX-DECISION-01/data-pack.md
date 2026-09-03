# SUBSCRIPTION-MIX-DECISION-01 — shared data pack

**Everyone assessing this question works from THIS file.** Three independent assessments are being
written — one by Claude (the lead), one by Codex, one by GLM — and GLM then synthesizes all three.
The founder's reason for wanting three is explicit and fair:

> «мне кажется что ты будешь топить за то чтобы деньги твоему провайдеру шли а он за своего»

So: **an assessment that recommends its own vendor without arithmetic from the numbers below will be
discarded.** If the honest answer is that your own provider should get less money, say that. Each
assessment names, in one line, which recommendation would favour its own vendor and why it did or
did not land there.

## The question

Today the founder pays for: **Claude Max 20x** (himself), **Codex**, **GLM**. Separately, **one
Claude Max 5x is provided by his employer** and is already available.

The candidate he is asking about:

> **2 × Max 5x + Codex at $100 + GLM Max** — instead of the current Max 20x mix.

His two constraints, in his words:

1. «Я единственное что не хочу упираться в 5 часовой лимит клода как орекстартора» — the binding
   pain is the **5-hour rolling window**, hit while acting as orchestrator.
2. «мб тогда просто перейду в кодекс как лид так как там нет 5 часового окна» — moving the **lead
   itself to Codex** is on the table precisely because Codex has no 5-hour window.

GLM on a Max subscription is close to settled either way: «Глм то точно будем на макс подписке видимо».

## Sources the founder pointed at — read them, do not paraphrase from memory

- https://www.reddit.com/r/ClaudeCode/comments/1w5z8yb/claude_burning_through_tokens_34x_faster_lately/
- https://www.reddit.com/r/ClaudeCode/comments/1w38v98/claude_max_20x_only_applies_to_the_5hour_window/

The second title is the crux: if "20x" scales the **5-hour** window and not the weekly one, then two
Max 5x accounts and one Max 20x are **not** interchangeable, and which is better depends on whether
our pain is peak-rate or total volume. Verify that claim against Anthropic's own published limits —
a Reddit title is a lead, not evidence.

## Our measured burn (authoritative — `~/.claude/burn/history.db`, read 2026-09-03)

Total tokens per day, all sessions, cache-read and cache-creation included:

| date | tokens | turns |
|---|---|---|
| 2026-09-03 (partial) | 0.63B | 3 994 |
| 2026-09-02 | 1.27B | 10 263 |
| 2026-09-01 | 1.09B | 8 392 |
| 2026-08-31 | 1.02B | 5 956 |
| 2026-08-30 | 1.14B | 6 925 |
| 2026-08-29 | 0.74B | 4 617 |
| 2026-08-28 | 0.70B | 4 080 |
| 2026-08-27 | 0.66B | 3 128 |
| 2026-08-26 | 1.10B | 6 103 |
| 2026-08-25 | 0.88B | 5 388 |
| 2026-08-24 | 0.50B | 4 246 |
| 2026-08-23 | 1.81B | 9 946 |

Peak single hours on record: 319M, 315M, 278M, 267M, 246M, 242M.

**Cache reads dominate this number.** Every turn re-sends the conversation, so a long lead session
costs cache-read per turn — one 2026-08-23 session was 1 699 turns / 513M at ~300K cache-read per
turn. Any assessment must state whether the plan limits it is comparing count cache reads, because
if they do not, this table overstates consumption against those limits by a large factor. **Say
which it is, with a source.**

## Prior research on this machine — use it, correct it if wrong

- `project_token_burn_doubling_20260823` — burn doubled 2026-08-14..23 (7d 8.72B vs ~4.5B).
  Drivers measured: headless spawn volume ×3 (43 lanes/day → 111–192), marathon lead sessions,
  worker base context ~106K at turn 1 and ~150K/turn.
- `project_glm_legacy_plan_undersized_20260824` — the founder's GLM plan is **Legacy V2 Pro, $30/mo**,
  measured headroom **~70M tokens/week at our mix**; the new credits Pro is **263–526M**, i.e.
  4–8× larger. Credit formula: `(in×M_in + cached_in×M_cached + out×M_out)/10 000`, GLM-5.3 =
  6.9 / 1.7 / 24, off-peak charged at 50%, peak = Mon–Fri 06:00–10:00 UTC. Also: z.ai silently
  routes GLM-5.2/5.1 requests to **GLM-5.3**, so our scripts asking for `glm-5.2` get 5.3.
- `feedback_quota_ceilings_per_provider` — the ceilings we actually enforce, weekly window:
  glm 80% ordinary / 90% review, codex 90/95, claude 95/95. Review keeps the higher ceiling because
  it is the last thing to sacrifice.

## What each assessment must contain

1. **The published limits of each option, with a source URL and a date.** Max 5x, Max 20x, Codex at
   $100, GLM Max. Where a vendor does not publish a number, say "not published" — never estimate it
   into a table as if it were fact.
2. **Whether "20x" multiplies the 5-hour window, the weekly window, or both.** This single fact
   decides the founder's question. If it cannot be established from vendor documentation, say so and
   say what measurement would settle it.
3. **Arithmetic against the table above, not against intuition.** Show whether each option covers
   our measured peak hour and our measured week.
4. **The orchestrator question separately from the worker question.** The lead is a thin router that
   talks to the founder and dispatches; workers are the volume. These have different shapes and may
   want different providers. Answer: does moving the lead to Codex actually remove the wall, or move
   it?
5. **Two accounts: does it actually work?** Two Max 5x accounts only help if work can be *routed*
   across them. State what exists today, what would have to be built, and what the session-identity
   and quota-accounting problems are. Do not assume it works because it is arithmetically appealing.
6. **A recommendation with a price**, and the one measurement that would change your mind.
7. **The bias line**: which recommendation favours your own vendor, and why you did or did not land
   there.

## Off limits

Recommending a plan whose limits you did not source; presenting an estimate as a published figure;
using our own token table against a limit that does not count cache reads without saying so; and
answering the orchestrator question with "use less context" — the founder is asking what to buy.
