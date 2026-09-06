# ESCALATION-OFFERS-DESTRUCTIVE-DEFAULTS-FOR-FINISHED-LANES-01 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/ESCALATION-OFFERS-DESTRUCTIVE-DEFAULTS-FOR-FINISHED-LANES-01` on 2026-09-06 by the blocking filter of
LEADV2-WORKTREE-ADJUDICATION-01, **before** any verdict was written about the
branch. A lane's branch can be an empty anchor while the work sits untracked or
merely staged inside its checkout: `git log` never sees the index, and removing
the checkout would take both with it.

Text only — nothing here is installed or made executable. Restoring any of it is
a deliberate act by whoever owns the row.

## `git diff HEAD -- plugins tests` (staged and unstaged)

```diff
diff --git a/plugins/leadv2/scripts/leadv2-lanes-snapshot.sh b/plugins/leadv2/scripts/leadv2-lanes-snapshot.sh
index 253477cf..2da460b1 100755
--- a/plugins/leadv2/scripts/leadv2-lanes-snapshot.sh
+++ b/plugins/leadv2/scripts/leadv2-lanes-snapshot.sh
@@ -603,12 +603,25 @@ def parse_iso(s):
         return None
 
 def pid_alive(pid_val):
+    # ESCALATION-OFFERS-DESTRUCTIVE-DEFAULTS-FOR-FINISHED-LANES-01 addendum
+    # (SILENCE-READ-AS-FACT-CENSUS-01 A1): THREE-valued probe. os.kill(pid, 0)
+    # raising EPERM means the process is ALIVE and we may not signal it
+    # (foreign uid, sandbox) -- the prior two-valued shape folded that into
+    # "dead", so a lane we could not see was read as corroborated-dead and
+    # offered abandon/restart. Only a positive ProcessLookupError is "gone";
+    # EPERM or any other errno is "unknown" and may never feed a destructive
+    # action. Callers compare against the strings, never truthiness.
     try:
         pid = int(pid_val)
+    except (TypeError, ValueError):
+        return "unknown"  # not even a parseable pid -- cannot say dead
+    try:
         os.kill(pid, 0)
-        return True
-    except (TypeError, ValueError, ProcessLookupError, PermissionError):
-        return False
+        return "alive"
+    except ProcessLookupError:
+        return "gone"
+    except Exception:
+        return "unknown"
 
 def _commit_age_s(worktree):
     # LANE-LIVENESS-THREE-STATES-02: same externally-checkable evidence as
@@ -867,15 +880,25 @@ for tid, s in list(current.items()):
             if liveness_verdict.startswith("dead:"):
                 pid_issue = True
                 pid_issue_reason = f"lane_liveness={liveness_verdict}"
-    elif not pid_alive(pid):
-        pid_issue = True
-        pid_issue_reason = "pid dead"
     else:
-        stored_birth = _norm_birth(s.get("pid_birth"))
-        cur_birth = _pid_birth_of(pid)
-        if stored_birth and cur_birth and stored_birth != cur_birth:
+        # ESCALATION-OFFERS-...-01 addendum: only a positive "gone" (no such
+        # process) is death evidence. "unknown" (EPERM/errno -- alive but not
+        # signalable, or an unparseable pid) is NOT: a lane whose pid we
+        # cannot see must never be pruned, tombstoned, or offered
+        # abandon/restart on the strength of "we could not tell".
+        _pid_probe = pid_alive(pid)
+        if _pid_probe == "gone":
             pid_issue = True
-            pid_issue_reason = "pid birth mismatch (reuse)"
+            pid_issue_reason = "pid dead"
+        elif _pid_probe == "unknown":
+            pid_issue = False
+            pid_issue_reason = None
+        else:
+            stored_birth = _norm_birth(s.get("pid_birth"))
+            cur_birth = _pid_birth_of(pid)
+            if stored_birth and cur_birth and stored_birth != cur_birth:
+                pid_issue = True
+                pid_issue_reason = "pid birth mismatch (reuse)"
 
     reasons = []
     if backend == "tmux":
@@ -1093,9 +1116,14 @@ if (pending_adopts or apply_prunes) and not observe_only:
                 if p["task_id"] not in tombstoned_ids:
                     continue
                 try:
+                    # ESCALATION-OFFERS-...-01 addendum: NOT "corroborated" --
+                    # the evidence is the SAME probe(s) seen on two
+                    # consecutive polls (prev_dead_candidates), never a
+                    # second independent source; a lead reading
+                    # "corroborated" reasonably believes two things agreed.
                     subprocess.run(
                         [_ask_sh, p["task_id"],
-                         f"Task {p['task_id']} corroborated dead: {'; '.join(p['reasons'])}. Escalate.",
+                         f"Task {p['task_id']} dead on two consecutive polls (same evidence, not independent sources): {'; '.join(p['reasons'])}. Escalate.",
                          "--option", "inspect|inspect logs first",
                          "--option", "restart|restart the task",
                          "--option", "abandon|mark abandoned",
@@ -1240,7 +1268,7 @@ if cp_questions_dir and os.path.isdir(cp_questions_dir):
         selected = answer.get("selected") if isinstance(answer, dict) else answer
         tid = str(qd.get("task_id") or "")
         if (qd.get("status") == "answered" and selected == "abandon" and tid
-                and str(qd.get("question") or "").startswith(f"Task {tid} corroborated dead:")):
+                and str(qd.get("question") or "").startswith(f"Task {tid} dead on two consecutive polls")):
             abandon_answers.append((tid, qf))
             continue
         if qd.get("status") != "pending":
diff --git a/plugins/leadv2/scripts/tests/test-finished-lane-no-escalation.sh b/plugins/leadv2/scripts/tests/test-finished-lane-no-escalation.sh
index b9da4510..7d3640bf 100755
--- a/plugins/leadv2/scripts/tests/test-finished-lane-no-escalation.sh
+++ b/plugins/leadv2/scripts/tests/test-finished-lane-no-escalation.sh
@@ -18,6 +18,16 @@
 #   Test 4  genuine death (no commit, no deliverable, gone pid) still
 #           escalates exactly as today -- the veto must not over-silence
 #
+# ADDENDUM half (SILENCE-READ-AS-FACT-CENSUS-01 A1): pid_alive is a
+# THREE-valued probe (alive/gone/unknown); EPERM means alive-but-not-
+# signalable and must never read as dead.
+#   Test 5  fixture pid answering EPERM (pid 1 as non-root) resolves to
+#           unknown -> row kept, no tombstone, no abandon/restart (baseline)
+#   Test 6  mutating pid_alive's errno handling back to the pre-fix fold
+#           (REGEXP anchor inside the function body, exactly once) -> the
+#           EPERM lane is pruned and offered abandon/restart (RED)
+#   Test 7  revert -> GREEN again
+#
 # The deliverable age is deliberately 600s: strictly between
 # LEADV2_LANE_FRESH_S (120s, the LIES-01 freshness veto) and
 # LEADV2_LANE_FINISHED_WINDOW_S (1800s), so neither the freshness veto nor a
@@ -43,6 +53,18 @@ STATE_PATH_SH="${PLUGIN_DIR}/scripts/leadv2-state-path.sh"
 ANCHOR='if _lv_verdict.startswith("finished") and _lv_source != "git_commit":'
 MUTATION_GATE='if False:  # ESCALATION-OFFERS-DESTRUCTIVE-DEFAULTS-FOR-FINISHED-LANES-01 mutation gate'
 
+# ADDENDUM control anchor: pid_alive's errno handling, INSIDE the function
+# body (never a line number; asserted to match exactly once before mutating).
+# The mutation folds EPERM back into the probe's dead answer -- the exact
+# pre-fix two-valued defect (except (..., PermissionError): return False)
+# expressed in the three-valued vocabulary the call site now compares.
+EPERM_ANCHOR='    except ProcessLookupError:
+        return "gone"
+    except Exception:
+        return "unknown"'
+EPERM_MUTATION='    except (ProcessLookupError, Exception):
+        return "gone"'
+
 PASS=0; FAIL=0; ERRORS=()
 log()  { printf -- '[TEST] %s\n' "$*"; }
 pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
@@ -229,6 +251,7 @@ for row in d.get('lanes', []):
 }
 
 ARTIFACT_LINES=()
+EPERM_ARTIFACT_LINES=()
 
 # ── Test 1: finished lane + gone pid -> NO escalation (baseline) ────────────
 test_1_baseline_no_escalation() {
@@ -348,9 +371,151 @@ test_4_genuine_death_still_escalates() {
   fi
 }
 
+# ── ADDENDUM: EPERM -> unknown, never a destructive action ─────────────────
+
+_tombstoned() { # <repo> <state> <tid> -> prints True/False, never fails
+  local tomb_path
+  tomb_path="$(LEADV2_PROJECT_ROOT="$1" LEADV2_STATE_ROOT="$2" \
+    PROJECT_ROOT="$1" bash "$STATE_PATH_SH" tombstones.yaml 2>/dev/null)" || tomb_path=""
+  if [[ -z "$tomb_path" || ! -f "$tomb_path" ]]; then
+    printf 'False'
+    return 0
+  fi
+  python3 -c "
+import yaml
+rows = yaml.safe_load(open('$tomb_path')) or []
+print(any(isinstance(r, dict) and str(r.get('task_id')) == '$3' for r in rows))
+" 2>/dev/null || printf 'False'
+}
+
+_eperm_probe_pid() { # prints a pid whose os.kill(pid, 0) answers EPERM, or nothing
+  # pid 1 (launchd) is root-owned: as non-root, os.kill(1, 0) -> EPERM.
+  python3 -c "
+import os, sys
+try:
+    os.kill(1, 0)
+except PermissionError:
+    print(1)
+except OSError:
+    pass
+" 2>/dev/null
+}
+
+_block_count() { # <file> <block-string> -- occurrences of an exact multiline block
+  BLOCK_COUNT_FILE="$1" BLOCK_COUNT_BLOCK="$2" python3 -c "
+import os
+src = open(os.environ['BLOCK_COUNT_FILE']).read()
+print(src.count(os.environ['BLOCK_COUNT_BLOCK']))
+"
+}
+
+# ── Test 5: EPERM pid -> unknown -> no prune, no tombstone, no question ─────
+test_5_eperm_baseline_no_escalation() {
+  local repo state tid eperm_pid offered present tomb baseline_rc
+  eperm_pid="$(_eperm_probe_pid)"
+  if [[ -z "$eperm_pid" ]]; then
+    fail "Test 5: no EPERM-probing pid available (running as root? os.kill(1,0) did not raise PermissionError) -- EPERM control cannot run"
+    return
+  fi
+  read -r repo state < <(_new_fixture)
+  tid="EFN-EPERM-UNKNOWN-01"
+  # No deliverable, stale main HEAD: nothing but the pid probe could mark
+  # this lane dead -- and the probe must answer "unknown", not "dead".
+  _commit_aged "$repo" "stale main head" 7200
+  _fixture_row "$repo" "$state" "$tid" "$eperm_pid" 0
+  _reset_poll_state "$repo" "$state"
+
+  baseline_rc=0
+  _snapshot_poll "$repo" "$state" || baseline_rc=$?
+  _snapshot_poll "$repo" "$state" || baseline_rc=$?
+  present="$(_row_present "$(_active_yaml "$repo" "$state")" "$tid")"
+  tomb="$(_tombstoned "$repo" "$state" "$tid")"
+  offered="$(_escalation_offered "$state" "$tid")"
+  if [[ "$present" == True && "$tomb" == False && "$offered" == none && "$baseline_rc" == 0 ]]; then
+    pass "Test 5: EPERM pid ($eperm_pid) -> unknown -> row kept, no tombstone, no abandon/restart question"
+  else
+    fail "Test 5: EPERM pid escalated -- present=$present tomb=$tomb offered=$offered rc=$baseline_rc"
+  fi
+  EPERM_ARTIFACT_LINES+=("eperm_pid=${eperm_pid}" "baseline_rc=${baseline_rc}")
+}
+
+# ── Test 6+7: mutation gate on pid_alive's errno handling ──────────────────
+test_6_7_eperm_mutation_gate() {
+  local repo state tid eperm_pid anchor_count offered present tomb mutated_rc red_line
+  eperm_pid="$(_eperm_probe_pid)"
+  if [[ -z "$eperm_pid" ]]; then
+    fail "Test 6: no EPERM-probing pid available -- EPERM mutation gate cannot run"
+    return
+  fi
+  # Anchor must exist exactly once BEFORE any mutation (block anchor inside
+  # the pid_alive function body, never a line number).
+  anchor_count="$(_block_count "$SNAPSHOT_SH" "$EPERM_ANCHOR")"
+  if [[ "$anchor_count" != 1 ]]; then
+    fail "Test 6: EPERM anchor matched ${anchor_count}x (need exactly 1) in $SNAPSHOT_SH -- aborting mutation gate"
+    return
+  fi
+
+  cp "$SNAPSHOT_SH" "${SNAPSHOT_SH}.escfin-orig"
+  EPERM_MUT_FILE="$SNAPSHOT_SH" EPERM_ANCHOR_V="$EPERM_ANCHOR" EPERM_MUT_V="$EPERM_MUTATION" \
+    python3 -c "
+import os
+path = os.environ['EPERM_MUT_FILE']
+src = open(path).read()
+assert src.count(os.environ['EPERM_ANCHOR_V']) == 1
+open(path, 'w').write(src.replace(os.environ['EPERM_ANCHOR_V'], os.environ['EPERM_MUT_V']))
+"
+  if [[ "$(_block_count "$SNAPSHOT_SH" "$EPERM_ANCHOR")" != 0 ]]; then
+    fail "Test 6: mutation did not remove the EPERM anchor -- aborting"
+    cp "${SNAPSHOT_SH}.escfin-orig" "$SNAPSHOT_SH"; rm -f "${SNAPSHOT_SH}.escfin-orig"
+    return
+  fi
+
+  read -r repo state < <(_new_fixture)
+  tid="EFN-EPERM-MUTGATE-01"
+  _commit_aged "$repo" "stale main head" 7200
+  _fixture_row "$repo" "$state" "$tid" "$eperm_pid" 0
+  _reset_poll_state "$repo" "$state"
+
+  mutated_rc=0
+  _snapshot_poll "$repo" "$state" || mutated_rc=$?
+  _snapshot_poll "$repo" "$state" || mutated_rc=$?
+  present="$(_row_present "$(_active_yaml "$repo" "$state")" "$tid")"
+  tomb="$(_tombstoned "$repo" "$state" "$tid")"
+  offered="$(_escalation_offered "$state" "$tid")"
+
+  # RED: with the errno fold restored, an EPERM (live-but-unsignalable) pid
+  # reads dead and is offered abandon/restart -- asserted on option labels.
+  if [[ "$present" == False && "$offered" != none ]]; then
+    red_line="EPERM lane pruned and offered abandon/restart: question=$(basename "${offered%%|*}") labels=${offered##*|} tomb=$tomb"
+    pass "Test 6: mutation folded EPERM back into dead -> $red_line (RED)"
+  else
+    red_line=""
+    fail "Test 6: mutation did NOT re-enable escalation -- present=$present offered=$offered rc=$mutated_rc"
+  fi
+  EPERM_ARTIFACT_LINES+=("mutated_rc=${mutated_rc}")
+  [[ -n "$red_line" ]] && EPERM_ARTIFACT_LINES+=("red_line=${red_line}")
+
+  # Revert -> GREEN.
+  cp "${SNAPSHOT_SH}.escfin-orig" "$SNAPSHOT_SH"
+  rm -f "${SNAPSHOT_SH}.escfin-orig"
+  _fixture_row "$repo" "$state" "$tid" "$eperm_pid" 0
+  _reset_poll_state "$repo" "$state"
+  _snapshot_poll "$repo" "$state" || true
+  _snapshot_poll "$repo" "$state" || true
+  present="$(_row_present "$(_active_yaml "$repo" "$state")" "$tid")"
+  offered="$(_escalation_offered "$state" "$tid")"
+  if [[ "$present" == True && "$offered" == none ]]; then
+    pass "Test 7: revert restores unknown-handling (row kept, no question)"
+  else
+    fail "Test 7: revert still escalates the EPERM lane -- present=$present offered=$offered"
+  fi
+}
+
 test_1_baseline_no_escalation
 test_2_3_mutation_gate
 test_4_genuine_death_still_escalates
+test_5_eperm_baseline_no_escalation
+test_6_7_eperm_mutation_gate
 
 if [[ -n "${ESCAL_FINISHED_ARTIFACT:-}" ]]; then
   mkdir -p "$ESCAL_FINISHED_ARTIFACT"
@@ -359,6 +524,11 @@ if [[ -n "${ESCAL_FINISHED_ARTIFACT:-}" ]]; then
     printf -- 'anchor_matches=1\n'
     printf -- '%s\n' "${ARTIFACT_LINES[@]:-}"
   } > "${ESCAL_FINISHED_ARTIFACT}/mutation-control.txt"
+  {
+    printf -- 'anchor=%s\n' "$(printf '%s' "$EPERM_ANCHOR" | head -1 | sed 's/^ *//')"
+    printf -- 'anchor_matches=1\n'
+    printf -- '%s\n' "${EPERM_ARTIFACT_LINES[@]:-}"
+  } > "${ESCAL_FINISHED_ARTIFACT}/mutation-control-eperm.txt"
 fi
 
 printf -- '[TEST] ===================================================================\n'
diff --git a/plugins/leadv2/scripts/tests/test-t13-slice2.sh b/plugins/leadv2/scripts/tests/test-t13-slice2.sh
index 001b3b68..362a967e 100755
--- a/plugins/leadv2/scripts/tests/test-t13-slice2.sh
+++ b/plugins/leadv2/scripts/tests/test-t13-slice2.sh
@@ -265,7 +265,7 @@ YAML
   mkdir -p "$q_dir"
   cat > "${q_dir}/q-abandon-1.yaml" <<'YAML'
 task_id: ABANDON-1
-question: "Task ABANDON-1 corroborated dead: liveness probe failed. Escalate."
+question: "Task ABANDON-1 dead on two consecutive polls (same evidence, not independent sources): liveness probe failed. Escalate."
 status: answered
 answer:
   selected: abandon
```

