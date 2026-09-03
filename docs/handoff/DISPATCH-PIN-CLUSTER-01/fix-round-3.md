# DISPATCH-PIN-CLUSTER-01 — round 3 (Standard)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`

LANE_WRITES: plugins/leadv2/scripts/tests/test-lane-placement-pin.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/lib/leadv2-lane-guard.sh,tests/run-all.sh

Five commits are in the lane, ending at `b7ee979`. `docs/handoff/DISPATCH-PIN-CLUSTER-01/context.yaml`
is still BINDING. Round 2's four review fixes are committed and five of six suites are green.
This round has exactly one job, plus whatever that job exposes.

## The one job: `test-lane-placement-pin.sh` is quota-dependent, so it proves nothing

Measured 2026-08-30 08:25Z in this lane, full 600s run: **passed=16 failed=11**.

Every one of the eleven failures traces to the same root, and none of them is the code under
test being wrong:

```
[TEST] FAIL: P-g: dispatch exited 3 (expected 0)
[TEST] FAIL: P-g: worker cwd='' == RESUME or empty (regression)
[TEST] FAIL: D3: ensure-created plan missing (rc=3, cwd='')
[TEST] FAIL: D3: worker mission omitted lane-local plan instruction
```

Exit code 3 is the dispatcher's documented `arm=opus (lead judgment, not auto-dispatched)`.
The suite stubs exactly one arm — `LEADV2_DISPATCH_GLM_BIN="${GLM_STUB}"` at `:136` — and
nothing else. So the arbiter consults **live** quota: today `util_glm=81`, GLM is over its
80% gate, the ladder walks past every stubbed arm and lands on opus, dispatch exits 3 before
a worker is ever spawned, and eleven assertions that all read `worker cwd` collapse for want
of a worker. On a day when GLM has headroom this same suite is green. **A suite whose verdict
depends on a provider's weekly quota is not a control.**

The consequence that matters: the Critical from round 2 — `_deliver_plan_into_lane` firing
after `WORK_ROOT` is bound — is currently **unproven, not disproven**. The call did move
(`leadv2-dispatch-code.sh:6110`, after the ensure block's `WORK_ROOT="${_lane_dir}"` at
`:6102`), but the assertion that would demonstrate it never got a worker to inspect.

### What to build

1. Pin the routing decision inside the suite so it never reads live quota. Stub every arm the
   ladder can reach, or pin the arm outright — whichever the dispatcher already supports; do
   not invent a new env knob if one exists. Read how `test-plan-in-lane.sh` and
   `test-lane-containment.sh` do it: both ran green today under the same live quota, so they
   already solved this.
2. Then re-run and report `passed=/failed=` verbatim. Every remaining failure after the quota
   dependency is gone is a REAL finding — fix it, or dispute it with evidence.
3. **The D3 assertion must exercise the ENSURE-created path** (no `--worktree`, no
   `--resume-lane`), because that is the path the Critical was about. Prove it with a
   negative control: move `_deliver_plan_into_lane` back above the ensure block, show the
   suite RED, revert, show GREEN. Paste both runs.

## Also fix, found live this session

Read `docs/handoff/DISPATCH-PIN-CLUSTER-01/live-evidence-20260830-0820.md` — four consecutive
dispatch refusals of one task, all inside this cluster's scope. Two are in your write set:

- **`--resume-lane <founder-id>` does not bind `founder_task_id`.** The placement step
  resolves it (`lane_placement_pinned … key=ANTI-SILENCE-STATUSLINE-01`) and then
  `_lane_writes_guard` (`:3443`) sees it empty, so its most forgiving admission path — "an
  existing lane worktree; isolation substitutes for a declaration" — cannot fire even though
  the lane worktree exists. Propagate the id the placement step already resolved. Add the
  control: a resume-lane dispatch with no `LANE_WRITES:` and no `--task-id` must be admitted
  on the strength of the existing worktree.
- **The `no_lane_writes` refusal names no remedy.** It parks without saying what grammar it
  wanted. It accepts a `LANE_WRITES: a,b,c` line; a prose "Write set:" section with markdown
  bullets — the obvious declaration for any human or worker — satisfies nothing. Make the
  refusal print the accepted grammar, the same way the phase-precondition refusal prints its
  `remedy:` lines. This cost two of the four refusals above.

`--task-id` being absent from `usage` is part of the same complaint; add it while you are there.

## Rules

- Every fix keeps its negative control and you RUN it: mutation inside the function body, RED,
  revert, GREEN. Paste the runs.
- Do not weaken any existing assertion to make a suite pass. If an assertion is wrong, say so
  with evidence and change it deliberately, in its own commit, with the reason in the message.
- **Commit before you stop.** Round 2 died at 05:32 with 150 lines uncommitted in this lane
  and had to be picked up by hand; that is the very defect this cluster exists to fix.

## Done means

`git -C <lane root> status --porcelain` shows only control-plane residue, commit shas reported,
the placement-pin suite's `passed=/failed=` pasted before and after, and one line per finding
saying fixed or disputed-with-evidence.
