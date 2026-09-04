#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-phase8-assert.sh leadv2-tasks-lib.sh
# tests/test-phase8-a2-id-resolution.sh — CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01.
#
# Defect: A2 in leadv2-phase8-assert.sh compared `row.id == task_id` where
# task_id is a HUMAN milestone name (e.g. V5-M0-SKELETON-01) while backlog
# rows are fingerprint-keyed (id: ca2177b9451b) and the name lives only in
# the row's `intent` as the text before its first colon. The comparison could
# NEVER match, so A2 always exited 2 and the close gate blocked forever.
# The comment "Not found in tasks.yaml — check lane yamls as fallback"
# described a fallback no code on that path performs, and the printed remedy
# (leadv2_tasks_release <name>) failed with the same id-scheme mismatch one
# layer down in leadv2-tasks-lib.sh.
#
# This suite pins the FIX: every id-scheme lookup resolves via
# row_matches() (row id == task_id, OR intent's FULL pre-colon segment ==
# task_id — never a substring: "V5-M1" must not match "V5-M10:").
#
# All fixtures are throwaway files in $(mktemp -d) — the real docs/tasks.yaml
# of any repo is NEVER read or written.

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${TEST_DIR}/.." && pwd)"
ASSERT_SH="${SCRIPTS_DIR}/leadv2-phase8-assert.sh"
TASKS_LIB="${SCRIPTS_DIR}/leadv2-tasks-lib.sh"
COMMON_PY="${SCRIPTS_DIR}/leadv2_tasks_yaml_common.py"

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
check(){ if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected [$3] got [$2])"; fi; }

# ── Status vocabularies from the single shared source ────────────────────────
VOCAB="$(python3 -c '
import sys; sys.path.insert(0, sys.argv[1])
from leadv2_tasks_yaml_common import TERMINAL_STATUSES, LANE_TERMINAL_STATUSES
print(TERMINAL_STATUSES)
print(LANE_TERMINAL_STATUSES)
' "${SCRIPTS_DIR}")"
TERMINALS="$(printf '%s\n' "$VOCAB" | sed -n 1p)"
LANE_TERMINALS="$(printf '%s\n' "$VOCAB" | sed -n 2p)"
if [[ -z "$TERMINALS" || -z "$LANE_TERMINALS" ]]; then
  echo "FATAL: could not load status vocabularies from ${COMMON_PY}" >&2
  exit 99
fi

# ── Extract the A2 python block verbatim from the live assert script ─────────
_extract_a2_python() {
  awk '/^import sys$/{found=1} found{print} /^PYEOF$/{if(found)exit}' "$ASSERT_SH" | sed '$d'
}

# args: task_id tasks_yaml -> rc in A2_RC, stderr in A2_ERR
_run_a2() {
  local snippet
  snippet="$(_extract_a2_python)"
  if [[ -z "$snippet" ]]; then
    echo "EXTRACT_FAILED" >&2; A2_RC=99; A2_ERR=""; return 0
  fi
  local snippet_file="${TMPDIR_ROOT}/a2-snippet.py"
  printf '%s\n' "$snippet" > "$snippet_file"
  A2_ERR="$(python3 "$snippet_file" "$1" "$2" "$TERMINALS" "$LANE_TERMINALS" "${SCRIPTS_DIR}" 2>&1 >/dev/null)"
  A2_RC=$?
  return 0
}

# ── E2E: run the shipped leadv2-phase8-assert.sh against a throwaway root ────
E2E_ROOT=""
# args: root -> sets E2E_RC / E2E_ERR (combined output of the real script)
_e2e_run() {
  local root="$1" task_id="$2"
  set +e
  E2E_ERR="$(CLAUDE_PROJECT_ROOT="$root" LEADV2_PROJECT_ROOT="$root" \
    LEADV2_STATE_ROOT="${root}/.state" \
    bash "$ASSERT_SH" "$task_id" 2>&1 >/dev/null)"
  E2E_RC=$?
  return 0
}

