# COMPLEXITY-ESTIMATOR-IS-OFF-01 — the complexity/cost brain exists, is built, and is switched off

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/COMPLEXITY-ESTIMATOR-IS-OFF-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-task-judge.sh,plugins/leadv2/config/leadv2-routing.yaml,plugins/leadv2/scripts/tests/test-complexity-routing.sh,tests/run-all.sh,docs/handoff/COMPLEXITY-ESTIMATOR-IS-OFF-01/

Main is `7927b0f` in `~/Projects/leadv2`. Branch from it.

Sibling lane `EFFORT-IS-NOT-WIRED-01` is in flight and touches the same resolver call. Rebase
onto it if it lands first; do not duplicate its work — effort is *one output* of the decision
this lane is about.

## What I established before writing this

There is a real estimator, and nothing on the live path calls it.

`_dispatch_v2` (`leadv2-dispatch-code.sh:2623-2651`) chains three components that already exist
on disk:

- `leadv2-task-judge.sh` → `estimate.json` carrying **`work_kind`, `duration_class`,
  `complexity`**;
- `leadv2-router-v2.sh filter|resolve` → eligibility and a resolved arm;
- `leadv2-route-bandit.sh sample --context-key <k>` → learned per-context preference.

Plus `leadv2-cost-estimate.sh`, which reads `docs/handoff/<id>/prior-art.yaml` — historical
costs of similar tasks — and writes a structured `cost-estimate.yaml`.

The whole chain sits behind `if [[ "${LEADV2_ROUTER_V2:-0}" == "1" ]]` at line **6708**. The
default is **0**. Every dispatch I ran today went through the other path instead:

```
route_resolved by=arbiter role=worker arm=codex model=gpt-5.6 tier=spark reason=cheapest_capable
route_resolved by=router router=arbiter model=sonnet rule=none reason=cheapest_capable
```

`cheapest_capable`, with **no notion of how hard the task is**. That is the whole defect: we do
not estimate complexity badly — on the live path we do not estimate it at all.

## [Critical] put the estimate on the live path

Make the judge's estimate part of every dispatch decision, not an opt-in branch. If
`_dispatch_v2` is the intended future, turn it on and make the fallback the exception; if it is
not, lift the judge out of it so the arbiter consults the same estimate. Say in `report.md`
which you chose and why, and what happens when the judge is unavailable — an absent estimate
must degrade to today's behaviour with a named log line, never crash a dispatch.

## [Critical] stop collapsing the estimate into two values

Line 2643 reduces the whole estimate to a context key:

```python
work_kind + ":" + ("short" if duration_class=="short" and complexity in ("trivial","simple") else "long")
```

Three dimensions in, one binary out. `complexity` and `duration_class` are thrown away
everywhere except that collapse, so a trivial one-line edit and a multi-subsystem refactor
reach the bandit under the same key whenever both are "long".

Keep the dimensions distinct in the routing decision. The key may stay coarse for the bandit's
own statistics if you justify it, but the arm/effort/tier choice must see `complexity` and
`duration_class` separately.

## [Critical] the estimate must reach the three things it should decide

An estimate that changes nothing is the same disease as an unwired knob:

1. **who does it** — arm selection weighs complexity, not only cost;
2. **how hard it thinks** — the effort/tier (coordinate with `EFFORT-IS-NOT-WIRED-01`);
3. **what it should cost** — `leadv2-cost-estimate.sh` runs and its number is recorded beside
   the decision, so a later round can compare estimate against actual.

The decision line must name the estimate that produced the choice — `complexity`,
`duration_class`, and the resulting arm/effort together. Today's line names none of them, which
is exactly how a switched-off brain went unnoticed.

## [Medium] close the loop

`prior-art.yaml` exists for a reason: the estimate should get better with history. Record, on
every terminal, the estimate and the actual (rounds, wall-clock, arm) so the next estimate has
something to learn from. If that loop already exists, prove it runs; if it does not, say so
plainly in `report.md` rather than half-building it.

## Acceptance

Build `test-complexity-routing.sh` against fixture missions and fixture routing data — never a
live provider, never a real dispatch — covering:

1. a trivial one-file edit and a multi-subsystem change ⇒ **different** arm/effort decisions;
2. same `work_kind`, differing `complexity` ⇒ decisions differ (this is the collapse bug);
3. same `complexity`, differing `duration_class` ⇒ decisions differ;
4. judge unavailable ⇒ dispatch still proceeds, with a log line naming the degradation;
5. the decision line names `complexity`, `duration_class` and the resulting arm;
6. a cost estimate is written and is retrievable beside the decision;
7. adding a routing rule changes the outcome with **no script edit**.

Add the `EXTRA_SUITE_MAP` rows and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production function body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. A fixture-only mutation is not a control for a call-site defect — that
  exact failure shipped in two lanes today.
- A kill counts only if **this suite alone** goes red.
- A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Never hardcode an arm into or out of routing — data decides.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

Complexity reaches the live decision, the three dimensions are no longer collapsed into a
binary, the decision line names what produced it, and a mutation that switches the estimator
back off turns the suite red with the exit code following.
