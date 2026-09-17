#!/usr/bin/env bash
# tests/test-close-blocks-on-red-acceptance.sh — A-LANE-LANDED-ITSELF-WITH-A-RED-ACCEPTANCE-01.
#
# Invariant: a close may not reach `landed` while the acceptance command the lane
# was dispatched with exits non-zero — and an acceptance that yields NO verdict is
# its own refusal, never a pass. Live defect (row 55de339ac133 / sig c4776136):
# the probe was walked as the close's LAST statement, after the T11 merge and the
# write-once landed row, so its rc=1 was dedup-refused (terminal_already_recorded)
# and `|| true` ate the exit — a red acceptance landed.
#
# Cases (each drives the REAL leadv2-dispatch-product-close.sh end to end):
#   1 — red probe (exit 3)        -> close rc!=0, NO landed row, NOT merged,
#                                    decision live_verify status=fail rc=3,
#                                    ledger dead row cause=live_verify_fail.
#   2 — green probe (exit 0)      -> close rc=0, landed row, lane branch merged
#                                    to main (a green acceptance still lands).
#   3 — whitespace-only probe     -> refused acceptance_could_not_run, no landed.
#   4 — probe ran, no exit code
#       (live-verify.out is a dir -> redirect impossible) -> refused
#                                    acceptance_no_exit_code, no landed.
#   5 — probe declared, phase
#       store unusable            -> refused acceptance_declared_not_run, no
#                                    landed (the old order silently skipped).
#   6 — no probe declared         -> n/a stays legal: close still lands (a
#                                    probe-less lane keeps landing; the guard is
#                                    not a blanket fail-closed).
#   7 — review-engine path
#       (LEADV2_REVIEW_ENGINE=1, stubbed engine bin): red probe -> refused
#       BEFORE the landed stamp; green probe -> landed row written.
#
# Hermetic: sandboxed HOME/TMPDIR/LEADV2_STATE_ROOT; the terminal ledger routes
# to a scratch file; no reviewer/provider is ever contacted (resolver + review
# stubs). Run: bash scripts/tests/test-close-blocks-on-red-acceptance.sh
# Exit 0 = all pass; non-zero = failures found.
# run-all-triggers: leadv2-dispatch-product-close leadv2-dispatch-ledger leadv2-lane-worktree

set -uo pipefail

export LEADV2_BURN_GOVERNOR=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_LIVE="$(cd "${TESTS_DIR}/.." && pwd)"

ORIG_HOME="${HOME}"
if [[ -z "${RACC_SANDBOXED:-}" ]]; then
  SANDBOX_HOME="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-racc-home.XXXXXX")"
  mkdir -p "${SANDBOX_HOME}/tmp"
  export HOME="${SANDBOX_HOME}" TMPDIR="${SANDBOX_HOME}/tmp" RACC_SANDBOXED=1
fi
if [[ -z "${LEADV2_STATE_ROOT:-}" ]]; then
  export LEADV2_STATE_ROOT="${TMPDIR:-/tmp}/racc-state"
  mkdir -p "${LEADV2_STATE_ROOT}"
