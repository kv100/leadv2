# B4 mechanical verification

The DoD CLI has no brief.md in this report directory, so its report and paste checks are skipped. An additional explicit check verifies the committed report heading and validates both final mutation receipts against the current diff hash. This does not override the changed-scope timeout.

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
