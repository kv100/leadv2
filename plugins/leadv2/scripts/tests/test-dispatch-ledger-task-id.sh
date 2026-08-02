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

# ── N7F-LANE-NAME extension ────────────────────────────────────────────────────────
#
# Why the six cases above never caught the live bug: N-7f's investigation found every
# real founder dispatch (the fanout path aside) runs WITHOUT --task-id, yet all six
# assertions above ALWAYS pass --task-id "${TASK_ID}" -- so this file exercised the one
# input shape (bound identity) that the live path never supplies, and its mission is a
# bare inline string with no H1, so even a mission-scrape fallback would have nothing to
# find. Concretely, three blindness properties, all present at once in the original
# suite:
#   1. it always passes --task-id -- the one input the live caller omits;
#   2. its mission is inline (`docs-only: ...`), never `class=product`, so the
#      prepass/act-two close-gate half of the writer chain is never reached;
#   3. it asserts only the pending/reserve row, never a terminal row -- and for a
#      product lane the terminal row is written by a DIFFERENT process
#      (leadv2-dispatch-product-close.sh), not dispatch-code.sh itself.
# C1-C3 close blindness #1 (drive the real --task-id-absent shape, with and without a
# mission H1). C4-C5 close blindness #3 (drive leadv2-dispatch-ledger.sh write-terminal
# directly, the product-lane terminal writer, without spawning a real close gate).

LEDGER_SH="${SCRIPTS_DIR}/leadv2-dispatch-ledger.sh"

# C1: @file mission WITH an H1 heading, NO --task-id. N1B F4 changed the schema:
# the H1 name-token is now a DISPLAY label (lane_label), NOT an identity. So the
# reserve row carries task_id="" (no founder identity bound) AND
# lane_label="N7F-C1" (the prose-derived display name). Before F4 the label went
# into task_id and collided with tasks.yaml identities -- exactly Finding 4.
c1_mission_file="${TMPDIR_ROOT}/c1-mission.md"
cat > "${c1_mission_file}" <<EOF
# N7F-C1 — case one heading, dispatch-ledger-task-id $$ $(date +%s 2>/dev/null || echo 0)
body text, deliberately no --task-id on this dispatch
EOF

out_c1="$(
  CLAUDE_PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
  LEADV2_DISPATCH_CACHE_DIR="${CACHE_DIR}" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${FAKE_SUBSESSION}" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
  LEADV2_JOURNAL_BIN=/bin/true \
  LEADV2_ROUTER_V2=0 \
  LEADV2_EXCLUDED_ARMS="__none__" \
  LEADV2_LANE_SHAPE=off \
  "${DISPATCH_SH}" "@${c1_mission_file}" --protected --spawn --kind docs 2>&1
)"
rc_c1=$?
row_c1="$(tail -1 "${LEDGER_FILE}" 2>/dev/null)"
if [[ "${rc_c1}" -eq 0 ]] && grep -q '"task_id":""' <<<"${row_c1}"; then
  pass "C1: no --task-id -> reserve row task_id is EMPTY (identity absent, not the H1)"
else
  fail "C1: no --task-id -> task_id empty (got rc=${rc_c1}, row: ${row_c1})"
fi
if [[ "${rc_c1}" -eq 0 ]] && grep -q '"lane_label":"N7F-C1"' <<<"${row_c1}"; then
  pass "C1: no --task-id, mission has H1 -> reserve row lane_label == H1 name-token (N7F-C1)"
else
  fail "C1: no --task-id, mission has H1 -> lane_label == H1 name-token (got row: ${row_c1})"
fi