fi

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# new_scenario <probe_rc|skip> [phase_record_bin] -> prints
#   root<TAB>wt<TAB>d<TAB>errf<TAB>ledger<TAB>close_rc
# Builds a scratch repo, a lane worktree with one commit on its branch, the
# dispatch handoff dir with the declared acceptance probe, review resolver and
# review-pass stubs, then runs the REAL close through the inline landing funnel.
new_scenario() { # <probe_rc|"none"|"ws"|"lvdir"> [phase_record_bin] [engine_bin]
  local probe="$1" prb="${2:-}" eng="${3:-}"
  local root wt d errf ledger tid
  root="$(mktemp -d "${TMPDIR:-/tmp}/racc-repo.XXXXXX")"
  ( cd "${root}" && git init -q -b main && git config user.email t@t && git config user.name t \
    && mkdir -p agent && printf 'seed\n' > agent/seed.py && git add -A && git commit -qm seed ) >/dev/null 2>&1
  tid="racc-$$-${RANDOM}"
  LEADV2_PROJECT_ROOT="${root}" bash "${SCRIPTS_LIVE}/leadv2-lane-worktree.sh" ensure "${tid}" standard >/dev/null 2>&1
  wt="${root}/.claude/worktrees/${tid}"
  [[ -d "${wt}" ]] || { printf 'worktree missing\n' >&2; return 2; }
  ( cd "${wt}" && printf '# lane work\n' >> agent/seed.py && git add -A && git commit -qm "lane work ${tid}" ) >/dev/null 2>&1
  d="$(mktemp -d "${TMPDIR:-/tmp}/racc-d.XXXXXX")"; errf="${d}/err.txt"; ledger="${d}/ledger.jsonl"
  cat > "${d}/resolver.py" <<'PYEOF'
#!/usr/bin/env python3
print("reviewer=codex")
print("pool=codex")
print("refusal=")
PYEOF
  chmod +x "${d}/resolver.py"
  printf '#!/usr/bin/env bash\nprintf "REVIEW_VERDICT: PASS\\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\\n"\nexit 0\n' > "${d}/codex.sh"
  chmod +x "${d}/codex.sh"
  mkdir -p "${root}/docs/handoff/dispatch-raccsig"
  case "${probe}" in
    none) : ;;
    ws)   printf '   \n\t\n' > "${root}/docs/handoff/dispatch-raccsig/lane-acceptance-cmd" ;;
    lvdir) printf 'true\n' > "${root}/docs/handoff/dispatch-raccsig/lane-acceptance-cmd"
           mkdir -p "${root}/docs/handoff/dispatch-raccsig/live-verify.out" ;;
    *)    printf 'true; exit %s\n' "${probe}" > "${root}/docs/handoff/dispatch-raccsig/lane-acceptance-cmd" ;;
  esac
  local prb_args=() eng_args=()
  [[ -n "${prb}" ]] && prb_args=(LEADV2_PHASE_RECORD_BIN="${prb}")
  [[ -n "${eng}" ]] && eng_args=(LEADV2_REVIEW_ENGINE=1 LEADV2_REVIEW_RUN_BIN="${eng}")
  env "${prb_args[@]}" "${eng_args[@]}" \
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}" \
  LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
  LEADV2_DISPATCH_TERMINAL_LEDGER=1 \
  LEADV2_DISPATCH_LEDGER_BIN="${SCRIPTS_LIVE}/leadv2-dispatch-ledger.sh" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="${ledger}" \
  LEADV2_JOURNAL_BIN=/bin/true LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
  LEADV2_LANE_WORK_ROOT="${wt}" LEADV2_REVIEW_DIFF_CROSS_REPO=0 \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${SCRIPTS_LIVE}/leadv2-dispatch-product-close.sh" "${root}" raccsig sonnet "" 0 1 racc-founder \
    >"${d}/out.txt" 2>"${errf}"
  local rc=$?
  printf '%s\t%s\t%s\t%s\t%s\t%s' "${root}" "${wt}" "${d}" "${errf}" "${ledger}" "${rc}"
}

cleanup_scenario() { # <root> <scratch_dir>
  rm -rf "$1" "$2"
}

# ── Case 1 — red acceptance blocks the landing ────────────────────────────────
case_1_red_refused() {
  local out root wt d errf ledger rc landed merged lv cause ok=0
  out="$(new_scenario 3)" || return 2
  IFS=$'\t' read -r root wt d errf ledger rc <<<"${out}"
  grep -q '"terminal":"landed"' "${ledger}" 2>/dev/null && { fail "c1: landed row present"; ok=1; }
  git -C "${root}" merge-base --is-ancestor "$(git -C "${wt}" symbolic-ref --short HEAD 2>/dev/null)" main 2>/dev/null \
    && { fail "c1: lane branch merged into main"; ok=1; }
  [[ "${rc}" -ne 0 ]] || { fail "c1: close exited 0 on a red probe"; ok=1; }
  lv="$(grep -E 'live_verify task=raccsig status=fail rc=3' "${errf}" 2>/dev/null | tail -1)"
  [[ -n "${lv}" ]] || { fail "c1: no live_verify status=fail rc=3 decision line"; ok=1; }
  cause="$(grep -o '"cause":"live_verify_fail"' "${ledger}" 2>/dev/null | head -1)"
  [[ "${cause}" == '"cause":"live_verify_fail"' ]] || { fail "c1: ledger row cause is not live_verify_fail"; ok=1; }
  cleanup_scenario "${root}" "${d}"
  (( ok == 0 )) && pass "c1: red acceptance (rc 3) refuses the close: no landed, no merge, rc!=0"
  return "${ok}"
}

