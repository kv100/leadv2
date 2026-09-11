#!/usr/bin/env bash
# test-deploy-judge-is-a-gate.sh — negative control for
# DEPLOY-JUDGE-IS-ADVISORY-AND-NORMALIZES-KNOWN-BAD-01.
#
# f3-judge.md findings 1+2: the deploy LLM-judge was advisory (nothing
# consumed its verdict rc) and known-bad results (parse error, cost-ceiling
# skip) were normalized into an admissible go-with-caveats. This suite
# proves leadv2-llm-judge-gate.sh actually refuses every known-bad state and
# passes every legitimate one — a red run here means the gate stopped
# being load-bearing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="${PROJECT_ROOT}/plugins/leadv2/scripts/leadv2-llm-judge-gate.sh"
PARSE="${PROJECT_ROOT}/plugins/leadv2/scripts/leadv2-llm-judge-parse.sh"

fail=0
pass=0

assert_rc() {
  local desc="$1" expect_rc="$2"; shift 2
  local actual_rc=0
  "$@" >/tmp/tdjg-out.$$ 2>&1 || actual_rc=$?
  if [[ "$actual_rc" -eq "$expect_rc" ]]; then
    echo "PASS: $desc (rc=$actual_rc)"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc — expected rc=$expect_rc, got rc=$actual_rc"
    cat /tmp/tdjg-out.$$
    fail=$((fail + 1))
  fi
  rm -f /tmp/tdjg-out.$$
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tdjg-XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

write_verdict() {
  local task="$1" body="$2"
  mkdir -p "${TMP_ROOT}/docs/handoff/${task}"
  printf '%s\n' "$body" > "${TMP_ROOT}/docs/handoff/${task}/llm-judge.yaml"
}

# --- Known-bad states: gate MUST refuse (nonzero) ---------------------------

write_verdict "t-no-go" 'llm_judge:
  verdict: no-go
  overall_risk: 2.0'
assert_rc "known-bad: verdict=no-go is refused" 1 \
  bash "$GATE" --task-id t-no-go --project-root "$TMP_ROOT"

write_verdict "t-unavailable-ceiling" 'llm_judge:
  verdict: judge_unavailable
  skip_reason: cost_ceiling_hard_stop'
assert_rc "known-bad: verdict=judge_unavailable (cost ceiling) is refused" 1 \
  bash "$GATE" --task-id t-unavailable-ceiling --project-root "$TMP_ROOT"

write_verdict "t-unavailable-parse" 'llm_judge:
  verdict: judge_unavailable
  parse_error: "mapping values are not allowed here"'
assert_rc "known-bad: verdict=judge_unavailable (parse error) is refused" 1 \
  bash "$GATE" --task-id t-unavailable-parse --project-root "$TMP_ROOT"

assert_rc "known-bad: missing verdict file is refused, not treated as pass" 1 \
  bash "$GATE" --task-id t-does-not-exist --project-root "$TMP_ROOT"

write_verdict "t-corrupt" ': this is not valid yaml: [ [ [ '
assert_rc "known-bad: unreadable/corrupt verdict file is refused" 1 \
  bash "$GATE" --task-id t-corrupt --project-root "$TMP_ROOT"

# --- Legitimate states: gate MUST pass (zero) --------------------------------

write_verdict "t-go" 'llm_judge:
  verdict: go
  overall_risk: 2.0'
assert_rc "good: verdict=go passes" 0 \
  bash "$GATE" --task-id t-go --project-root "$TMP_ROOT"

write_verdict "t-caveats" 'llm_judge:
  verdict: go-with-caveats
  overall_risk: 5.5'
assert_rc "good: verdict=go-with-caveats passes" 0 \
  bash "$GATE" --task-id t-caveats --project-root "$TMP_ROOT"

write_verdict "t-light-skip" 'llm_judge:
  verdict: go
  skipped: true
  skip_reason: "Light+clean: offlimits clean, premortem proceed, hack block=0"'
assert_rc "good: legitimate Light+clean skip passes" 0 \
  bash "$GATE" --task-id t-light-skip --project-root "$TMP_ROOT"

# --- Parser-level control: a malformed judge response must land as a refusal,
#     not a silently-passing go-with-caveats (this is the exact finding-2
#     regression: parse error used to write go-with-caveats + exit 3).
mkdir -p "${TMP_ROOT}/docs/handoff/t-parse-err"
printf 'this is: not, [valid} yaml: {{{\n' > "${TMP_ROOT}/response.txt"
parse_rc=0
bash "$PARSE" --task-id t-parse-err --response-file "${TMP_ROOT}/response.txt" \
  --project-root "$TMP_ROOT" >/tmp/tdjg-parse.$$ 2>&1 || parse_rc=$?
if [[ "$parse_rc" -eq 1 ]]; then
  echo "PASS: parser rc=1 on malformed judge response (was silently 3/go-with-caveats)"
  pass=$((pass + 1))
else
  echo "FAIL: parser rc on malformed response — expected 1, got $parse_rc"
  cat /tmp/tdjg-parse.$$
  fail=$((fail + 1))
fi
rm -f /tmp/tdjg-parse.$$
assert_rc "good: gate refuses the verdict the parser just wrote for a malformed response" 1 \
  bash "$GATE" --task-id t-parse-err --project-root "$TMP_ROOT"

echo "---"
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
