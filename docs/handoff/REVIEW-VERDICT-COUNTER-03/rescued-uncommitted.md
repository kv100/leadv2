# REVIEW-VERDICT-COUNTER-03 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/REVIEW-VERDICT-COUNTER-03` on 2026-09-06 by the blocking filter of
LEADV2-WORKTREE-ADJUDICATION-01, **before** any verdict was written about the
branch. A lane's branch can be an empty anchor while the work sits untracked or
merely staged inside its checkout: `git log` never sees the index, and removing
the checkout would take both with it.

Text only — nothing here is installed or made executable. Restoring any of it is
a deliberate act by whoever owns the row.

## `git diff HEAD -- plugins tests` (staged and unstaged)

```diff
diff --git a/plugins/leadv2/scripts/ask-lead.sh b/plugins/leadv2/scripts/ask-lead.sh
index 514f9f18..a55579ae 100755
--- a/plugins/leadv2/scripts/ask-lead.sh
+++ b/plugins/leadv2/scripts/ask-lead.sh
@@ -45,6 +45,13 @@ ASKED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
 
 touch "$SIGNAL"
 
+# LEAD-WORKER-CHANNEL-01: the durable row is written above (PENDING); this
+# is only the wake-up optimisation on top, so its own failure must never
+# block the blocking poll below. stderr only -- stdout is reserved for the
+# eventual answer text.
+SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
+PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-notify-lead.sh" "$TASK_ID" question "$QUESTION" >&2 2>/dev/null || true
+
 LOCK="$Q_DIR/${QID}-answer.lock"
 DEADLINE=$(($(date +%s) + TIMEOUT))
 # If lead writes the .lock file it signals "answer in progress — keep waiting even past soft deadline".
diff --git a/plugins/leadv2/scripts/leadv2-ask.sh b/plugins/leadv2/scripts/leadv2-ask.sh
index 907be2e8..b16108b2 100755
--- a/plugins/leadv2/scripts/leadv2-ask.sh
+++ b/plugins/leadv2/scripts/leadv2-ask.sh
@@ -335,6 +335,12 @@ else
   printf -- '[leadv2-ask] qid=%s task_id=%s file=%s\n' "$QID" "$TASK_ID" "$QFILE" >&2
 fi
 
+# LEAD-WORKER-CHANNEL-01: durable row above (V2 or legacy) is already
+# written by this point in either branch -- this is only the wake-up
+# optimisation on top, so its own failure must never block the poll below.
+# stderr only -- stdout is reserved for the QID (NO_BLOCK) or answer text.
+"${SCRIPT_DIR}/leadv2-notify-lead.sh" "$TASK_ID" question "$QUESTION" >&2 2>/dev/null || true
+
 if [[ "$NO_BLOCK" -eq 1 ]]; then
   printf -- '%s\n' "$QID"
   exit 0
diff --git a/plugins/leadv2/scripts/leadv2-broad-status.sh b/plugins/leadv2/scripts/leadv2-broad-status.sh
index 4204577c..f8b4b10a 100755
--- a/plugins/leadv2/scripts/leadv2-broad-status.sh
+++ b/plugins/leadv2/scripts/leadv2-broad-status.sh
@@ -1332,6 +1332,17 @@ fi
 # with no rows — it must be unmistakable in the first two lines. Line 1
 # stays the machine-parseable dispatched= stamp (the relay contract's
 # format), so the headline is line 2, ahead of everything else, when set.
+# LEAD-WORKER-CHANNEL-01: drain the durable lead inbox on every beat, so an
+# unread worker event reaches this status EVEN IF every SendMessage wake-up
+# was lost -- that is the property that makes the mechanism real rather
+# than another thing that only works when everything already works. Lead
+# id resolved the same way leadv2-dispatch-code.sh computes
+# _lead_session_id, since this beat runs under that same lead's session.
+# Never fatal: an inbox drain failure degrades to no inbox section, not a
+# failed beat.
+_LWC_LEAD_ID="${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-${CLAUDE_SESSION_ID:-direct}}}"
+INBOX_MD="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-inbox.sh" drain --lead "${_LWC_LEAD_ID}" 2>/dev/null || true)"
+
 BLOCK="$(
   printf '%s [BROAD_STATUS] dispatched=%s\n' "$BEAT_AT" "$DISPATCHED"
   if [[ -n "$EMPTY_HEADLINE" ]]; then
@@ -1345,6 +1356,9 @@ BLOCK="$(
   if [[ -n "$PULSE_MD" ]]; then
     printf '\n%s\n' "$PULSE_MD"
   fi
+  if [[ -n "$INBOX_MD" ]]; then
+    printf '\n**Unread lead-worker events:**\n%s\n' "$INBOX_MD"
+  fi
   printf '%s\n' "$DECISIONS_LINE"
   if [[ -n "$HIDDEN_NOTE" ]]; then
     printf '%s\n' "$HIDDEN_NOTE"
diff --git a/plugins/leadv2/scripts/leadv2-dispatch-code.sh b/plugins/leadv2/scripts/leadv2-dispatch-code.sh
index 9c599ebc..83f5438e 100755
--- a/plugins/leadv2/scripts/leadv2-dispatch-code.sh
+++ b/plugins/leadv2/scripts/leadv2-dispatch-code.sh
@@ -6521,6 +6521,12 @@ cmd_resolve() {
       if [[ "${_lane_register_rc}" != "0" ]]; then
         if [[ "${_lane_register_rc}" == "3" ]]; then
           emit decision "dispatch_refused reason=lead_session_lane_cap task=${sig8} lead_session=${_lead_session_id}"
+          # LEAD-WORKER-CHANNEL-01: admission refusal is a lane-blocked
+          # event -- the lead already knows _lead_session_id right here
+          # (registration itself failed, so active.yaml has no row for
+          # ${sig8} yet to look it up from), so pass it explicitly rather
+          # than relying on the notifier's active.yaml fallback.
+          LEADV2_LEAD_SESSION_ID="${_lead_session_id}" "${SCRIPT_DIR}/leadv2-notify-lead.sh" "${sig8}" blocked "admission refused: lead_session_lane_cap (2 lanes already live for this lead)" >/dev/null 2>&1 || true
           exit 3
         fi
         emit decision "lane_state_register_failed task=${sig8} rc=${_lane_register_rc}"
diff --git a/plugins/leadv2/scripts/leadv2-inbox.sh b/plugins/leadv2/scripts/leadv2-inbox.sh
new file mode 100755
index 00000000..d2e5af6c
--- /dev/null
+++ b/plugins/leadv2/scripts/leadv2-inbox.sh
@@ -0,0 +1,197 @@
+#!/usr/bin/env bash
+# leadv2-inbox.sh — LEAD-WORKER-CHANNEL-01 durable, cross-repo lead inbox.
+#
+# A worker cannot reliably reach a lead via SendMessage (busy/dead/headless
+# model on the other end), so every lead-addressed event lands HERE first,
+# unconditionally, with no network and no model involved. SendMessage is an
+# optimisation layered on top by the caller (leadv2-notify-lead.sh) -- this
+# script never sends anything, it only durably records and durably drains.
+#
+# CROSS-REPO PLACEMENT (verified, not assumed): leadv2-state-path.sh
+# resolves a control-plane root that is PER-REPO (${base}/${repo-slug},
+# repo-slug = basename of the main repo toplevel, see its own header) --
+# that isolation is the entire point of LEAD-CONTROL-PLANE-01, so reusing
+# it verbatim (the way leadv2-bus.sh does for bus.jsonl) would put
+# persona-engine's events and leadv2's events in TWO DIFFERENT files, and a
+# lead draining from one repo would never see a worker's event from the
+# other. This inbox instead lives ONE LEVEL UP, at the shared base itself
+# (dirname of the per-repo root) -- the same physical disk location for
+# every repo on this machine, so a worker in ANY repo and a lead in ANY
+# repo resolve to the SAME lead-inbox.jsonl. See _lv2_inbox_dir below.
+#
+# Storage: one JSONL file, one row per event, appended and drained through
+# a python3 fcntl.flock(LOCK_EX) critical section -- the same primitive
+# leadv2-bus.sh uses and its test suite proves safe for concurrent writers
+# on darwin (BSD flock is a real advisory lock on APFS/HFS+).
+#
+# Usage:
+#   leadv2-inbox.sh append <lead-id> <repo> <task-id> <lane> <event> <text>
+#     Appends one durable row. Exits 0 on success, 1 if the write itself
+#     failed (e.g. unwritable inbox dir). This script reports failure
+#     honestly on its own exit code -- it is leadv2-notify-lead.sh's job
+#     (the caller) to never let that failure propagate into a lane's exit
+#     code, never this script's.
+#   leadv2-inbox.sh drain [--lead <id>]
+#     Prints unread rows for that lead, oldest-first, one rendered line
+#     each (never raw JSON -- the lead renders it straight into a status
+#     line without opening anything else), and atomically advances that
+#     lead's read-offset so a second drain call never re-prints the same
+#     row. Exits 0 with no output when nothing is unread. `--lead` defaults
+#     to the same resolution order leadv2-dispatch-code.sh uses to compute
+#     _lead_session_id.
+#
+# Env overrides (tests sandbox with these -- never the real ~/.claude
+# state root from a test):
+#   PROJECT_ROOT          - repo root (used only to derive the per-repo
+#                           root before taking its dirname; see below)
+#   LEADV2_LEAD_INBOX_DIR - full override of the inbox's directory. Tests
+#                           MUST set this to a throwaway dir; production
+#                           never sets it.
+
+set -uo pipefail
+
+SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
+PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
+
+_lv2_inbox_dir() {
+  if [[ -n "${LEADV2_LEAD_INBOX_DIR:-}" ]]; then
+    printf '%s' "${LEADV2_LEAD_INBOX_DIR}"
+    return 0
+  fi
+  local per_repo_root
+  per_repo_root="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link 2>/dev/null)" || per_repo_root=""
+  if [[ -n "$per_repo_root" ]]; then
+    dirname "$per_repo_root"
+  else
+    printf '%s/.claude/leadv2-state' "$HOME"
+  fi
+}
+
+LEADV2_DIR="$(_lv2_inbox_dir)"
+INBOX_FILE="${LEADV2_DIR}/lead-inbox.jsonl"
+INBOX_LOCK="${LEADV2_DIR}/.lead-inbox.lock"
+OFFSETS_DIR="${LEADV2_DIR}/.lead-inbox-offsets"
+
+usage() {
+  printf -- 'Usage:\n' >&2
+  printf -- '  leadv2-inbox.sh append <lead-id> <repo> <task-id> <lane> <event> <text>\n' >&2
+  printf -- '  leadv2-inbox.sh drain [--lead <id>]\n' >&2
+  exit 1
+}
+
+[[ $# -ge 1 ]] || usage
+CMD="$1"; shift
+
+case "$CMD" in
+  append)
+    [[ $# -eq 6 ]] || usage
+    LEAD_ID="$1"; REPO="$2"; TASK_ID="$3"; LANE="$4"; EVENT="$5"; TEXT="$6"
+    mkdir -p "$LEADV2_DIR" 2>/dev/null || { printf -- '[inbox] cannot create %s\n' "$LEADV2_DIR" >&2; exit 1; }
+    python3 - "$INBOX_FILE" "$INBOX_LOCK" "$LEAD_ID" "$REPO" "$TASK_ID" "$LANE" "$EVENT" "$TEXT" <<'PYEOF'
+import fcntl, json, os, sys, time
+
+inbox_file, inbox_lock, lead, repo, task_id, lane, event, text = sys.argv[1:9]
+
+line = json.dumps({
+    "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
+    "lead": lead,
+    "repo": repo,
+    "task_id": task_id,
+    "lane": lane,
+    "event": event,
+    "text": text,
+}, sort_keys=True)
+
+try:
+    lockf = open(inbox_lock, "a+")
+    try:
+        fcntl.flock(lockf, fcntl.LOCK_EX)
+        with open(inbox_file, "a", encoding="utf-8") as f:
+            f.write(line + "\n")
+            f.flush()
+            os.fsync(f.fileno())
+    finally:
+        fcntl.flock(lockf, fcntl.LOCK_UN)
+        lockf.close()
+except OSError as e:
+    sys.stderr.write("[inbox] append failed: %s\n" % e)
+    sys.exit(1)
+PYEOF
+    ;;
+
+  drain)
+    LEAD_ID="${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-${CLAUDE_SESSION_ID:-direct}}}"
+    while [[ $# -gt 0 ]]; do
+      case "$1" in
+        --lead) LEAD_ID="$2"; shift 2 ;;
+        *) usage ;;
+      esac
+    done
+    mkdir -p "$LEADV2_DIR" "$OFFSETS_DIR" 2>/dev/null || true
+    python3 - "$INBOX_FILE" "$INBOX_LOCK" "$OFFSETS_DIR" "$LEAD_ID" <<'PYEOF'
+import fcntl, json, os, sys
+
+inbox_file, inbox_lock, offsets_dir, lead = sys.argv[1:5]
+
+def read_lines():
+    if not os.path.exists(inbox_file):
+        return []
+    with open(inbox_file, encoding="utf-8") as f:
+        return [l for l in f.read().splitlines() if l.strip()]
+
+# Shared lock while reading the whole file -- appenders hold this SAME lock
+# exclusively, so a reader never observes a torn write.
+lockf = open(inbox_lock, "a+")
+fcntl.flock(lockf, fcntl.LOCK_SH)
+try:
+    lines = read_lines()
+finally:
+    fcntl.flock(lockf, fcntl.LOCK_UN)
+    lockf.close()
+
+# Offset is keyed by lead id ONLY (never by caller/pid): two concurrent
+# `drain` calls for the SAME lead must split the unread rows between them,
+# not both see the same ones. The exclusive flock below is what makes that
+# atomic -- the second caller only starts reading once the first has
+# advanced the offset and released the lock.
+os.makedirs(offsets_dir, exist_ok=True)
+offset_path = os.path.join(offsets_dir, lead)
+offset_lock_path = offset_path + ".lock"
+olockf = open(offset_lock_path, "a+")
+try:
+    fcntl.flock(olockf, fcntl.LOCK_EX)
+    try:
+        with open(offset_path, encoding="utf-8") as f:
+            start = int(f.read().strip() or "0")
+    except (FileNotFoundError, ValueError):
+        start = 0
+
+    out = []
+    for l in lines[start:]:
+        try:
+            ev = json.loads(l)
+        except Exception:
+            continue
+        if ev.get("lead") == lead:
+            out.append(ev)
+
+    tmp = offset_path + (".tmp.%d" % os.getpid())
+    with open(tmp, "w", encoding="utf-8") as f:
+        f.write(str(len(lines)))
+    os.replace(tmp, offset_path)
+finally:
+    fcntl.flock(olockf, fcntl.LOCK_UN)
+    olockf.close()
+
+for ev in out:
+    print("%s [%s/%s] lane=%s event=%s: %s" % (
+        ev.get("at", "?"), ev.get("repo", "?"), ev.get("task_id", "?"),
+        ev.get("lane", "?"), ev.get("event", "?"), ev.get("text", ""),
+    ))
+PYEOF
+    ;;
+
+  *)
+    usage
+    ;;
+esac
diff --git a/plugins/leadv2/scripts/leadv2-notify-lead.sh b/plugins/leadv2/scripts/leadv2-notify-lead.sh
new file mode 100755
index 00000000..960bc2e8
--- /dev/null
+++ b/plugins/leadv2/scripts/leadv2-notify-lead.sh
@@ -0,0 +1,95 @@
+#!/usr/bin/env bash
+# leadv2-notify-lead.sh — LEAD-WORKER-CHANNEL-01 the ONE worker->lead notifier.
+#
+# The design constraint that decides everything: bash cannot call
+# SendMessage, only a model can. So a design where delivery depends on the
+# message going out is a design that goes silent the moment a model is
+# busy, dead, or headless. Therefore the message is the fast path and the
+# durable row is the guaranteed path:
+#   1. append one row to leadv2-inbox.sh, unconditionally, no network, no
+#      model involved;
+#   2. print, on stdout, the one-line SendMessage payload a worker MODEL
+#      may choose to relay. Printing it is the WHOLE contract -- this
+#      script never calls SendMessage and never blocks on one.
+# A notifier that can fail a lane is worse than no notifier: every failure
+# below is swallowed and this script exits 0 regardless.
+#
+# Usage: leadv2-notify-lead.sh <task-id> <event> <one-line-text>
+#
+# Lead resolution, in order:
+#   1. $LEADV2_LEAD_SESSION_ID, if the caller already knows it (e.g. a
+#      dispatch-code.sh call site that computed _lead_session_id moments
+#      earlier for a lane whose registration was refused, so no row for
+#      this task-id exists yet in active.yaml to look up);
+#   2. active.yaml -- the SAME lane registry leadv2-dispatch-code.sh's
+#      lane_register() writes (schema: data['sessions'] rows keyed by
+#      task_id, each carrying lead_session_id), read at the SAME
+#      control-plane root leadv2-inbox.sh appends to (leadv2-state-path.sh
+#      --no-link active.yaml). This is the "lead's identity IS already
+#      captured" fact this task's brief points at.
+#   3. "unknown" -- row still written, exit 0 (rule 4: a lead unknown or
+#      unreachable never fails the caller's lane).
+#
+# Env overrides (tests sandbox with these):
+#   PROJECT_ROOT               - repo root
+#   LEADV2_LEAD_SESSION_ID      - explicit lead override (see step 1 above)
+#   LEADV2_ACTIVE_YAML_PATH     - explicit active.yaml path (test seam)
+#   LEADV2_LEAD_INBOX_DIR       - forwarded to leadv2-inbox.sh unchanged
+
+set -uo pipefail
+
+SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
+PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
+
+# Never fail the caller's lane, even over a usage mistake.
+if [[ $# -lt 3 ]]; then
+  printf -- 'Usage: leadv2-notify-lead.sh <task-id> <event> <one-line-text>\n' >&2
+  exit 0
+fi
+TASK_ID="$1"; EVENT="$2"; shift 2
+TEXT="$*"
+
+REPO="$(basename "${PROJECT_ROOT}")"
+LANE="${TASK_ID}"
+
+_resolve_lead() {
+  if [[ -n "${LEADV2_LEAD_SESSION_ID:-}" ]]; then
+    printf '%s' "${LEADV2_LEAD_SESSION_ID}"
+    return 0
+  fi
+  local active_yaml
+  active_yaml="${LEADV2_ACTIVE_YAML_PATH:-}"
+  if [[ -z "$active_yaml" ]]; then
+    active_yaml="$(PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/leadv2-state-path.sh" --no-link active.yaml 2>/dev/null)" || active_yaml=""
+  fi
+  [[ -n "$active_yaml" && -f "$active_yaml" ]] || { printf 'unknown'; return 0; }
+  python3 - "$active_yaml" "$TASK_ID" <<'PYEOF' 2>/dev/null
+import sys
+try:
+    import yaml
+except ImportError:
+    print("unknown"); sys.exit(0)
+path, task_id = sys.argv[1:3]
+try:
+    with open(path, encoding="utf-8") as f:
+        doc = yaml.safe_load(f) or {}
+except Exception:
+    print("unknown"); sys.exit(0)
+rows = doc.get("sessions") if isinstance(doc, dict) else []
+if not isinstance(rows, list):
+    rows = []
+found = "unknown"
+for row in rows:
+    if isinstance(row, dict) and row.get("task_id") == task_id:
+        found = row.get("lead_session_id") or "unknown"
+print(found)
+PYEOF
+}
+
+LEAD_ID="$(_resolve_lead)"
+[[ -n "$LEAD_ID" ]] || LEAD_ID="unknown"
+
+"${SCRIPT_DIR}/leadv2-inbox.sh" append "$LEAD_ID" "$REPO" "$TASK_ID" "$LANE" "$EVENT" "$TEXT" >/dev/null 2>&1 || true
+
+printf -- '[leadv2-notify] lead=%s task=%s event=%s: %s\n' "$LEAD_ID" "$TASK_ID" "$EVENT" "$TEXT"
+exit 0
diff --git a/plugins/leadv2/scripts/leadv2-review-run.sh b/plugins/leadv2/scripts/leadv2-review-run.sh
index 1d1b3597..a89778e7 100755
--- a/plugins/leadv2/scripts/leadv2-review-run.sh
+++ b/plugins/leadv2/scripts/leadv2-review-run.sh
@@ -1582,13 +1582,10 @@ if [[ -z "${verdict}" ]]; then
   exit 6
 fi
 
-# REVIEW-VERDICT-COUNTER-03: FINDINGS_*_TOTAL used to seed here from the
-# reviewer's self-declared REVIEW_FINDINGS: line (parse_review_verdict's
-# FINDINGS_CRITICAL/HIGH/MEDIUM/LOW globals). That is a DECLARED number with
-# no guaranteed relationship to the FINDING: lines actually unioned below --
-# they are derived from the union+dedup array (FINDINGS_JSON) once it exists,
-# a few dozen lines down, so the printed gate count and review-findings.json
-# can never disagree.
+FINDINGS_CRITICAL_TOTAL="${FINDINGS_CRITICAL}"
+FINDINGS_HIGH_TOTAL="${FINDINGS_HIGH}"
+FINDINGS_MEDIUM_TOTAL="${FINDINGS_MEDIUM}"
+FINDINGS_LOW_TOTAL="${FINDINGS_LOW}"
 
 # --- Step 6/7: synthesis — union FINDING: lines across ran_arms + hack-detect,
 # dedup by (file,line,severity,dimension), then verify each Critical/High on an
@@ -1628,9 +1625,8 @@ done
 SECURITY_CRITICAL="$(awk -F'\t' '$1 == "hackdetect" && $2 == "Critical" { n++ } END { print n + 0 }' "${FINDINGS_RAW}" 2>/dev/null)"
 SECURITY_HIGH="$(awk -F'\t' '$1 == "hackdetect" && $2 == "High" { n++ } END { print n + 0 }' "${FINDINGS_RAW}" 2>/dev/null)"
 if [[ "${SECURITY_CRITICAL}" -gt 0 || "${SECURITY_HIGH}" -gt 0 ]]; then
-  # No manual total bump here: hackdetect's own FINDING: lines are already
-  # unioned into FINDINGS_RAW/FINDINGS_DEDUP above and will be counted from
-  # FINDINGS_JSON below like every other arm's findings -- one array, one count.
+  FINDINGS_CRITICAL_TOTAL=$(( FINDINGS_CRITICAL_TOTAL + SECURITY_CRITICAL ))
+  FINDINGS_HIGH_TOTAL=$(( FINDINGS_HIGH_TOTAL + SECURITY_HIGH ))
   verdict="FAIL"
   emit decision "review_security_block task=${TASK} critical=${SECURITY_CRITICAL} high=${SECURITY_HIGH}"
 fi
@@ -1688,29 +1684,6 @@ FINDINGS_JSON="${HANDOFF}/review-findings.json"
 } > "${FINDINGS_JSON}.tmp"
 mv -f "${FINDINGS_JSON}.tmp" "${FINDINGS_JSON}"
 
-# REVIEW-VERDICT-COUNTER-03: the gate's printed severity counts must come from
-# the SAME findings array just written to review-findings.json, not from the
-# reviewer's self-declared REVIEW_FINDINGS: line and not from a second
-# hackdetect-only tally added on top of it. One array, one count, everywhere.
-FINDINGS_CRITICAL_TOTAL="$({ grep -oE '"severity":"Critical"' "${FINDINGS_JSON}" 2>/dev/null || :; } | wc -l | tr -d '[:space:]')"; FINDINGS_CRITICAL_TOTAL="${FINDINGS_CRITICAL_TOTAL:-0}"
-FINDINGS_HIGH_TOTAL="$({ grep -oE '"severity":"High"' "${FINDINGS_JSON}" 2>/dev/null || :; } | wc -l | tr -d '[:space:]')"; FINDINGS_HIGH_TOTAL="${FINDINGS_HIGH_TOTAL:-0}"
-FINDINGS_MEDIUM_TOTAL="$({ grep -oE '"severity":"Medium"' "${FINDINGS_JSON}" 2>/dev/null || :; } | wc -l | tr -d '[:space:]')"; FINDINGS_MEDIUM_TOTAL="${FINDINGS_MEDIUM_TOTAL:-0}"
-FINDINGS_LOW_TOTAL="$({ grep -oE '"severity":"Low"' "${FINDINGS_JSON}" 2>/dev/null || :; } | wc -l | tr -d '[:space:]')"; FINDINGS_LOW_TOTAL="${FINDINGS_LOW_TOTAL:-0}"
-
-# A FAIL verdict asserts Critical/High findings exist. If the union+dedup
-# array that just fed review-findings.json has none, the verdict and the
-# array disagree -- an impossible state, not a real fail. Print it honestly
-# as a blocked gate rather than a "fail: high=N" nobody can match against the
-# findings array (round-2 live incident: gate printed high=5 while
-# review-findings.json held an empty findings array).
-if [[ "${verdict}" == FAIL && "${FINDINGS_CRITICAL_TOTAL}" -eq 0 && "${FINDINGS_HIGH_TOTAL}" -eq 0 ]]; then
-  printf 'status: blocked\nreason: findings_lost\narms: %s\ndeclared_verdict: FAIL\nfindings_total: 0\n' \
-    "$(IFS=,; echo "${ran_arms[*]}")" > "${HANDOFF}/review-gate.md.tmp"
-  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
-  emit decision "review_gate task=${TASK} status=blocked reason=findings_lost declared_verdict=FAIL findings_total=0"
-  exit 6
-fi
-
 # Recompute _needs_verify/_verified_count outside the subshell the while-loop
 # ran in (pipes/process substitution create subshells; re-derive from the JSON
 # so the counts are accurate in THIS shell).
```

