#!/usr/bin/env bash
# test-dispatch-outcome-terminal-retry.sh — DEDUP-REFUSED-RETRY-01 regression.
#
# _dispatch_outcome_blocks (leadv2-dispatch-code.sh) used to decide a dead lane's fate from
# ONLY worker liveness + filesystem evidence -- it never consulted the terminal-state
# ledger (leadv2-dispatch-ledger.sh's dispatch-terminal-ledger.jsonl). A scope-gate refusal
# writes terminal=refused there BEFORE the worker's own process exits, but by the time the
# NEXT dispatch attempt re-checks the sig, liveness has already resolved to "dead" and the
# refused lane's own worktree/mission artifacts can still satisfy the evidence check --
# wrongly blocking a fresh re-dispatch of a row the ledger itself had already recorded as
# refused (docs/handoff/<task>/*, the treadmill this fix ends). This suite proves the new
# terminal-ledger-aware branch frees refused/dead rows, keeps landed rows blocking, keeps
# alive/unknown liveness fail-closed regardless of any terminal row, and leaves the
# pre-existing dead+evidence protection (no terminal row at all) byte-identical.
#
# Technique: identical to test-dispatch-checkpoint-commit-cutoff.sh -- source the REAL
# leadv2-dispatch-code.sh function bodies (never a hand-reimplemented copy) by truncating
# the shipped script just before its trailing `case "$1" in ...` dispatch block, sourced
# from a sibling temp file inside SCRIPTS_DIR (SCRIPT_DIR-relative `source` lines require
# this). _dispatch_terminal_ledger_state shells out to the REAL leadv2-dispatch-ledger.sh
# with LEADV2_DISPATCH_TERMINAL_LEDGER_FILE pointed at a per-case scratch ledger file we
# populate directly (same JSON shape dispatch_ledger_write_terminal itself writes) -- so
# this test exercises the real ledger reader, not a stub.
#
# Run: bash plugins/leadv2/scripts/tests/test-dispatch-outcome-terminal-retry.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_SH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
source "${SCRIPTS_DIR}/leadv2-temp.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

RUN_ID="dispatch-outcome-terminal-$$-$(date +%s 2>/dev/null || echo 0)"
TMPDIR_ROOT="$(lv2_mktemp_dir "${RUN_ID}")"
ROOT="${TMPDIR_ROOT}/repo"

FUNCS_SH="${SCRIPTS_DIR}/.test-dispatch-outcome-terminal-funcs.$$.sh"
cleanup() { rm -rf "${TMPDIR_ROOT}"; rm -f "${FUNCS_SH}"; }
trap cleanup EXIT

CUT_LINE="$(grep -n '^# .. dispatch ..*$' "${DISPATCH_SH}" | tail -1 | cut -d: -f1)"
[[ -z "${CUT_LINE}" ]] && CUT_LINE="$(grep -n 'dispatch ─' "${DISPATCH_SH}" | tail -1 | cut -d: -f1)"
if [[ -z "${CUT_LINE}" ]]; then
  echo "[TEST] SETUP FAILED: could not locate trailing dispatch-case marker in ${DISPATCH_SH}" >&2
  exit 1
fi
head -n "$((CUT_LINE - 1))" "${DISPATCH_SH}" > "${FUNCS_SH}"

