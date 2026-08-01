#!/usr/bin/env bash
# tests/test-dispatch-ledger-task-id.sh — SWIFTBAR-LIVE-01 round 2 (§2.4) writer regression.
#
# THE BUG: dispatch_reserve() called _dispatch_append_pending_locked with only 6 of its
# 8 positional args, so every pending-ledger row was written with task_id="" and
# mission_path="" -- even when the caller was invoked with --task-id N4-TESTRUNNER-FALSE-RED.
# The status surface then had nothing to name the lane by and fell back to scraping the
# mission's prose first line, rendering things like "You are implementing task
# dispatch-14b3b worker confirmed" as a lane's NAME.
#
# THIS TEST drives the REAL dispatch-code.sh (never a hand-reimplemented copy of the
# ledger-write logic) with a bound --task-id, same hermetic-fixture discipline as
# test-dispatch-duplicate-caller-race.sh / test-leadv2-dispatch-outcome-ledger.sh, and
# asserts the PENDING ledger row (the one leadv2-status-surface.sh reads for worker rows)
# carries a non-empty task_id equal to what was passed on the command line.
#
# Run: bash plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_SH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
source "${SCRIPTS_DIR}/leadv2-temp.sh"

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

if bash -n "${DISPATCH_SH}" 2>/dev/null; then
  pass "bash -n leadv2-dispatch-code.sh"
else
  fail "bash -n leadv2-dispatch-code.sh"
fi
if bash -n "${BASH_SOURCE[0]}" 2>/dev/null; then
  pass "bash -n $(basename "${BASH_SOURCE[0]}")"
else
  fail "bash -n $(basename "${BASH_SOURCE[0]}")"
fi

RUN_ID="dispatch-ledger-task-id-$$-$(date +%s 2>/dev/null || echo 0)"
TMPDIR_ROOT="$(lv2_mktemp_dir "${RUN_ID}")"
ROOT="${TMPDIR_ROOT}/repo"
CACHE_DIR="${TMPDIR_ROOT}/cache"
FAKE_SUBSESSION="${TMPDIR_ROOT}/fake-claude-subsession.sh"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

mkdir -p "${ROOT}/.claude/ref" "${ROOT}/docs/leadv2/.bus-offsets" "${ROOT}/platform"
( cd "${ROOT}" && git init -q && git config user.email test@example.com && git config user.name test \
  && printf 'seed\n' > seed.txt && git add seed.txt && git commit -qm seed )

cat > "${ROOT}/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    sonnet_exceptions:
      - id: safety_gate_publish_payments
    opus_only_mission_kinds: []
    codex_fitting_mission_kinds: []
    codex_default_tier: standard
YAML

# Same fake launcher shape as the other dispatch-code tests: spawns a real, short-lived
# OS process and prints its PID in the exact shape spawn_worker's sonnet-arm parser expects.
cat > "${FAKE_SUBSESSION}" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
nohup sleep 0.3 >/dev/null 2>&1 &
pid=$!
disown
printf 'PID=%s LABEL=fake-lane SESSION_ID=fake-session\n' "${pid}"
exit 0
EOF
chmod +x "${FAKE_SUBSESSION}"

TASK_ID="N4-TESTRUNNER-FALSE-RED"
mission="docs-only: dispatch-ledger-task-id $$ $(date +%s)"

out="$(
  CLAUDE_PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
  LEADV2_DISPATCH_CACHE_DIR="${CACHE_DIR}" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${FAKE_SUBSESSION}" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
  LEADV2_JOURNAL_BIN=/bin/true \
  LEADV2_ROUTER_V2=0 \
  LEADV2_EXCLUDED_ARMS="__none__" \
  LEADV2_LANE_SHAPE=off \
  "${DISPATCH_SH}" "${mission}" --protected --spawn --task-id "${TASK_ID}" 2>&1
)"
rc=$?

if [[ "${rc}" -eq 0 ]]; then
  pass "dispatch with --task-id exits 0"
else
  fail "dispatch with --task-id exits 0 (got rc=${rc}, out=${out})"
fi

repo_base="$(basename "${ROOT}")"
repo_slug="$(printf '%s' "${repo_base}" | tr -cd 'A-Za-z0-9._-')"
LEDGER_FILE="${CACHE_DIR}/dispatch-ledger/${repo_slug}.jsonl"

if [[ -f "${LEDGER_FILE}" ]]; then
  pass "pending dispatch ledger file exists"
else
  fail "pending dispatch ledger file exists (expected ${LEDGER_FILE}; dir contents: $(ls -la "${CACHE_DIR}/dispatch-ledger" 2>&1))"
fi

row="$(tail -1 "${LEDGER_FILE}" 2>/dev/null)"

if grep -q "\"task_id\":\"${TASK_ID}\"" <<<"${row}"; then
  pass "ledger row's task_id equals the bound --task-id (${TASK_ID})"
else
  fail "ledger row's task_id equals the bound --task-id (got row: ${row})"
fi

if grep -q '"mission_path":""' <<<"${row}"; then
  # this dispatch passed the mission inline (not via @file), so an empty
  # mission_path is the correct, honest value here -- the writer link
  # (dispatch_reserve receiving DISPATCH_MISSION_PATH) is proven by task_id
  # above, which travels the identical code path.
  pass "ledger row's mission_path is empty for an inline (non-@file) mission, as expected"
else
  fail "ledger row's mission_path unexpected for an inline mission (got row: ${row})"
fi

printf '[TEST] === %s passed, %s failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
