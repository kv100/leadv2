#!/usr/bin/env bash
# changed-scope triggers, self-registered:
# run-all-triggers: leadv2-dispatch-product-close
# plugins/leadv2/tests/test-review-rounds-scale-with-complexity.sh — A6-REVIEW-ROUNDS
# (PRE-WAVES-PLAN.md row A6): does review run N rounds scaled by complexity,
# and does a round that finds something lead to another round?
#
# MEASUREMENT this suite pins (2026-09-09, real journals — full evidence in
# docs/handoff/A6-REVIEW-ROUNDS/report.md):
#   Q1 the round number is decided at leadv2-dispatch-code.sh:4655-4659
#      (trivial|simple->1, standard->2, else->3 from effective complexity),
#      journaled at :4838 (complexity_gate_applied ... review_rounds=N),
#      env-threaded at :6072, consumed by _pc_review_round_ceiling here.
#   Q2 it changes with class: 50 live lanes standard->2, 23 complex->3
#      (dispatch-d6cd245f, Heavy class_source=escalated -> complexity=complex
#      -> review_rounds=3). trivial->1 has no live instance yet — pinned here
#      by construction (default_is_named + the mut-1 control).
#   Q3 a finding does lead to another round — persona-engine dispatch-2f652446
#      journaled review_round_retry round=1 ceiling=3 on a selfcheck_failed
#      verdict. BUT its round 2 resolved ceiling=2: the advance-arm successor
#      close gate lost LEADV2_DISPATCH_REVIEW_ROUNDS (threaded at exactly one
#      site — the initial spawn) and the journal fallback read a journal with
#      no complexity_gate_applied line, so the §3 default 2 silently ate the
#      complex lane's third round. successor_keeps_ceiling below is that lane,
#      replayed; the fix pins the ceiling to ${HANDOFF}/.review-round-ceiling
#      on first resolution and names ceiling_source= on every decision line.
#
# Harness (test-close-chain.sh scope note applies — the multi-thousand-line
# close script is not driven end to end): the REAL _pc_review_round_ceiling
# and _pc_review_round_retry are extracted byte-for-byte from the live script
# at run time and driven with stubbed emit/journal/dispatcher bins in scratch
# dirs. Extraction is loud: a renamed or moved function is a FATAL here,
# never a silent no-op, so the suite cannot drift green past a refactor.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), applied by
# leadv2-mutation-control.sh to the marked lines INSIDE function bodies
# (never at top level). Both must turn THIS suite red:
#   M1 a6-mut-1 — force the ceiling to 1 regardless of complexity (the row's
#   symptom, one round for everything):
#     leadv2-mutation-control.sh plugins/leadv2/tests/test-review-rounds-scale-with-complexity.sh \
#       plugins/leadv2/scripts/leadv2-dispatch-product-close.sh \
#       's|return 0  # a6-mut-1: forced-collapse anchor.*|_PC_CEILING=1|'
#     -> env_scale_complex / successor_keeps_ceiling / journal_source /
#        default_is_named / exhausted_at_ceiling / sticky_wins RED: every
#        budget collapses to one round.
#   M2 a6-mut-2 — make the follow-up round unreachable (a round-1 finding
#   terminates exactly like a clean lane):
#     leadv2-mutation-control.sh plugins/leadv2/tests/test-review-rounds-scale-with-complexity.sh \
#       plugins/leadv2/scripts/leadv2-dispatch-product-close.sh \
#       's|if (( round >= ceiling )); then|if (( round >= 0 )); then|'
#     -> env_scale_complex / successor_keeps_ceiling / journal_source /
#        sticky_wins RED: no finding ever produces a next round.
#        (default_is_named / exhausted_at_ceiling stay green under M2 — one
#        round IS their expected outcome; the mutation is caught by the
#        handoff cases, which is the point of the control.)
#
# Portable: bash 3.2. Run from anywhere:
#   bash plugins/leadv2/tests/test-review-rounds-scale-with-complexity.sh
set -uo pipefail
export LEADV2_TEST_CONTEXT="${LEADV2_TEST_CONTEXT:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
PC="${LEADV2_TEST_PRODUCT_CLOSE:-$ROOT/plugins/leadv2/scripts/leadv2-dispatch-product-close.sh}"
[[ -f "$PC" ]] || { echo "FAIL: product-close not found at $PC" >&2; exit 1; }

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/a6rr.XXXXXX")"
trap 'rm -rf "${SCRATCH}"' EXIT

