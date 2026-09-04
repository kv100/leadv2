verdict: APPROVE
next_action: review_round_2

Added `lib/leadv2-lead-identity.sh` (leadv2_lead_session_id) + wired it into the 4 permitted call sites + `test-lead-session-identity.sh` (4/4 green, negative control confirmed red on mutation).
- New resolver reuses `_lv2_durable_pid`/`_lv2_pid_birth` from `leadv2-active-registry.sh` (sourced, not copied); fail-open to "direct".
- `leadv2-codex-session-runner.sh`, `leadv2-session-runner.sh`, `leadv2-inbox.sh`, `leadv2-broad-status.sh` updated (third fallback link only).
- `leadv2-active-registry.sh` untouched (writeset conflict, per scope cut). `tests/run-all.sh` untouched (writeset conflict, D4 owns it) — EXTRA_SUITE_MAP row given in full.md for lead to land.
- `leadv2-dispatch-code.sh:7071` untouched (off-limits) — exact replacement text in full.md for its owning session.
Full: full.md
