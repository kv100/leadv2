# PHASE-DISCIPLINE-01 — fix round 1

Fixed Gate 1’s explicit zero-second daemon timeout: macOS Bash can make
`read -t 0` succeed with an empty value at EOF, which incorrectly selected the
decline path. Zero now goes directly to the documented timeout auto-accept
path (rc 2). Ledger JSON is emitted compactly, preserving the event contract.

Hardened the backlog-pump test harness against the host kill switch. The suite
declares itself fully isolated; it now clears inherited `LEADV2_BACKLOG_PUMP`,
while its dedicated kill-switch case still explicitly sets `0`. No assertion
was weakened or removed. The Phase-4 `--pre-build` resolver and shared
admission helper remain included from the GLM build.

Foreground evidence:

- `test-backlog-pump.sh`: 21 passed, 0 failed.
- `test-gate1-discipline.sh`: 12 passed, 0 failed.
- `test-freepool-model-selector.sh`: 25 passed, 0 failed.
- `test-admission-class.sh`: 21 passed, 0 failed.
- Scoped `git diff --check`: clean.

DELIVERABLE_COMPLETE
