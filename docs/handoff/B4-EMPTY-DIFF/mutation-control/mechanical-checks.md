# B4 mechanical verification

The DoD CLI returned 0 for registration and runtime-path checks. There is no
brief.md in this report directory, so its report/paste checks are skipped.
Additional checks verify the committed report heading and validate both final
mutation receipts against the current diff hash.

The report's earlier diff-check statement refers to the clean code/test diff.
The full evidence diff has trailing whitespace copied verbatim from test output:
`git diff --check main...HEAD` returns 2 for those transcript lines. The scoped
code/test check returns 0. This does not override the broad runner's rc=124.

The first header probe used `git show | grep -q` under pipefail and stopped on
the producer's SIGPIPE; the final probe uses a materialized committed report.
The final selection checkpoint was still present after its wrapper returned.
Its exact path and expected HEAD value were verified, then it was deleted with
a path-specific Python unlink and absence was confirmed. No pre-existing
checkpoint was overwritten.

## Final check output

```text
valid_final_mutation=docs/handoff/B4-EMPTY-DIFF/mutation-control/20260908T153825Z-79892.txt lane_diff_hash=7c55b362a0a0a4e0ff5103089100cf71d1047b21323958989d18a89564226833
valid_final_mutation=docs/handoff/B4-EMPTY-DIFF/mutation-control/20260908T154136Z-27756.txt lane_diff_hash=7c55b362a0a0a4e0ff5103089100cf71d1047b21323958989d18a89564226833
committed_report_with_evidence_heading=1
code_and_test_diff_check_rc=0
docs/handoff/B4-EMPTY-DIFF/mutation-control/changed-scope.md:22: trailing whitespace.
+ 
docs/handoff/B4-EMPTY-DIFF/mutation-control/changed-scope.md:265: trailing whitespace.
+[TEST] FAIL: loudness (3/4): e2e-gate.md missing status: fail_foreign -- 
docs/handoff/B4-EMPTY-DIFF/mutation-control/changed-scope.md:281: trailing whitespace.
+FAIL: loudness (3/4): e2e-gate.md missing status: fail_foreign -- 
docs/handoff/B4-EMPTY-DIFF/report.md:208: trailing whitespace.
+[TEST] FAIL: loudness (3/4): e2e-gate.md missing status: fail_foreign -- 
docs/handoff/B4-EMPTY-DIFF/report.md:222: trailing whitespace.
+FAIL: loudness (3/4): e2e-gate.md missing status: fail_foreign -- 
full_diff_check_rc=2 (trailing whitespace in verbatim report transcripts only)
checkpoint_removed=1
```

## DoD CLI output

```text
# dod-gate report — 2026-09-08T15:43:50Z

dod_skip check=report_not_required
dod_skip check=paste_not_required reason=no_brief
dod_pass check=suite_registration
dod_pass check=runtime_state
dod_rc=0
valid_final_mutation=docs/handoff/B4-EMPTY-DIFF/mutation-control/20260908T153825Z-79892.txt lane_diff_hash=7c55b362a0a0a4e0ff5103089100cf71d1047b21323958989d18a89564226833
valid_final_mutation=docs/handoff/B4-EMPTY-DIFF/mutation-control/20260908T154136Z-27756.txt lane_diff_hash=7c55b362a0a0a4e0ff5103089100cf71d1047b21323958989d18a89564226833
```
