# SessionStart merged-worktree sweep cost

## Evidence

On 2026-09-09, a safe reproduction set `LEADV2_SWEEP_MIN_AGE_S=2147483647`,
so it could not remove a worktree, and ran the hook with xtrace enabled. The
trace reached this invocation before entering the per-worktree loop and did
not advance for the measurement interval:

```text
+... leadv2-merged-worktree-sweep.sh:105: bash .../leadv2-orphan-checkpoint.sh --project-root /Users/kostiantyn.vlasenko/Projects/persona-engine
```

The stalled line is the orphan checkpoint call, not `git status` or the
per-worktree `git worktree list` check. The original hook did not reach its
first loop iteration during the probe, so it supplied no evidence that it had
removed any worktree in that run.

## Decision

Move orphan checkpointing off the SessionStart critical path. The merged
sweeper remains registered and continues to enforce its registered,
arm-open, live-pid, young, and fail-closed protections. Its default startup
path no longer invokes `leadv2-orphan-checkpoint.sh`; the old invocation is a
reversible diagnostic opt-in only via
`LEADV2_SESSION_START_ORPHAN_CHECKPOINT=1`.

The guarantee deliberately lost at SessionStart is automatic durable
checkpointing of a dead dirty lane. The safety direction remains conservative:
the sweep sees genuine dirt and keeps that lane; it does not remove it. Run
`leadv2-orphan-checkpoint.sh` from its dedicated periodic/manual path to make
that dirty work durable.

## Bound and regression proof

`plugins/leadv2/tests/test-merged-worktree-sweep-is-bounded.sh` measures the
default hook on a scratch repository and requires it to finish under one
second while a fake checkpoint would sleep for two seconds. It also creates a
clean, old, registered linked worktree and proves it survives. The two
negative controls mutate only function-body guards: re-enabling the checkpoint
makes the budget assertion red; bypassing `lv2_worktree_protected` makes the
registered-lane assertion red.
