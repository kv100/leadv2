status: fail
reason: dod_runtime_state_in_diff

# dod-gate report — 2026-09-03T08:09:35Z

dod_pass check=report
dod_skip check=paste_not_required
dod_pass check=suite_registration
dod_fail check=runtime_state_in_diff paths=docs/LEAD_V2_STATE.md
