verdict: APPROVE
next_action: continue

Reproduced on macOS: `date +%s%3N` exits 0 emitting a literal `N`, so line 227's arithmetic fatally unwinds and the script dies on a trailing `exit 0` — F1 *is* F3.

- Fix: shape-validated `now_ms()`, single arg-parse exit path, RUN_COMPLETED sentinel + EXIT trap, 3 real shellcheck fixes.
- New F5: case (c) fails from `pipefail` in the test harness, not the gate.

Full: architect.full.md
