status: fail
reason: dod_paste_evidence_missing

# dod-gate report — 2026-09-03T11:05:04Z

dod_skip check=report_not_required
dod_fail check=paste_evidence_missing brief_line=66
dod_pass check=suite_registration
dod_fail check=runtime_state_in_diff paths=docs/LEAD_V2_STATE.md
