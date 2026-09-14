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
2. **Explain the 31 `phase_record_refused` and the 3 `phase_record_failed` (rc=6).** A refusal that
   nobody reads is the same class of defect as the launcher refusals we made into journal events on
   2026-09-14. Name the reasons and their counts.
3. **Make same-vendor review impossible, not merely unusual.** Author and reviewer must resolve to
   different vendors. Vendor is not the arm: `glm`/`glm-flash` are one vendor, `codex`/`sol`/`astra`
   are one, `sonnet`/`haiku`/`opus`/`fable` are one. The three violations found were all
   Anthropic-internal, which is the easy case to miss precisely because the arms look different.
   Where a cross-vendor reviewer genuinely cannot be had (quota, capability, an arm being the only
   capable one), the lane must say so in a named, journalled event — never silently accept a
   same-vendor review.
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
3. Same-vendor review refused at the gate, demonstrated both ways by the negative control; the
   "no cross-vendor reviewer available" case journalled as a named event rather than silently
   allowed.
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
