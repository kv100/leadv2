# MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01` on 2026-09-06 by the blocking filter of
LEADV2-WORKTREE-ADJUDICATION-01, **before** any verdict was written about the
branch. A lane's branch can be an empty anchor while the work sits untracked or
merely staged inside its checkout: `git log` never sees the index, and removing
the checkout would take both with it.

Text only — nothing here is installed or made executable. Restoring any of it is
a deliberate act by whoever owns the row.

## `git diff HEAD -- plugins tests` (staged and unstaged)

```diff
diff --git a/plugins/leadv2/scripts/tests/test-worker-dod-gate.sh b/plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
index 32388183..1c3b578c 100644
--- a/plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
+++ b/plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
@@ -519,6 +519,31 @@ else
   fail "mutation-control: distinct mutations collided (rc=${mc_rc}, first=${MC_FIRST_HASH}, second=${MC_SECOND_HASH})"
 fi
 
+# ---------------------------------------------------------------------------
+# MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01 gap: the two-mutations case
+# above only ever drives REAL non-empty mutations through the writer, so it
+# never exercises the reader's degenerate-hash rejection at
+# lib/leadv2-dod-gate.sh's `artifact_hash != e3b0c442...` line. Hand-craft an
+# artifact with every field valid except diff_hash forged to the sha256("")
+# constant, and call the real production function directly — this is the one
+# shape today's suite never touched, and reverting that one guard line would
+# not have turned any existing case red.
+MC_FORGED_ARTIFACT="${MC_TASK_DIR}/mutation-control/forged-empty-hash.txt"
+mkdir -p "${MC_TASK_DIR}/mutation-control"
+cat > "${MC_FORGED_ARTIFACT}" <<EOF
+suite=suite.sh
+file=lib/target.sh
+baseline_rc=0
+mutated_rc=1
+diff_hash=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
+lane_diff_hash=${MC_FIRST_HASH}
+EOF
+if _dod_valid_mutation_artifact "${MC_FORGED_ARTIFACT}" "${MC_FIRST_HASH}"; then
+  fail "_dod_valid_mutation_artifact: forged empty-hash diff_hash was accepted (expected rc=1 reject)"
+else
+  pass "_dod_valid_mutation_artifact: forged diff_hash=sha256(\"\") artifact is rejected (rc=1)"
+fi
+
 ( cd "${MC_REPO}" && LEADV2_LANE_START_SHA="${MC_BASE_SHA}" bash "${MUT_CTL_SH}" suite.sh lib/target.sh 's/NOPE_NO_MATCH_ANCHOR/x/' "${MC_TASK_DIR}" ) \
   >"${FIXTURE}/mc-anchor.out" 2>&1
 mc_rc=$?
```

