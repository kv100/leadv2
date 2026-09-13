# ARBITER-DECISION-RECORD-CARRIES-ITS-INPUTS-01

## Why this exists — a measured blocker, not a guess

Round 2 of `48b8297b4cc1` (merge `1e688f5c`, report `docs/handoff/ARBITER-DECISION-INPUTS/report.md`)
tried to answer "does finer granularity move any routing decision" and could not, for a reason it
measured rather than asserted. The recorded arbiter-decision artifact had 348 rows, and:

```text
complexity_present=0/348
duration_class_present=0/348
req_eff_present=0/348
quota_present=0/348
fit_bucket_present=0/348
```

The OUTPUTS are recorded (arms: fable 248, codex 66, sonnet 34). The INPUTS the decision was made
from are not. So no counterfactual replay is possible: "refining this axis moves zero decisions"
would be fabricated, and the honest answer is **not measurable**. The lane correctly refused to
refine anything and said so.

That is this lane's job: make the decision record carry the inputs, so the next lane can replay.

The same reason blocks D2 (token estimate): `cost_actual_rows=68 numeric_tokens=1
estimate_files=429 numeric_joined_to_estimate=0` — 429 estimate files and 68 actual rows that do
not join, so R² is *undefined*, not bad. A join key is missing too.

## What to build

### 1. The decision record carries its inputs

Every arbiter decision already PRINTS these on the success line — `complexity=`, `duration_class=`,
`req_eff=`, `util_*`, `reset_*`, `fit_bucket=`, and since 2026-09-13 also `reset_urgency=` and
`cost_src=`. Find where the recorded artifact is written (it is NOT the same surface as the printed
line — that is the whole defect) and make it carry the same fields.

- Do not invent new fields. Start from the fields the line already emits; a field that is printed
  but not recorded is the bug.
- Record the CANDIDATE SET too, not only the winner. A counterfactual replay needs to know which
  arms were available and why each was excluded (`arm_excluded=codex:price_ratio,glm:capped` is
  already printed).
- Schema-version the record so an old row is distinguishable from a new one. A replay that silently
  mixes both is worse than one that refuses.

### 2. A join key between an estimate and its actual

`docs/handoff/*/cost-estimate.yaml` (429 of them) and the `cost_actual` rows (68) cannot be joined.
Find why — most likely they are keyed differently (row id vs lane sig8 vs attempt id) — and make
one of them carry the other's key. Report the joined count afterwards; if it is still under 2,
say so with the number rather than shipping a fit.

### 3. The two capability gates disagree

Measured today, both halves verified:
- `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:1918` computes `_fit_order` from kind/size
  BEFORE the economic sort, so the arbiter does consider capability when ranking.
- AND the launcher refused the arbiter's pick on the very next step:
  `/var/folders/.../leadv2-dispatch-spawn-0a148de1.stderr.log` contains exactly
  `refused: arm_not_capable_for_kind`, after the arbiter had picked sonnet for `--kind plugin`.
  A later resolve-only run emitted `kind_unmapped=tooling`.

So there are TWO notions of "capable" — the arbiter's `_fit` and the launcher's kind check — and on
that dispatch they disagreed, costing a wasted selection and a silent re-roll to codex. Round 2
concluded "a second capability matrix would duplicate a pre-ranking admission gate"; that is right
about not adding a matrix and wrong about there being no gap. **The deliverable is not a new
matrix: it is to make the arbiter's `_fit` know what the launcher will refuse**, or, if they cannot
be unified, to RECORD the disagreement as its own event so its frequency is countable.

Count how often it happens first. If it is rare, say so with the number and stop — a rare
disagreement that is now visible in the record is an acceptable outcome.

## Method — binding

- Every claim carries its probe: a decision line, a replay, or the exact search that returned nothing.
- Every change gets a NEGATIVE CONTROL: mutate inside the function body in a scratch worktree, show
  the suite goes red, restore. Strip comments when grepping — a mutation whose target text lives in
  a comment rots into a permanent green.
- Re-check what looks obviously true. Today's round-2 lane falsified a premise I handed it, and was
  half right: the premise's observation was real, its remedy was wrong. Do that to this brief too.

## Acceptance

1. A replay over the recorded decisions is POSSIBLE after your change — demonstrate it by replaying
   at least one axis and reporting the movement count (zero is a result).
2. `test-reset-urgency.sh` 10/10, `test-arbiter-prices-by-provider.sh` 7/7,
   `test-leadv2-task-judge.sh` 31/31 all still green — you did not break what landed today.
3. New suites registered so `tests/run-all.sh --scope changed` SELECTS them; commit first, then
   show the selection output.
4. Per item: BUILT (with the number), MEASURED AND REJECTED (with the number), or NOT REACHED.

## Off limits

- `reset_urgency`, `provider_cost`, the judge's arm switch — all landed today, not yours to revise.
- Any hardcoded arm exclusion.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
