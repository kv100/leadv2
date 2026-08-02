#!/usr/bin/env bash
# leadv2-phase8-e2e-gate.sh — E2E-INTO-DEV-LOOP-01
# Runs tests/run-all.sh --scope changed for <task_id> and writes the sentinel
# leadv2-phase8-assert.sh's A7 check reads. Called by leadv2-phase8-close.sh
# before it invokes leadv2-phase8-assert.sh; also callable standalone (used
# by this task's own verification plan, see plan.md §8).
#
# Usage:
#   leadv2-phase8-e2e-gate.sh <task_id>
#   LEADV2_TASK_ID=PO-XXX leadv2-phase8-e2e-gate.sh
#
# Exit codes:
#   0  tests/run-all.sh --scope changed exited 0 -> sentinel written
#   1  tests/run-all.sh --scope changed exited non-zero -> sentinel NOT written
#   2  bad usage (missing task_id)
#
# Bypass (emergency only, same convention as PE_SKIP_TESTS elsewhere):
#   PE_SKIP_TESTS=1 leadv2-phase8-e2e-gate.sh <task_id>
#   -> sentinel IS written but with bypassed: true (visible, not silent —
#      "every decision is explainable" per CLAUDE.md non-negotiables).
#
# DEPLOY-CLASS-VERIFY-GATE-01 (D6): when the task classifies as `deploy`,
# a deploy-verify check MUST pass BEFORE this reaches PE_SKIP_TESTS or the
# normal test run — inserted above both so neither can bypass it. Bypass
# for THIS check is a separate, explicit env pair:
#   LEADV2_SKIP_DEPLOY_VERIFY=1 LEADV2_SKIP_DEPLOY_VERIFY_REASON="..."
#   -> empty reason still fails-closed (a reasonless bypass is a silent one).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# shellcheck source=leadv2-helpers.sh
source "${SCRIPT_DIR}/leadv2-helpers.sh"
_lv2_load_paths
cd "$PROJECT_ROOT"

TASK_ID="${1:-${LEADV2_TASK_ID:-}}"
if [[ -z "$TASK_ID" ]]; then
  echo "task_id required (arg1 or LEADV2_TASK_ID env)" >&2
  exit 2
fi

OUT_DIR="${LEADV2_HANDOFF_DIR}/${TASK_ID}"
mkdir -p "$OUT_DIR"
SENTINEL="${OUT_DIR}/e2e-gate-passed.flag"
LOG="${OUT_DIR}/e2e-gate.log"

# Advisory lock: prevent two concurrent invocations for the SAME task_id
# from interleaving writes to $LOG (see plan.md §9 R4). Mirrors the flock
# convention already used by the deploy path.
LOCK="/tmp/leadv2-e2e-gate-${TASK_ID}.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "leadv2-phase8-e2e-gate: another run in progress for ${TASK_ID} (lock: ${LOCK})" >&2
  exit 1
fi

# N1-EMPTY-LANE-IS-NOT-A-PASS: a lane that wrote nothing is never a pass. This is
# the SECOND writer of e2e-gate-passed.flag (the first, leadv2-dispatch-product-
# close.sh, now exits before stamping on an empty diff). Refuse to stamp the
# sentinel here too -- checked ONCE up front so NONE of the three stamp sites below
# (PE_SKIP bypass, rc==0 pass, foreign-failure) can launder a do-nothing lane into
# green. Reads the SAME architect-prepass.md LANE_WRITES the rest of this script
# resolves lower down; lv2_lane_diff_is_empty comes from leadv2-helpers.sh.
_p8_prepass_writes_early() {
  local f="${OUT_DIR}/architect-prepass.md" line
  [[ -s "${f}" ]] || return 0
  line="$(grep -m1 -iE '^[[:space:]*_]*LANE_WRITES[*_]*:' "${f}" 2>/dev/null)" || return 0
  line="$(printf '%s' "${line}" | sed -E 's/^[[:space:]*_]*LANE_WRITES[*_]*:[[:space:]]*//I')"
  local -a raw kept=()
  IFS=',' read -ra raw <<< "${line}"
  for e in "${raw[@]}"; do
    e="$(printf '%s' "${e}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n "${e}" ]] && kept+=("${e}")
  done
  (IFS=','; printf '%s' "${kept[*]:-}")
}
_p8_refuse_empty_lane() {
  local _wc; _wc="$(_p8_prepass_writes_early)"
  if lv2_lane_diff_is_empty "${PROJECT_ROOT}" "${_wc}"; then
    rm -f "$SENTINEL"
    printf 'status: blocked\nreason: no_work\n' > "${OUT_DIR}/review-gate.md" 2>/dev/null || true
    echo "leadv2-phase8-e2e-gate: lane diff is empty (no_work) -- refusing to stamp sentinel" | tee "$LOG" >&2
    exit 1
  fi
}
_p8_refuse_empty_lane

