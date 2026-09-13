# 83577d79c310 round 2 — the fix is unverified by its own suite

Round 1 landed two real commits on branch `worktree-83577d79c310` in this repo:

```
48550f5a  fix: scope close-gate truth across lane repos
          leadv2-dispatch-product-close.sh          +306/-83
          leadv2-lane-worktree.sh                    +44
          tests/test-lane-worktree-places-env.sh      +52
          tests/test-review-gate-counts-the-right-repo.sh +90
6a72af64  fix: keep foreign git truth out of lane verdicts
          leadv2-dispatch-product-close.sh           +45
          tests/test-review-gate-counts-the-right-repo.sh +31
```

Keep all of it. Round 1 then died on `worker_timeout` before its own suite passed.

## What is already proven — do not redo

`test-lane-worktree-places-env.sh` is **2 passed, 0 failed**, including the case
where the source `.env` is absent and the skip reason is recorded. The `.env`
half of the row is done and measured. Leave it alone.

## The gap

`test-review-gate-counts-the-right-repo.sh` is **2 passed, 3 failed**, measured
by the lead on the lane branch. All three failures, including the negative
control, look identical:

```
[TEST] FAIL: plugin lane did not pass    (rc=0, ... worker_liveness=unknown ... action=proceed_legacy)
[TEST] FAIL: project lane did not pass   (rc=0, ... worker_liveness=unknown ... action=proceed_legacy)
[TEST] FAIL: negative control was relaxed (rc=5, ... worker_liveness=unknown ... action=proceed_legacy)
```

`proceed_legacy` is emitted at `leadv2-dispatch-product-close.sh:1402` and `:1531`
when worker liveness cannot be determined. **The fixture never gets the gate as
far as the repo-scoping code.** So the repo-scoping change may well be correct —
nobody has shown it either way, and the negative control is not controlling
anything, which is worse than a red.

A guard whose test cannot reach it is not a guard. Fix the harness so each case
lands on the code under test, then make the three cases pass or report honestly
which of them the design cannot satisfy.

## What round 2 must do

1. **Give the fixture a determinate worker liveness** so the gate proceeds past
   `:1402`/`:1531` into the repo-scoping decision. Say in the report which knob
   you used and why it is legitimate rather than a test-only bypass. If the only
   way past is a test-only bypass, that itself is the finding — a gate reachable
   only in production cannot be regression-tested, and we need to know.
2. **The negative control must actually refuse.** `rc=5` with `proceed_legacy` is
   not a refusal. A lane that committed nothing in either repo must be refused,
   and the case must prove it by the refusal code and the journal line.
3. **The refusal must name the repo and branch it counted on.** Round 1's commits
   may already do this — verify it with a real refusal, not by reading the code.

## Traps carried over

- `git log main..<branch>` does not see the index. Staged-but-uncommitted work
  shows an empty log; that is not "no work".
- Branch naming differs per repo (`worktree-<id>` here). Do not assume one name
  resolves in both.
- Do not relax the gate into always passing. The refusal must still fire.

## Acceptance

- `test-review-gate-counts-the-right-repo.sh` rc 0, all cases, run **on the lane
  branch** and pasted.
- `test-lane-worktree-places-env.sh` still 2/0.
- A live replay: one of the four lanes the row cites is still on disk. Run the
  fixed gate against it and show the verdict flip, with the journal line naming
  the repo.
- All suites guarding `leadv2-dispatch-product-close.sh`, before → after.
- `run-all.sh --scope changed` proof, after the commit.
- Second-model review, named. Round 1's never ran.
- Commit in this repo, on the lane branch.
