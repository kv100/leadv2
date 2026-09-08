verdict: APPROVE
next_action: deploy

scan_suite_triggers() was never broken — the test's own "every root in the map" check had a pipefail+`grep -q` SIGPIPE race, fixed with a here-string.
- Confirmed `plugins/leadv2/scripts/tests` is walked (765 rows) and run-all.sh untouched, byte-identical after the negative control.
- test-run-all-self-registration.sh: 11/1 (flaky) → 12/0 (stable, 5x).
- Negative control: temporarily dropped the root from scan_suite_triggers() → red for the right reason; restored → green.

Full: full.md