# Extract the REAL functions from the live script — loud on drift.
FUNCS="${SCRATCH}/funcs.inc"
awk '/^_pc_review_round_ceiling\(\) \{/,/^\}$/' "$PC" > "$FUNCS"
awk '/^_pc_review_round_retry\(\) \{/,/^\}$/' "$PC" >> "$FUNCS"
grep -q '^_pc_review_round_ceiling() {' "$FUNCS" \
  || { echo "FATAL: _pc_review_round_ceiling not extractable from $PC" >&2; exit 1; }
grep -q '^_pc_review_round_retry() {' "$FUNCS" \
  || { echo "FATAL: _pc_review_round_retry not extractable from $PC" >&2; exit 1; }

# Stub bins the extracted functions call.
JOURNAL_BIN="${SCRATCH}/journal-stub.sh"
cat > "$JOURNAL_BIN" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "tail" && -n "${A6_JOURNAL_FIXTURE:-}" && -f "${A6_JOURNAL_FIXTURE}" ]]; then
  cat "${A6_JOURNAL_FIXTURE}"
fi
exit 0
STUB
DISPATCH_BIN="${SCRATCH}/dispatch-stub.sh"
cat > "$DISPATCH_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${A6_DISPATCH_LOG:?}"
exit 0
STUB
chmod +x "$JOURNAL_BIN" "$DISPATCH_BIN"
export A6_JOURNAL_FIXTURE=""

emit() { printf '%s\n' "$*" >> "${EMIT_LOG:?}"; }

CASE_N=0
# fresh_env <case-slug> -> unique TASK + fresh HANDOFF/mission/logs per case.
fresh_env() {
  CASE_N=$((CASE_N + 1))
  local d="${SCRATCH}/$1"
  TASK="a6case$(printf '%02d' "${CASE_N}")ab01"
  HANDOFF="${d}/docs/handoff/dispatch-${TASK}"
  mkdir -p "${HANDOFF}"
  ROOT="${d}"
  AUTHOR="glm"
  FOUNDER_TASK_ID="A6-CASE-${CASE_N}"
  WRITES_CSV=""
  _lane_root=""
  LEADV2_REVIEW_ROUND_RETRY=1
  LEADV2_DISPATCH_LANE_MISSION="${HANDOFF}/lane-mission.md"
  printf 'mission: make the failing suite green\n' > "${LEADV2_DISPATCH_LANE_MISSION}"
  EMIT_LOG="${d}/emit.log"; : > "${EMIT_LOG}"
  A6_DISPATCH_LOG="${d}/dispatch.log"; export A6_DISPATCH_LOG; : > "${A6_DISPATCH_LOG}"
  unset LEADV2_DISPATCH_REVIEW_ROUNDS || true
}

# Load the REAL functions AFTER emit/stubs exist (they are called at
# runtime, so order only matters for readability — kept adjacent anyway).
# shellcheck source=/dev/null
source "$FUNCS"
# bash-guard: allow

