# PLUGIN-PAPERCUTS-01 Analysis Report

## Decision: Main is right

After analyzing the code and the deliberate design choice documented in the commit history, I conclude that **main is correct**: an unknown-reader pass must never stop the beat loop.

### Why Main's Decision is Correct

The commit message explicitly states:
> "That removal was deliberate: a loop that dies on reader-error passes goes quiet, and the silence this loop exists to prevent comes back. So `P1` asserts a contract that main removed on purpose."

The fundamental purpose of the single-lead beat loop is to prevent founder-blindness - ensuring that when at least one lane is live, the founder receives regular status updates via `founder-status.md`. 

If the loop were to stop on reader errors (when the heartbeat script fails to execute or returns unparseable output), we would create exactly the failure mode the loop is designed to prevent:
- Monitor becomes blind (heartbeat errors)
- Loop stops beating 
- No updates to `founder-status.md`
- Founder sees no new data and assumes everything is fine
- Founder's blindness persists and worsens

This is precisely what fix-round H4 sought to address, and why the `LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX` stop was intentionally removed.

### Addressing Resource Concerns

While the lane's concern about unbounded loops in test/dead environments is valid, main's version already includes appropriate bounds:
1. **Hard lifetime cap** (`LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S`, default 24 hours)
2. **Project root monitoring** (exits if project root disappears)
3. **Owner-based self-reap** from WATCHER-LIFECYCLE-LEAK-01 (when explicitly configured)

These bounds ensure that even in permanently broken environments, the loop will not run indefinitely - it will either:
- Exit when the project root is removed (test fixture teardown)
- Self-reap when an owner process dies (if owner is explicitly set)
- Hit the 24-hour lifetime cap as a final safety net

The 24-hour cap is a reasonable balance: long enough to avoid prematurely stopping during transient monitor issues, but short enough to prevent permanent resource leaks in abandoned test environments.

### The Flaw in P1's Assumption

Test case P1 assumes that the loop should stop after `LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX` consecutive reader-error passes. This assumption is incorrect because:
- It confuses "reader error" (temporary monitor blindness) with "permanently dead environment"
- Implementing this stop would re-introduce the founder-blindness failure
- The existing lifetime cap and project-root monitoring already provide sufficient bounds for test scenarios

## Test Replacement Strategy

Since P1 tests a retired contract, it must be replaced with a test case that validates main's actual contract:
> "The loop stops on ZERO_MAX consecutive REAL zeros (where zero means heartbeat successfully parsed and reported zero live lanes), and does NOT stop on reader errors."

The replacement test will:
1. Verify the loop stops when presented with ZERO_MAX consecutive real zero lane counts
2. Verify the loop continues running when presented with reader errors (unknown passes)
3. Demonstrate that mutating the zero-stop rule (e.g., setting ZERO_MAX=0 or removing zero-stop logic) causes the test to fail

This approach maintains the backlog's purpose of preventing regressions while aligning with main's correct design decision.

---

# W18 root-dirty gate report

## Reused mechanism

`leadv2-dispatch-product-close.sh` now invokes `leadv2-land.sh --root-dirt-check`.
That probe builds the prospective `git merge-tree --write-tree` result and
uses the existing `land_in_write_set` predicate against its changed-path set;
there is no second path-membership rule. `leadv2-land.sh:303` was confirmed to
have the same unrelated-tracked-dirt defect and now calls that same probe after
the throwaway landing tip is prepared. It no longer rewrites unrelated state
files.

## Real-root probe

Raw output, 2026-09-10:

```text
dirty_total=746 tracked=2 untracked=744
real_root_probe_rc=0
docs/leadv2/.compact-freeze.md
docs/leadv2/open-threads.md
```

The probe was run against the true primary root and this lane branch. It
returned zero because neither tracked dirty path intersects this lane's
prospective merged tree. No merge of the primary checkout was attempted by
this worker lane.

## Green focused runs

```text
# root-dirty-gate pass=7 fail=0
# land-suite pass=76 fail=0
```

The root-dirty fixture covers tracked non-intersection (including a real
merge), tracked intersection with the named path, untracked non-intersection,
and an untracked path the merge would create.

## Red mutation control

Command:

```text
bash plugins/leadv2/scripts/leadv2-mutation-control.sh --live plugins/leadv2/scripts/tests/test-root-dirty-gate.sh plugins/leadv2/scripts/leadv2-land.sh 's@if land_in_write_set "${path}"; then@if [[ -n "$(git -C "${ROOT}" status --porcelain 2>/dev/null)" ]]; then@' docs/handoff/w18-root-dirty-gate
```

Raw output:

```text
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-root-dirty-gate.sh file=plugins/leadv2/scripts/leadv2-land.sh red_line=FAIL - T1 tracked non-intersection permits merge (expected [0], got [1]) diff_hash=0861aa15e04290e1820f51b8158fe5499b5735a5c9f3b194f4b84338e26404bd lane_diff_hash=67bc494acbc1260d256d5526e8ec3c77d7deb74c524bc4da0aa439408bbe6ebb porcelain_clean=yes
```

The artifacts are under `docs/handoff/w18-root-dirty-gate/mutation-control/` and are ignored by the repository, so the final live proof can be present without entering the lane diff.

## Changed-scope runner

Raw bounded run after the fix:

```text
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9cf1390c197a/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
changed_scope_rc=124
```

The runner was foregrounded with `timeout 600`; it exhausted that bound in
`run-core-offline.sh` before a verdict. This is a timeout, not a green claim.

---

# W18 closer throughput report

## Journal measurement

Source census (2026-09-10): terminal `e2e_gate status=ran verdict=...` records from `~/.claude/leadv2-state/{leadv2,persona-engine}/tasks/*/journal.md`. Each task path was resolved through `leadv2-journal.sh path <task>`; for example:

```text
$ LEADV2_PROJECT_ROOT=/Users/kostiantyn.vlasenko/Projects/leadv2 bash plugins/leadv2/scripts/leadv2-journal.sh path fb9df7f1
/Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/tasks/fb9df7f1/journal.md
```

```text
n=61 complete=6 censored_at_900=55 p50=900 p95=900 max=900
   1 120 timeout
   1 164 complete
   1 169 complete
   1 176 complete
   1 272 complete
   1 456 complete
   1 690 complete
  54 900 timeout
```

`p95=900` is right-censored: 55 of 61 observations reached a timeout ceiling. The fixed 900-second close budget is implicated. The new default is `min(3600, 1200 + 120 * (selected_suites - 1))`: 1200 is the censored 900-second p95 plus a 300-second reserve, and each additional selected suite adds 120 seconds. An explicit `LEADV2_PHASE8_E2E_TIMEOUT_S` remains authoritative.

Timeout artifacts now record selected suites, completed suites, and the last `[RUN]` suite.

## Git truth behavior

Before `no_work`, the closer checks the lane branch against the local default branch and independently checks `git diff --cached`. Commits become `refused/git_truth_commits` with the SHA journaled; staged-only work becomes `refused/git_truth_staged`; only an absent/clean lane remains `no_work`. Landing policy remains `leadv2-land.sh` and its merged-tree/`land_in_write_set` authority.

## Red then green

```text
# environmental preflight red (before product code):
mktemp: mkdtemp failed on .../tmp.s2gCHAwB6l: Operation not permitted
mkdir: /repo: Operation not permitted

# green, after redirecting no-argument mktemp to /private/tmp:
[TEST] PASS: committed branch without report is git_truth_commits and journals its SHA
[TEST] PASS: staged but uncommitted work is git_truth_staged, not no_work
[TEST] PASS: missing branch with no index/commits remains no_work
[TEST] 3 passed, 0 failed
[TEST] PASS: timeout artifact names selection/progress even when the custom entrypoint has no selector seam
[TEST] 10 passed, 0 failed, 0 not run

# syntax floor:
bash -n plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
bash -n plugins/leadv2/scripts/tests/test-close-gate-git-truth.sh
bash -n plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
git diff --check
# all exited 0

# changed-scope runner, foregrounded with timeout 180:
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
```

The changed-scope runner produced no verdict in the tool's 30-second foreground window; it was not claimed green. No detached process was started.

## Mutation control

Task B control (artifact: `/private/tmp/w18-mutation-artifact-final/mutation-control/20260910T085424Z-86316.txt`):

```text
$ LEADV2_BUILDER_SELFCHECK=0 bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
  plugins/leadv2/scripts/tests/test-close-gate-git-truth.sh \
  plugins/leadv2/scripts/leadv2-dispatch-product-close.sh \
  's/_PC_GIT_TRUTH_KIND="commits"/_PC_GIT_TRUTH_KIND="none"/' \
  /private/tmp/w18-mutation-artifact-final
suite=plugins/leadv2/scripts/tests/test-close-gate-git-truth.sh
file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
anchor=s/_PC_GIT_TRUTH_KIND="commits"/_PC_GIT_TRUTH_KIND="none"/
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: committed branch was misclassified (...)
diff_hash=ef70dab37636b9a1879b2f43a510ca65687d9d6343afa5d7df7098003c0b0aac
lane_diff_hash=c8e45965550dc5e711a5425da705e1b755adedbffa1a49f81895a7527a0118c7
```