# ── Case 2 — a green acceptance still lands (mission control 2) ───────────────
case_2_green_lands() {
  local out root wt d errf ledger rc landed merged ok=0 branch
  out="$(new_scenario 0)" || return 2
  IFS=$'\t' read -r root wt d errf ledger rc <<<"${out}"
  grep -q '"terminal":"landed"' "${ledger}" 2>/dev/null || { fail "c2: landed row missing"; ok=1; }
  branch="$(git -C "${wt}" symbolic-ref --short HEAD 2>/dev/null)"
  git -C "${root}" merge-base --is-ancestor "${branch}" main 2>/dev/null || { fail "c2: branch not merged"; ok=1; }
  [[ "${rc}" -eq 0 ]] || { fail "c2: close rc=${rc} on a green probe"; ok=1; }
  cleanup_scenario "${root}" "${d}"
  (( ok == 0 )) && pass "c2: green acceptance still lands: landed row + merge + rc=0"
  return "${ok}"
}

# ── Case 3 — whitespace-only probe: acceptance_could_not_run ──────────────────
case_3_empty_probe() {
  local out root wt d errf ledger rc lv ok=0
  out="$(new_scenario ws)" || return 2
  IFS=$'\t' read -r root wt d errf ledger rc <<<"${out}"
  grep -q '"terminal":"landed"' "${ledger}" 2>/dev/null && { fail "c3: landed row present"; ok=1; }
  [[ "${rc}" -ne 0 ]] || { fail "c3: close exited 0"; ok=1; }
  lv="$(grep -E 'status=refused reason=acceptance_could_not_run' "${errf}" 2>/dev/null | tail -1)"
  [[ -n "${lv}" ]] || { fail "c3: no acceptance_could_not_run refusal"; ok=1; }
  cleanup_scenario "${root}" "${d}"
  (( ok == 0 )) && pass "c3: whitespace probe refuses as acceptance_could_not_run, no landed"
  return "${ok}"
}

# ── Case 4 — probe ran, no exit code: acceptance_no_exit_code ─────────────────
case_4_no_exit_code() {
  local out root wt d errf ledger rc lv ok=0
  out="$(new_scenario lvdir)" || return 2
  IFS=$'\t' read -r root wt d errf ledger rc <<<"${out}"
  grep -q '"terminal":"landed"' "${ledger}" 2>/dev/null && { fail "c4: landed row present"; ok=1; }
  [[ "${rc}" -ne 0 ]] || { fail "c4: close exited 0"; ok=1; }
  lv="$(grep -E 'status=refused reason=acceptance_no_exit_code' "${errf}" 2>/dev/null | tail -1)"
  [[ -n "${lv}" ]] || { fail "c4: no acceptance_no_exit_code refusal"; ok=1; }
  cleanup_scenario "${root}" "${d}"
  (( ok == 0 )) && pass "c4: missing probe_rc refuses as acceptance_no_exit_code, no landed"
  return "${ok}"
}

# ── Case 5 — probe declared, phase store unusable: acceptance_declared_not_run ─
case_5_declared_not_run() {
  local out root wt d errf ledger rc lv ok=0
  out="$(new_scenario 0 /nonexistent/racc-phase-record-$$)" || return 2
  IFS=$'\t' read -r root wt d errf ledger rc <<<"${out}"
  grep -q '"terminal":"landed"' "${ledger}" 2>/dev/null && { fail "c5: landed row present"; ok=1; }
  [[ "${rc}" -ne 0 ]] || { fail "c5: close exited 0"; ok=1; }
  lv="$(grep -E 'status=refused reason=acceptance_declared_not_run' "${errf}" 2>/dev/null | tail -1)"
  [[ -n "${lv}" ]] || { fail "c5: no acceptance_declared_not_run refusal"; ok=1; }
  cleanup_scenario "${root}" "${d}"
  (( ok == 0 )) && pass "c5: declared probe + unusable phase store refuses as acceptance_declared_not_run"
  return "${ok}"
}

