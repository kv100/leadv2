#!/usr/bin/env bash
# tests/test-phase8-closes-the-backlog-row.sh — BACKLOG-ONLY-GROWS-CLOSING-IS-MANUAL-01
# run-all-triggers: leadv2-phase8-close
#
# Founder order 2026-09-04: a lane closing on a success outcome must remove its
# own backlog row. This suite proves the rule against the REAL
# leadv2-phase8-close.sh, end to end — the only thing faked is one level BELOW
# it: ${PROJECT_ROOT}/scripts/task-close.sh is an interceptor that records its
# arguments and exits 0 (or 7, for the non-blocking test). A suite that mocks
# what it checks proves nothing; this one fakes only the repo-native seam the
# plugin calls into.
#
# T1  dispatch path: journal binding dispatch_task_bound resolves
#     founder_task; the interceptor is called once with the row's shortid and
#     a --reason naming lane + founder task.
# T2  worktree path (the REAL dispatched shape): journal exists only in the
#     main checkout, close runs inside a linked git worktree — the binding
#     must be found via the git-common-dir root, and the row still closes.
# T3  interactive path: TASK_ID without the dispatch- prefix IS the founder
#     task (no journal consulted); row closes via intent-head match.
# T4  refused: outcome=refused never calls the interceptor, close still RC=0.
# T5  seam absent: no scripts/task-close.sh in the repo -> log_info skip,
#     close RC=0 (the plugin never requires a repo-native script).
# T6  ambiguous: TWO rows with the founder's intent-head -> NO call, logged.
# T7  zero matches: founder bound by journal but absent from tasks.yaml ->
#     NO call, logged.
# T8  non-blocking: interceptor exits 7 -> close STILL RC=0 with log_error.
# T9  no binding: dispatch- TASK_ID with no journal anywhere -> NO call, RC=0.
# T0  bash -n on the close script and on this suite.
#
# Negative controls (mutation, run via leadv2-mutation-control.sh) that MUST
# redden this suite:
#   (а) the task-close.sh invocation is neutralised      -> T1/T2/T3 red
#   (б) the success-outcome guard is forced always-true  -> T4 red
#   (в) the >=2 ambiguity guard takes the first hit      -> T6 red
#
# Run: bash plugins/leadv2/scripts/tests/test-phase8-closes-the-backlog-row.sh
# Exit 0 = all pass; non-zero = failures found.
set -uo pipefail
# zsh safety (same as test-phase8-e2e-gate-unknown.sh): BASH_SOURCE is absent
# under zsh; fall back to $0 when it names a real file.
_t9_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_t9_src" && -f "${0:-}" ]]; then _t9_src="$0"; fi
SCRIPT_DIR="$(cd "$(dirname "$_t9_src")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

CLOSE_SH="${SCRIPTS_ROOT}/leadv2-phase8-close.sh"
SIG="dispatch-TESTSIG01"
FOUNDER="FOUNDER-ALPHA-01"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir phase8-backlog-row-test)"
trap 'rm -rf "$TMP"' EXIT

# ── fixture builder ───────────────────────────────────────────────────────────
# _mkfx <variant> -> sets FX (fixture root), FX_CAP (interceptor capture path)
# Variants:
#   plain      dispatch row terminal + one founder row + decoy, journal bound
#   ambiguous  dispatch row terminal + TWO founder rows, journal bound
#   ghost      dispatch row terminal + decoy only, journal binds FOUNDER-GHOST-99
#   nobinding  dispatch row terminal + founder row, NO journal
#   nobin      plain, but scripts/task-close.sh absent
#   failbin    plain, but interceptor exits 7
#   interactive single founder row (terminal) — for the no-prefix TASK_ID path
_mkfx() {
  local variant="$1"
  local R; R="$(lv2_mktemp_dir p8c-fx)"
  git -C "$R" init -q
  git -C "$R" config user.email test@test.local
  git -C "$R" config user.name test
  mkdir -p "${R}/docs/leadv2/tasks/${SIG}" "${R}/scripts" "${R}/docs/handoff/${SIG}"
  printf 'history:\n' > "${R}/docs/LEAD_V2_STATE.md"
  # A4 keys on the CLOSING task id: dispatch-<sig> on the dispatched variants,
  # the founder name itself on the interactive variant.
  local fx_task="${SIG}"
  [[ "${variant}" == "interactive" ]] && fx_task="${FOUNDER}"
  cat > "${R}/docs/leadv2/reflect-history.yaml" <<RH
entries:
- task: ${fx_task}
  outcome: completed_success
RH

  case "${variant}" in
    plain|nobinding|nobin|failbin)
      cat > "${R}/docs/tasks.yaml" <<YAML