# ── D6: deploy-class verify gate (DEPLOY-CLASS-VERIFY-GATE-01) ──────────────
# Runs BEFORE the PE_SKIP_TESTS branch so that bypass cannot skip deploy
# verification. When the classifier says `deploy`, requires
# leadv2-deploy-verify-check.sh to pass before the sentinel is written.
# If the classifier itself is absent (not yet vendored here), classification
# degrades to `code` -- never a false-RED for repos mid-propagation.
DEPLOY_VERIFIED="false"
DEPLOY_VERIFY_BYPASSED="false"
DEPLOY_VERIFY_BYPASS_REASON=""

CLASSIFIER="${SCRIPT_DIR}/leadv2-deploy-classify.sh"
if [[ -f "$CLASSIFIER" ]]; then
  CLASSIFICATION="$(bash "$CLASSIFIER" "$TASK_ID" 2>/dev/null || echo code)"
else
  CLASSIFICATION="code"
fi

if [[ "$CLASSIFICATION" == "deploy" ]]; then
  if [[ "${LEADV2_SKIP_DEPLOY_VERIFY:-}" == "1" ]]; then
    if [[ -z "${LEADV2_SKIP_DEPLOY_VERIFY_REASON:-}" ]]; then
      echo "leadv2-phase8-e2e-gate: LEADV2_SKIP_DEPLOY_VERIFY=1 requires a non-empty LEADV2_SKIP_DEPLOY_VERIFY_REASON -- fail-closed" >&2
      rm -f "$SENTINEL"
      exit 1
    fi
    DEPLOY_VERIFY_BYPASSED="true"
    DEPLOY_VERIFY_BYPASS_REASON="${LEADV2_SKIP_DEPLOY_VERIFY_REASON}"
    echo "leadv2-phase8-e2e-gate: deploy-verify BYPASSED -- ${DEPLOY_VERIFY_BYPASS_REASON}" >&2
  else
    DEPLOY_CHECK="${SCRIPT_DIR}/leadv2-deploy-verify-check.sh"
    if [[ ! -f "$DEPLOY_CHECK" ]]; then
      echo "leadv2-phase8-e2e-gate: task classified deploy but leadv2-deploy-verify-check.sh not found (${DEPLOY_CHECK}) -- fail-closed" >&2
      rm -f "$SENTINEL"
      exit 1
    fi
    dv_out=""
    dv_rc=0
    dv_out=$(bash "$DEPLOY_CHECK" "$TASK_ID" 2>&1) || dv_rc=$?
    if [[ $dv_rc -eq 0 ]]; then
      DEPLOY_VERIFIED="true"
      echo "leadv2-phase8-e2e-gate: deploy-verify PASS -- ${dv_out}" >&2
    else
      echo "leadv2-phase8-e2e-gate: deploy-verify FAIL (exit ${dv_rc}) -- ${dv_out}" >&2
      rm -f "$SENTINEL"
      exit 1
    fi
  fi
fi

