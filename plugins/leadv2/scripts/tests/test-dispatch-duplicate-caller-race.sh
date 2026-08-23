#!/usr/bin/env bash
# test-dispatch-duplicate-caller-race.sh — wave2 round2 finding 1 regression.
#
# THE BUG: the non-Opus duplicate-signature refusal branch (leadv2-dispatch-code.sh's
# `case "${arc}" in 2) ... ;;` inside the candidate-arm loop) used to call
# `_dl_note "${sig8}" refused duplicate_task_signature ...` -- writing a terminal row for
# a caller that never actually ran anything. Because the terminal ledger is write-once
# per sig8, and the duplicate-refusal path is fast (a lock check) while the REAL winning
# caller's path is slow (reserve -> spawn worker -> confirm -> THEN write "landed"), the
# loser's "refused" row would very often land FIRST and permanently block the winner's
# true "landed" outcome from ever being recorded -- a successful dispatch misrecorded
# forever as a refusal.
#
# THIS TEST drives the REAL dispatch-code.sh (never a hand-reimplemented copy of the
# duplicate-signature logic) with two concurrent, non-Opus (sonnet-arm) callers racing
# the SAME mission signature -- same hermetic-fixture discipline as
# test-leadv2-dispatch-outcome-ledger.sh / test-routing-enforcement-p1.sh's own "racing
# reserves" case, extended to also inspect the terminal ledger's actual content, not just
# exit codes.
set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_SH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
source "${SCRIPTS_DIR}/leadv2-temp.sh"

PASS=0; FAIL=0; ERRORS=()
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); printf '[TEST] FAIL: %s\n' "$1"; }

RUN_ID="dispatch-race-$$-$(date +%s 2>/dev/null || echo 0)"
TMPDIR_ROOT="$(lv2_mktemp_dir "${RUN_ID}")"
ROOT="${TMPDIR_ROOT}/repo"
CACHE_DIR="${TMPDIR_ROOT}/cache"
LEDGER_FILE="${TMPDIR_ROOT}/terminal-ledger.jsonl"
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

# Same fake launcher shape as test-leadv2-dispatch-outcome-ledger.sh: spawns a real,
# short-lived OS process and prints its PID in the exact shape spawn_worker's sonnet-arm
# parser expects. A small random delay on ONE of the two racers (below, via
# LEADV2_DISPATCH_RACE_DELAY) is what lets the SECOND caller's reservation attempt land
# while the first is still mid-flight, without making the test flaky on timing alone --
# the real race is the reservation lock itself (atomic_dispatch_reserve_spawn_confirm),
# not this launcher.
cat > "${FAKE_SUBSESSION}" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
sleep "${LEADV2_DISPATCH_RACE_DELAY:-0}"
nohup sleep 0.3 >/dev/null 2>&1 &
pid=$!
disown
printf 'PID=%s LABEL=fake-lane SESSION_ID=fake-session\n' "${pid}"
exit 0
EOF
chmod +x "${FAKE_SUBSESSION}"

