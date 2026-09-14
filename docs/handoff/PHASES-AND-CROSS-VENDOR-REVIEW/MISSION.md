# DO-THE-PHASES-AND-THE-CROSS-VENDOR-REVIEW-ACTUALLY-RUN-01

Founder, 2026-09-14: *«важно чтобы работали все фазы, чтобы было ревью каждой задачи другим
вендором… мы про это говорили, мы это делали, но работоспособность хз»*. He is right to doubt it.
Two measurements, both taken today, both pointing at gaps.

## Measured, 2026-09-14

**Cross-vendor review — mostly holds, not enforced.** Of the `review_gate` lines that carry BOTH
`author=` and `reviewer=` (28 lines; note the boundary — 101 journal lines mention a reviewer, so
most review records do not carry the author on the same line):

```text
25/28  (89.3%)  cross-vendor
 3/28  (10.7%)  SAME vendor:  sonnet -> fable (2),  fable -> opus (1)
most common pair: glm -> codex (11)
```

So the intent works in the common case and nothing stops the exception.

**Phases — the later ones barely appear.** Counts of `phase=` across all lane journals:

```text
build 718 | pre_arm_selection 493 | classify 365 | plan 112 | e2e 44 | gate1 28 | review 9 | test 6 | diverge 5
phase_recorded 645 | phase_record_refused 31 | phase_record_failed 3 (all rc=6)
```

A two-orders-of-magnitude cliff between `build` and `review`. Counting cannot distinguish the two
explanations — **later phases are not RECORDED**, or **lanes do not REACH them** — and that
ambiguity is exactly why nobody can answer the founder's question today.

## What to establish, in this order

1. **Resolve the phase cliff to one of the two causes, with evidence per lane.** Take a bounded,
   named set of recent terminal lanes and, for each, determine whether it reached review/test/e2e
   and failed to record, or never got there. The answer is probably "both, in different
   proportions" — then give the proportions. This is the whole question; the rest is downstream.

   **Do NOT attribute a lane to a repo by its state-root directory — it is roughly a coin flip.**
   Measured 2026-09-14 from the explicit work-root field in the journals under
   `~/.claude/leadv2-state/leadv2/tasks/`: **196 lanes declare `~/Projects/leadv2` and 195 declare
   `~/Projects/persona-engine`.** The state root comes from the session environment, not from cwd,
   so a leadv2 lane dispatched from a persona-engine session books itself in persona-engine's
   control plane and vice versa. Root totals for context: leadv2 735 lanes, persona-engine 609,
   getmany-followup-bot 64.

   Consequence for you: any per-repo denominator built on the directory is wrong, and a "recent
   lanes in this repo" sample selected that way is half foreign. Use the declared work-root field.
   My own cliff counts (build 718 … review 9) were globbed across ALL roots, so they are totals and
   are not distorted by this — but they also cannot be split per repo without re-deriving from the
   field. Say which denominator you used.

   Second boundary on the same data, from the peer session: persona-engine set `LEADV2_E2E_CMD` at
   **2026-09-14T08:20Z** so its e2e gate stops parking lanes before review. Treat persona-engine
   lanes before and after that timestamp as two regimes; mixing them will make the cliff look like
   it healed on its own.
2. **Explain the 31 `phase_record_refused` and the 3 `phase_record_failed` (rc=6).** A refusal that
   nobody reads is the same class of defect as the launcher refusals we made into journal events on
   2026-09-14. Name the reasons and their counts.