if [[ "${PE_SKIP_TESTS:-}" == "1" ]]; then
  printf 'e2e-gate-passed: %s\nasserted_at: %s\nscope: changed\nbypassed: true\ndeploy_verified: %s\ndeploy_verify_bypassed: %s\ndeploy_verify_bypass_reason: %s\n' \
    "$TASK_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$DEPLOY_VERIFIED" "$DEPLOY_VERIFY_BYPASSED" "$DEPLOY_VERIFY_BYPASS_REASON" > "$SENTINEL"
  echo "leadv2-phase8-e2e-gate: BYPASSED via PE_SKIP_TESTS=1 (sentinel marked bypassed:true)" | tee "$LOG" >&2
  exit 0
fi

rc=0
e2e_cmd=""
if ! e2e_cmd="$(bash "${SCRIPT_DIR}/leadv2-e2e-entrypoint.sh" "${PROJECT_ROOT}")"; then
  echo "leadv2-phase8-e2e-gate: no e2e entrypoint in $(basename "${PROJECT_ROOT}") -- blocked" \
    | tee "$LOG" >&2
  rm -f "$SENTINEL"
  exit 1
fi
bash -c "${e2e_cmd} --scope changed" > "$LOG" 2>&1 || rc=$?

# GATE-FOREIGN-FAILURE-01: resolves the lane's own write set itself (this
# path has no LEADV2_DISPATCH_LANE_WRITES export -- it is standalone-
# callable, see usage header) by reading the SAME architect-prepass.md
# LANE_WRITES: line the dispatch path resolves via _prepass_writes(), out of
# this task's own handoff dir. No LANE_WRITES declared -> empty, and the
# whole_tree_fallback branch below applies exactly as before.
JOURNAL_BIN="${LEADV2_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"
_p8_emit() { # <type> <text>
  [[ -f "${JOURNAL_BIN}" ]] && bash "${JOURNAL_BIN}" append "${TASK_ID}" "$1" "$2" >/dev/null 2>&1 || true
  printf '[leadv2-phase8-e2e-gate] %s\n' "$2" >&2
}
_p8_prepass_writes() {
  local f="${OUT_DIR}/architect-prepass.md" line
  [[ -s "${f}" ]] || return 0
  line="$(grep -m1 -iE '^[[:space:]*_]*LANE_WRITES[*_]*:' "${f}" 2>/dev/null)" || return 0
  line="$(printf '%s' "${line}" | sed -E 's/^[[:space:]*_]*LANE_WRITES[*_]*:[[:space:]]*//I')"
  local -a raw kept=()
  IFS=',' read -ra raw <<< "${line}"
  for e in "${raw[@]}"; do
    e="$(printf '%s' "${e}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n "${e}" ]] && kept+=("${e}")
  done
  (IFS=','; printf '%s' "${kept[*]:-}")
}
WRITES_CSV="$(_p8_prepass_writes)"
E2E_OWNERSHIP="${LEADV2_E2E_OWNERSHIP:-1}"
PASS_SCOPE="changed"
[[ "${E2E_OWNERSHIP}" == "1" && -n "${WRITES_CSV}" ]] && PASS_SCOPE="lane_writes"

if [[ $rc -eq 0 ]]; then
  printf 'e2e-gate-passed: %s\nasserted_at: %s\nscope: %s\nbypassed: false\ndeploy_verified: %s\ndeploy_verify_bypassed: %s\ndeploy_verify_bypass_reason: %s\n' \
    "$TASK_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${PASS_SCOPE}" "$DEPLOY_VERIFIED" "$DEPLOY_VERIFY_BYPASSED" "$DEPLOY_VERIFY_BYPASS_REASON" > "$SENTINEL"
  echo "leadv2-phase8-e2e-gate: PASS — sentinel written: ${SENTINEL}" >&2
  exit 0
fi