# args: task_id -> prints a throwaway root satisfying every hard assertion
# OTHER than A2 (mirrors the harness proven in test-leadv2-phase8-assert-a2-schema.sh)
_e2e_new_project() {
  local task_id="$1"
  local root="${E2E_ROOT}/${task_id}.$$.${RANDOM}"
  mkdir -p "${root}/docs/leadv2/closed" "${root}/docs/handoff/${task_id}"
  printf -- 'task_id: %s\nclosed_at: 2026-01-01T00:00:00Z\n' "$task_id" \
    > "${root}/docs/leadv2/closed/${task_id}.yaml"                       # A1
  printf -- 'entries:\n  - task: %s\n' "$task_id" \
    > "${root}/docs/leadv2/reflect-history.yaml"                         # A4
  touch "${root}/docs/handoff/${task_id}/e2e-gate-passed.flag"           # A7 fresh
  # A3: no active.yaml; A5/A6/A8 pass/warn-only by omission.
  printf -- '%s\n' "$root"
}

TMPDIR_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/a2-id-resolve.XXXXXX")"
E2E_ROOT="${TMPDIR_ROOT}/e2e"
mkdir -p "$E2E_ROOT"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ── Fixture: the REAL-repo shape (fingerprint ids, human names in intent) ────
# This one fixture is the negative-control anchor: the mutation control below
# must go red HERE, not only on a row whose id already equals the name.
FINGERPRINT_YAML="${TMPDIR_ROOT}/fingerprint-tasks.yaml"
cat > "$FINGERPRINT_YAML" <<'EOF'
total_open: 3
tasks:
  - id: ca2177b9451b
    intent: 'V5-M0-SKELETON-01: веха M0 плана v5'
    status: done
  - id: V5-LEGACY-01
    intent: 'legacy row whose id already is the human name'
    status: done
  - id: 00aa11bb22cc
    intent: 'V5-M10: a later milestone that V5-M1 must NOT match'
    status: done
EOF

echo "# CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01 — A2 id resolution"

# Test 0: extraction sanity — the real A2 body uses the shared resolver.
echo "Test 0: A2 python extracted from live source routes through row_matches"
SNIPPET="$(_extract_a2_python)"
if [[ -n "$SNIPPET" && "$SNIPPET" == *"row_matches"* && "$SNIPPET" == *"load_tasks_items"* ]]; then
  ok "A2 body imports row_matches + load_tasks_items"
else
  bad "A2 body does not route through row_matches/load_tasks_items"
fi

# Test 1 (THE defect): fingerprint-keyed row whose intent names the milestone.
echo "Test 1: fingerprint row with intent prefix 'V5-M0-SKELETON-01:' resolves"
_run_a2 "V5-M0-SKELETON-01" "$FINGERPRINT_YAML"
check "A2 passes for milestone name on the real-repo fixture" "$A2_RC" "0"

# Test 2: regression guard — a row whose id equals the task id still passes.
echo "Test 2: row whose id equals the task id still resolves"
_run_a2 "V5-LEGACY-01" "$FINGERPRINT_YAML"
check "A2 passes for id==task_id row" "$A2_RC" "0"

# Test 3: no substring bleed — both directions.
echo "Test 3: 'V5-M1' must NOT match the 'V5-M10:' row (and 'V5-M10' must)"
_run_a2 "V5-M1" "$FINGERPRINT_YAML"
check "V5-M1 does not match V5-M10 row" "$A2_RC" "2"
_run_a2 "V5-M10" "$FINGERPRINT_YAML"
check "V5-M10 itself still matches its row" "$A2_RC" "0"

# Test 4: genuinely absent task still fails, message names what was searched.
echo "Test 4: absent task fails with a search-describing message"
_run_a2 "V5-DOES-NOT-EXIST" "$FINGERPRINT_YAML"
check "A2 fails for absent task" "$A2_RC" "2"
if [[ "$A2_ERR" == *"not found in"* && "$A2_ERR" == *"pre-colon segment"* ]]; then
  ok "failure message names the id + intent pre-colon search"
else
  bad "failure message does not describe the search: ${A2_ERR}"