# C2: mission with NO H1, NO --task-id -> reserve row task_id is empty (rule 3: no
# invented name -- never a hash, filename, or prose fragment).
c2_mission="plain mission body, no heading line, dispatch-ledger-task-id c2 $$ $(date +%s 2>/dev/null || echo 0)"
out_c2="$(
  CLAUDE_PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
  LEADV2_DISPATCH_CACHE_DIR="${CACHE_DIR}" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${FAKE_SUBSESSION}" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
  LEADV2_JOURNAL_BIN=/bin/true \
  LEADV2_ROUTER_V2=0 \
  LEADV2_EXCLUDED_ARMS="__none__" \
  LEADV2_LANE_SHAPE=off \
  "${DISPATCH_SH}" "${c2_mission}" --protected --spawn --kind docs 2>&1
)"
rc_c2=$?
row_c2="$(tail -1 "${LEDGER_FILE}" 2>/dev/null)"
if [[ "${rc_c2}" -eq 0 ]] && grep -q '"task_id":""' <<<"${row_c2}"; then
  pass "C2: no --task-id, mission has no H1 -> reserve row task_id is empty (no invented name)"
else
  fail "C2: no --task-id, mission has no H1 -> reserve row task_id is empty (got rc=${rc_c2}, row: ${row_c2}, out: ${out_c2})"
fi

# C3: --task-id PRESENT and mission has an H1 -> reserve row task_id == the --task-id
# (rule 1 wins; guards against this fix hijacking the fanout path, which always binds
# --task-id and must never have it overridden by mission prose).
c3_mission_file="${TMPDIR_ROOT}/c3-mission.md"
cat > "${c3_mission_file}" <<EOF
# N7F-C3-WRONG-NAME — must NOT win over the bound --task-id
body text, dispatch-ledger-task-id c3 $$ $(date +%s 2>/dev/null || echo 0)
EOF
C3_TASK_ID="N7F-C3-BOUND-ID"
out_c3="$(
  CLAUDE_PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
  LEADV2_DISPATCH_CACHE_DIR="${CACHE_DIR}" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${FAKE_SUBSESSION}" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
  LEADV2_JOURNAL_BIN=/bin/true \
  LEADV2_ROUTER_V2=0 \
  LEADV2_EXCLUDED_ARMS="__none__" \
  LEADV2_LANE_SHAPE=off \
  "${DISPATCH_SH}" "@${c3_mission_file}" --protected --spawn --kind docs --task-id "${C3_TASK_ID}" 2>&1
)"
rc_c3=$?
row_c3="$(tail -1 "${LEDGER_FILE}" 2>/dev/null)"
if [[ "${rc_c3}" -eq 0 ]] && grep -q "\"task_id\":\"${C3_TASK_ID}\"" <<<"${row_c3}"; then
  pass "C3: --task-id AND mission-H1 both present -> reserve row task_id == bound --task-id (rule 1 wins)"
else
  fail "C3: --task-id AND mission-H1 both present -> reserve row task_id == bound --task-id (got rc=${rc_c3}, row: ${row_c3}, out: ${out_c3})"
fi

# C4/C5 isolate the terminal ledger file the SAME way test-t-core-dispatch-ledger.sh
# does (LEADV2_DISPATCH_TERMINAL_LEDGER_FILE override) rather than re-deriving
# dispatch_terminal_ledger_file()'s CACHE_BASE fallback path here -- that fn tries
# leadv2-state-path.sh FIRST, which (unlike dispatch-code.sh's own simpler
# dispatch_ledger_file()) can resolve to a real path outside this test's sandbox even
# for an isolated tmp repo; the explicit override is what every other write-terminal
# test in this suite family relies on for hermeticity.
TERMINAL_LEDGER_FILE="${TMPDIR_ROOT}/terminal-ledger.jsonl"

# C4: leadv2-dispatch-ledger.sh write-terminal driven directly with a display-name 7th
# arg and an EMPTY founder -- covers the class=product terminal writer (dispatch-
# product-close.sh) without spawning a real close gate. Expect: task_id from the
# display name, founder_task_id stays empty.
C4_SIG8="c4sig888"
C4_NAME="N7F-C4-Display"
LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="${TERMINAL_LEDGER_FILE}" PROJECT_ROOT="${ROOT}" \
  LEADV2_JOURNAL_BIN=/bin/true \
  bash "${LEDGER_SH}" write-terminal "${C4_SIG8}" "" landed test_cause "" "attempt-c4" "${C4_NAME}" >/dev/null 2>&1