mkdir -p "${ROOT}/.claude/ref"
( cd "${ROOT}" && git init -q && git config user.email t@e.com && git config user.name t \
  && printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' > .claude/ref/leadv2-routing.yaml \
  && : > seed && git add seed .claude/ref/leadv2-routing.yaml && git commit -qm seed )
lv2_assert_scratch_repo "${ROOT}"

# A definitely-dead pid: fork+immediately-reap a subshell, then re-check kill -0 fails.
# Pid reuse under load is a real (if rare) risk, so fall back to a high improbable pid if
# the reaped one somehow got recycled before the check.
_dead_pid() {
  local p
  ( exit 0 ) & p=$!
  wait "${p}" 2>/dev/null
  if kill -0 "${p}" 2>/dev/null; then p=999999; fi
  printf '%s' "${p}"
}
DEAD_PID="$(_dead_pid)"

# Runs the real _dispatch_outcome_blocks in a fresh subshell so each case starts clean.
# <sig8> <created_epoch> <arm> <handle> <term_ledger_file> -> prints rc on stdout
_run_outcome() {
  local sig8="$1" created="$2" arm="$3" handle="$4" termfile="$5"
  ( set -uo pipefail
    cd "${ROOT}" || exit 9
    CLAUDE_PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="${termfile}" \
    LEADV2_DISPATCH_CHECKPOINT_CUTOFF=0 \
    LEADV2_DISPATCH_EVIDENCE_ATTRIBUTION=1 \
    LEADV2_DISPATCH_TERMINAL_LEDGER=1 \
    bash -c '
      source "'"${FUNCS_SH}"'"
      _dispatch_outcome_blocks "'"${arm}"'" "'"${handle}"'" "'"${created}"'" "'"${sig8}"'"
      echo $?
    '
  )
}

_write_term_row() {  # <termfile> <sig8> <word>
  local f="$1" sig8="$2" word="$3"
  printf '{"ts":"2026-08-21T00:00:00Z","task_sig":"%s","founder_task_id":"t","task_id":"t","terminal":"%s","cause":"c","evidence":"","commit":"none","deliverable":"unknown","attempt":""}\n' \
    "${sig8}" "${word}" >> "${f}"
}

NOW="$(date +%s)"

# ── 1. terminal=refused row, dead liveness -> freed (rc1) ───────────────────────────
SIG1="11111111"
TERM1="${TMPDIR_ROOT}/term1.jsonl"
_write_term_row "${TERM1}" "${SIG1}" "refused"
rc1="$(_run_outcome "${SIG1}" "$((NOW - 100))" "sonnet" "${DEAD_PID}" "${TERM1}")"
if [[ "${rc1}" == "1" ]]; then ok "1: terminal=refused row frees a fresh dispatch (rc=1)"; else bad "1: expected rc=1, got '${rc1}'"; fi

# ── 2. terminal=dead row, dead liveness -> freed (rc1) ───────────────────────────────
SIG2="22222222"
TERM2="${TMPDIR_ROOT}/term2.jsonl"
_write_term_row "${TERM2}" "${SIG2}" "dead"
rc2="$(_run_outcome "${SIG2}" "$((NOW - 100))" "sonnet" "${DEAD_PID}" "${TERM2}")"
if [[ "${rc2}" == "1" ]]; then ok "2: terminal=dead row frees a fresh dispatch (rc=1)"; else bad "2: expected rc=1, got '${rc2}'"; fi

# ── 3. terminal=landed row, dead liveness -> still blocked (rc0) ────────────────────
SIG3="33333333"
TERM3="${TMPDIR_ROOT}/term3.jsonl"
_write_term_row "${TERM3}" "${SIG3}" "landed"
rc3="$(_run_outcome "${SIG3}" "$((NOW - 100))" "sonnet" "${DEAD_PID}" "${TERM3}")"
if [[ "${rc3}" == "0" ]]; then ok "3: terminal=landed row still blocks (rc=0)"; else bad "3: expected rc=0, got '${rc3}'"; fi

# ── 4. alive worker -> still blocked (rc0), even with a refused row present ─────────
SIG4="44444444"
TERM4="${TMPDIR_ROOT}/term4.jsonl"
_write_term_row "${TERM4}" "${SIG4}" "refused"
( sleep 30 ) & ALIVE_PID=$!
rc4="$(_run_outcome "${SIG4}" "$((NOW - 100))" "sonnet" "${ALIVE_PID}" "${TERM4}")"
kill "${ALIVE_PID}" 2>/dev/null; wait "${ALIVE_PID}" 2>/dev/null
if [[ "${rc4}" == "0" ]]; then ok "4: alive worker still blocks (rc=0) regardless of a refused terminal row"; else bad "4: expected rc=0, got '${rc4}'"; fi

# ── 5. unknown/unresolvable liveness -> still blocked (rc0, fail-closed), even with a
# refused row present ────────────────────────────────────────────────────────────────
SIG5="55555555"
TERM5="${TMPDIR_ROOT}/term5.jsonl"
_write_term_row "${TERM5}" "${SIG5}" "refused"
rc5="$(_run_outcome "${SIG5}" "$((NOW - 100))" "sonnet" "" "${TERM5}")"
if [[ "${rc5}" == "0" ]]; then ok "5: unknown liveness (empty handle) stays fail-closed (rc=0) despite a refused terminal row"; else bad "5: expected rc=0, got '${rc5}'"; fi

# ── 6. dead liveness + evidence present + NO terminal-state row -> still blocked (rc0)
# -- the pre-existing dead+evidence protection must be untouched.  ──────────────────
SIG6="66666666"
TERM6="${TMPDIR_ROOT}/term6-empty.jsonl"   # no row for SIG6 written -> file may not even exist
CREATED6=$((NOW - 100))
mkdir -p "${ROOT}/docs/handoff/dispatch-${SIG6}"
printf 'done\n' > "${ROOT}/docs/handoff/dispatch-${SIG6}/SUMMARY.md"
python3 -c "import os,sys; t=int(sys.argv[2])+10; os.utime(sys.argv[1], (t, t))" \
  "${ROOT}/docs/handoff/dispatch-${SIG6}/SUMMARY.md" "${CREATED6}"
rc6="$(_run_outcome "${SIG6}" "${CREATED6}" "sonnet" "${DEAD_PID}" "${TERM6}")"
if [[ "${rc6}" == "0" ]]; then ok "6: dead+evidence with no terminal row stays blocked (rc=0, pre-existing protection intact)"; else bad "6: expected rc=0, got '${rc6}'"; fi

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[[ ${FAIL} -eq 0 ]]
