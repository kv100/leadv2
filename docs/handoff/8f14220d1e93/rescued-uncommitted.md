# 8f14220d1e93 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/8f14220d1e93` on 2026-09-06 by the blocking filter of
LEADV2-WORKTREE-ADJUDICATION-01, **before** any verdict was written about the
branch. A lane's branch can be an empty anchor while the work sits untracked or
merely staged inside its checkout: `git log` never sees the index, and removing
the checkout would take both with it.

Text only — nothing here is installed or made executable. Restoring any of it is
a deliberate act by whoever owns the row.

## `git diff HEAD -- plugins tests` (staged and unstaged)

```diff
diff --git a/plugins/leadv2/scripts/tests/test-idle-lead-guard.sh b/plugins/leadv2/scripts/tests/test-idle-lead-guard.sh
index f6186186..59ca23e7 100755
--- a/plugins/leadv2/scripts/tests/test-idle-lead-guard.sh
+++ b/plugins/leadv2/scripts/tests/test-idle-lead-guard.sh
@@ -414,13 +414,6 @@ assert d["decision"] == "block"
 
 # ════════════════════════════════════════════════════════════════════════════
 # Case 10: hooks.json registration assertion
-# ONE-LANE-WATCH-01 (9f00e7ed, 2026-09-01) retired the idle-lead-guard Stop
-# registration in favour of the self-arming lane watcher leadv2-lane-watch-v2
-# (SessionStart --arm-from-hook / SessionEnd --disarm-from-hook). The old
-# "idle-lead-guard last after promise-guard" ordering assertion rotted the day
-# that landed; the registration contract now is: retired hook ABSENT, its
-# ordering partner promise-guard still present, replacement watcher registered
-# on both of its events.
 # ════════════════════════════════════════════════════════════════════════════
 {
   HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"
@@ -430,18 +423,16 @@ with open(sys.argv[1]) as f:
     d = json.load(f)
 stop_hooks = d["hooks"]["Stop"][0]["hooks"]
 ids = [h["command"] for h in stop_hooks]
-assert not any("leadv2-idle-lead-guard.sh" in c for c in ids), \
-    f"retired idle-lead-guard still registered in Stop: {ids}"
-assert any("leadv2-promise-guard.sh" in c for c in ids), \
-    f"promise-guard (the old ordering partner) vanished from Stop: {ids}"
-arm = [h["command"] for h in d["hooks"]["SessionStart"][0]["hooks"]]
-disarm = [h["command"] for h in d["hooks"]["SessionEnd"][0]["hooks"]]
-assert any("leadv2-lane-watch-v2.sh" in c and "--arm-from-hook" in c for c in arm), \
-    f"lane-watch-v2 --arm-from-hook missing from SessionStart: {arm}"
-assert any("leadv2-lane-watch-v2.sh" in c and "--disarm-from-hook" in c for c in disarm), \
-    f"lane-watch-v2 --disarm-from-hook missing from SessionEnd: {disarm}"
+# Must contain idle-lead-guard
+assert any("leadv2-idle-lead-guard.sh" in c for c in ids), f"idle-lead-guard not found in {ids}"
+# Must be after promise-guard
+pg_idx = next(i for i, c in enumerate(ids) if "leadv2-promise-guard.sh" in c)
+ig_idx = next(i for i, c in enumerate(ids) if "leadv2-idle-lead-guard.sh" in c)
+assert ig_idx > pg_idx, f"idle-guard (idx {ig_idx}) must be after promise-guard (idx {pg_idx})"
+# Must be the last entry
+assert ig_idx == len(ids) - 1, f"idle-guard is not last (idx {ig_idx}, last {len(ids)-1})"
 ' "$HOOKS_JSON" 2>/dev/null; then
-    pass "case 10: idle-lead-guard retired; promise-guard kept; lane-watch-v2 armed on both events"
+    pass "case 10: hooks.json has idle-lead-guard last after promise-guard"
   else
     fail "case 10: registration assertion failed"
   fi
diff --git a/plugins/leadv2/scripts/tests/test-injector-dedup.sh b/plugins/leadv2/scripts/tests/test-injector-dedup.sh
index a0753cbb..ec9070ee 100755
--- a/plugins/leadv2/scripts/tests/test-injector-dedup.sh
+++ b/plugins/leadv2/scripts/tests/test-injector-dedup.sh
@@ -317,15 +317,7 @@ if upc_multisession "$UPC"; then pass "multisession: 4th session (note+blocked_b
 # Mutant lives in a full copy of hooks/ so relative `source` neighbors resolve.
 cp -R "$(dirname "$UPC")" "$ROOT/hooks-mut"
 UPC_MUT="$ROOT/hooks-mut/$(basename "$UPC")"
-# Mutation anchor matches the comprehension across line breaks ([^\]]* crosses
-# \n) — TERMINAL-LANES-STILL-READ-AS-LIVE-01 (b8db6058) rewrote it multi-line
-# and the old single-line literal silently stopped matching, turning this
-# control into a no-op that "stayed green". The grep below makes anchor rot a
-# loud failure instead of a meaningless pass.
-perl -0pi -e "s/(others = \[sess for sess in s[^\]]*\])/\${1}[:3]/" "$UPC_MUT"
-if ! grep -q '\[:3\]' "$UPC_MUT"; then
-  fail "negative-control anchor rotted: mutation did not apply to $UPC_MUT"
-fi
+perl -0pi -e "s/others = \[sess for sess in s if sess\.get\('task_id'\) != mine\]/others = [sess for sess in s if sess.get('task_id') != mine][:3]/" "$UPC_MUT"
 if upc_multisession "$UPC_MUT"; then fail "multisession negative control stayed green"; else pass "multisession negative-control red (cap reintroduced => 4th session lost)"; fi
 
 printf -- '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
diff --git a/plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh b/plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh
index a24961af..93ece42a 100644
--- a/plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh
+++ b/plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh
@@ -34,13 +34,6 @@
 
 set -uo pipefail
 
-# The suite's own tripwire flags ANY new path under plugins/ — including
-# __pycache__/*.pyc that CPython writes next to the imported lib modules
-# (observed 2026-09-05: leadv2_tasks_yaml_common + lib/leadv2_pid_birth).
-# Bytecode caches are not lane writes; suppress them at the interpreter level
-# so the tripwire only ever sees real file changes.
-export PYTHONDONTWRITEBYTECODE=1
-
 SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
 LEADV2_REPO="$(cd "${SELF_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
 
diff --git a/plugins/leadv2/scripts/tests/test-phase-precondition.sh b/plugins/leadv2/scripts/tests/test-phase-precondition.sh
index fe1340ff..8d4837a4 100755
--- a/plugins/leadv2/scripts/tests/test-phase-precondition.sh
+++ b/plugins/leadv2/scripts/tests/test-phase-precondition.sh
@@ -279,12 +279,11 @@ case "${1:-}" in
     mkdir -p "$RUNS" 2>/dev/null
     handle="stub-run-$(date +%s)-$$"
     printf '%s' "$handle" > "$RUNS/$handle" 2>/dev/null
-    # GLM-ARM-THROUGHPUT-01: dispatch-code's GLM adapter treats bg's stdout as
-    # the BARE run_id (trimmed newline, no doubling, no "$RUNS/" prefix) — the
-    # legacy "<run-dir>/<handle><handle>" envelope was retired with the
-    # halving logic. Emit the bare handle so `status <handle>` below resolves
-    # the run record this stub just wrote.
-    printf '%s\n' "$handle"
+    # dispatch-code's GLM adapter extracts a handle from the legacy
+    # "<run-dir>/<handle><handle>" launch envelope.  Emit that exact envelope
+    # so the fixture exercises its liveness check instead of falling through
+    # to a real later arm after a false not_live result.
+    printf '%s/%s%s\n' "$RUNS" "$handle" "$handle"
     exit 0
     ;;
   status)
diff --git a/plugins/leadv2/scripts/tests/test-t14-worker-mcp.sh b/plugins/leadv2/scripts/tests/test-t14-worker-mcp.sh
index 09b5cf83..524e616c 100644
--- a/plugins/leadv2/scripts/tests/test-t14-worker-mcp.sh
+++ b/plugins/leadv2/scripts/tests/test-t14-worker-mcp.sh
@@ -188,9 +188,6 @@ test_03_killswitch_off() {
     fail "kill-switch=0 still emits MCP flags (rc=${G_RC})"
   fi
   local argv_masked baseline_file
-  # Baseline includes the effort seam's `--effort max` (GLM-EFFICIENCY-01,
-  # probes 2026-09-04): it rides the spawn line regardless of MCP state, so it
-  # is part of the kill-switch=0 contract, not drift.
   baseline_file="${FIXTURE}/t14-03-baseline-$$.txt"
   cat > "${baseline_file}" <<'BASEEOF'
 -p
@@ -202,8 +199,6 @@ Agent
 sonnet
 --output-format
 json
---effort
-max
 BASEEOF
   CLEANUP_PATHS+=("${baseline_file}")
   # Mask from `-p` until the first REAL spawn flag (the FINISH CONTRACT trailer
```

