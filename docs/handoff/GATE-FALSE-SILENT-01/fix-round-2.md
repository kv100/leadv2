# Fix round 2 — GATE-FALSE-SILENT-01: the commits-ahead probe still reads 0

Repo: ~/Projects/leadv2. Continue in the EXISTING lane worktree
`.claude/worktrees/2d8a2849` (commit `fb97555`). Do not start from scratch — the
product change there is sound and its reasoning is correct; two tests are red.

## What round 1 got right (keep it)

`_pc_lane_commits_ahead` in `leadv2-dispatch-product-close.sh` correctly identified that
`_pc_diff_base` is defined INSIDE `pc_scope_diff`'s body and therefore does not exist as
a callable function at the probe's call site, and duplicated the base-resolution
algorithm inline instead. That analysis is right — do not "simplify" it back into a call
to `_pc_diff_base`.

## What is red (selfcheck, verbatim)

`docs/handoff/dispatch-2d8a2849/selfcheck.md` — checks: 7, failed: 2.

**Red 1 — the fix does not actually fire.**
`tests/test-silent-arm-commits-ahead.sh`:
```
FAIL: Case A: a lane with a commit ahead of base was classified arm_produced_nothing
FAIL: Case A: arm_advance decision emitted for a lane that produced a commit
```
The lane in that fixture HAS a commit ahead of base, and the verdict is still
`arm_produced_nothing`. So `_pc_lane_commits_ahead` returns 0 there. The most likely
cause is its own documented fail-closed branch: base resolution fails in the fixture
(no `LEADV2_LANE_START_SHA`, no `${CACHE_BASE}/dispatch-${TASK}.start-sha`, no
`origin/main`), it returns "0", and 0 is indistinguishable from today's blindness.
Diagnose it for real — print the resolved base and the count in the failing fixture —
then make it work. If no base is resolvable, `HEAD` vs the worktree's own merge-base
with its parent branch is still enough to prove "this lane produced a commit"; a probe
that cannot tell must NOT conclude silence.

**Red 2 — a fixture bug in the sibling test.**
`tests/test-dispatch-silent-arm.sh` Case 2 expects terminal `landed`, gets
`refused / unscoped_lane_work`, evidence `lane_root=lane dirty=1 offending=newfile.txt`.
The fixture writes `newfile.txt` without declaring it, so the scope gate refuses —
correctly. Fix the FIXTURE (declare the file it writes, or assert the refusal it
actually deserves). Do not weaken the scope gate to make this pass.

## Off-limits
- Do not touch `pc_scope_diff`, the e2e gate, or any assertion outside these two tests.
- Do not touch main's unrelated uncommitted files: no stash/reset/clean.
- Do not merge anything.

## Verify (real pasted output)
1. `bash plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh` — all cases,
   including the positive control that a truly silent arm still yields
   `arm_produced_nothing` and still advances exactly once.
2. `bash plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` — all cases.
3. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` — counts + exit code. Known
   pre-existing, NOT yours: `deferred-GLM ladder (V3-GLM-LADDER-01)` and
   `fanout classifier/runner guard`.

## Deliverable
`docs/handoff/GATE-FALSE-SILENT-01/report.md` — what made the probe read 0, the changed
lines with file:line, the three verifications with pasted output, `git diff --stat`.
**Run every verification in the FOREGROUND with a timeout; ending your turn while a job
is still running is a protocol violation.** End with DELIVERABLE_COMPLETE.