total_open: 2
tasks:
- id: ${SIG}
  status: closed
  intent: '${SIG}: fixture lane row (terminal for A2)'
- id: ab12cd34ef56
  status: queued
  intent: '${FOUNDER}: make the backlog row closable'
- id: ff9988776655
  status: queued
  intent: 'DECOY-ROW-02: never matches'
YAML
      ;;
    ambiguous)
      cat > "${R}/docs/tasks.yaml" <<YAML
total_open: 3
tasks:
- id: ${SIG}
  status: closed
  intent: '${SIG}: fixture lane row (terminal for A2)'
- id: aa1111111111
  status: queued
  intent: '${FOUNDER}: first duplicate row'
- id: bb2222222222
  status: queued
  intent: '${FOUNDER}: second duplicate row'
YAML
      ;;
    ghost)
      cat > "${R}/docs/tasks.yaml" <<YAML
total_open: 2
tasks:
- id: ${SIG}
  status: closed
  intent: '${SIG}: fixture lane row (terminal for A2)'
- id: ff9988776655
  status: queued
  intent: 'DECOY-ROW-02: never matches'
YAML
      ;;
    interactive)
      cat > "${R}/docs/tasks.yaml" <<YAML
total_open: 1
tasks:
- id: ab12cd34ef56
  status: verified_closed
  intent: '${FOUNDER}: make the backlog row closable'
YAML
      ;;
  esac

  if [[ "${variant}" != "nobin" ]]; then
    local cap="${R}/task-close-calls.txt"
    local rc_exit="exit 0"
    [[ "${variant}" == "failbin" ]] && rc_exit="exit 7"
    sed -e "s|@CAP@|${cap}|g" -e "s|@EXIT@|${rc_exit}|" > "${R}/scripts/task-close.sh" <<'STUB'
#!/usr/bin/env bash
# interceptor: record args, then exit @EXIT@
printf '%s\n' "$*" >> @CAP@
@EXIT@
STUB
    chmod +x "${R}/scripts/task-close.sh"
    : > "$cap"
    FX_CAP="$cap"
  else
    FX_CAP=""
  fi

  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${R}/fake-e2e.sh"
  chmod +x "${R}/fake-e2e.sh"
  # c1 adds exactly the files the linked worktree (T2) must inherit — the e2e
  # stub and the interceptor above all. c2 is a trivial no-yaml commit so the
  # close-time HEAD~1 diff never trips the docs/tasks.yaml mirror guard.
  printf 'A\n' > "${R}/A.txt"
  git -C "$R" add docs A.txt fake-e2e.sh scripts && git -C "$R" commit -q -m c1
  printf 'B\n' > "${R}/B.txt"
  git -C "$R" add B.txt && git -C "$R" commit -q -m c2
  # The journal is written AFTER the commits and left untracked: dispatch
  # journals live only in the dispatcher's checkout (the census fact T2 proves
  # the close survives that by falling back to the git-common-dir root).
  if [[ "${variant}" != "nobinding" ]]; then
    local bound="${FOUNDER}"
    [[ "${variant}" == "ghost" ]] && bound="FOUNDER-GHOST-99"
    cat > "${R}/docs/leadv2/tasks/${SIG}/journal.md" <<J
- 2026-09-04T10:00:00Z [decision] dispatch_classified task=TESTSIG01 class=Light
- 2026-09-04T10:00:01Z [decision] dispatch_task_bound task=TESTSIG01 founder_task=${bound}
J
  fi
  lv2_assert_scratch_repo "$R"
  FX="$R"
}

