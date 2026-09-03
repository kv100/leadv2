#!/usr/bin/env bash
# tests/nc-safety-doctrine-prose-collision.sh — NC1 (CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01)
#
# Proves T15 (body-only 'publish' homograph -> risk_class=none) actually
# bites: applies a one-line mutation INSIDE _fallback_estimate()'s body --
# restores the pre-fix behaviour of substring-matching SAFETY_TOKENS against
# the whole mission body (text_lower), the exact category error the lane
# exists to remove (CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01, the
# 'publish' homograph false positive). Runs the whole suite against that
# mutated copy via LEADV2_TEST_JUDGE_BIN, and PASSES only when the suite
# reports FAIL > 0. Mirrors nc-claude-account-collapse.sh's NC-SETUP-FAIL
# guard: if the target line ever changes shape, this script fails loudly
# instead of silently mutating nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${SCRIPTS_ROOT}/leadv2-task-judge.sh"
MUT="${SCRIPTS_ROOT}/.nc-mutated-leadv2-task-judge-prose-collision.sh"
trap 'rm -f "${MUT}"' EXIT

# Mutation: inside _fallback_estimate()'s body, OR the id/title token match
# with a whole-body substring scan for the same tokens -- restores the old
# defect this lane was filed to remove.
sed 's|title_hit = bool(title_tokens & set(SAFETY_TOKENS))|title_hit = bool(title_tokens \& set(SAFETY_TOKENS)) or any(k in text_lower for k in SAFETY_TOKENS)|' \
  "${SRC}" > "${MUT}" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "${SRC}" "${MUT}"; then
  echo "NC-SETUP-FAIL: mutation pattern not found (title_hit line changed shape? update this NC)" >&2
  exit 2
fi
chmod +x "${MUT}"

echo "--- NC1: running suite against mutated judge ($MUT) ---"
LEADV2_TEST_JUDGE_BIN="${MUT}" bash "${SCRIPT_DIR}/test-leadv2-task-judge.sh"
rc=$?
echo "--- NC1: suite exit=${rc} ---"
if (( rc != 0 )); then
  echo "NC-PASS: suite went red against the restored prose-collision matcher, as required"
  exit 0
fi
echo "NC-FAIL: suite stayed green with the prose-collision defect restored -- its assertions do not bite" >&2
exit 1