row_c4="$(grep -F "\"task_sig\":\"${C4_SIG8}\"" "${TERMINAL_LEDGER_FILE}" 2>/dev/null | tail -1)"
if grep -q "\"task_id\":\"${C4_NAME}\"" <<<"${row_c4}" && grep -q '"founder_task_id":""' <<<"${row_c4}"; then
  pass "C4: write-terminal with empty founder + display-name 7th arg -> task_id from display name, founder_task_id empty"
else
  fail "C4: write-terminal with empty founder + display-name 7th arg (got row: ${row_c4})"
fi

# C5: write-terminal with 6 args (no display name) -> task_id falls back to founder
# (back-compat: a pre-N7F-LANE-NAME caller's output is byte-identical).
C5_SIG8="c5sig888"
C5_FOUNDER="N7F-C5-Founder"
LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="${TERMINAL_LEDGER_FILE}" PROJECT_ROOT="${ROOT}" \
  LEADV2_JOURNAL_BIN=/bin/true \
  bash "${LEDGER_SH}" write-terminal "${C5_SIG8}" "${C5_FOUNDER}" landed test_cause "" "attempt-c5" >/dev/null 2>&1
row_c5="$(grep -F "\"task_sig\":\"${C5_SIG8}\"" "${TERMINAL_LEDGER_FILE}" 2>/dev/null | tail -1)"
if grep -q "\"task_id\":\"${C5_FOUNDER}\"" <<<"${row_c5}"; then
  pass "C5: write-terminal with 6 args (no display name) -> task_id falls back to founder (back-compat)"
else
  fail "C5: write-terminal with 6 args (no display name) -> task_id falls back to founder (got row: ${row_c5})"
fi

# ── N1B-ARM-COOLDOWN-HARDEN F4: identity vs display-label collision ───────────
# Finding 4: a no-`--task-id` mission headed `# OPS-42 — cleanup` used to land
# the H1 name-token "OPS-42" in the identity field, which the status reader then
# resolved against tasks.yaml -> rendered an UNRELATED record's title. After F4
# the label lives in lane_label (rendered verbatim, never looked up), so the row
# shows "OPS-42", not "Totally unrelated record".
RENDER_SH="${SCRIPTS_DIR}/leadv2-status-surface.sh"
F4_REPO="$(printf '%s' "$(basename "${ROOT}")" | tr -cd 'A-Za-z0-9._-')"
# render NOW ~= the reserve moment so the freshly-reserved row is within the
# freshness window (a dead handle at +166 days is age-dropped and never reaches
# resolve_name, which would make this test assert against nothing).
F4_NOW="$(date +%s 2>/dev/null || echo 1800000000)"

# tasks.yaml fixture: an OPS-42 id that is NOT this mission.
F4_TASKS="${TMPDIR_ROOT}/f4-tasks.yaml"
cat > "${F4_TASKS}" <<'YAML'
meta: {}
tasks:
  - id: OPS-42
    title: Totally unrelated record
YAML

# render the worker rows for one isolated ledger; echo the NAME (field 1) of the
# single data row. empty STATE_DIR (no active.yaml) -> reserve row renders as a
# worker row, name = resolve_name(task_id, lane_label, ...).
_f4_render_name() {  # <ledger_dir> <state_dir> <runs_root>
  LEADV2_STATUS_STATE_DIR="$2" \
  LEADV2_STATUS_LEDGER_DIR="$1" \
  LEADV2_STATUS_RUNS_ROOT="$3" \
  LEADV2_STATUS_REPO="${F4_REPO}" \
  LEADV2_STATUS_REPO_ROOT="${ROOT}" \
  LEADV2_STATUS_NOW="${F4_NOW}" \
  LEADV2_STATUS_TASKS_YAML="${F4_TASKS}" \
  bash "${RENDER_SH}" 2>/dev/null | awk '$NF ~ /^[0-9a-f]{6,}$/ {sub(/^ +/,""); sub(/ +(worker|lane) .*/,""); print; exit}'
}

