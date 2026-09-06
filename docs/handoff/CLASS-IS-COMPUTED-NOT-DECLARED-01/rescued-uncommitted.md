# CLASS-IS-COMPUTED-NOT-DECLARED-01 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/CLASS-IS-COMPUTED-NOT-DECLARED-01` on 2026-09-06 by the blocking filter of
LEADV2-WORKTREE-ADJUDICATION-01, **before** any verdict was written about the
branch. A lane's branch can be an empty anchor while the work sits untracked or
merely staged inside its checkout: `git log` never sees the index, and removing
the checkout would take both with it.

Text only — nothing here is installed or made executable. Restoring any of it is
a deliberate act by whoever owns the row.

## `git diff HEAD -- plugins tests` (staged and unstaged)

```diff
diff --git a/plugins/leadv2/scripts/leadv2-broad-status.sh b/plugins/leadv2/scripts/leadv2-broad-status.sh
index f8b4b10a..da550547 100755
--- a/plugins/leadv2/scripts/leadv2-broad-status.sh
+++ b/plugins/leadv2/scripts/leadv2-broad-status.sh
@@ -197,10 +197,35 @@ PY
 # below is computed AT BEAT TIME from active.yaml directly, independent of
 # whatever the collector/renderer failed to do, so the fallback always
 # carries real, current facts.
+# ── CLASS-IS-COMPUTED-NOT-DECLARED-01 item 3: any non-"ok" admission
+# class-floor verdict (a refusal or an escalation, written by
+# leadv2_admission_write_class_floor in lib/leadv2-admission-class.sh) is
+# founder-visible, never a quiet decision-log line only the lead can find.
+# Read-only, glob-bounded, never throws -- same degrade-gracefully contract
+# as _live_lane_facts above. <root> defaults to PROJECT_ROOT; overridable for
+# fixture testing.
+_class_floor_alerts() {
+  local root="${1:-$PROJECT_ROOT}" f sig8 fields out=""
+  for f in "${root}"/docs/handoff/dispatch-*/class-floor.yaml; do
+    [[ -f "$f" ]] || continue
+    sig8="$(basename "$(dirname "$f")")"
+    sig8="${sig8#dispatch-}"
+    fields="$(sed -n 's/^verdict:[[:space:]]*//p;s/^declared:[[:space:]]*//p;s/^computed:[[:space:]]*//p' "$f" 2>/dev/null | tr '\n' ' ')"
+    [[ -n "$fields" ]] || continue
+    out="${out}${out:+; }${sig8}: ${fields% }"
+  done
+  if [[ -z "$out" ]]; then
+    printf 'class-floor: none\n'
+  else
+    printf 'class-floor: %s\n' "$out"
+  fi
+}
+
 _write_degraded_status() {  # <reason> -> rc 0 if the artifact was replaced
-  local reason="$1" block lane_facts
+  local reason="$1" block lane_facts class_alerts
   lane_facts="$(_live_lane_facts)"
   [[ -z "$lane_facts" ]] && lane_facts="живые линии: недоступно"
+  class_alerts="$(_class_floor_alerts)"
   block="$(
     printf '%s [BROAD_STATUS] dispatched=%s degraded=1\n' "$BEAT_AT" "$DISPATCHED"
     printf '| Линия | Что делает | Состояние |\n'
@@ -209,6 +234,7 @@ _write_degraded_status() {  # <reason> -> rc 0 if the artifact was replaced
     printf 'СТАТУС НЕ СОБРАН на beat %s: %s.\n' "$BEAT_AT" "$reason"
     printf 'Таблица линий за этот beat недоступна — это НЕ значит, что линий нет.\n'
     printf '%s\n' "$lane_facts"
+    printf '%s\n' "$class_alerts"
     printf '[BROAD_STATUS_END]\n'
   )"
   printf '%s\n' "$block" >>"$LOG_FILE"
diff --git a/plugins/leadv2/scripts/leadv2-dispatch-code.sh b/plugins/leadv2/scripts/leadv2-dispatch-code.sh
index 411d622b..69704b57 100755
--- a/plugins/leadv2/scripts/leadv2-dispatch-code.sh
+++ b/plugins/leadv2/scripts/leadv2-dispatch-code.sh
@@ -3777,6 +3777,36 @@ _admission_classify() {
   return 0
 }
 
+# CLASS-IS-COMPUTED-NOT-DECLARED-01: a floor on task_class independent of the
+# TaskEstimate judge -- computed from the declared LANE_WRITES path set alone
+# (leadv2_admission_writes_gate, lib/leadv2-admission-class.sh). Called twice:
+# right after _admission_classify (whatever --writes/row declared LANE_WRITES
+# already) and again once the architect prepass's own LANE_WRITES: line fills
+# it in (the common product-dispatch case, where nothing is known this early).
+# Kill switch mirrors REQUIRE_PHASES/REQUIRE_LANE_WRITES: emergency rollback only.
+# _class_floor_check <sig8> <task_id> <task_class> <writes> -> 0 proceed, 3 refuse
+_class_floor_check() {
+  [[ "${LEADV2_REQUIRE_CLASS_FLOOR:-1}" == "1" ]] || return 0
+  local sig8="$1" ftid="${2:-dispatch-$1}" cls="$3" writes="${4:-}"
+  local pair rc=0 verdict declared computed signals
+  pair="$(leadv2_admission_writes_gate "${cls}" 1 "${writes}")" || rc=$?
+  IFS=$'\t' read -r verdict declared computed signals <<<"${pair}"
+  case "${verdict}" in
+    refused)
+      emit decision "class_floor_refused task=${sig8} declared=${declared} computed=${computed} ${signals}"
+      leadv2_admission_write_class_floor "${PROJECT_ROOT}" "${sig8}" "${ftid}" refused "${declared}" "${computed}" "${signals}" 2>/dev/null || true
+      log_err "dispatch refused: task-class ${declared} is below the class computed from LANE_WRITES (${computed}; ${signals})"
+      log_err "  remedy: dispatch with --task-class ${computed} (or higher), or drop --task-class to accept the computed class"
+      return 3
+      ;;
+    escalated)
+      emit decision "class_floor_escalated task=${sig8} declared=${declared} computed=${computed} ${signals}"
+      leadv2_admission_write_class_floor "${PROJECT_ROOT}" "${sig8}" "${ftid}" escalated "${declared}" "${computed}" "${signals}" 2>/dev/null || true
+      ;;
+  esac
+  return 0
+}
+
 # _phase_precondition_guard <sig8> <class> <writes> [waiver-args...] -> 0 proceed, 1 refuse
 # PHASES-ARE-THE-ONLY-PATH-01: sits at the same structural slot as _lane_writes_guard/
 # _acceptance_guard, after arg validation, before any spawn side effect and before
@@ -6463,6 +6493,7 @@ cmd_resolve() {
   # refuses class>=Standard without same-task pre-build phase records.
   _admission_classify "${mission}" "${sig}" "${sig8}" "${task_class}" "${task_class_flagged:-0}"
   task_class="${ADMISSION_CLASS}"
+  _class_floor_check "${sig8}" "${founder_task_id:-dispatch-${sig8}}" "${task_class}" "${lane_writes}" || exit 3
   # COMPLEXITY-ESTIMATOR-IS-OFF-01: unconditional -- every dispatch (not only
   # LEADV2_ROUTER_V2=1) now carries a complexity estimate into the live
   # arbiter descriptor below and the arm_resolved decision line.
@@ -6677,6 +6708,12 @@ cmd_resolve() {
       lane_writes="$(_prepass_writes "${sig8}")"
       [[ -n "${lane_writes}" ]] && emit decision "lane_writes task=${sig8} source=prepass writes=${lane_writes}"
     fi
+    # CLASS-IS-COMPUTED-NOT-DECLARED-01: re-check now that LANE_WRITES is fully
+    # known -- the phase-precondition guard already ran (above) against
+    # whatever task_class _admission_classify produced; this closes the gap
+    # where the architect prepass reveals a broader scope than the flag/
+    # estimate implied (the exact bypass the founder incident used).
+    _class_floor_check "${sig8}" "${founder_task_id:-dispatch-${sig8}}" "${task_class}" "${lane_writes}" || exit 3
     # The developer receives the independently-produced design -- but INLINE, and only
     # when one actually exists. Two failures on 2026-07-29 came from this line: it replaced
     # the mission with a bare pointer to a file that was empty (so the worker closed as a
diff --git a/plugins/leadv2/scripts/lib/leadv2-admission-class.sh b/plugins/leadv2/scripts/lib/leadv2-admission-class.sh
index 4fb6a759..bb465107 100644
--- a/plugins/leadv2/scripts/lib/leadv2-admission-class.sh
+++ b/plugins/leadv2/scripts/lib/leadv2-admission-class.sh
@@ -107,6 +107,194 @@ leadv2_admission_freepool_role() {  # <work_kind> -> stdout: review|implement|bu
   return 0
 }
 
+# ── LANE_WRITES-derived deterministic class floor (CLASS-IS-COMPUTED-NOT-
+# DECLARED-01) ────────────────────────────────────────────────────────────
+# A SECOND, independent floor alongside the TaskEstimate-based escalate-only
+# rule above. leadv2_admission_class (D1) escalates off an LLM judge's
+# TaskEstimate; this floor escalates off the declared LANE_WRITES path set
+# itself -- a signal the lead states in the mission/CLI, not a model call, so
+# it is deterministic and re-runnable from the recorded dispatch inputs
+# alone (no I/O beyond the CSV it is given).
+#
+# Unlike leadv2_admission_class's silent re-escalation, a downgrade attempt
+# here is REFUSED (rc 3) -- the incident this exists to close was a flag
+# proceeding at a lower class than the work warranted; a silent auto-
+# correction still lets the dispatch continue unexamined. See
+# docs/handoff/CLASS-IS-COMPUTED-NOT-DECLARED-01/brief.md items 1-2.
+
+# <repo-relative-path> -> stdout: the path itself if it hits a control-plane
+# signal, else empty. This repo IS its own production/safety/publish/payment
+# surface (it dispatches, gates and judges three live project repos) -- these
+# are the filename signals for "touches the mechanism that judges other work".
+_admission_control_plane_hit() {
+  case "$1" in
+    *dispatch*|*admission*|*gate*|*ledger*|*deploy*|*supervise*|*phase-record*|*phase-precondition*|*lane-guard*|*active-registry*|*suite-lock*|*review-run*|*verify*|*close*)
+      printf '%s\n' "$1" ;;
+  esac
+}
+
+# <writes-csv> -> stdout: matched control-plane paths, one per line (may be empty).
+leadv2_admission_control_plane_paths() {
+  local csv="${1:-}" old_ifs="$IFS" p
+  [[ -n "$csv" ]] || return 0
+  IFS=','
+  for p in $csv; do
+    p="$(_lv2_norm_write "$p")"
+    [[ -n "$p" ]] || continue
+    _admission_control_plane_hit "$p"
+  done
+  IFS="$old_ifs"
+  return 0
+}
+
+# <writes-csv> -> stdout: count of unique subsystems (first 2 path segments).
+leadv2_admission_writes_subsystems() {
+  local csv="${1:-}" old_ifs="$IFS" p keys=""
+  [[ -n "$csv" ]] || { printf '0\n'; return 0; }
+  IFS=','
+  for p in $csv; do
+    p="$(_lv2_norm_write "$p")"
+    [[ -n "$p" ]] || continue
+    keys="${keys}$(printf '%s' "$p" | awk -F/ '{ if (NF>=2) print $1"/"$2; else print $1 }')"$'\n'
+  done
+  IFS="$old_ifs"
+  printf '%s' "$keys" | sed '/^$/d' | sort -u | wc -l | tr -d ' '
+}
+
+# <writes-csv> -> stdout: Light|Standard|Heavy (deterministic; empty writes -> Light).
+leadv2_admission_writes_class() {
+  local csv="${1:-}" cp_n subs
+  [[ -n "$csv" ]] || { printf 'Light\n'; return 0; }
+  cp_n="$(leadv2_admission_control_plane_paths "$csv" | grep -c . 2>/dev/null || true)"
+  subs="$(leadv2_admission_writes_subsystems "$csv")"
+  cp_n="${cp_n:-0}"; subs="${subs:-0}"
+  if (( cp_n > 0 )) || (( subs >= 4 )); then
+    printf 'Heavy\n'
+  elif (( subs >= 2 )); then
+    printf 'Standard\n'
+  else
+    printf 'Light\n'
+  fi
+}
+
+# <writes-csv> -> stdout: human-readable signal summary for refusal/escalation messages.
+leadv2_admission_writes_signals() {
+  local csv="${1:-}" subs cp_list cp_csv
+  subs="$(leadv2_admission_writes_subsystems "$csv")"
+  cp_list="$(leadv2_admission_control_plane_paths "$csv")"
+  cp_csv="$(printf '%s' "$cp_list" | sed '/^$/d' | tr '\n' ',' | sed 's/,$//')"
+  printf 'subsystems=%s control_plane=%s\n' "${subs:-0}" "${cp_csv:-none}"
+}
+
+# <explicit-class> <flagged 0|1> <writes-csv> -> stdout "verdict<TAB>declared<TAB>computed<TAB>signals"
+# verdict: ok (no flag, or flag matches computed) | escalated (flag ABOVE
+# computed -- accepted, recorded) | refused (flag BELOW computed -- rc 3,
+# caller MUST NOT proceed). Never returns a nonzero rc other than 3 -- a
+# caller checking `(( rc == 3 ))` for "stop" cannot be fooled by an unrelated
+# failure silently reading as pass-through.
+leadv2_admission_writes_gate() {
+  local explicit="${1:-}" flagged="${2:-0}" csv="${3:-}"
+  local computed signals declared rank_d rank_c
+  computed="$(leadv2_admission_writes_class "$csv")"
+  signals="$(leadv2_admission_writes_signals "$csv")"
+  if [[ "$flagged" != "1" || -z "$explicit" ]]; then
+    printf 'ok\t%s\t%s\t%s\n' "$computed" "$computed" "$signals"
+    return 0
+  fi
+  declared="$(_lv2_class_canonical "$explicit")"
+  rank_d="$(_lv2_class_rank "$declared")"
+  rank_c="$(_lv2_class_rank "$computed")"
+  if (( rank_d < rank_c )); then
+    # leadv2_admission_writes_class never emits "Trivial" (mirrors D1's own
+    # map, which never emits it either) -- its floor bottoms out at Light. A
+    # declared Trivial on a genuinely Light writes set has nothing below
+    # Light to be refused AGAINST; treating that one combination as "ok"
+    # keeps Trivial reachable (acceptance #7) instead of permanently
+    # unreachable through this axis alone.
+    if [[ "$computed" == "Light" && "$declared" == "Trivial" ]]; then
+      printf 'ok\t%s\t%s\t%s\n' "$declared" "$computed" "$signals"
+      return 0
+    fi
+    printf 'refused\t%s\t%s\t%s\n' "$declared" "$computed" "$signals"
+    return 3
+  elif (( rank_d > rank_c )); then
+    printf 'escalated\t%s\t%s\t%s\n' "$declared" "$computed" "$signals"
+    return 0
+  else
+    printf 'ok\t%s\t%s\t%s\n' "$declared" "$computed" "$signals"
+    return 0
+  fi
+}
+
+leadv2_admission_class_floor_path() { printf '%s/docs/handoff/dispatch-%s/class-floor.yaml' "$1" "$2"; }
+
+# <root> <sig8> <task_id> <verdict> <declared> <computed> <signals> -> rc 0 written, 1 failed
+# Founder-visible record of a non-"ok" admission verdict (item 3: a surviving
+# classification event is never silent). Overwrites on each call -- one row
+# per dispatch sig8, latest verdict wins, same tmp+mv atomicity as the
+# admission receipt above.
+leadv2_admission_write_class_floor() {
+  local root="$1" sig8="$2" task_id="$3" verdict="$4" declared="$5" computed="$6" signals="$7"
+  local f dir tmp
+  f="$(leadv2_admission_class_floor_path "$root" "$sig8")"
+  dir="$(dirname "$f")"
+  mkdir -p "$dir" 2>/dev/null || return 1
+  tmp="${dir}/.class-floor.$$.tmp"
+  {
+    printf 'task_id: %s\n' "$task_id"
+    printf 'verdict: %s\n' "$verdict"
+    printf 'declared: %s\n' "$declared"
+    printf 'computed: %s\n' "$computed"
+    printf 'signals: %s\n' "$signals"
+    printf 'recorded_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
+  } > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
+  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
+  return 0
+}
+
+# <declared-class> <admission-computed-class> <actual-writes-csv> -> stdout
+# "declared<TAB>computed<TAB>actual<TAB>mismatch(0|1)"
+# The diff is unknowable at dispatch, so admission's computed class can be
+# honestly wrong; this recomputes the SAME deterministic function against
+# what the lane actually changed. mismatch=1 iff actual outranks declared --
+# a single mismatch is noise, a PATTERN across the ledger is the signal this
+# exists to surface (brief item 4).
+leadv2_admission_close_recompute() {
+  local declared="${1:-}" computed="${2:-}" actual_csv="${3:-}"
+  local actual rank_d rank_a mismatch
+  declared="$(_lv2_class_canonical "${declared:-Standard}")"
+  actual="$(leadv2_admission_writes_class "$actual_csv")"
+  rank_d="$(_lv2_class_rank "$declared")"
+  rank_a="$(_lv2_class_rank "$actual")"
+  mismatch=0
+  (( rank_a > rank_d )) && mismatch=1
+  printf '%s\t%s\t%s\t%s\n' "$declared" "${computed:-$declared}" "$actual" "$mismatch"
+}
+
+leadv2_admission_close_ledger_path() { printf '%s/docs/handoff/dispatch-%s/class-close.yaml' "$1" "$2"; }
+
+# <root> <sig8> <task_id> <declared> <computed> <actual> <mismatch 0|1> -> rc 0/1
+# Appends (never overwrites -- close fires once per lane) so a systematically
+# under-declared lead accumulates a visible trail across many closes, not
+# just the last one.
+leadv2_admission_write_close_ledger() {
+  local root="$1" sig8="$2" task_id="$3" declared="$4" computed="$5" actual="$6" mismatch="$7"
+  local f dir
+  f="$(leadv2_admission_close_ledger_path "$root" "$sig8")"
+  dir="$(dirname "$f")"
+  mkdir -p "$dir" 2>/dev/null || return 1
+  {
+    printf -- '---\n'
+    printf 'task_id: %s\n' "$task_id"
+    printf 'declared: %s\n' "$declared"
+    printf 'computed: %s\n' "$computed"
+    printf 'actual: %s\n' "$actual"
+    printf 'mismatch: %s\n' "$mismatch"
+    printf 'recorded_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
+  } >> "$f" 2>/dev/null || return 1
+  return 0
+}
+
 # ── admission receipt (D2) ───────────────────────────────────────────────────
 # Flat single-level YAML, same parse contract as leadv2-phase-record.sh's
 # records. Path: <root>/docs/handoff/dispatch-<sig8>/admission-receipt.yaml.
diff --git a/tests/run-all.sh b/tests/run-all.sh
index 2750a881..096beac5 100755
--- a/tests/run-all.sh
+++ b/tests/run-all.sh
@@ -194,7 +194,10 @@ leadv2-broad-status:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
 leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
 leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-complexity-routing.sh
 leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-complexity-routing.sh
-leadv2-router-v2:plugins/leadv2/scripts/tests/test-complexity-routing.sh"
+leadv2-router-v2:plugins/leadv2/scripts/tests/test-complexity-routing.sh
+leadv2-admission-class.sh:plugins/leadv2/scripts/tests/test-class-cannot-be-downgraded.sh
+leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-class-cannot-be-downgraded.sh
+leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-class-cannot-be-downgraded.sh"
 
 if [[ "${SCOPE}" == "all" ]]; then
   while IFS= read -r f; do add_suite "$f"; done < <(
```

