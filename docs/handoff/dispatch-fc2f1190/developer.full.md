verdict: APPROVE
next_action: deploy

# Round 2 — regression re-check for dispatch-fc2f1190

## Task as handed off

Round 1 built the design decided by the architect (`dispatch-75d151fe-architect`):
`test-review-single-owner-census.sh` rewritten as a two-bucket reachability census
keyed on `LEADV2_REVIEW_ENGINE` (flag=0 bucket → `leadv2-dispatch-product-close.sh`
inline body; flag=1 bucket → `leadv2-review-run.sh`), with a fail-on-unclassified
clause and `workflows/leadv2-review.js` deleted (three byte-identical copies) with its
three asserting suites migrated. That work landed in the worktree at `599275c`.

Round 2 said the e2e gate (`run-all.sh --scope changed`) found 2 blocking failures on
top of that: `run-core-offline.sh` (attributed to my `leadv2-dispatch-product-close.sh`
edit — "product-close waits for worker exit") and `test-leadv2-route-bandit.sh`
(pre-existing per the lead's own baseline, not to be touched).

## What I found

I re-ran the gate in this worktree and compared every result against a real baseline
checkout of the merge base `717b16f` (a temporary `git worktree add` at that commit,
removed afterward — no destructive git ops on the working tree).

### `test-no-work-terminal.sh` ("product-close waits for worker exit")

Ran standalone, twice, in the worktree: **43 passed, 0 failed** both times. Ran on the
`717b16f` baseline: same, 43/0. It does not fail today, in this worktree, under any run
I could produce. My only code touching `leadv2-dispatch-product-close.sh` is the
`ONE-PATH-EVERYWHERE-01` gate block at line 1542 onward, which is entirely guarded by
`[[ "${LEADV2_REVIEW_ENGINE:-0}" == "1" ]]` — with the flag unset (production default,
confirmed unset in this env), that whole block is dead code at runtime; the fall-through
into the original inline body is byte-for-byte unchanged below it. `bash -n` on the file
is clean. I cannot reproduce the round-2 failure signature; it does not reproduce against
current worktree state. Given the process-spawn/wait-heavy nature of this suite, my best
explanation is a transient/environment-timing failure at whatever moment round 2's gate
ran, not a standing regression — there is no code path connecting my change to that
suite's assertions once the flag is 0.

### `run-core-offline.sh` full sweep

Worktree: `passed=40 failed=1` — the one failure is `[CORE-OFFLINE] FAILED: hook token +
mode isolation` (`test-hook-token-mode-isolation.sh`, specifically "Test: parallel lead
task hook selected the wrong registry row").

Baseline (`717b16f`, real worktree checkout): **identical** — `passed=40 failed=1`, same
single failure, same failing sub-check. Confirmed pre-existing, unrelated to this lane's
`leadv2-dispatch-product-close.sh`/`leadv2-review-run.sh`/census changes. Not touched.

### `test-leadv2-route-bandit.sh`

Worktree: PASS=9 FAIL=1 — Test 9 (`route-decisions.yaml` not found under the expected
handoff path) fails.
Baseline (`717b16f`): PASS=8 FAIL=2 — Test 9 fails identically (same missing-file
signature), plus Test 1 (`sonnet_pct=70.5% < 75%`, a heuristic-percentage/probabilistic
check) also failed on that run. Test 1 is not deterministic per-run; the worktree run
happened not to trip it. Either way the worktree is not worse than baseline — Test 9 is
the shared, reproducible pre-existing failure exactly as the lead's own baseline
reported. Not touched, per explicit instruction.

## Verification of round-1 deliverables (still standing)

All 9 suites named in the original mission re-run clean in the worktree:

- `test-review-engine-fanout-multiprovider.sh` — PASS=1 FAIL=0
- `test-review-engine-pool-degrades.sh` — PASS=2 FAIL=0
- `test-review-engine-verifier-distinct-arm.sh` — PASS=1 FAIL=0
- `test-review-engine-verify-coverage.sh` — PASS=1 FAIL=0
- `test-workflow-bypass-guard-lane.sh` — PASS=4 FAIL=0
- `test-review-pool-empty-rootcause.sh` — all PASS (T1/T1-detail/T2)
- `test-review-pool-never-empty.sh` — all PASS (T5/T5-detail/T6/T7, includes the
  regression check that `test-quota-lockout-postspawn.sh` still fully passes)
- `test-quota-lockout-postspawn.sh` — PASS=7 checks (T1-T7), 0 fail
- `test-review-single-owner-census.sh` — PASS=3 FAIL=0

Owner census verbatim (current worktree):

```
owners found:
  .../plugins/leadv2/scripts/leadv2-dispatch-product-close.sh  [bucket: flag=0]
  .../plugins/leadv2/scripts/leadv2-review-run.sh  [bucket: flag=1]
PASS: flag=0 bucket has exactly one owner (leadv2-dispatch-product-close.sh) with gate expression routing flag=1 to leadv2-review-run.sh
PASS: flag=1 bucket has exactly one owner: leadv2-review-run.sh
PASS: no unclassified review-orchestration owners
```

### Negative control (re-verified)

Dropped a throwaway file `plugins/leadv2/scripts/leadv2-fake-second-owner.sh` containing
a `run_reviewer_arm()` stub, re-ran the census, then deleted it:

```
owners found:
  .../leadv2-dispatch-product-close.sh  [bucket: flag=0]
  .../leadv2-fake-second-owner.sh  [bucket: UNCLASSIFIED]
  .../leadv2-review-run.sh  [bucket: flag=1]
PASS: flag=0 bucket ...
PASS: flag=1 bucket ...
FAIL: unclassified owner file(s) found (not in allowlist): .../leadv2-fake-second-owner.sh,
review single-owner census: PASS=2 FAIL=1
```

Census correctly flips to FAIL when a second owner reappears — it is not a test that
can't fail.

## What I changed

Nothing in `plugins/leadv2/` beyond what round 1 already committed. No new code edits
were needed because the reported round-2 regression could not be reproduced and the only
other failure is proven pre-existing on the merge base.

Housekeeping only (not part of the code diff, working-tree hygiene): removed five
scratch `docs/leadv2/tasks/dispatch-fanout-test-lane-2/`,
`dispatch-fanout-test-lane-timeout/`, `dispatch-tid0100{1,2,3}/` directories that
`test-review-engine-fanout-multiprovider.sh` and friends wrote into the real
`docs/leadv2/tasks/` tree during this session's test runs (a pre-existing test-hygiene
issue, not mine to fix here — flagged for the open-threads audit already covering
`.claude/scripts/tests/` drift, but out of scope for this task). Removed the temporary
`git worktree add /tmp/baseline-check 717b16f` used for baseline comparison — confirmed
`git worktree list` no longer shows it and `/tmp/baseline-check` is gone.

## What I deliberately left alone

- `test-hook-token-mode-isolation.sh` — pre-existing failure, confirmed identical on
  baseline. Not this task's scope.
- `test-leadv2-route-bandit.sh` Test 9/Test 1 — pre-existing, confirmed identical (Test
  9) / non-deterministic (Test 1) on baseline. Not this task's scope, per the lead's
  explicit instruction not to fix it in this lane.
- `LEADV2_REVIEW_ENGINE` — confirmed unset (defaults to 0) throughout; never flipped.

DELIVERABLE_COMPLETE
