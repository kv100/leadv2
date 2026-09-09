# SessionStart merged-worktree sweep cost

## Evidence

On 2026-09-09, a safe reproduction set `LEADV2_SWEEP_MIN_AGE_S=2147483647`,
so it could not remove a worktree, and ran the hook with xtrace enabled. The
trace reached this invocation before entering the per-worktree loop:

```text
+... leadv2-merged-worktree-sweep.sh:105: bash .../leadv2-orphan-checkpoint.sh --project-root /Users/kostiantyn.vlasenko/Projects/persona-engine
```

The direct safe probe took 544.46 seconds before that child returned; no
per-worktree trace record appeared after the checkpoint invocation. Its raw
tail was:

```text
... leadv2-merged-worktree-sweep.sh:103: bash .../leadv2-orphan-checkpoint.sh --project-root .../persona-engine
real 544.46
user 262.05
sys 202.79
```

The original hook did not reach its first loop iteration during the probe, so
it supplied no evidence that it had removed any worktree in that run. After
the change, the same safe probe completed its actual hook body in 3.50 seconds
and its xtrace invocation exited 0:

```text
real 3.50
user 0.78
sys 1.18
```

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

### Green output

```text
PASS: budget fixture hook exits 0
PASS: SessionStart budget <1s (0.40061426162719727s)
PASS: default path does not invoke orphan checkpoint
PASS: registered-lane hook exits 0
PASS: registered lane survives sweep
PASS: merged-worktree-sweep bounded (5 assertions)
leadv2-merged-worktree-sweep:plugins/leadv2/tests/test-merged-worktree-sweep-is-bounded.sh
hooks.json:plugins/leadv2/tests/test-merged-worktree-sweep-is-bounded.sh
```

### leadv2-mutation-control.sh red output

```text
MUTATION-CONTROL ok suite=plugins/leadv2/tests/test-merged-worktree-sweep-is-bounded.sh file=plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh red_line=FAIL: SessionStart exceeded 1s (2.476357936859131s)
MUTATION-CONTROL ok suite=plugins/leadv2/tests/test-merged-worktree-sweep-is-bounded.sh file=plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh red_line=FAIL: registered lane was removed
```

The full immutable artifacts are committed under `docs/reference/mutation-control/`.