## `plugins/leadv2/scripts/tests/test-class-cannot-be-downgraded.sh` (untracked, 9781 bytes)

```
#!/usr/bin/env bash
# test-class-cannot-be-downgraded.sh — CLASS-IS-COMPUTED-NOT-DECLARED-01
# coverage for lib/leadv2-admission-class.sh's LANE_WRITES-derived class
# floor: leadv2_admission_writes_class (deterministic compute),
# leadv2_admission_writes_gate (escalate-only, HARD REFUSE on downgrade),
# leadv2_admission_close_recompute (item 4), and the class-floor/close-ledger
# sidecar writers -- all against fixture inputs and a fixture root, never a
# real dispatch, never the real ledger.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../lib/leadv2-admission-class.sh"
# shellcheck disable=SC1091
source "$LIB"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

# ── acceptance #1: a write set spanning production/safety paths -> Standard+ ──
[[ "$(leadv2_admission_writes_class 'plugins/leadv2/scripts/leadv2-dispatch-code.sh,tests/run-all.sh')" == "Heavy" ]] \
  && pass "writes_class: control-plane touch -> Heavy (>= Standard)" || fail "control-plane class"
[[ "$(leadv2_admission_writes_class 'a/one/x,b/two/y,c/three/z,d/four/w')" == "Heavy" ]] \
  && pass "writes_class: 4 subsystems (no control-plane) -> Heavy" || fail "4-subsystems class"
[[ "$(leadv2_admission_writes_class 'plugins/foo/bar.sh,tests/baz.sh')" == "Standard" ]] \
  && pass "writes_class: 2 subsystems, no control-plane -> Standard" || fail "2-subsystems class"
[[ "$(leadv2_admission_writes_class 'docs/readme.md')" == "Light" ]] \
  && pass "writes_class: single non-control path -> Light" || fail "single-path class"
[[ "$(leadv2_admission_writes_class '')" == "Light" ]] \
  && pass "writes_class: empty writes -> Light" || fail "empty writes class"

# ── acceptance #2: --task-class light on a prod/safety write set -> REFUSED ──
pair="$(leadv2_admission_writes_gate light 1 'plugins/leadv2/scripts/leadv2-dispatch-code.sh,tests/run-all.sh')"; rc=$?
IFS=$'\t' read -r verdict declared computed signals <<<"${pair}"
[[ $rc -eq 3 && "$verdict" == "refused" ]] \
  && pass "gate: light flag on Heavy-computed writes -> refused rc=3" || fail "gate refuse rc: rc=$rc verdict=$verdict"
[[ "$declared" == "Light" && "$computed" == "Heavy" ]] \
  && pass "gate: refusal message names both classes" || fail "refusal classes: declared=$declared computed=$computed"
[[ "$signals" == *"subsystems="* && "$signals" == *"control_plane="* ]] \
  && pass "gate: refusal message names the signals" || fail "refusal signals: $signals"

# ── acceptance #3: --task-class heavy on a computed-light dispatch -> escalation ──
pair="$(leadv2_admission_writes_gate heavy 1 'docs/readme.md')"; rc=$?
IFS=$'\t' read -r verdict declared computed signals <<<"${pair}"
[[ $rc -eq 0 && "$verdict" == "escalated" && "$declared" == "Heavy" && "$computed" == "Light" ]] \
  && pass "gate: heavy flag on Light-computed writes -> accepted, escalated" || fail "gate escalate: rc=$rc verdict=$verdict d=$declared c=$computed"

# ── acceptance #4: no flag at all -> the computed class is used ──
pair="$(leadv2_admission_writes_gate '' 0 'plugins/foo/bar.sh,tests/baz.sh')"; rc=$?
IFS=$'\t' read -r verdict declared computed signals <<<"${pair}"
[[ $rc -eq 0 && "$verdict" == "ok" && "$declared" == "Standard" && "$computed" == "Standard" ]] \
  && pass "gate: no flag -> computed class (Standard) used" || fail "gate no-flag: rc=$rc verdict=$verdict d=$declared c=$computed"

# ── acceptance #5 / item 3: no quiet downgrade path was kept (see report.md) --
# instead, every refused/escalated verdict is recorded founder-visibly via the
# class-floor sidecar, which leadv2-broad-status.sh's _class_floor_alerts
# renders into the beat. Covered directly against the real broad-status.sh
# source below (not reimplemented).
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
leadv2_admission_write_class_floor "$TMP" "aaaaaaaa" "T-1" refused Light Heavy "subsystems=2 control_plane=x.sh"
rc=$?
[[ $rc -eq 0 && -f "$TMP/docs/handoff/dispatch-aaaaaaaa/class-floor.yaml" ]] \
  && pass "class-floor: refusal record written" || fail "class-floor write rc=$rc"
grep -q '^verdict: refused$' "$TMP/docs/handoff/dispatch-aaaaaaaa/class-floor.yaml" \
  && pass "class-floor: verdict field present" || fail "class-floor verdict field missing"

BROAD_STATUS_SRC="${SCRIPT_DIR}/../leadv2-broad-status.sh"
CFA_FN="$TMP/class-floor-alerts.fn.sh"
sed -n '/^_class_floor_alerts() {/,/^}/p' "$BROAD_STATUS_SRC" > "$CFA_FN"
[[ -s "$CFA_FN" ]] || fail "class-floor-alerts: could not extract _class_floor_alerts from broad-status.sh (drifted)"
(
  # shellcheck disable=SC1090
  source "$CFA_FN"
  out="$(_class_floor_alerts "$TMP")"
  [[ "$out" == *"aaaaaaaa"* && "$out" == *"refused"* ]] && exit 0 || exit 1
)
[[ $? -eq 0 ]] && pass "status: refusal is rendered by _class_floor_alerts (founder-visible)" \
  || fail "status: refusal NOT rendered"
(
  # shellcheck disable=SC1090
  source "$CFA_FN"
  out="$(_class_floor_alerts "$(mktemp -d)")"
  [[ "$out" == "class-floor: none" ]] && exit 0 || exit 1
)
[[ $? -eq 0 ]] && pass "status: no class-floor records -> 'class-floor: none'" \
  || fail "status: empty-root rendering wrong"

# ── acceptance #6: close-time recompute records declared/computed/actual ──
pair="$(leadv2_admission_close_recompute Light Light 'plugins/leadv2/scripts/leadv2-dispatch-code.sh,tests/run-all.sh')"
IFS=$'\t' read -r c_declared c_computed c_actual c_mismatch <<<"${pair}"
[[ "$c_declared" == "Light" && "$c_computed" == "Light" && "$c_actual" == "Heavy" && "$c_mismatch" == "1" ]] \
  && pass "close: actual outranks declared -> mismatch=1" || fail "close recompute mismatch: $pair"
pair="$(leadv2_admission_close_recompute Heavy Heavy 'docs/readme.md')"
IFS=$'\t' read -r c_declared c_computed c_actual c_mismatch <<<"${pair}"
[[ "$c_mismatch" == "0" ]] && pass "close: actual does not outrank declared -> mismatch=0" || fail "close no-mismatch: $pair"

LEDGER_TMP="$(mktemp -d)"
leadv2_admission_write_close_ledger "$LEDGER_TMP" "bbbbbbbb" "T-2" Light Light Heavy 1
rc=$?
LEDGER_FILE="$LEDGER_TMP/docs/handoff/dispatch-bbbbbbbb/class-close.yaml"
[[ $rc -eq 0 && -f "$LEDGER_FILE" ]] && pass "close ledger: fixture row written" || fail "close ledger write rc=$rc"
grep -q '^mismatch: 1$' "$LEDGER_FILE" && pass "close ledger: mismatch visible in the fixture ledger" \
  || fail "close ledger: mismatch not visible"
# never overwritten -- close fires once per lane, a second close appends a new row
leadv2_admission_write_close_ledger "$LEDGER_TMP" "bbbbbbbb" "T-2" Standard Standard Standard 0
[[ "$(grep -c '^task_id: T-2$' "$LEDGER_FILE")" -eq 2 ]] \
  && pass "close ledger: appends (accumulates a trail), never overwrites" || fail "close ledger overwrote"
rm -rf "$LEDGER_TMP"

# ── acceptance #7: the honest path stays open for every class this axis emits ──
pair="$(leadv2_admission_writes_gate Light 1 'docs/readme.md')"
[[ "$pair" == ok* ]] && pass "honest path: Light on Light-computed writes -> ok" || fail "honest Light: $pair"
pair="$(leadv2_admission_writes_gate Standard 1 'plugins/foo/bar.sh,tests/baz.sh')"
[[ "$pair" == ok* ]] && pass "honest path: Standard on Standard-computed writes -> ok" || fail "honest Standard: $pair"
pair="$(leadv2_admission_writes_gate Heavy 1 'plugins/leadv2/scripts/leadv2-dispatch-code.sh')"
[[ "$pair" == ok* ]] && pass "honest path: Heavy on Heavy-computed writes -> ok" || fail "honest Heavy: $pair"
pair="$(leadv2_admission_writes_gate Strategic 1 'plugins/leadv2/scripts/leadv2-dispatch-code.sh')"
[[ "$pair" == escalated* ]] && pass "honest path: Strategic is always reachable (never refused)" || fail "honest Strategic: $pair"
# Trivial: writes_class never emits it (mirrors D1's own map) -- a genuinely
# light dispatch declaring --task-class trivial must not be permanently
# unreachable through this axis (see the Light/Trivial special-case in the gate).
pair="$(leadv2_admission_writes_gate Trivial 1 'docs/readme.md')"
[[ "$pair" == ok* ]] && pass "honest path: Trivial on Light-computed writes -> ok (not refused)" || fail "honest Trivial: $pair"

# ── Rules: mutation INSIDE the production body on the real call path ──────────
# Negative control: the refusal branch (`printf 'refused\t...'; return 3`) is
# what makes the downgrade cheat mechanically unavailable. Flip it to silently
# fall through to "ok" on a temp copy of the real lib and assert this suite's
# OWN acceptance-#2 assertion above would then go red.
MUT_LIB="$TMP/leadv2-admission-class.mut.sh"
cp "${SCRIPT_DIR}/../lib/leadv2-lane-guard.sh" "$TMP/leadv2-lane-guard.sh"
python3 - "$LIB" "$MUT_LIB" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
old = "    printf 'refused\\t%s\\t%s\\t%s\\n' \"$declared\" \"$computed\" \"$signals\"\n    return 3\n"
new = "    printf 'ok\\t%s\\t%s\\t%s\\n' \"$declared\" \"$computed\" \"$signals\"\n    return 0\n"
if old not in text:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYEOF
mut_status=$?
if [[ $mut_status -ne 0 ]]; then
  fail "control: refusal mutation source pattern not found (lib drifted, update mutation)"
else
  (
    # shellcheck disable=SC1090
    source "$MUT_LIB"
    pair2="$(leadv2_admission_writes_gate light 1 'plugins/leadv2/scripts/leadv2-dispatch-code.sh,tests/run-all.sh')"
    rc2=$?
    [[ $rc2 -eq 3 && "$pair2" == refused* ]] && exit 0 || exit 1
  )
  mut_rc=$?
  [[ $mut_rc -ne 0 ]] && pass "control: mutated lib lets a downgrade through -> caught (would be red)" \
    || fail "control: mutation NOT caught — the downgrade refusal is not actually tested"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
```

