verdict: APPROVE
next_action: deploy

Both items shipped and committed (b1aba72); run-core-offline 56/1 solo (1 pre-existing, unrelated failure).

- TEST-FALSIFICATION-GATE-01 (C4): builder-selfcheck now blocks a changed test file unless its own raw run shows a "RED-then-GREEN:" line; kill-switch LEADV2_TEST_FALSIFICATION_GATE=0.
- test-stop-gate.sh: new red-first Case I (untracked-timeout, mutant-based) — 13/0 green.
- test-builder-selfcheck-gate.sh: +3 red-first Part D cases — 34/1 (1 pre-existing failure, reproduces on clean HEAD).

Full: full.md