fi
E4_ROOT="$(_e2e_new_project "V5-DOES-NOT-EXIST")"
printf -- 'total_open: 1\ntasks:\n  - id: ca2177b9451b\n    intent: '"'"'V5-M0-SKELETON-01: веха M0 плана v5'"'"'\n    status: done\n' \
  > "${E4_ROOT}/docs/tasks.yaml"
_e2e_run "$E4_ROOT" "V5-DOES-NOT-EXIST"
if [[ "$E2E_RC" -ne 0 && "$E2E_ERR" == *"searched"*"by row id and by intent pre-colon segment"* ]]; then
  ok "shipped script fails absent task and reports what was searched"
else
  bad "shipped script absent-task reporting wrong (rc=${E2E_RC}): $(printf '%s' "$E2E_ERR" | tail -3)"
fi

# Test 5: the printed remedy is executable end-to-end.
echo "Test 5: leadv2_tasks_release <milestone-name> clears the failure"
R5_ROOT="${TMPDIR_ROOT}/remedy"
mkdir -p "${R5_ROOT}/docs/handoff"
printf -- 'total_open: 1\ntasks:\n  - id: ca2177b9451b\n    intent: '"'"'V5-M0-SKELETON-01: веха M0 плана v5'"'"'\n    status: claimed_done\n' \
  > "${R5_ROOT}/docs/tasks.yaml"
set +e
REMEDY_ERR="$(PROJECT_ROOT="$R5_ROOT" LEADV2_HANDOFF_DIR="${R5_ROOT}/docs/handoff" \
  bash -c '
  source "'"${TASKS_LIB}"'"
  leadv2_tasks_release "V5-M0-SKELETON-01" --outcome success
' 2>&1)"
REMEDY_RC=$?
set -u
check "leadv2_tasks_release by milestone name succeeds" "$REMEDY_RC" "0"
ROW_STATUS="$(python3 -c '
import sys; sys.path.insert(0, sys.argv[1])
from leadv2_tasks_yaml_common import load_tasks_items
items = load_tasks_items(sys.argv[2])
print([it.get("status") for it in items if it.get("id")=="ca2177b9451b"][0])
' "${SCRIPTS_DIR}" "${R5_ROOT}/docs/tasks.yaml")"
check "fixture row promoted to terminal by the remedy" "$ROW_STATUS" "done"
_run_a2 "V5-M0-SKELETON-01" "${R5_ROOT}/docs/tasks.yaml"
check "A2 passes after the remedy ran" "$A2_RC" "0"

# Test 6 (real-repo shape, full gate): claimed_done + receipt + phase8 flag.
echo "Test 6: E2E — fingerprint row claimed_done passes the shipped gate"
T6_ROOT="$(_e2e_new_project "V5-M0-SKELETON-01")"
printf -- 'total_open: 1\ntasks:\n  - id: ca2177b9451b\n    intent: '"'"'V5-M0-SKELETON-01: веха M0 плана v5'"'"'\n    status: claimed_done\n' \
  > "${T6_ROOT}/docs/tasks.yaml"
printf -- 'outcome: completed_success\ntask_id: V5-M0-SKELETON-01\n' \
  > "${T6_ROOT}/docs/leadv2/closed/.tasks-sentinel-V5-M0-SKELETON-01.yaml"
touch "${T6_ROOT}/docs/handoff/V5-M0-SKELETON-01/phase8-passed.flag"
_e2e_run "$T6_ROOT" "V5-M0-SKELETON-01"
if [[ "$E2E_ERR" == *"A2 PASS (lane-terminal"* || "$E2E_ERR" == *"PASS: A2 tasks.yaml: V5-M0-SKELETON-01 has terminal status"* ]]; then
  ok "shipped gate prints A2 PASS for the fingerprint+intent row"
else
  bad "shipped gate did not print A2 PASS (rc=${E2E_RC}): $(printf '%s' "$E2E_ERR" | grep -m2 'A2' || true)"
fi

echo
echo "passed=${PASS} failed=${FAIL}"
if [[ "$FAIL" -eq 0 ]]; then
  echo "A2-ID-RESOLUTION: ALL GREEN"
  exit 0
fi
echo "A2-ID-RESOLUTION: RED"
exit 1
