verdict: APPROVE
next_action: review_round_4

Round-4 fix: `tests/run-all.sh --scope changed` now persists the last-checked HEAD sha
(per git-dir) and diffs from there instead of always unioning the whole merge-base
range, so an already-tested suite no longer re-selects forever. Committed 0f95c19.
- Property 1 (docs-only HEAD + unrelated dirt, no prior state) still selects
  `test-hook-output-cap.sh` 7/7 — round 3's win preserved.
- Property 2 (clean HEAD + one unrelated dirty file, state persisted) selects ONLY
  that file's own suite — `test-hook-output-cap.sh` no longer re-appears.
- Control: reverting the bounding logic reproduces the unbounded re-selection (RED),
  revert of the revert restores GREEN. All from a scratch clone.
- `/tmp/leadv2-core-offline.lock`: real flock, cannot orphan; wait is unbounded by
  design (run-core-offline.sh:52-56) — that's what caused observed hangs, not staleness.
Full: full.md