# ── Case 6 — no probe declared: n/a stays legal, lane still lands ─────────────
case_6_no_probe_lands() {
  local out root wt d errf ledger rc branch ok=0
  out="$(new_scenario none)" || return 2
  IFS=$'\t' read -r root wt d errf ledger rc <<<"${out}"
  grep -q '"terminal":"landed"' "${ledger}" 2>/dev/null || { fail "c6: landed row missing"; ok=1; }
  branch="$(git -C "${wt}" symbolic-ref --short HEAD 2>/dev/null)"
  git -C "${root}" merge-base --is-ancestor "${branch}" main 2>/dev/null || { fail "c6: branch not merged"; ok=1; }
  cleanup_scenario "${root}" "${d}"
  (( ok == 0 )) && pass "c6: probe-less lane still lands (n/a legal — nothing was promised)"
  return "${ok}"
}

# ── Case 7 — review-engine path: gate sits BEFORE the landed stamp ────────────
case_7_engine_path() {
  local eng out root wt d errf ledger rc ok=0
  eng="$(mktemp "${TMPDIR:-/tmp}/racc-eng.XXXXXX")"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${eng}"; chmod +x "${eng}"
  out="$(new_scenario 3 "" "${eng}")" || { rm -f "${eng}"; return 2; }
  IFS=$'\t' read -r root wt d errf ledger rc <<<"${out}"
  grep -q '"terminal":"landed"' "${ledger}" 2>/dev/null && { fail "c7: engine landed on a red probe"; ok=1; }
  [[ "${rc}" -ne 0 ]] || { fail "c7: engine close exited 0 on a red probe"; ok=1; }
  grep -qE 'live_verify task=raccsig status=fail rc=3' "${errf}" 2>/dev/null \
    || { fail "c7: no red-probe decision line on engine path"; ok=1; }
  cleanup_scenario "${root}" "${d}"
  out="$(new_scenario 0 "" "${eng}")" || { rm -f "${eng}"; return 2; }
  IFS=$'\t' read -r root wt d errf ledger rc <<<"${out}"
  grep -q '"terminal":"landed"' "${ledger}" 2>/dev/null || { fail "c7: engine green probe did not land"; ok=1; }
  [[ "${rc}" -eq 0 ]] || { fail "c7: engine close rc=${rc} on a green probe"; ok=1; }
  cleanup_scenario "${root}" "${d}"; rm -f "${eng}"
  (( ok == 0 )) && pass "c7: engine path gates the probe before the landed stamp (red refuses, green lands)"
  return "${ok}"
}

case_1_red_refused;      [[ $? -eq 2 ]] && fail "c1: scenario setup error" || true
case_2_green_lands;      [[ $? -eq 2 ]] && fail "c2: scenario setup error" || true
case_3_empty_probe;      [[ $? -eq 2 ]] && fail "c3: scenario setup error" || true
case_4_no_exit_code;     [[ $? -eq 2 ]] && fail "c4: scenario setup error" || true
case_5_declared_not_run; [[ $? -eq 2 ]] && fail "c5: scenario setup error" || true
case_6_no_probe_lands;   [[ $? -eq 2 ]] && fail "c6: scenario setup error" || true
case_7_engine_path;      [[ $? -eq 2 ]] && fail "c7: scenario setup error" || true

log "─────────────────────────────────────────"
log "pass=${PASS} fail=${FAIL} of $((PASS + FAIL)) — close-blocks-on-red-acceptance"
(( ${#ERRORS[@]} )) && printf '%s\n' "${ERRORS[@]}"
(( FAIL == 0 ))
