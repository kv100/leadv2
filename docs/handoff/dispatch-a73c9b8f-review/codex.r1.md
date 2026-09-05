# Adversarial review — TEST-FALSIFICATION-GATE-01

Reviewed `git -C /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a73c9b8f diff 215890e...HEAD`.

## Findings

### HIGH — the gate accepts forged evidence and ignores whether the test succeeded

`leadv2-builder-selfcheck.sh:425-429` runs the changed test, records its exit status in `tf_rc`, and then ignores that status. Any output containing the literal `RED-then-GREEN:` produces a passing C4 row, including an `echo`/comment-like print immediately followed by `exit 1`, or a print followed by a timeout. This allows a broken or hung test to satisfy the proposed falsification requirement under `LEADV2_BUILDER_SELFCHECK_TESTS=never`.

The new positive test is itself a concrete demonstration of the weakness: `test-builder-selfcheck-gate.sh:942-960` only prints the marker and exits zero; it does not perform a red run, mutate a condition, or establish that the test could fail. There is no test for marker-plus-nonzero or marker-plus-timeout.

Required fix: make the proof structured and independently verifiable (rather than a free-form grep), and require the test invocation to exit 0. At a minimum, reject nonzero/124 regardless of output and add red-first negative tests; however, that still leaves an `echo` forge unless the proof is produced outside the test or checked against a defined harness protocol.

### MEDIUM — coverage is limited to directly resolved `*/tests/test-*.sh` paths

The selection at `leadv2-builder-selfcheck.sh:417-422` is a path spelling heuristic, not an inventory of changed test executables. Test files under `tests/helpers/test-x.sh`, alternative test directories, alternate shell suffixes, or renamed-to-a-nonmatching paths do not enter C4. Also, resolution only examines the first `LEADV2_BUILDER_SELFCHECK_MAX_FILES` changed paths; a matching test after that cutoff is skipped rather than blocked. The C0 oversized check does not reliably close this path when no write set is declared or its kill switch is used.

If the intended policy is strictly and only root-level `tests/test-*.sh` (and direct plugin equivalent), document that explicit limitation. Otherwise discover test files from the project’s supported test layout and fail closed when a candidate is omitted by the cap.

### MEDIUM — the claimed C4 kill-switch byte-restore is not tested

Despite its comment, `case_falsification_kill_switch_byte_restore` (`test-builder-selfcheck-gate.sh:962-988`) compares only return codes and `FAILED_NAMES`; it never compares `out_new` and `out_old`. It therefore cannot detect a changed selfcheck artifact, counters, rows, or raw log content. The unrelated scope test’s new removal of `diff_hash` makes that other comparison less sensitive, but does not supply the missing C4 comparison.

Add an artifact comparison after removing only the volatile `generated_at` line (and retain `diff_hash` when the same diff is used), plus a check of the exported check/failed/skipped counters.

## Items that checked out

- The depth guard prevents C4 re-entry at depth >= 1, aligned with C3’s suite guard. Its intentional lack of a C4 row is observable only when C3 runs an `auto|always` branch; with `tests_mode=never`, no depth evidence is emitted.
- The stop-gate untracked-timeout case has a real red-first mutant: replacing the capture routine with plain `git diff HEAD` omits the untracked file, while the fixed path captures it and the checkpoint commit includes it.
- Both specified suites passed in the target worktree: builder selfcheck `35 passed / 0 failed`; stop gate `13 passed / 0 failed`.

VERDICT: FAIL
