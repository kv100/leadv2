status: fail
reason: dod_paste_evidence_missing

# dod-gate report — 2026-09-03T12:56:01Z

dod_skip check=report_not_required
dod_fail check=paste_evidence_missing brief_line=160
dod_fail check=paste_evidence_missing brief_line=170
dod_fail check=paste_evidence_missing brief_line=175
dod_fail check=mutation_control_not_via_runner brief_line=175
dod_pass check=suite_registration
dod_fail check=runtime_state_in_diff paths=docs/LEAD_V2_STATE.md
