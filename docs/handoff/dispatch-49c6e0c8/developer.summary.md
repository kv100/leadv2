verdict: APPROVE
next_action: review_round_2

Second safety door was real (dispatch-code.sh's own arm resolver, not the file the census named) — fixed, tested, DoD gate green.

- Live before/after `route_resolved` probe proves the door: pre-fix, judge `risk_class=safety_publish_payments` never reached routing enforcement; post-fix it does.
- Fix: `cmd_resolve` folds `ADMISSION_RISK_CLASS` into `safety` unconditionally, outside the override surface (same placement as `HEAVY-TIER-VS-SAFETY-OPUS-01`'s pin). `arch` carve-out untouched (different router, different signal).
- New suite `test-admission-safety-pin.sh` (registered), green on macOS + Linux container; DoD gate (`lib/leadv2-dod-gate.sh`) run standalone: exit 0, all 4 hard checks pass.

Full: full.md