# ── close runner ──────────────────────────────────────────────────────────────
# _run_close <root> <task_id> <outcome> -> FX_RC (exit code), FX_LOG (output)
# HOME is deliberately NOT overridden: redirecting it removes python3's user-site
# pyyaml (ModuleNotFoundError, proven live). The real-home side effects of a full
# close are neutralised instead: CLAUDE_PROJECT_DIR is unset so the memory
# archiver's slug lookup misses, and the session-close advisory counter keyed on
# the suite's own pid is a benign log-only nudge.
_run_close() {
  local root="$1" task_id="$2" outcome="$3"
  FX_RC=0
  CLAUDE_PROJECT_ROOT="$root" LEADV2_PROJECT_ROOT="$root" \
  LEADV2_HANDOFF_DIR="${root}/docs/handoff" \
  LEADV2_E2E_CMD="bash ${root}/fake-e2e.sh" LEADV2_PHASE8_E2E_TIMEOUT_S=15 \
  LEADV2_E2E_OWNERSHIP=0 LEADV2_LANE_WORK_ROOT="$root" \
  LEADV2_SCORECARD_ON_CLOSE=0 \
  LEADV2_OUTCOME="$outcome" \
    env -u CLAUDE_PROJECT_DIR bash "$CLOSE_SH" "$task_id" \
    >"${root}/close.log" 2>&1 || FX_RC=$?
  FX_LOG="$(cat "${root}/close.log" 2>/dev/null || true)"
}

_calls() { # <cap-path>
  [[ -n "$1" && -f "$1" ]] || { printf '0'; return; }
  wc -l < "$1" | tr -d '[:space:]'
}

# ── T0: syntax ────────────────────────────────────────────────────────────────
if bash -n "$CLOSE_SH"; then pass "T0: bash -n clean (leadv2-phase8-close.sh)"; else fail "T0: bash -n failed (close)"; fi
if bash -n "${_t9_src}";   then pass "T0: bash -n clean (suite)";               else fail "T0: bash -n failed (suite)"; fi

# ── T1: dispatch path, journal binding -> one call with the right args ───────
_mkfx plain
_run_close "$FX" "$SIG" completed_success
_n="$(_calls "$FX_CAP")"; _line="$(tail -1 "$FX_CAP" 2>/dev/null || true)"
if [[ "${FX_RC}" -eq 0 && "$_n" == "1" ]] \
   && grep -q '^ab12cd34ef56 --reason ' <<<"$_line" \
   && grep -q "lane ${SIG}" <<<"$_line" \
   && grep -q "founder task ${FOUNDER}" <<<"$_line"; then
  pass "T1: dispatch close called task-close.sh once: <${_line}>"
else
  fail "T1: rc=${FX_RC} calls=${_n} line=<${_line}> logtail=<$(tail -6 <<<"$FX_LOG")>"
fi

# ── T2: worktree path — journal ONLY in main, close runs in the worktree ─────
_mkfx plain
WT="$(lv2_mktemp_dir p8c-wt)"; rmdir "$WT"
git -C "$FX" worktree add -q "$WT" -b p8c-wt-branch >/dev/null 2>&1
# the journal is untracked in main (see _mkfx) -> the worktree has no copy of it
_run_close "$WT" "$SIG" completed_success
_n="$(_calls "$FX_CAP")"
_common="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | xargs dirname 2>/dev/null || true)"
# macOS path-form: git resolves /var -> /private/var and mktemp can carry a
# double slash — canonicalize both sides before comparing (same lesson as
# test-leadv2-phase8-learn-counter.sh Test 7).
_common_real="$(cd "$_common" 2>/dev/null && pwd -P || printf '%s' "$_common")"
_fx_real="$(cd "$FX" 2>/dev/null && pwd -P || printf '%s' "$FX")"
if [[ "${FX_RC}" -eq 0 && "$_n" == "1" && -n "$_common" && "$_common_real" == "$_fx_real" ]] \
   && grep -q '^ab12cd34ef56 --reason ' <<<"$(tail -1 "$FX_CAP" 2>/dev/null)"; then
  pass "T2: close in linked worktree found the journal via git-common-dir root (${_common}) and closed the row"
else
  fail "T2: rc=${FX_RC} calls=${_n} common=<${_common}> (fx=${FX}) logtail=<$(tail -6 <<<"$FX_LOG")>"
fi
git -C "$FX" worktree remove --force "$WT" >/dev/null 2>&1 || true