# c1 — Q2/Q3 pin: a Heavy/complex lane (dispatcher-derived ceiling 3) whose
# round-1 selfcheck FAILED must hand off round 2, and the journal must say
# the ceiling AND where it came from.
env_scale_complex() {
  fresh_env "c1"
  LEADV2_DISPATCH_REVIEW_ROUNDS=3
  rc=0; _pc_review_round_retry "falsification:suite/red:test_failed" || rc=$?
  unset LEADV2_DISPATCH_REVIEW_ROUNDS
  [[ $rc -eq 0 ]] || { fail "env_scale_complex: rc=$rc, expected handed-off rc0"; return 1; }
  grep -q "review_round_retry task=${TASK} round=1 ceiling=3 ceiling_source=env reason=selfcheck_failed" "${EMIT_LOG}" \
    || { fail "env_scale_complex: decision line missing ceiling=3 or ceiling_source=env: $(cat "${EMIT_LOG}")"; return 1; }
  [[ "$(cat "${HANDOFF}/.review-round-ceiling" 2>/dev/null)" == "3" ]] \
    || { fail "env_scale_complex: sticky ceiling not pinned to 3"; return 1; }
  [[ "$(cat "${HANDOFF}/.review-round" 2>/dev/null)" == "1" ]] \
    || { fail "env_scale_complex: round marker not consumed (expected 1)"; return 1; }
  grep -q "advance-arm" "${A6_DISPATCH_LOG}" \
    || { fail "env_scale_complex: successor round not dispatched via advance-arm"; return 1; }
  pass "env_scale_complex: complex(3) round-1 finding -> round-2 handoff, ceiling_source=env"
}

# c2 — THE MEASURED DEFECT, replayed (persona-engine dispatch-2f652446,
# 2026-09-08): the advance-arm successor close gate has NO env (single
# threading site) and its journal has NO complexity_gate_applied line. Round
# 2 must still resolve ceiling 3 from the lane's own sticky marker — never
# the silent §3 default 2 that ate the live lane's third round.
successor_keeps_ceiling() {
  fresh_env "c2"
  printf '1\n' > "${HANDOFF}/.review-round"
  printf '3\n' > "${HANDOFF}/.review-round-ceiling"
  rc=0; _pc_review_round_retry "falsification:suite/red:test_failed" || rc=$?
  [[ $rc -eq 0 ]] \
    || { fail "successor_keeps_ceiling: rc=$rc — ceiling collapsed (the measured 3->2 shrink is back)"; return 1; }
  grep -q "review_round_retry task=${TASK} round=2 ceiling=3 ceiling_source=marker reason=selfcheck_failed" "${EMIT_LOG}" \
    || { fail "successor_keeps_ceiling: expected round=2 ceiling=3 ceiling_source=marker, got: $(cat "${EMIT_LOG}")"; return 1; }
  pass "successor_keeps_ceiling: env-less successor keeps ceiling=3 via marker"
}

# c3 — journal-fallback source: no env, no marker, but the task's journal
# carries its complexity_gate_applied line -> ceiling 3, named as journal.
journal_source() {
  fresh_env "c3"
  A6_JOURNAL_FIXTURE="${SCRATCH}/c3/journal.md"; export A6_JOURNAL_FIXTURE
  printf '%s\n' "- 2026-09-08T23:17:25Z [decision] complexity_gate_applied task=${TASK} complexity=complex complexity_source=flag pipeline_route=plan_first forced_plan=0 review_rounds=3" > "${A6_JOURNAL_FIXTURE}"
  rc=0; _pc_review_round_retry "falsification:suite/red:test_failed" || rc=$?
  [[ $rc -eq 0 ]] || { fail "journal_source: rc=$rc, expected handoff from journal-derived 3"; return 1; }
  grep -q "review_round_retry task=${TASK} round=1 ceiling=3 ceiling_source=journal reason=selfcheck_failed" "${EMIT_LOG}" \
    || { fail "journal_source: expected ceiling=3 ceiling_source=journal, got: $(cat "${EMIT_LOG}")"; return 1; }
  pass "journal_source: complexity_gate_applied line resolves ceiling=3, named"
}