# GATE-FOREIGN-FAILURE-01: same ownership classification as the dispatch
# close gate (leadv2-e2e-ownership.sh) -- own failures always win over
# foreign ones, and undecidable folds into own (fail-closed).
OWN_CSV=""; FOREIGN_CSV=""; UNDECIDABLE_CSV=""; OWNER_LANE="unknown"
if [[ "${E2E_OWNERSHIP}" == "1" && -n "${WRITES_CSV}" ]]; then
  OWN_OUT="$(bash "${SCRIPT_DIR}/leadv2-e2e-ownership.sh" "${PROJECT_ROOT}" "${TASK_ID}" "${WRITES_CSV}" "$LOG" 2>/dev/null || true)"
  OWN_CSV="$(sed -n 's/^own=//p' <<< "${OWN_OUT}")"
  FOREIGN_CSV="$(sed -n 's/^foreign=//p' <<< "${OWN_OUT}")"
  UNDECIDABLE_CSV="$(sed -n 's/^undecidable=//p' <<< "${OWN_OUT}")"
  OWNER_LANE="$(sed -n 's/^owner_lane=//p' <<< "${OWN_OUT}")"
  [[ -z "${OWNER_LANE}" ]] && OWNER_LANE="unknown"
fi

if [[ -n "${FOREIGN_CSV}" && -z "${OWN_CSV}" && -z "${UNDECIDABLE_CSV}" ]]; then
  IFS=',' read -r -a _lane_writes <<< "${WRITES_CSV}"
  mapfile -t _all_changed < <(
    { git -C "${PROJECT_ROOT}" diff --name-only HEAD -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null
      git -C "${PROJECT_ROOT}" ls-files --others --exclude-standard -- ':(exclude)docs/leadv2' ':(exclude)docs/handoff' 2>/dev/null; } | sort -u
  )
  _foreign_files=()
  for _f in "${_all_changed[@]}"; do
    [[ -z "${_f}" ]] && continue
    _is_write=0
    for _w in "${_lane_writes[@]}"; do [[ "${_f}" == "${_w}" ]] && { _is_write=1; break; }; done
    (( _is_write )) || _foreign_files+=("${_f}")
  done
  FOREIGN_FILES_CSV="$(IFS=,; echo "${_foreign_files[*]:-}")"
  printf 'e2e-gate-passed: %s\nasserted_at: %s\nscope: lane_writes\nbypassed: false\nforeign_failures: %s\ndeploy_verified: %s\ndeploy_verify_bypassed: %s\ndeploy_verify_bypass_reason: %s\n' \
    "$TASK_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${FOREIGN_CSV}" "$DEPLOY_VERIFIED" "$DEPLOY_VERIFY_BYPASSED" "$DEPLOY_VERIFY_BYPASS_REASON" > "$SENTINEL"
  _p8_emit decision "e2e_gate task=${TASK_ID} status=ran verdict=foreign_failure scope=lane_writes foreign_suites=${FOREIGN_CSV} foreign_files=${FOREIGN_FILES_CSV} owner_lane=${OWNER_LANE} own_failures=0"
  IFS=',' read -r -a _foreign_suite_arr <<< "${FOREIGN_CSV}"
  for _s in "${_foreign_suite_arr[@]}"; do
    [[ -z "${_s}" ]] && continue
    _p8_emit decision "foreign_failure task=${TASK_ID} suite=${_s} file=${FOREIGN_FILES_CSV} owner_lane=${OWNER_LANE}"
  done
  echo "leadv2-phase8-e2e-gate: FOREIGN_FAILURE — ${FOREIGN_CSV} not reproducible against lane's own writes (owner_lane=${OWNER_LANE}); sentinel written — see ${LOG}" >&2
  exit 0
fi

rm -f "$SENTINEL"   # never leave a stale PASS behind on a red re-run
if [[ -z "${WRITES_CSV}" ]]; then
  _p8_emit decision "e2e_gate task=${TASK_ID} status=ran verdict=fail rc=${rc} scope=whole_tree_fallback"
else
  _p8_emit decision "e2e_gate task=${TASK_ID} status=ran verdict=fail rc=${rc}"
fi
echo "leadv2-phase8-e2e-gate: FAIL (tests/run-all.sh --scope changed exit ${rc}) — see ${LOG}" >&2
tail -40 "$LOG" >&2 || true
exit 1
