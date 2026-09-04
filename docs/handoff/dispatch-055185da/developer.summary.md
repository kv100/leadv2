verdict: APPROVE
next_action: review_round_2

Round 2: added `unscored` outcome so a broken run can no longer be counted as a kill.

- `lib/leadv2-control-prover.sh`: baseline must be proven green + non-silent BEFORE mutation; mutated target must still `bash -n` parse AFTER mutation — either failure is `[UNSCORED]`, never `[KILLED]`, and excluded from all kill tallies.
- `tests/test-control-prover.sh`: 4 new fixtures (tests 8-11: suite_missing regression, baseline-red, zero-output, target-unparseable), all pass (11/11); updated existing fixtures/assertions for the new `unscored=%d` summary field.
- `tests/run-all.sh`: no diff, round 1 already wired it.
- Falsified round-1's `shared_gate_kill` guard AND all three new round-2 checks by removal (each turns the suite red), then restore (green, byte-identical) — see full.md for raw output.

Full: full.md
