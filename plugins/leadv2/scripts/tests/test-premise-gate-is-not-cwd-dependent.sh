#!/usr/bin/env bash
# PREMISE-GATE-IS-BYPASSED-BY-CHANGING-DIRECTORY-01
# run-all-triggers: leadv2-dispatch-code
# The real premise gate is called through its source-only seam under bash -c.
set -uo pipefail

_src="${BASH_SOURCE[0]:-}"
[[ -n "${_src}" && -f "${_src}" ]] || _src="$0"
SCRIPT_DIR="$(cd "$(dirname "${_src}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_SH="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

PASS=0; FAIL=0; ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir premise-cwd-owner)"
trap 'rm -rf "${TMP}"' EXIT
WORKSPACE="${TMP}/workspace"
OWNER="${WORKSPACE}/owner-backlog-cc7dcbc210eb"
CALLER_A="${WORKSPACE}/caller-a-cc7dcbc210eb"
CALLER_B="${WORKSPACE}/caller-b-cc7dcbc210eb"
TASK_ID="CWD-OWNER-ROW-01"
mkdir -p "${OWNER}/docs" "${CALLER_A}" "${CALLER_B}"

root="${CALLER_A}"
( cd "${root}" && git init -q && git config user.email test@example.com && git config user.name test \
  && printf 'fixture\n' > seed.txt && git add seed.txt && git commit -qm seed ) || exit 1
root="${CALLER_B}"
( cd "${root}" && git init -q && git config user.email test@example.com && git config user.name test \
  && printf 'fixture\n' > seed.txt && git add seed.txt && git commit -qm seed ) || exit 1

printf 'alive-marker\n' > "${OWNER}/alive-marker.txt"
cat > "${OWNER}/docs/tasks.yaml" <<YAML
tasks:
- id: ${TASK_ID}
  intent: 'CWD-OWNER-ROW-01: owner row, red acceptance probe'
  status: queued
  acceptance_cmd: 'test -f ${OWNER}/alive-marker.txt && false'
YAML