# ── T3: interactive path — TASK_ID without dispatch- prefix ──────────────────
_mkfx interactive
_run_close "$FX" "$FOUNDER" completed_success
_n="$(_calls "$FX_CAP")"; _line="$(tail -1 "$FX_CAP" 2>/dev/null || true)"
if [[ "${FX_RC}" -eq 0 && "$_n" == "1" ]] \
   && grep -q '^ab12cd34ef56 --reason ' <<<"$_line" \
   && grep -q "founder task ${FOUNDER}" <<<"$_line"; then
  pass "T3: interactive close (TASK_ID=${FOUNDER}, no journal) closed the row by intent-head"
else
  fail "T3: rc=${FX_RC} calls=${_n} line=<${_line}> logtail=<$(tail -6 <<<"$FX_LOG")>"
fi

# ── T4: refused never closes the row ─────────────────────────────────────────
_mkfx plain
_run_close "$FX" "$SIG" refused
_n="$(_calls "$FX_CAP")"
if [[ "${FX_RC}" -eq 0 && "$_n" == "0" ]] \
   && grep -q 'not a success outcome' <<<"$FX_LOG"; then
  pass "T4: outcome=refused left the backlog row open (no call), close RC=0"
else
  fail "T4: rc=${FX_RC} calls=${_n} logtail=<$(tail -6 <<<"$FX_LOG")>"
fi

# ── T5: seam absent -> quiet skip ────────────────────────────────────────────
_mkfx nobin
_run_close "$FX" "$SIG" completed_success
if [[ "${FX_RC}" -eq 0 ]] && grep -q '\[backlog-row\].*not present/not executable' <<<"$FX_LOG"; then
  pass "T5: no scripts/task-close.sh in repo -> log_info skip, close RC=0"
else
  fail "T5: rc=${FX_RC} logtail=<$(tail -6 <<<"$FX_LOG")>"
fi

# ── T6: ambiguous (>=2 intent-head matches) closes NOTHING ───────────────────
_mkfx ambiguous
_run_close "$FX" "$SIG" completed_success
_n="$(_calls "$FX_CAP")"
if [[ "${FX_RC}" -eq 0 && "$_n" == "0" ]] \
   && grep -q 'ambiguous_backlog_row 2 rows resolve founder' <<<"$FX_LOG"; then
  pass "T6: two rows with intent-head ${FOUNDER} -> no call, logged, close RC=0"
else
  fail "T6: rc=${FX_RC} calls=${_n} logtail=<$(tail -6 <<<"$FX_LOG")>"
fi

# ── T7: zero matches closes NOTHING ──────────────────────────────────────────
_mkfx ghost
_run_close "$FX" "$SIG" completed_success
_n="$(_calls "$FX_CAP")"
if [[ "${FX_RC}" -eq 0 && "$_n" == "0" ]] \
   && grep -q 'no_backlog_row' <<<"$FX_LOG"; then
  pass "T7: founder bound but absent from tasks.yaml -> no call, logged, close RC=0"
else
  fail "T7: rc=${FX_RC} calls=${_n} logtail=<$(tail -6 <<<"$FX_LOG")>"
fi

# ── T8: interceptor failure is non-blocking ───────────────────────────────────
_mkfx failbin
_run_close "$FX" "$SIG" completed_success
_n="$(_calls "$FX_CAP")"
if [[ "${FX_RC}" -eq 0 && "$_n" == "1" ]] \
   && grep -q '\[backlog-row\] task-close.sh exited non-zero' <<<"$FX_LOG"; then
  pass "T8: task-close.sh exit 7 -> row-close logged as failed, lane close STILL RC=0"
else
  fail "T8: rc=${FX_RC} calls=${_n} logtail=<$(tail -6 <<<"$FX_LOG")>"
fi

# ── T9: dispatch TASK_ID with no journal anywhere ─────────────────────────────
_mkfx nobinding
_run_close "$FX" "$SIG" completed_success
_n="$(_calls "$FX_CAP")"
if [[ "${FX_RC}" -eq 0 && "$_n" == "0" ]] \
   && grep -q 'no_journal_binding' <<<"$FX_LOG"; then
  pass "T9: dispatch-* TASK_ID without a journal binding -> no call, logged, close RC=0"
else
  fail "T9: rc=${FX_RC} calls=${_n} logtail=<$(tail -6 <<<"$FX_LOG")>"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
