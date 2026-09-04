#!/usr/bin/env bash
# tests/test-plugin-repo-backlog.sh — PLUGIN-REPO-HAS-NO-BACKLOG-01 negative
# control. Proves the leadv2 plugin repo's own docs/tasks.yaml is real and
# readable by leadv2-tasks-lib.sh's real functions -- not just parseable by a
# bare yaml.safe_load.
#
# Deliberately fakes NOTHING: leadv2_tasks_top_n / leadv2_tasks_by_id are
# sourced from the shipped leadv2-tasks-lib.sh and run against the repo's
# real docs/tasks.yaml (PROJECT_ROOT auto-resolves via git toplevel to this
# checkout, same as every other caller of the lib).
#
# Falsification proof (recorded manually, not run by this script): with
# load_tasks() in leadv2-tasks-lib.sh mutated to `return []` as the first
# line of the `if isinstance(doc, dict):` block (right after line 131,
# before the _LIST_KEYS loop), this suite's Test 2 goes RED because the lib
# reports zero tasks against a real 74-row file -- Test 1 (bare
# yaml.safe_load) is untouched by that mutation and stays green, which is
# why both assertions are required, not just one.
#
# Run: bash plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh
# Exit 0 = all pass; non-zero = failures found.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TASKS_LIB="${SCRIPTS_DIR}/leadv2-tasks-lib.sh"
PROJECT_ROOT="$(cd "${SCRIPTS_DIR}/../../.." && pwd)"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

test_1_yaml_is_a_mapping_with_open_tasks() {
  if PROJECT_ROOT="${PROJECT_ROOT}" python3 -c "
import yaml
d = yaml.safe_load(open('${PROJECT_ROOT}/docs/tasks.yaml'))
assert isinstance(d, dict) and 'total_open' in d and isinstance(d['tasks'], list) and len(d['tasks']) > 0
"; then
    pass "Test 1: docs/tasks.yaml is a {total_open, tasks:[...]} mapping with >0 rows"
  else
    fail "Test 1: docs/tasks.yaml is not a valid non-empty mapping"
  fi
}

test_2_lib_reads_real_file_via_top_n() {
  local out rc
  set +e
  out="$(PROJECT_ROOT="${PROJECT_ROOT}" bash -c "source '${TASKS_LIB}'; leadv2_tasks_top_n 5" 2>&1)"
  rc=$?
  set -e
  local nonempty_rows
  nonempty_rows="$(printf '%s\n' "${out}" | grep -c $'\t' || true)"
  if [[ "${rc}" -eq 0 && "${nonempty_rows}" -eq 5 ]]; then
    pass "Test 2: leadv2_tasks_top_n 5 (real lib, real file) returned 5 tab-separated rows"
  else
    fail "Test 2: expected rc=0 and 5 tab-separated rows, got rc=${rc} rows=${nonempty_rows}: ${out}"
  fi
}

main() {
  log "=== PLUGIN-REPO-HAS-NO-BACKLOG-01 negative control (PROJECT_ROOT=${PROJECT_ROOT}) ==="
  echo ""
  test_1_yaml_is_a_mapping_with_open_tasks
  test_2_lib_reads_real_file_via_top_n
  echo ""
  log "=== Results: PASS=$PASS FAIL=$FAIL ==="
  if [[ "${#ERRORS[@]}" -gt 0 ]]; then
    log "Failures:"
    for e in "${ERRORS[@]}"; do log "  $e"; done
    exit 1
  fi
  log "All tests passed."
  exit 0
}

main "$@"