# _gate <cwd> <task-id> [no-probe-yet] -> gate output and RC.
_gate() {
  local cwd="$1" task="$2" no_probe="${3:-0}"
  ( cd "${cwd}" && \
    LEADV2_CANONICAL_ROOT="$(cd "${SCRIPTS_ROOT}/../../.." && pwd)" \
    LEADV2_PREMISE_BACKLOG_ROOTS="${OWNER}" LEADV2_STATE_ROOT="${TMP}/state" \
    LEADV2_DISPATCH_CACHE_DIR="${TMP}/cache" LEADV2_DISPATCH_SOURCE_ONLY=1 \
    LEADV2_DISPATCH_TERMINAL_LEDGER=0 LEADV2_JOURNAL_BIN=/bin/true LEADV2_EVENT_BIN=/bin/true \
    bash -c '
      source "$1"
      sig8="cwdgate01"; founder_task_id="$2"; lane_acceptance_cmd=""
      placement_lane_ref=""; placement_path=""; JOURNAL_TASK=""
      premise_no_probe_yet="$3"; _premise_probe_gate
    ' _ "${DISPATCH_SH}" "${task}" "${no_probe}" )
}

# ── same owner row, two different cwds ───────────────────────────────────
OUT_A="$(_gate "${CALLER_A}" "${TASK_ID}" 2>&1)"; RC_A=$?
OUT_B="$(_gate "${CALLER_B}" "${TASK_ID}" 2>&1)"; RC_B=$?
printf '%s\n' "${OUT_A}" "${OUT_B}"
[[ "${RC_A}" == "0" && "${RC_B}" == "0" ]] \
  && pass "same owner row reaches red/alive gate from both cwds" \
  || fail "same row verdict rc mismatch: caller-a=${RC_A}, caller-b=${RC_B}"
if [[ "$(grep -c "row=${TASK_ID} verdict=alive rc=1" <<<"${OUT_A}")" == "1" ]]; then
  pass "caller-a has one exact alive/red verdict"
else
  fail "caller-a verdict is not exactly alive/red once: ${OUT_A}"
fi
if [[ "$(grep -c "row=${TASK_ID} verdict=alive rc=1" <<<"${OUT_B}")" == "1" ]]; then
  pass "caller-b has one exact alive/red verdict"
else
  fail "caller-b verdict is not exactly alive/red once: ${OUT_B}"
fi

# ── negative: a missing row refuses, never skips ──────────────────────────
OUT_MISS="$(_gate "${CALLER_A}" "NO-SUCH-BACKLOG-ROW-01" 0 2>&1)"; RC_MISS=$?
printf '%s\n' "${OUT_MISS}"
if [[ "${RC_MISS}" == "8" ]] && grep -q 'reason=backlog_row_not_found' <<<"${OUT_MISS}" \
    && ! grep -q 'verdict=skipped' <<<"${OUT_MISS}"; then
  pass "missing owner row refuses loudly without skip"
else
  fail "missing owner row was not a loud refusal: rc=${RC_MISS} out=${OUT_MISS}"
fi

# ── explicit ad-hoc escape hatch is a separate audited outcome ────────────
OUT_ADHOC="$(_gate "${CALLER_A}" "NO-SUCH-BACKLOG-ROW-02" 1 2>&1)"; RC_ADHOC=$?
printf '%s\n' "${OUT_ADHOC}"
if [[ "${RC_ADHOC}" == "0" ]] && grep -q 'verdict=skipped reason=no_probe_yet' <<<"${OUT_ADHOC}" \
    && grep -q 'actor=' <<<"${OUT_ADHOC}" && grep -q 'why=explicit_no_probe_yet' <<<"${OUT_ADHOC}"; then
  pass "--no-probe-yet is a distinct audited escape hatch"
else
  fail "ad-hoc override was not audited: rc=${RC_ADHOC} out=${OUT_ADHOC}"
fi

# ── declared negative control: exact anchor count, then force refusal green
MUTANT="${TMP}/leadv2-dispatch-code.mutant.sh"
ln -s "${SCRIPTS_ROOT}/leadv2_tasks_yaml_common.py" "${TMP}/leadv2_tasks_yaml_common.py"
python3 - "${DISPATCH_SH}" "${MUTANT}" <<'PY'
import sys
source_path, mutant_path = sys.argv[1:]
source = open(source_path, encoding="utf-8").read()
old = '''        emit decision "premise_probe task=${sig8} verdict=refused reason=backlog_row_not_found"
        log_err "premise refused: reason=backlog_row_not_found task=${sig8} founder=${founder_task_id:-none} -- no docs/tasks.yaml or markdown backlog row carries this id; use --no-probe-yet only for deliberately ad-hoc work (audited with actor and why)"
        exit "${PREMISE_REFUSED_RC}"'''
count = source.count(old)
if count != 1:
    raise SystemExit(f"ANCHOR_COUNT={count}, want=1")
new = old.replace('exit "${PREMISE_REFUSED_RC}"', 'return 0')
open(mutant_path, "w", encoding="utf-8").write(source.replace(old, new, 1))
print(f"ANCHOR_COUNT={count}")
PY
if [[ "$?" == "0" ]]; then
  MUTANT_OUT="$(cd "${CALLER_A}" && \
    LEADV2_CANONICAL_ROOT="$(cd "${SCRIPTS_ROOT}/../../.." && pwd)" \
    LEADV2_PREMISE_BACKLOG_ROOTS="${OWNER}" LEADV2_STATE_ROOT="${TMP}/state-mutant" \
    LEADV2_DISPATCH_SOURCE_ONLY=1 LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
    LEADV2_JOURNAL_BIN=/bin/true LEADV2_EVENT_BIN=/bin/true \
    bash -c 'source "$1"; sig8="cwdmut01"; founder_task_id="NO-SUCH-BACKLOG-ROW-03"; lane_acceptance_cmd=""; placement_lane_ref=""; placement_path=""; JOURNAL_TASK=""; premise_no_probe_yet=0; _premise_probe_gate' _ "${MUTANT}" 2>&1)"
  MUTANT_RC=$?
  printf '%s\n' "${MUTANT_OUT}"
  if [[ "${MUTANT_RC}" != "8" ]]; then
    pass "negative control goes RED after anchored refusal mutation"
  else
    fail "negative control survived mutation: rc=${MUTANT_RC}"
  fi
else
  fail "negative control anchor did not match exactly once"
fi

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
if [[ "${FAIL}" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}" >&2
  exit 1
fi
