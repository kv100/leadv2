#!/usr/bin/env bash
# tests/test-promise-guard.sh — offline tests for hooks/leadv2-promise-guard.sh
# Usage: bash tests/test-promise-guard.sh
# Exit 0 = all pass; non-zero = failure count.
#
# Each case builds a fixture JSONL in a temp dir, points
# LEADV2_PROMISE_GUARD_TRANSCRIPT at it, pipes a stub stdin JSON, and asserts the
# hook's stdout contains `"decision":"block"` (FIRES) or is empty (silent).
# HOME is redirected to the temp dir so sentinel + log writes are sandboxed.
set -euo pipefail

SCRIPT="${BASH_SOURCE[0]%/*}/../hooks/leadv2-promise-guard.sh"
PASS=0
FAIL=0

pass() { printf -- 'PASS: %s\n' "$1"; PASS=$(( PASS + 1 )); }
fail() { printf -- 'FAIL: %s\n' "$1"; FAIL=$(( FAIL + 1 )); }

# Build a fixture JSONL from lines on stdin. Lines starting with `A:` are
# assistant records (text after the prefix is the final text), `AT:` assistant
# with a tool_use, `U:` a real user record, `UR:` a tool_result-only user record.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
SID="test-session"

write_fixture() {
  local out="$1"; shift
  : > "$out"
  while [[ $# -gt 0 ]]; do
    printf '%s\n' "$1" >> "$out"
    shift
  done
}

# Emit JSONL records via python for correctness.
mk_assistant_text() {  # $1 = text
  python3 -c '
import json, sys
print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":sys.argv[1]}]}}))
' "$1"
}
mk_assistant_tool() {  # $1 = tool name, $2 = bash command (for Bash) or ""
  python3 -c '
import json, sys
name = sys.argv[1]; cmd = sys.argv[2]
inp = {"command": cmd} if name == "Bash" and cmd else {}
print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":name,"input":inp}]}}))
' "$1" "$2"
}
mk_assistant_tool_then_text() {  # $1 tool name, $2 bash cmd, $3 final text
  python3 -c '
import json, sys
name = sys.argv[1]; cmd = sys.argv[2]; text = sys.argv[3]
inp = {"command": cmd} if name == "Bash" and cmd else {}
print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":name,"input":inp}]}}))
print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":text}]}}))
' "$1" "$2" "$3"
}
mk_user_real() {  # $1 = text
  python3 -c '
import json, sys
print(json.dumps({"type":"user","message":{"role":"user","content":sys.argv[1]}}))
' "$1"
}
mk_user_toolresult() {
  python3 -c '
import json
print(json.dumps({"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}))
'
}

# run_case <fixture_lines...> -> stdout = hook stdout
run_case() {
  local fixture="$TMP/f.jsonl"
  write_fixture "$fixture" "$@"
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "$SID" "$fixture" "$TMP" \
    | env LEADV2_PROMISE_GUARD_TRANSCRIPT="$fixture" bash "$SCRIPT" 2>/dev/null || true
}

# run_case_env <env_assign> <fixture_lines...>
run_case_env() {
  local env_assign="$1"; shift
  local fixture="$TMP/f.jsonl"
  write_fixture "$fixture" "$@"
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","stop_hook_active":false}' "$SID" "$fixture" "$TMP" \
    | env $env_assign LEADV2_PROMISE_GUARD_TRANSCRIPT="$fixture" bash "$SCRIPT" 2>/dev/null || true
}

expect_fires() {  # $1 = label, $2 = actual stdout
  if printf '%s' "$2" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "$1"
  else
    fail "$1 (expected FIRES, got: $(printf '%s' "$2" | head -c 120))"
  fi
}
expect_silent() {  # $1 = label, $2 = actual stdout
  if [[ -z "$(printf '%s' "$2" | tr -d '[:space:]')" ]]; then
    pass "$1"
  else
    fail "$1 (expected silent, got: $(printf '%s' "$2" | head -c 120))"
  fi
}

PROMISE_RU="сейчас поднимаю наблюдателя"
PROMISE_EN="I'll dispatch the build agent now"

# --- Case 1: forward-tense + zero tools -> FIRES ----------------------------
OUT="$(run_case "$(mk_user_real "go")" "$(mk_assistant_text "$PROMISE_RU")")"
expect_fires "1: forward-tense + no tool_use -> FIRES" "$OUT"

# --- Case 2: same text + Edit in same turn -> silent -----------------------
OUT="$(run_case "$(mk_user_real "go")" "$(mk_assistant_tool Edit "")" "$(mk_assistant_text "$PROMISE_RU")")"
expect_silent "2: forward-tense + Edit -> silent" "$OUT"

# --- Case 3: same text + only Bash:grep -> FIRES ---------------------------
OUT="$(run_case "$(mk_user_real "go")" "$(mk_assistant_tool Bash "grep -rn foo .")" "$(mk_assistant_text "$PROMISE_RU")")"
expect_fires "3: forward-tense + only Bash grep -> FIRES (reading is not doing)" "$OUT"

# --- Case 4: past-tense + sha, no tools -> silent --------------------------
OUT="$(run_case "$(mk_user_real "go")" "$(mk_assistant_text "три линии ушли: ba541e6e")")"
expect_silent "4: past-tense + sha -> silent" "$OUT"

# --- Case 5: «сделал» alone, no sha, no tools -> silent (by design) --------
OUT="$(run_case "$(mk_user_real "go")" "$(mk_assistant_text "сделал")")"
expect_silent "5: «сделал» alone -> silent (commitment-triggered, not artifact-required)" "$OUT"

# --- Case 6: empty final text / tool-only turn -> silent -------------------
OUT="$(run_case "$(mk_user_real "go")" "$(mk_assistant_tool Bash "ls -la")")"
expect_silent "6: tool-only turn, no final text -> silent" "$OUT"

# --- Case 7: Edit in earlier assistant record, final text-only + I'll dispatch -> silent (turn-boundary regression)
OUT="$(run_case "$(mk_user_real "go")" "$(mk_assistant_tool Edit "")" "$(mk_assistant_text "$PROMISE_EN")")"
expect_silent "7: Edit in earlier record + final text promise -> silent (turn-boundary)" "$OUT"

# --- Case 8: «сейчас проверил логи», no tools -> silent (past-tense) -------
OUT="$(run_case "$(mk_user_real "go")" "$(mk_assistant_text "сейчас проверил логи")")"
expect_silent "8: «сейчас проверил логи» -> silent (past-tense)" "$OUT"

# --- Case 9: «I'll dispatch» + Agent spawn -> silent -----------------------
OUT="$(run_case "$(mk_user_real "go")" "$(mk_assistant_tool Agent "")" "$(mk_assistant_text "$PROMISE_EN")")"
expect_silent "9: I'll dispatch + Agent spawn -> silent" "$OUT"

# --- Case 10: «закоммитил <sha>, сейчас поднимаю наблюдателя», no tools -> FIRES, quote = promise clause
OUT="$(run_case "$(mk_user_real "go")" "$(mk_assistant_text "закоммитил 4eb4c304, сейчас поднимаю наблюдателя")")"
expect_fires "10: past-report + fresh unkept promise -> FIRES" "$OUT"
if printf '%s' "$OUT" | grep -q 'сейчас поднимаю наблюдателя' \
   && ! printf '%s' "$OUT" | grep -q 'закоммитил 4eb4c304, сейчас'; then
  pass "10b: quote = only the promise clause"
else
  fail "10b: quote should be only the promise clause (got: $(printf '%s' "$OUT" | head -c 200))"
fi

# --- Case 11: stop_hook_active=true + case-1 text -> silent (anti-loop) ----
FIXTURE="$TMP/f11.jsonl"
write_fixture "$FIXTURE" "$(mk_user_real "go")" "$(mk_assistant_text "$PROMISE_RU")"
OUT="$(printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","stop_hook_active":true}' "$SID" "$FIXTURE" "$TMP" \
     | env LEADV2_PROMISE_GUARD_TRANSCRIPT="$FIXTURE" bash "$SCRIPT" 2>/dev/null || true)"
expect_silent "11: stop_hook_active=true -> silent (anti-loop)" "$OUT"

# --- Case 12: LEADV2_PROMISE_GUARD=0 + case-1 text -> silent (kill switch) -
OUT="$(run_case_env "LEADV2_PROMISE_GUARD=0" "$(mk_user_real "go")" "$(mk_assistant_text "$PROMISE_RU")")"
expect_silent "12: LEADV2_PROMISE_GUARD=0 kill switch -> silent" "$OUT"

printf -- '\n%d/%d pass\n' "$PASS" "$(( PASS + FAIL ))"
[[ "$FAIL" -eq 0 ]]