# F4: NO --task-id, mission H1 `# OPS-42 — cleanup` -> renders "OPS-42" (the
# label verbatim), NOT "Totally unrelated record" (the tasks.yaml title).
F4A_CACHE="${TMPDIR_ROOT}/f4a-cache"; F4A_LDIR="${F4A_CACHE}/dispatch-ledger"
F4A_STATE="${TMPDIR_ROOT}/f4a-state"; F4A_RUNS="${TMPDIR_ROOT}/f4a-runs"
mkdir -p "${F4A_LDIR}" "${F4A_STATE}" "${F4A_RUNS}"
# an empty-but-readable active.yaml keeps the renderer on its normal row path
# (a missing active.yaml takes the warn branch and suppresses the worker row).
printf 'meta: {}\nsessions: []\n' > "${F4A_STATE}/active.yaml"
f4a_mission="${TMPDIR_ROOT}/f4a-mission.md"
cat > "${f4a_mission}" <<EOF
# OPS-42 — cleanup, N1B-F4 no-task-id $$ $(date +%s 2>/dev/null || echo 0)
body: display label must not collide with the tasks.yaml OPS-42 identity
EOF
LEADV2_DISPATCH_CACHE_DIR="${F4A_CACHE}" \
  CLAUDE_PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${FAKE_SUBSESSION}" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
  LEADV2_JOURNAL_BIN=/bin/true LEADV2_ROUTER_V2=0 \
  LEADV2_EXCLUDED_ARMS="__none__" LEADV2_LANE_SHAPE=off \
  "${DISPATCH_SH}" "@${f4a_mission}" --protected --spawn --kind docs >/dev/null 2>&1
f4a_name="$(_f4_render_name "${F4A_LDIR}" "${F4A_STATE}" "${F4A_RUNS}")"
if [[ "${f4a_name}" == "OPS-42" ]]; then
  pass "F4: no --task-id, mission H1 `# OPS-42 — cleanup` -> renders OPS-42 (not the tasks.yaml title)"
else
  fail "F4: no --task-id collision (got name=[${f4a_name}], want OPS-42)"
fi

# F4b: WITH --task-id OPS-42 + same fixture -> renders the tasks.yaml title
# (the identity lookup is PRESERVED; this guards against the fix over-reaching
# and breaking the bound-identity path).
F4B_CACHE="${TMPDIR_ROOT}/f4b-cache"; F4B_LDIR="${F4B_CACHE}/dispatch-ledger"
F4B_STATE="${TMPDIR_ROOT}/f4b-state"; F4B_RUNS="${TMPDIR_ROOT}/f4b-runs"
mkdir -p "${F4B_LDIR}" "${F4B_STATE}" "${F4B_RUNS}"
printf 'meta: {}\nsessions: []\n' > "${F4B_STATE}/active.yaml"
f4b_mission="${TMPDIR_ROOT}/f4b-mission.md"
cat > "${f4b_mission}" <<EOF
# OPS-42 — cleanup, N1B-F4b with-task-id $$ $(date +%s 2>/dev/null || echo 0)
body: bound --task-id OPS-42 must still resolve via tasks.yaml
EOF
LEADV2_DISPATCH_CACHE_DIR="${F4B_CACHE}" \
  CLAUDE_PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${FAKE_SUBSESSION}" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
  LEADV2_JOURNAL_BIN=/bin/true LEADV2_ROUTER_V2=0 \
  LEADV2_EXCLUDED_ARMS="__none__" LEADV2_LANE_SHAPE=off \
  "${DISPATCH_SH}" "@${f4b_mission}" --protected --spawn --kind docs --task-id OPS-42 >/dev/null 2>&1
f4b_name="$(_f4_render_name "${F4B_LDIR}" "${F4B_STATE}" "${F4B_RUNS}")"
if [[ "${f4b_name}" == "Totally unrelated record" ]]; then
  pass "F4b: --task-id OPS-42 -> renders the tasks.yaml title (identity lookup preserved)"
else
  fail "F4b: identity lookup (got name=[${f4b_name}], want 'Totally unrelated record')"
fi

printf '[TEST] === %s passed, %s failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