_dispatch() {  # <mission> <race-delay>
  ( CLAUDE_PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
    LEADV2_DISPATCH_CACHE_DIR="${CACHE_DIR}" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${FAKE_SUBSESSION}" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_JOURNAL_BIN=/bin/true \
    LEADV2_ROUTER_V2=0 \
    LEADV2_EXCLUDED_ARMS="__none__" \
    LEADV2_LANE_SHAPE=off \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="${LEDGER_FILE}" \
    LEADV2_DISPATCH_RACE_DELAY="$2" \
    "${DISPATCH_SH}" "$1" --protected --spawn )
}

_sig8_from_output() {  # <dispatch stdout> -> task signature prefix
  sed -n 's/.*task=\([a-f0-9][a-f0-9]*\).*/\1/p' <<<"$1" | tail -1
}

# "docs-only" prefix forces classify_product_work() to non_product (explicit_mission_
# fast_path) so the WINNING caller writes its terminal row (landed) immediately after a
# successful spawn -- a product-classified mission's terminal state instead belongs to
# dispatch-product-close.sh (a separate script), which this hermetic fixture does not
# exercise, and this test needs the WINNER'S own write to prove the race.
mission="docs-only: duplicate-caller-race $$ $(date +%s)"

# Racer A gets a small artificial delay INSIDE its (already-reserved) spawn step -- this
# reliably reproduces the historical race shape (the duplicate-refusal loser finishes
# fast; the eventual winner's landed-write comes later) regardless of which of the two
# actually wins dispatch_reserve's atomic lock.
out_a=""
out_b=""
CLAUDE_PROJECT_ROOT="${ROOT}" _tmp_a="${TMPDIR_ROOT}/out-a" _tmp_b="${TMPDIR_ROOT}/out-b"
( _dispatch "${mission}" 0.3 > "${_tmp_a}" 2>&1; echo $? > "${TMPDIR_ROOT}/rc-a" ) &
pid_a=$!
sleep 0.05
( _dispatch "${mission}" 0 > "${_tmp_b}" 2>&1; echo $? > "${TMPDIR_ROOT}/rc-b" ) &
pid_b=$!
wait "${pid_a}"
wait "${pid_b}"
out_a="$(cat "${_tmp_a}")"; rc_a="$(cat "${TMPDIR_ROOT}/rc-a")"
out_b="$(cat "${_tmp_b}")"; rc_b="$(cat "${TMPDIR_ROOT}/rc-b")"

successes=0; [[ "${rc_a}" -eq 0 ]] && successes=$((successes + 1)); [[ "${rc_b}" -eq 0 ]] && successes=$((successes + 1))
refusals=0;  [[ "${rc_a}" -eq 2 ]] && refusals=$((refusals + 1));  [[ "${rc_b}" -eq 2 ]] && refusals=$((refusals + 1))

if [[ ${successes} -eq 1 && ${refusals} -eq 1 ]]; then
  pass "exactly one racer wins (rc=0), exactly one is refused (rc=2)"
else
  fail "setup: expected 1 success + 1 refusal, got successes=${successes} refusals=${refusals} (rc_a=${rc_a} rc_b=${rc_b}) out_a=${out_a} out_b=${out_b}"
fi

sig8="$(_sig8_from_output "${out_a}")"
[[ -n "${sig8}" ]] || sig8="$(_sig8_from_output "${out_b}")"

if [[ -n "${sig8}" && -f "${LEDGER_FILE}" ]]; then
  rows="$(grep -c "\"task_sig\":\"${sig8}\"" "${LEDGER_FILE}" 2>/dev/null || echo 0)"
  if [[ "${rows}" -eq 1 ]]; then
    pass "exactly one terminal row exists for the shared sig8 (write-once held under the race)"
  else
    fail "expected exactly 1 terminal row for sig8=${sig8}, found ${rows} -- $(grep "\"${sig8}\"" "${LEDGER_FILE}" 2>/dev/null)"
  fi

  row="$(grep "\"task_sig\":\"${sig8}\"" "${LEDGER_FILE}" 2>/dev/null)"
  if grep -q '"terminal":"landed"' <<<"${row}"; then
    pass "the ONE terminal row records the WINNER's landed outcome, not the loser's refusal"
  else
    fail "the terminal row does not say landed -- the loser's refusal won the write-once race (the exact wave2 round2 finding 1 regression): ${row}"
  fi
else
  fail "setup: no sig8 extracted from dispatch output, or ledger file never created (out_a=${out_a} out_b=${out_b})"
fi

printf '\n[TEST] %s passed, %s failed\n' "${PASS}" "${FAIL}"
if (( FAIL > 0 )); then
  printf '[TEST] Failures:\n'
  for e in "${ERRORS[@]}"; do printf '  - %s\n' "$e"; done
  exit 1
fi
exit 0
