# W1-LAND-STRANDED-8F14220D-01 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/W1-LAND-STRANDED-8F14220D-01` on 2026-09-06 by the blocking filter of
LEADV2-WORKTREE-ADJUDICATION-01, **before** any verdict was written about the
branch. A lane's branch can be an empty anchor while the work sits untracked or
merely staged inside its checkout: `git log` never sees the index, and removing
the checkout would take both with it.

Text only — nothing here is installed or made executable. Restoring any of it is
a deliberate act by whoever owns the row.

## `git diff HEAD -- plugins tests` (staged and unstaged)

```diff
diff --git a/tests/known-red-suites.txt b/tests/known-red-suites.txt
index 4b5fde98..d012ca52 100644
--- a/tests/known-red-suites.txt
+++ b/tests/known-red-suites.txt
@@ -22,9 +22,7 @@
 
 core:landed-at-spawn (no terminal=landed at spawn; target repo keying)  # plugins/leadv2/scripts/tests/test-landed-at-spawn.sh — red on main at CI-RUNS-THE-SUITES-01 baseline (2026-09-02); see FIFTEEN-RED-SUITES-01
 core:dispatch arm vocabulary (kimi retirement)  # plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh — red on main at CI-RUNS-THE-SUITES-01 baseline (2026-09-02); see FIFTEEN-RED-SUITES-01
-core:phase precondition guard matrix  # plugins/leadv2/scripts/tests/test-phase-precondition.sh — red on main at CI-RUNS-THE-SUITES-01 baseline (2026-09-02); see FIFTEEN-RED-SUITES-01
 core:claim-evidence gate (CLAIM-EVIDENCE-GATE-01 preamble + round-1 lens)  # plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh — red on main at CI-RUNS-THE-SUITES-01 baseline (2026-09-02); see FIFTEEN-RED-SUITES-01
-core:product-close scopes a single-repo lane worktree  # plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh — red on main at CI-RUNS-THE-SUITES-01 baseline (2026-09-02); see FIFTEEN-RED-SUITES-01
 core:codex-dead review reroute (QUOTA-GATE-PARITY-01)  # plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh — red on main at CI-RUNS-THE-SUITES-01 baseline (2026-09-02); see FIFTEEN-RED-SUITES-01
 core:review round exhaustive/verify-only (REVIEW-ROUND1-EXHAUSTIVE-01)  # plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh — red on main at CI-RUNS-THE-SUITES-01 baseline (2026-09-02); see FIFTEEN-RED-SUITES-01
 core:deferred-GLM ladder (V3-GLM-LADDER-01)  # plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh — red on main at CI-RUNS-THE-SUITES-01 baseline (2026-09-02); see FIFTEEN-RED-SUITES-01
```

