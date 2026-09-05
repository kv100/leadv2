status: fail
reason: dod_report_missing_or_unheaded

# dod-gate report — 2026-09-03T04:13:42Z

dod_fail check=report_missing_or_unheaded detail=no_evidence_heading
dod_fail check=paste_evidence_missing brief_line=49
dod_pass check=suite_registration
dod_pass check=runtime_state
dod_note check=unverified_claim line=4
dod_note check=unverified_claim line=50
