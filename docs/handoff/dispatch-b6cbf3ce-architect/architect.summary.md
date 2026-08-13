verdict: APPROVE
next_action: continue

Design scoped to F1/F2/F3 only; all three reproduce verbatim in `5ba7620`.

- F1: hash `docs/handoff/dispatch-<sig8>/review.diff` with the same `shasum -a 256` product-close:1478 uses; require a ledger row with that hash + PASS/PASS_WITH_NITS.
- F2: re-hash vs `artifact_sha256` on all five phases; plus start-sha diff (build), origin/main ancestry (deploy); test/live_verify/e2e declared unprovable-by-existence.
- F3: drive real `cmd_resolve` with spy launchers — never `--no-spawn`; refusal needs a distinct exit code (3 collides with arm=opus).

Full: architect.full.md
