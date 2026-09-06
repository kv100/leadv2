# TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01` on 2026-09-06 by the blocking filter of
LEADV2-WORKTREE-ADJUDICATION-01, **before** any verdict was written about the
branch. A lane's branch can be an empty anchor while the work sits untracked or
merely staged inside its checkout: `git log` never sees the index, and removing
the checkout would take both with it.

Text only — nothing here is installed or made executable. Restoring any of it is
a deliberate act by whoever owns the row.

## `git diff HEAD -- plugins tests` (staged and unstaged)

```diff
diff --git a/tests/run-all.sh b/tests/run-all.sh
index bd32b8c9..ad3f81e4 100755
--- a/tests/run-all.sh
+++ b/tests/run-all.sh
@@ -132,6 +132,7 @@ add_suite "${ROOT}/tests/test-status-surface-fast-names.sh"
 # not by any test-dispatch-code.sh) is mapped here so --scope changed still
 # runs its suite instead of silently dropping it.
 EXTRA_SUITE_MAP="leadv2-quota-read:plugins/leadv2/scripts/tests/test-quota-read-anthropic-liveness.sh
+leadv2-claude-profile-select.sh:plugins/leadv2/scripts/tests/test-claude-profile-select.sh
 glm-coder.sh:plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh
 glm-coder.sh:plugins/leadv2/scripts/tests/test-glm-flash-handle.sh
 glm-coder.sh:plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh
```

