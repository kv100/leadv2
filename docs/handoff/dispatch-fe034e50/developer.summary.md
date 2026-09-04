verdict: APPROVE
next_action: review_round_2

Fixed CORE-OFFLINE-WORKTREE-GAP-01: fanout's registry resolution now tries SCRIPT_DIR sibling first (worktree/fixture-HOME-safe), then vendored/canonical/shared, fail-closed if all four miss.

- fanout.sh + fanout-lane-launcher.sh: 4-branch resolution, both live launch paths fixed.
- Guard test: hermetic sandbox staging + new test 5 (sibling-only resolution). PASS=5 FAIL=0.
- Ladder test (d): root cause was NOT env leak or a dispatch-code.sh bug — the assertion checked the wrong artifact (founder-status.md, which always compacts the queue section into founder-status-full.md by design). Fixed test to check founder-status-full.md. dispatch-code.sh needed no change (diff is empty).
- Full run-core-offline.sh from inside this worktree: 73 suites, 0 failed, 0 missing.

Full: developer.full.md
