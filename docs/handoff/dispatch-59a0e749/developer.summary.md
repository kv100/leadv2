verdict: APPROVE
next_action: review_round_2

Layer A (loud resolver failure) added on top of the lane's existing D1-D4 never-empty-pool work; fixed a real codex-precheck regression + 2 test bugs. All suites green (18+7+11+4/4).

- review-gate.md now always carries refusal/resolver_rc/resolver_stderr/merge_blocked
- fixed: codex lockout silently skipped the loud precheck log line (dispatch-code.sh)
- NOT committed (repo boundary: no commit/push/merge) — tree left for lead review

Full: full.md