3. **Enforce THE RULE — and the rule is stated once, here, verbatim:**

   > A review is valid when the reviewer is a **different vendor** from the author, **OR** the
   > reviewer's `capability` is **strictly greater** than the author's. Everything else refuses.

   Build the gate and every negative control against **that sentence and no other phrasing**. In
   particular an earlier draft of this mission said "make same-vendor review impossible" — that is
   now WRONG and superseded: under the founder's strength order (landed `6b548736`) `sonnet(4) ->
   fable(6)` is legal, and a gate written to the older wording would reject it. A negative control
   proving the wrong rule is harder to spot than a missing one, so pin the phrasing before you
   write a single assertion.

   Vendor is not the arm: `glm`/`glm-flash` are one vendor, `codex`/`sol`/`astra` are one,
   `sonnet`/`haiku`/`opus`/`fable` are one. The violations found were all Anthropic-internal —
   the easy case to miss precisely because the arms look different.

   Where neither condition can be met (quota, capability, an arm being the only capable one), the
   lane must say so in a named, journalled event — never silently accept the review.

   **Author-exclusion and the strength rule are two different mechanisms and they can disagree.**
   A live probe on 2026-09-14 (peer session, K1's real diff, author sonnet) returned
   `excluded=glm=ok:83,opus=ok:24,sonnet=author` — the author was removed **by role, before any
   strength comparison**, and `fable` was not in the pool at all (`pool_ok=3`). So that probe
   proves author-exclusion works and proves **nothing** about whether a legal same-vendor pair
   would be SELECTED when available. Your acceptance needs its own case: fable in the pool, sonnet
   the author, and a demonstration of what actually happens.

   That same exclusion field is where a gate's evidence must come from, and it currently mixes
   exclusion-by-role (`sonnet=author`) with exclusion-by-quota (`glm=ok:83`) under one key with no
   parseable grammar. Fix the grammar before building the gate on it.

3a. **A verification that could not run must not report success.** The same probe returned
   `verified: 0/1 reason=single_arm_pool` with `verifier_arm:` empty and `verifier_verdict:
   unverified` — while the SAME line said `degraded=false`. A check that could not execute,
   reported beside a flag asserting nothing was degraded, is the same defect class as the quota
   reader that printed a plausible number for twelve hours while returning `refresh http 401`.
   A degraded verification must make `degraded` true, or the field is decorative.
4. **Make the author recorded wherever the reviewer is.** Only 28 of 101 reviewer mentions carry the
   author, so compliance cannot even be audited on the other 73. Fix the record, then re-run the
   measurement above and report the real percentage over the full population.

## Method — binding

- **Negative control, run it:** force a same-vendor pairing in a fixture and show the gate refusing
  with its named reason; then a cross-vendor pairing passing. A rule you cannot demonstrate
  refusing is not a rule.
- **Do not fix the phase cliff by recording phases the lane did not actually reach.** That converts
  a visible gap into a false green, which is the disease this whole programme exists to kill. If a
  lane legitimately skips a phase, the skip must be recorded AS a skip with its reason.
- Name the surface of every count, and carry the boundary of every sample (the 28-of-101 above is
  the model).

## Acceptance

1. The phase cliff attributed to not-recorded vs not-reached, with proportions over a named lane
   set.
2. The 31 refusals and 3 failures explained by reason with counts.
3. The rule as stated verbatim in item 3 enforced at the gate, with FOUR demonstrated cases, not
   two: (a) cross-vendor pair passes; (b) same-vendor with a strictly stronger reviewer passes —
   use `sonnet` author, `fable` in the pool, the exact case the founder's ruling legalised;
   (c) same-vendor with an equal-or-weaker reviewer refuses with a named reason — `fable(6)`
   author, `opus(5)` reviewer is the real violation still standing; (d) neither condition
   satisfiable is journalled as a named event rather than silently allowed.
3b. A verification that could not run reports `degraded=true`, demonstrated; and the exclusion
   field distinguishes exclusion-by-role from exclusion-by-quota in a parseable way.
4. Author recorded alongside reviewer, and the cross-vendor percentage re-measured over the full
   population rather than the 28-line sample.
5. New suite registered so `tests/run-all.sh --scope changed` SELECTS it.
6. Still green: `test-arbiter-prices-by-provider.sh`, `test-reset-urgency.sh`,
   `test-arbiter-decision-record-inputs.sh`, `test-launcher-refusal-event.sh`,
   `test-leadv2-task-judge.sh`, `test-codex-drain-fit.sh`, `test-codex-lane-token-total.sh`.
   `test-codex-tiers-selectable.sh` is PRE-EXISTING RED (3 FAIL / 6 PASS, identical on untouched
   main) — do not fix it here, do not make it worse.

## Off limits

- Recording a phase that did not happen, for any reason.
- Relaxing the cross-vendor rule to make a number look better.
- `router_v2.cost`, the price machinery, the balancer's headroom terms — a sibling lane
  (`THE-BALANCER-CONCENTRATES-ON-THE-EMPTIEST-BUCKET-01`) owns arm selection. Do not touch
  selection logic; this lane is about what is RECORDED and what is ENFORCED after selection.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.

## AMENDMENT (founder ruling, 2026-09-14): same vendor is acceptable when the reviewer is STRONGER

*«ну это было бы ок если бы всегда ревью более слабой модели делал более сильная»*. The rule is
therefore not "never same vendor" but: **the reviewer must be a different vendor, OR a strictly
stronger model.** Implement that, not the cruder version above.

Applied to the three violations found, it rescues **none** of them — all three are
capability-EQUAL, not stronger:

```text
sonnet(cap 4) -> fable(cap 4)   x2     equal
fable (cap 4) -> opus (cap 4)   x1     equal
```

And here is the blocker you must solve first: **the matrix cannot express "stronger" today.**
Seven of twelve rows share `capability: 4`:

```text
capability 2 : glm-flash, freepool, haiku
capability 3 : codex/gpt-5.6-luna
capability 4 : glm, codex/terra, codex/sol, sol, sonnet, opus, fable
capability 5 : astra/gpt-6-astra
```

So `capability` cannot order opus above sonnet, or sol above terra. A strictly-stronger test built
on it would silently pass every same-vendor pair inside the cap-4 block — a false green wearing a
rule's name. Either establish a real strength ordering (OpenAI publishes one for its own family:
`~/.codex/models_cache.json` priorities astra 1, sol 6, terra 7, luna 8 — a strength ladder we
already cite in `leadv2-routing.yaml:294-312`; Anthropic has no equivalent column in our config),
or state plainly that "stronger" is not expressible and the rule degrades to different-vendor for
the arms where it cannot be decided. Do not fake an ordering.

Report which arms you can order and which you cannot, and say which rule each pair fell under.
