#!/usr/bin/env bash
# tests/nc-safety-doctrine-title-blind.sh — NC2 (CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01)
#
# Proves T10/T13/T14 (the genuine safety_publish_payments mission is still
# caught) actually bite: applies a one-line mutation INSIDE
# _fallback_estimate()'s body -- forces the id/title matcher to always yield
# no match, so the resolver never selects risk_class=safety_publish_payments
# no matter what flag_source is in play. "We stopped the false positives"
# achieved by matching nothing at all is formally correct and operationally
# catastrophic (a real safety/publish/payments task would ship with no
# floor). Runs the whole suite against that mutated copy via
# LEADV2_TEST_JUDGE_BIN, and PASSES only when the suite reports FAIL > 0.
# Mirrors nc-claude-account-collapse.sh's NC-SETUP-FAIL guard: if the target
# line ever changes shape, this script fails loudly instead of silently
# mutating nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${SCRIPTS_ROOT}/leadv2-task-judge.sh"
MUT="${SCRIPTS_ROOT}/.nc-mutated-leadv2-task-judge-title-blind.sh"
trap 'rm -f "${MUT}"' EXIT

# Mutation: inside _fallback_estimate()'s body, force title_hit to always be
# False -- the selected flag_source ('title' today) never actually matches
# anything, regardless of mission content.
sed 's|title_hit = bool(title_tokens & set(SAFETY_TOKENS))|title_hit = False|' \
  "${SRC}" > "${MUT}" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "${SRC}" "${MUT}"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (title_hit line changed shape? update this NC)" >&2
  exit 2
fi
chmod +x "${MUT}"

echo "--- NC2: running suite against mutated judge ($MUT) ---"
LEADV2_TEST_JUDGE_BIN="${MUT}" bash "${SCRIPT_DIR}/test-leadv2-task-judge.sh"
rc=$?
echo "--- NC2: suite exit=${rc} ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red when the safety matcher was blinded to always-no-match, as required"
  exit 0
fi
echo "NC-FAIL: suite stayed green with the safety matcher blinded -- a real safety task would ship unflagged" >&2
exit 1
