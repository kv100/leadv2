verdict: APPROVE
next_action: review_round_2

rc=124 now classifies as its own `e2e_timeout` cause (terminal `parked`, not `dead`), separate from a real `e2e_regression`; the round's work already survives via the existing pre-gate autocommit checkpoint.

- Fixed `leadv2-dispatch-product-close.sh` (the script that actually killed the measured lane) and `leadv2-phase8-e2e-gate.sh` (same conflation, standalone gate).
- New suite `test-e2e-timeout-classification.sh` proves both directions (rc=124 vs a real rc=1 failure) and is registered in `tests/run-all.sh`'s `EXTRA_SUITE_MAP`; `--scope changed` selection proven.
- Found an unrelated pre-existing environment flake in `test-e2e-foreign-failure.sh` (reproduces on a clean HEAD worktree, untouched by this diff) — reported, not fixed.

Full: developer.full.md
