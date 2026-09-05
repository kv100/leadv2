# BOARD-BLIND-TO-DETACHED-WORKERS-01 — round 2: make the red test green

**Canonical repo. The fix applies to persona-engine, m3-market and respiro-ios at once.**
Founder approved editing shared on 2026-08-29.

## Step 0 — take the prior work

The round-1 worker died before writing the fix, but its test survived and is committed on branch
`worktree-0ac989a9`. Your lane starts from `main` and does not have it. Begin with:

```
git merge --no-edit worktree-0ac989a9
```

Then confirm `plugins/leadv2/scripts/tests/test-board-blind-detached-workers-01.sh` is present.

## The job, stated as a measurement

That test is **red today, for the right reason.** Verified by the lead on 2026-08-29:

```
FAIL Test 1: live detached worker (pgid alive, handle only) -> verdict=dead:no_log_artifact, expected alive
FAIL Test 2: row still_present=False table_status=dead, expected True/active
FAIL Test 5: live detached codex job (job registry says running) -> verdict=dead:no_log_artifact, expected alive
PASS Test 3: finished worker -> dead verdict, row pruned (no leak)
PASS Test 4: disarmed exit trap keeps the detached row; worker-role row refused
```

**Make 1, 2 and 5 pass. Keep 3 and 4 passing.** Tests 3 and 4 are the anti-leak direction — if
your change makes a genuinely finished lane immortal on the board, you have traded one lie for
another and the round fails.

**Do not edit the test to fit the code.** If you believe an assertion in it is actually wrong,
stop and say so in your report with the reasoning; do not quietly relax it.

## The mechanism — as the round-1 worker established it, not as the lead first guessed

The lead's original hypothesis (the dispatcher's exit trap deletes the row) is **wrong**, and the
round-1 test header documents why: on a confirmed spawn the exit trap is disarmed
(`dispatch-code.sh` R5 §4). The `active_lane_released where=exit_trap` line observed at 00:10:20Z
belonged to an attempt that exited `phase_precondition_refused` before any spawn — a correct
release.

The real deleter is the **corroborated prune in `leadv2-lanes-snapshot.sh`**: it reads the exited
dispatcher's pid as dead and tombstones/deletes rows whose work is still running. The row carries
`pid_role=lead_durable` with the dispatcher's pid; `leadv2-lane-liveness.sh` rightly refuses to
read a `lead_durable` pid as worker evidence (LANE-REGISTRY-SELF-DEADLOCK-01), but nothing
replaced the missing worker leg — a detached worker's artifacts live in its run dir / worktree,
not in `docs/handoff/<tid>/`, so it resolves `dead:no_log_artifact`.

Follow the code. If your own reading contradicts the paragraph above, say so plainly and design
against the code.

## Scope

`plugins/leadv2/scripts/leadv2-lane-liveness.sh` and
`plugins/leadv2/scripts/leadv2-lanes-snapshot.sh` are both **in scope** — an earlier plan listed
the snapshot as off-limits based on the lead's wrong diagnosis; that restriction is lifted.

Do not touch `leadv2-status-render.sh`: the renderer reports its source faithfully, and the source
is what is wrong.

## Prove it

1. The test run, pasted: red before your change (5 tests, 3 failing), green after (5/5).
2. `git diff --stat`.
3. The repo's own suite green — name the exact command you ran.
4. One paragraph in your report: what a detached worker now presents as liveness evidence, and
   what stops a dead one from lingering.

Report to `docs/handoff/dispatch-<task>/developer.md`.
