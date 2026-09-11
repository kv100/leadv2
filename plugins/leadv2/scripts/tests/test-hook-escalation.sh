#!/usr/bin/env bash
# test-hook-escalation.sh — HARD-BLOCK-WITHOUT-AN-ESCALATION-PATH-01
# run-all-triggers: leadv2-block-bash-heredoc.sh leadv2-deny-floor.sh leadv2-hook-escalation.sh
# Proves a real hook deny stays denied without a reason, a meaningful one-command
# escalation is journalled, and the closed destructive class cannot escalate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HEREDOC_HOOK="${PLUGIN_DIR}/hooks/leadv2-block-bash-heredoc.sh"
DENY_HOOK="${PLUGIN_DIR}/hooks/leadv2-deny-floor.sh"
JOURNAL="${PLUGIN_DIR}/scripts/leadv2-journal.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-hook-escalation.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

PASS=0
FAIL=0
SESSION_ID="hook-escalation-test"
REASON="recover blocked lane safely"
BIG_BODY="$(python3 -c 'print("x" * 2050)')"
HEREDOC_CMD="$(printf "cat <<'EOF'\\n%s\\nEOF" "${BIG_BODY}")"

pass() { printf 'PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name":"Bash", "tool_input":{"command":sys.argv[1]}, "session_id":sys.argv[2]}))' \
    "$1" "$SESSION_ID"
}

run_hook() { # <hook> <command> [reason]
  local hook="$1" command="$2" reason="${3:-}" input
  input="$(payload "$command")"
  set +e
  if [[ -n "$reason" ]]; then
    OUT="$(LEADV2_PROJECT_ROOT="$TMP_ROOT" LEADV2_HOOK_ESCALATE="$reason" bash "$hook" <<< "$input" 2>&1)"
  else
    OUT="$(LEADV2_PROJECT_ROOT="$TMP_ROOT" bash "$hook" <<< "$input" 2>&1)"
  fi
  RC=$?
  set -e
}

run_hook "$HEREDOC_HOOK" "$HEREDOC_CMD"
[[ "$RC" -eq 2 && "$OUT" == *"Bash command is"* ]] \
  && pass "heredoc without escalation remains denied" \
  || fail "heredoc without escalation rc=${RC} out=${OUT}"

run_hook "$HEREDOC_HOOK" "$HEREDOC_CMD" "oneword"
[[ "$RC" -eq 2 && "$OUT" == *"LEADV2_HOOK_ESCALATE"* ]] \
  && pass "one-word reason remains denied" \
  || fail "one-word reason rc=${RC} out=${OUT}"

run_hook "$HEREDOC_HOOK" "$HEREDOC_CMD" "$REASON"
JOURNAL_PATH="$(LEADV2_PROJECT_ROOT="$TMP_ROOT" bash "$JOURNAL" path "$SESSION_ID")"
if [[ "$RC" -eq 0 && -f "$JOURNAL_PATH" ]] \
  && grep -Fq "$HEREDOC_CMD" "$JOURNAL_PATH" \
  && grep -Fq "$REASON" "$JOURNAL_PATH" \
  && grep -Fq "leadv2-block-bash-heredoc" "$JOURNAL_PATH"; then
  pass "meaningful heredoc escalation passes and is journalled"
else
  fail "meaningful heredoc escalation rc=${RC} journal=${JOURNAL_PATH} out=${OUT}"
fi

run_hook "$DENY_HOOK" "git reset --hard" "$REASON"
[[ "$RC" -eq 2 && "$OUT" == *"not eligible for LEADV2_HOOK_ESCALATE"* ]] \
  && pass "reset --hard remains a closed non-escalatable class" \
  || fail "reset --hard rc=${RC} out=${OUT}"

# Mutation control: remove the validation branch inside the helper in a copied
# hook tree. The one-word fixture must now (incorrectly) pass; observing that
# red outcome proves the normal assertion is not ornamental.
MUTANT_ROOT="${TMP_ROOT}/mutant"
mkdir -p "${MUTANT_ROOT}"
cp -R "${PLUGIN_DIR}/hooks" "${MUTANT_ROOT}/hooks"
python3 - "$MUTANT_ROOT/hooks/lib/leadv2-hook-escalation.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = 'if ! lv2_hook_escalation_reason_valid "$reason"; then # escalation-reason-validation\n'
assert needle in s, 'mutation seam missing'
open(p, 'w').write(s.replace(needle, 'if false; then # escalation-reason-validation\n', 1))
PY
run_hook "${MUTANT_ROOT}/hooks/leadv2-block-bash-heredoc.sh" "$HEREDOC_CMD" "oneword"
[[ "$RC" -eq 0 ]] \
  && pass "MUTATION RED: removing reason validation lets one word through" \
  || fail "mutation control did not turn red rc=${RC} out=${OUT}"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
