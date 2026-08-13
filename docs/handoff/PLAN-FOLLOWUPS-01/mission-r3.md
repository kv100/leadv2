FINAL fix round r3 (judge-mandated, no round 4). Worktree: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PLAN-FOLLOWUPS-01, on top of commit 125760e. Fix EXACTLY these six review findings, no other scope:

1. CRITICAL plugins/leadv2/scripts/leadv2-plan-run.sh:381 — "Order-B output with any text after the closing fence returns that trailing prose instead of the YAML — pass A early-returns on non-empty garbage". Pass-A awk must not extract from order-B-shaped input; both orders must extract clean YAML even with prose before AND after the block.
2. CRITICAL plugins/leadv2/scripts/leadv2-plan-run.sh:395 — "Marker-without-fence input regressed from clean YAML to whole-file — yaml.safe_load now fails on it". Restore old behavior: PLAN_YAML: marker with NO fences → everything after the marker is the YAML.
3. HIGH plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:275 — "Post-filter len(rank_table)<2 discards a legitimate sole dispatchable floor arm, breaking the D3 never-empty-pool invariant".
4. HIGH plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:544 — "Caller elif rank_table: ignores floor_ok, so --plan-pool still returns pool_floor_table_degenerate on a valid ladder — docstring contract unhonoured".
5. HIGH plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:527 — "resolve_review_pool elif rank_table: branch not updated for the new _review_floor(ok=True, arm=None) post-filter-empty case — misclassifies as pool_floor_table_degenerate instead of all_review_arms_unavailable".
6. HIGH plugins/leadv2/scripts/tests/test-plan-followups-01.sh:66 — "Caveat-2 and caveat-4 tests are not mutation-gated (fixtures put dispatch_ladder at top level, parser reads router.dispatch_ladder) — reverting those fixes keeps 2a/2b/2c/4b/4c/4d green". Fix fixture shape so those tests exercise the fixed code paths.

Also ADD test cases: order-B with trailing prose after closing fence; marker-without-fence; sole-dispatchable-floor-arm.

Verification you MUST run and report:
- bash plugins/leadv2/scripts/tests/test-plan-followups-01.sh green.
- Mutation: revert fix 1 → suite FAILS (report rc); prove fixture fix 6 makes caveat-2/4 tests catch reverted fixes. Report rcs.
- ONE commit: "fix(plan-engine): PLAN-FOLLOWUPS-01 r3 — pass-A/B extraction correctness (trailing prose, marker-only), sole-arm floor honored end-to-end, mutation-gated fixtures"

Do NOT push/merge. Final line: sha + rcs + DELIVERABLE_COMPLETE.
