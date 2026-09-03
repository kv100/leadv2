# ARBITER-ESTIMATES-BLIND-01 — round 2: your census was right, the brief was wrong

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- **Commit after every step.** A worker that dies at max_turns with an uncommitted tree leaves
  nothing; four previous attempts on this task died exactly that way.
- Suite path is `tests/run-all.sh` at the repo **ROOT**. Do NOT open with a full suite run.

**Class:** Standard. **Repo:** leadv2 plugin.

## The question a previous round asked, and its answer

A previous round stopped and asked:

> The brief's chain (`resolve_arm` v1 / `resolve_v2_dispatch` v2, gated by `LEADV2_ROUTER_V2` at
> `dispatch-code.sh:6458`) is a SHADOW path. The REAL live arm-selection mechanism is
> `route_arbiter()` in `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`, called unconditionally
> at `dispatch-code.sh:6635`, which is what emitted the brief's own evidence line
> `reason=cheapest_capable`. The arbiter selects by static per-cell `cost` in `routing.yaml`'s
> `capability_matrix`, keyed only on `(kind, size=admission task_class, protected)` — it never calls
> `leadv2-task-judge.sh` and never sees complexity/duration_class. Wire the arbiter instead?

**Answer: yes. Wire the ARBITER.** The census is accepted as the ground truth and this brief
supersedes the original. The founder's own words on it: the arbiter is the thing that is supposed to
be smart — deciding hardness is its job, not the lead's. Do not touch `resolve_arm` /
`resolve_v2_dispatch`; implementing the original brief would have left the real defect untouched,
which is precisely why that round was right to stop.

**Record that finding in your report** — a round that falsifies its own brief is the most valuable
output this task has produced so far, and it must not be lost in the rewrite.

## The defect, stated against the real path

`route_arbiter()` picks the cheapest cell that can do `(kind, size, protected)`. `size` is the
admission task_class — Trivial/Light/Standard/Heavy — which says how much *ceremony* the task gets,
not how *hard* it is. So a one-line doc edit and a cross-subsystem rewrite that both classify
Standard get the same arm, and the arm is always the cheapest one. That is why cheap arms keep being
handed work they then fail twice, and why `leadv2-task-judge.sh` and `cost-estimate.sh` exist and
are never consulted on the live path.

## Deliver

1. **The arbiter sees complexity.** Compute the judge estimate (`leadv2-task-judge.sh`, plus
   `cost-estimate.sh` where it applies) **unconditionally** before arm selection, and pass
   complexity / duration_class into `route_arbiter()`. Additive: if the estimate cannot be produced,
   the arbiter must behave exactly as it does today — a missing estimate is never a hard failure.
2. **Complexity reorders or floors the candidate chain.** State plainly which you chose and why —
   a floor ("below complexity X the cheapest arms are not candidates") is easier to reason about
   than a reordering, but say it either way. Costs stay in `routing.yaml`; do not hardcode an arm.
3. **The decision line names the complexity it used.** Today it says `reason=cheapest_capable` and a
   reader cannot tell what it knew. It must say what complexity/duration it saw and why that led to
   this arm — a verdict nobody can check is how this defect survived.
4. **Reversible with a knob that already exists** — `routing.yaml` / an env flag. No new flag day.

## Prove it
- Two tasks that both classify Standard, one trivially small and one cross-subsystem → different
  arms, and both decision lines name the complexity. Paste both.
- Estimate unavailable (make the judge fail in a mktemp fixture) → selection identical to today's.
  Paste before and after.
- **Negative control:** remove the complexity input inside `route_arbiter()`'s body in a mktemp FULL
  copy whose baseline is proven green → the two Standard tasks collapse back onto one arm. Paste
  baseline and mutant runs. Insert the mutation INSIDE the function body, never at top level.
- `tests/run-all.sh --scope changed` from the LANE ROOT at the END, FOREGROUND, `timeout 1800`.

## Constraints
LANE_WRITES: `plugins/leadv2/scripts/`, `plugins/leadv2/scripts/lib/`, `plugins/leadv2/config/`,
`tests/`, this task's handoff dir. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`critic.*`. Mutants and fixtures in mktemp only.

## Done when
The live arbiter consults a complexity estimate, two same-class tasks of different hardness get
different arms with decision lines that say why, a missing estimate changes nothing, and the
negative control collapses them back against a green baseline.
