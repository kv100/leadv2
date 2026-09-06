# ARBITER-COST-IS-A-HAND-WRITTEN-CONSTANT-01 + CODEX-TIERS-SHARE-ONE-MODEL-01 — census

Measurement round, no fixes. Source: `plugins/leadv2/config/leadv2-routing.yaml` (`capability_matrix`,
lines ~188-218), `docs/leadv2/model-select-telemetry.csv` (leadv2 repo, 692 rows), git history.

## Founder's question, restated

"Cost-ranking always cuts off the smart choice" and "codex has different tiers/models for
different tasks — that was the point of making the arbiter smart." He's questioning the premise
of cost-ranking itself, not the implementation. This census answers: (1) is the cost scale real or
invented, (2) does the scale match observed behavior, (3) are codex's three tiers actually
different arms.

## 1. Where do the nine numbers come from

| arm | cost | origin |
|---|---|---|
| glm | 1 | `d6179dff` (2026-08-26, author "Claude Code", commit msg "T17 — route arbiter"). No pricing citation, no founder sign-off in the commit. Comment added later: "`cost` is a relative unit used only among capable, uncapped arms" — a definition, not a derivation. |
| freepool | 1 | same commit, same non-derivation. |
| codex (volume) | 3 | same commit. |
| codex (standard) | 4 | same commit. |
| codex (top) | 7 | same commit. |
| haiku | 2 | same commit. |
| sonnet | 5 | same commit. |
| opus | 9 | same commit. |
| glm-flash | 0.33 | **Different, later, real.** `GLM-EFFICIENCY-01`, founder ruling on ask q-bba84179 (2026-09-02, option b): corrected from a legacy 0.4 against Z.AI's published credit multipliers (docs.z.ai/devpack/teamplan.md, fetched 2026-09-02) — flash 2.3in/0.56cached/8out vs glm-5.3 6.9/1.7/24, exactly ⅓. This is the one number in the ladder with a shown computation and a named founder decision behind it. |

**Verdict on the hypothesis: confirmed for 8 of 9.** All eight non-flash numbers were introduced in
one commit by an AI agent implementing the arbiter feature, with a comment that states they are "a
relative unit" and shows no computation, no vendor pricing citation, and no founder decision
reference. They are not measured, and — with one partial exception below — nothing since has ever
measured them either. `cheapest_capable` is optimizing a number a coding agent picked while writing
the feature, for 8 of its 9 arms.

