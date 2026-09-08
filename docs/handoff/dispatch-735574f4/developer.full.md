verdict: BLOCK
next_action: escalate_to_founder

# dispatch-735574f4 — BLOCKED at hard precondition

## Mission
P1b — LAUNCH-WHAT-THE-ARBITER-ACTUALLY-CHOSEN-01. Three changes to
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` and
`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`, gated on a hard precondition:

> Lane `13581c3eb064` (P2, commit `4e15098b`) must be merged into `main` first. It rewrites
> `lib/leadv2-route-arbiter.sh` and `config/leadv2-routing.yaml` under your feet otherwise. Check with
> `git branch --merged main | grep worktree-13581c3eb064`. If it is not merged, STOP and say so — do
> not rebase around it and do not re-implement its parts.

## Precondition check (evidence)

```
$ git branch --merged main | grep worktree-13581c3eb064
(no output, exit 1 — branch not in --merged list)

$ git branch -a | grep -i 13581c3eb064
+ worktree-13581c3eb064

$ git merge-base --is-ancestor 4e15098b HEAD
$ echo $?
1   # NOT an ancestor of current HEAD — not merged
```

`git log --oneline --all | grep 4e15098b` resolves the commit:

```
4e15098b 260907-212812-13581c3eb064-19f0: auto-commit (worker exited dirty)
```

The commit message itself ("worker exited dirty") suggests P2's lane may not have closed
cleanly, independent of the merge status.

`git show --stat 4e15098b`:

```
 plugins/leadv2/config/leadv2-routing.yaml          |  24 +-
 plugins/leadv2/scripts/leadv2-dispatch-code.sh     | 308 ++++++++++++++++++-
 .../scripts/lib/leadv2-glm-policy-resolve.py       |   9 +
 plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 126 ++++++--
 plugins/leadv2/tests/test-arm-pool-reachability.sh | 328 +++++++++++++++++++++
 plugins/leadv2/tests/test-exclusion-stages.sh      | 202 +++++++++++++
 6 files changed, 958 insertions(+), 39 deletions(-)
```

This confirms the mission's warning: P2 touches `leadv2-route-arbiter.sh`,
`leadv2-routing.yaml`, and `leadv2-dispatch-code.sh` — the exact files this mission (P1b) is
scoped to edit (`LANE_WRITES`). Starting work now would mean editing a pre-P2 version of the
arbiter/dispatch script and either conflicting with or silently reverting P2's `pool_default`
per-cell rework and its ordered exclusion-stage list once P2 eventually merges.

## What I did NOT do
- No edits to `leadv2-dispatch-code.sh` or `leadv2-route-arbiter.sh`.
- No test files created (`test-launch-uses-the-chosen-arm.sh`,
  `test-unmetered-account-not-penalised.sh` — not started).
- No rebase attempt, no re-implementation of P2's `pool_default` / exclusion-stage / opus-park work.
- No commit — worktree is unchanged from base `462eeb22`.

## Self-check (bash -n / py_compile / test runner)
Not applicable — no files were touched, so there is nothing to falsify.

## Recommendation
Escalate to founder/lead: either (a) merge lane `worktree-13581c3eb064` (commit `4e15098b`)
into `main` first, verifying it closed cleanly despite the "worker exited dirty" commit
message, then re-dispatch this task; or (b) if that lane is abandoned/superseded, explicitly
instruct this task to proceed against current `main` and re-derive the P2 pieces it depends on
(pool_default per-cell dispatch, `classify_account_state` unmetered/unknown split) itself —
which the mission text explicitly says NOT to do without that direction.

DELIVERABLE_COMPLETE