# c4 — named degradation: nothing derivable (no env, no marker, empty
# journal). The §3 default 2 must be exercised as a NAMED outcome — an
# unremarked single round is exactly the disease this row exists for.
default_is_named() {
  fresh_env "c4"
  printf '1\n' > "${HANDOFF}/.review-round"
  rc=0; _pc_review_round_retry "falsification:suite/red:test_failed" || rc=$?
  [[ $rc -eq 1 ]] || { fail "default_is_named: rc=$rc, expected exhausted rc1 at default ceiling"; return 1; }
  grep -q "review_round_exhausted task=${TASK} round=2 ceiling=2 ceiling_source=default reason=selfcheck_failed" "${EMIT_LOG}" \
    || { fail "default_is_named: default ceiling not NAMED: $(cat "${EMIT_LOG}")"; return 1; }
  pass "default_is_named: underivable budget degrades loudly (ceiling=2 ceiling_source=default)"
}

# c5 — the budget ENDS at the right number: third round offered of three
# consumed -> exhausted at round 3, ceiling 3, from the marker.
exhausted_at_ceiling() {
  fresh_env "c5"
  printf '2\n' > "${HANDOFF}/.review-round"
  printf '3\n' > "${HANDOFF}/.review-round-ceiling"
  rc=0; _pc_review_round_retry "falsification:suite/red:test_failed" || rc=$?
  [[ $rc -eq 1 ]] || { fail "exhausted_at_ceiling: rc=$rc, expected exhausted rc1 at round 3 of 3"; return 1; }
  grep -q "review_round_exhausted task=${TASK} round=3 ceiling=3 ceiling_source=marker reason=selfcheck_failed" "${EMIT_LOG}" \
    || { fail "exhausted_at_ceiling: expected round=3 ceiling=3 ceiling_source=marker, got: $(cat "${EMIT_LOG}")"; return 1; }
  pass "exhausted_at_ceiling: complex lane ends at round 3 of 3, loudly"
}

# c6 — kill switch preserves the pre-gate single-pass refusal byte-for-byte.
kill_switch() {
  fresh_env "c6"
  LEADV2_REVIEW_ROUND_RETRY=0
  rc=0; _pc_review_round_retry "falsification:suite/red:test_failed" || rc=$?
  [[ $rc -eq 1 ]] || { fail "kill_switch: rc=$rc, expected rc1"; return 1; }
  grep -q "review_round_retry_skipped task=${TASK} reason=kill_switch" "${EMIT_LOG}" \
    || { fail "kill_switch: no kill_switch decision line"; return 1; }
  [[ ! -f "${HANDOFF}/.review-round-ceiling" ]] \
    || { fail "kill_switch: budget pinned despite kill switch"; return 1; }
  pass "kill_switch: single-pass refusal preserved, no budget pinned"
}

# c7 — stickiness wins in BOTH directions: a successor that somehow gets a
# different env value must not change the lane's already-pinned budget.
sticky_wins() {
  fresh_env "c7"
  printf '1\n' > "${HANDOFF}/.review-round"
  printf '3\n' > "${HANDOFF}/.review-round-ceiling"
  LEADV2_DISPATCH_REVIEW_ROUNDS=2
  rc=0; _pc_review_round_retry "falsification:suite/red:test_failed" || rc=$?
  unset LEADV2_DISPATCH_REVIEW_ROUNDS
  [[ $rc -eq 0 ]] || { fail "sticky_wins: rc=$rc, expected handoff at pinned 3"; return 1; }
  grep -q "review_round_retry task=${TASK} round=2 ceiling=3 ceiling_source=marker reason=selfcheck_failed" "${EMIT_LOG}" \
    || { fail "sticky_wins: marker must beat a later env of 2, got: $(cat "${EMIT_LOG}")"; return 1; }
  pass "sticky_wins: pinned ceiling 3 beats conflicting env 2"
}

main() {
  echo "A6-REVIEW-ROUNDS: review rounds scale with complexity (real functions from ${PC##*/})"
  env_scale_complex; successor_keeps_ceiling; journal_source
  default_is_named; exhausted_at_ceiling; kill_switch; sticky_wins
  echo "----"
  echo "pass=${PASS} fail=${FAIL}"
  [[ $FAIL -eq 0 ]] || { echo "SUITE RED"; exit 1; }
  echo "SUITE GREEN"; exit 0
}
main "$@"
# bash-guard: allow