**One caveat, stated as a check, not a defense of the process:** I compared the Claude-family three
(haiku=2, sonnet=5, opus=9 → ratio 1 : 2.5 : 4.5) against Anthropic's currently published API output
pricing (Haiku 4.5 $5, Sonnet 5 $10, Opus 5 $25 per M tokens → ratio 1 : 2 : 5 — [Anthropic pricing,
Sept 2026](https://www.finout.io/blog/anthropic-api-pricing)). The hand-picked ratio is close to the
real one for this one triple. That does not make the number "measured" — the commit shows no such
comparison and nobody could have cited September 2026 pricing in August — but it means the ladder's
ordinal SHAPE for the Claude family isn't wildly wrong, likely because whoever picked 2/5/9 had a
rough real intuition for relative Claude pricing even without writing it down. glm/freepool/codex
have no equivalent public per-effort benchmark to check against at all, so this partial vindication
does not extend to them.

## 2. Does the ladder match observed behavior

Source: `docs/leadv2/model-select-telemetry.csv`, 692 rows, cross-checked for the fixture
contamination named in the brief (`~/.claude/leadv2-state/.ephemeral/leadv2-lwt.*`, 357 test-harness
roots found there) — **zero overlap** between this CSV's 212 distinct task ids and any
`dispatch-ledger.jsonl` inside those fixture roots (checked a 100-id sample, full cross-reference
would need all 212 but the sample found none, and the CSV's own generation path is a single shared
file, not one per lwt scratch root, so contamination here is structurally unlikely). This data
source looks clean; I am not vouching for journal-based data outside this CSV.

**Scope, attached here because it belongs next to the number, not in a footnote:** `role` is 100%
`worker` and `work_kind` never contains `plan` in any of the 692 rows (confirmed in the follow-up,
`haiku-opus-zero-rows.md`) — this table describes the **build/worker dispatch path only**. Every
number below (freepool vs. glm's 34-point gap, sonnet's 41% rescue rate) is a statement about build
routing, not about routing in general. The plan path (where opus and fable are live candidates) is
separately unmeasured by this file — see that follow-up.

Per arm, all 692 rows (no haiku, no opus, no per-tier codex breakdown — see gaps below):

| arm | n | terminal | avg spawn→terminal (s) | fallback_depth>0 |
|---|---|---|---|---|
| sonnet | 303 | win 273 / fail 30 (90%/10%) | 59.8 | 123 (41%) |
| codex | 99 | win 99 / fail 0 (100%) | 44.2 | 6 (6%) |
| glm-flash | 88 | win 88 / fail 0 (100%) | 29.0 | 0 |
| glm | 76 | win 64 / fail 12 (84%/16%) | 18.2 | 0 |
| freepool | 64 | win 32 / fail 32 (50%/50%) | 13.9 | 19 (30%) |
| refuse | 62 | fail 62 (0%) | 0.8 | 0 |

**The number, not the impression:** freepool (cost=1, same rank as glm) wins exactly half its 64
dispatches. glm, at the identical cost=1, wins 84%. Two arms sharing one cost rank differ by 34
points of win rate — the cost ladder cannot see this at all, since cost is its only ranking axis and
both are tied. An arm that fails half the time is not "cost 1" in any sense that matters to whether
the work gets done; the ladder currently treats it as indistinguishable from an arm that fails one
time in six.

sonnet's 41% fallback-depth>0 rate says something structural: two-fifths of sonnet's dispatches were
not the arbiter's first choice — they were reached after something cheaper already failed or
refused. sonnet is functioning largely as the RESCUE arm, not a competitively-ranked peer choice,
which is a different role than "cost 5, ranked below codex/haiku."

**Gaps — stated as gaps, not filled in:**
- **haiku, opus: zero rows.** No data. Cannot say anything about whether their cost rank (2, 9)
  matches observed behavior, because there is no observed behavior in this file.
- **codex's three tiers: cannot be separated in this telemetry.** The `model` column holds `codex`
  or the bare model slug (`gpt-5.6` — itself stale, predating the `gpt-6-astra` rename in the current
  config) inconsistently across rows, with no `tier` or `cost` column at all. All 99 codex rows are
  one undifferentiated bucket. I cannot tell you whether volume/standard/top differ in win rate or
  latency from this data source — that is a real gap, not an implied "probably fine."

## 3. Codex's three tiers — do they differ in anything but the price label

`capability_matrix` lines 213-215: all three rows have `model: gpt-6-astra`. Traced the actual
launcher (`leadv2-codex-planner.sh:89-121`, `_resolve_tier()`):

```
top:      TIER_MODEL="gpt-6-astra"; TIER_EFFORT="high"
standard: TIER_MODEL="gpt-6-astra"; TIER_EFFORT="medium"
volume:   TIER_MODEL="gpt-6-astra"; TIER_EFFORT="low"
```

The resolver's own comment (line 96, dated to an incident on 2026-09-06) states this outright:
**"One model; tier is the effort dial."**

**Verdict: partially confirmed, partially not — not "one hand with three price tags."** It is one
model, exactly as the founder suspected. But `reasoning effort` (low/medium/high) is a real Codex
CLI parameter that measurably changes latency, token spend, and output quality — it is not
decorative, and `codex-task.sh` genuinely refuses the banned `spark` tier and enforces a `--reason`
gate on `top` (scarce-tier guardrail, `CODEX-QUOTA-GUARDRAILS-01`), both real behavioral gates, not
cosmetic. So the three "tiers" are not an illusion of choice — they are one model at three real
effort settings, which is a narrower kind of choice than the founder's framing ("different models
for different tasks") implied, but not zero choice either. I cannot quantify whether the three
efforts actually differ in win rate or latency, per the telemetry gap above — that would need a
proper tier-tagged data source, which doesn't currently exist.

## 4. Fable

`capability_matrix` (the arbiter's own list): **zero occurrences of `fable`.** Confirmed by direct
grep — it is unreachable through `cheapest_capable` by construction, exactly as you and the founder
noted.

It exists in a second, separate list further down the file (line 495, `id: fable`, `dispatch: false`),
justified by its own comment: "never dispatched by dispatch-code.sh (the plan workflow uses fable
directly via `workflows/leadv2-plan.js`)." Checked: **that file does not exist.** The most recent
commit touching it, `09a45cb7`, is titled "ONE-PATH plan doc-flip — leadv2-plan-run.sh canonical,
Workflow('leadv2-plan') deleted." The replacement, `leadv2-plan-run.sh`, mentions fable only in a
comment listing valid model names (line 396) — no actual dispatch call.

**Verdict: dead entry, not unfinished work.** Its own justification names a code path that was
deleted in a later commit, and nothing replaced the wiring. Combined with the project-wide Fable
retirement (`FABLE-RETIRE-01`, 2026-07-07 sunset, noted elsewhere in this project's history), this
reads as a stale artifact from before that retirement that nobody removed when the file it pointed
to was deleted out from under it — not a row someone meant to finish.

## Summary for the founder's actual question

Cost-ranking isn't wrong because ranking-by-cost is a bad idea in principle — it's that the cost
number it ranks by was written by an agent in one afternoon with no pricing behind 8 of 9 entries,
and nothing has checked it against outcomes since (freepool and glm sit at an identical rank while
one fails 3x more often than the other). Separately, codex's "three models for different tasks" is
actually one model at three effort settings — a real but narrower kind of differentiation than the
framing suggested. Neither finding says cost-ranking must go; both say the current numbers aren't
trustworthy inputs to it, in different ways, for different reasons.
