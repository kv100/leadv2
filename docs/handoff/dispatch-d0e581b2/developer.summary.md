verdict: APPROVE
next_action: review_round_2

Deadlock was already closed by a prior lane (55d40e29); found and fixed one leftover doc/UX gap plus added the missing composition test.

- Reproduced all 3 claimed refusals: 2 no longer occur (fixed 2026-09-10), 1 (unspeakable `freepool-default`) still occurred via the gate's own manual fallback CLI text, which omitted `speakable_models`.
- Fixed: threaded `speakable_models` into that fallback suggestion (one text edit, no decision-logic change). New suite `test-spawn-gate-composition.sh` runs both hooks in sequence (20/20), with 2 mutation controls via `leadv2-mutation-control.sh`.
- Pre-existing reds noted, not touched: `test-spawn-arbiter-gate.sh` ("refusal not recorded"), `run-core-offline.sh`.

Full: full.md
