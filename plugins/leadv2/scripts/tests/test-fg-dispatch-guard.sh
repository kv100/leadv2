#!/usr/bin/env bash
# DISPATCH-FG-GUARD-01 — offline regression for leadv2-block-fg-dispatch.sh hook.
# Tests: deny foreground launcher, allow backgrounded, allow exemptions, allow override,
# fail-open on malformed/empty stdin, hooks.json validity, trailing-& regex precision.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/leadv2-block-fg-dispatch.sh"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf -- '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf -- '[TEST] FAIL: %s\n' "$1"; }

# --- Helper: invoke hook with JSON payload, capture exit code and stderr ---
run_hook() {
  local json="$1"
  printf '%s' "$json" | bash "$HOOK" 2>/tmp/fg-guard-stderr.$$ ; local rc=$?
  cat /tmp/fg-guard-stderr.$$ >/tmp/fg-guard-last-stderr
  rm -f /tmp/fg-guard-stderr.$$
  return $rc
}

make_payload() {
  # $1 = command, $2 = run_in_background (optional: "true"/"false"/omit)
  python3 -c "
import json, sys
cmd = sys.argv[1]
ti = {'command': cmd}
if len(sys.argv) > 2:
    ti['run_in_background'] = sys.argv[2] == 'true'
print(json.dumps({'tool_name': 'Bash', 'tool_input': ti}))
" "$1" "${2:-}"
}

# ================================================================
# 1. Foreground dispatch launcher → DENY (exit 2)
# ================================================================
payload="$(make_payload 'bash leadv2-dispatch-code.sh @mission.md')"
if run_hook "$payload"; then
  fail "foreground dispatch should be denied"
else
  rc=$?
  if [[ $rc -eq 2 ]]; then
    if grep -q '\[leadv2-block-fg-dispatch\] BLOCKED' /tmp/fg-guard-last-stderr && \
       grep -q 'SIGTERM' /tmp/fg-guard-last-stderr && \
       grep -q 'Run this instead:' /tmp/fg-guard-last-stderr && \
       grep -q 'leadv2-dispatch-code.sh @mission.md &' /tmp/fg-guard-last-stderr; then
      pass "foreground dispatch denied with correct message"
    else
      fail "deny message missing required content"
    fi
  else
    fail "foreground dispatch exited $rc, expected 2"
  fi
fi

# ================================================================
# 2. Backgrounded (trailing &) → ALLOW (exit 0)
# ================================================================
payload="$(make_payload 'bash leadv2-dispatch-code.sh @mission.md &')"
run_hook "$payload" && pass "trailing-& dispatch allowed" \
  || fail "trailing-& dispatch should be allowed"

# ================================================================
# 3. run_in_background=true → ALLOW
# ================================================================
payload="$(make_payload 'bash leadv2-dispatch-code.sh @mission.md' true)"
run_hook "$payload" && pass "run_in_background=true allowed" \
  || fail "run_in_background=true should be allowed"

# ================================================================
# 4. run_in_background absent, no & → DENY (tri-state: absent is not true)
# ================================================================
payload="$(make_payload 'bash leadv2-dispatch-code.sh @mission.md')"
if run_hook "$payload"; then
  fail "absent run_in_background + no & should deny"
else
  pass "absent run_in_background + no & denied"
fi

# ================================================================
# 5. Exemption: --no-spawn → ALLOW
# ================================================================
payload="$(make_payload 'bash leadv2-dispatch-code.sh --no-spawn @mission.md')"
run_hook "$payload" && pass "--no-spawn allowed" \
  || fail "--no-spawn should be allowed"

# ================================================================
# 6. Exemption: LEADV2_DISPATCH_SPAWN=0 → ALLOW
# ================================================================
payload="$(make_payload 'LEADV2_DISPATCH_SPAWN=0 bash leadv2-dispatch-code.sh @mission.md')"
run_hook "$payload" && pass "LEADV2_DISPATCH_SPAWN=0 allowed" \
  || fail "LEADV2_DISPATCH_SPAWN=0 should be allowed"

# ================================================================
# 7. Exemption: --help → ALLOW
# ================================================================
payload="$(make_payload 'bash leadv2-dispatch-code.sh --help')"
run_hook "$payload" && pass "--help allowed" \
  || fail "--help should be allowed"

# ================================================================
# 8. Exemption: status subcommand → ALLOW
# ================================================================
payload="$(make_payload 'bash leadv2-dispatch-code.sh status')"
run_hook "$payload" && pass "status subcommand allowed" \
  || fail "status subcommand should be allowed"

# ================================================================
# 9. Exemption: record-review subcommand → ALLOW
# ================================================================
payload="$(make_payload 'bash leadv2-dispatch-code.sh record-review')"
run_hook "$payload" && pass "record-review subcommand allowed" \
  || fail "record-review subcommand should be allowed"

# ================================================================
# 10. Override comment → ALLOW
# ================================================================
payload="$(make_payload 'bash leadv2-dispatch-code.sh @mission.md # fg-dispatch: allow')"
run_hook "$payload" && pass "# fg-dispatch: allow override works" \
  || fail "# fg-dispatch: allow should override"

# ================================================================
# 11. Env override LEADV2_ALLOW_FG_DISPATCH=1 → ALLOW
# ================================================================
payload="$(make_payload 'bash leadv2-dispatch-code.sh @mission.md')"
printf '%s' "$payload" | LEADV2_ALLOW_FG_DISPATCH=1 bash "$HOOK" 2>/dev/null \
  && pass "LEADV2_ALLOW_FG_DISPATCH=1 env override works" \
  || fail "LEADV2_ALLOW_FG_DISPATCH=1 should override"

# ================================================================
# 12. Non-matching command → ALLOW
# ================================================================
payload="$(make_payload 'grep -n foo leadv2-temp.sh')"
run_hook "$payload" && pass "non-matching command allowed" \
  || fail "non-matching command should be allowed"

# ================================================================
# 13. Empty stdin → ALLOW (fail-open)
# ================================================================
printf '' | bash "$HOOK" 2>/dev/null && pass "empty stdin allowed" \
  || fail "empty stdin should be allowed (fail-open)"

# ================================================================
# 14. Malformed JSON → ALLOW (fail-open)
# ================================================================
printf 'this is not json' | bash "$HOOK" 2>/dev/null && pass "malformed JSON allowed" \
  || fail "malformed JSON should be allowed (fail-open)"

# ================================================================
# 15. Other guarded launchers also denied
# ================================================================
for launcher in leadv2-codex-session-runner.sh leadv2-fanout.sh glm-coder.sh omp-task.sh; do
  payload="$(make_payload "bash ./${launcher} --task x")"
  if run_hook "$payload"; then
    fail "${launcher} foreground should be denied"
  else
    pass "${launcher} foreground denied"
  fi
done

# ================================================================
# 16. Trailing-& regex precision: && must NOT be treated as background
# ================================================================
payload="$(make_payload 'bash leadv2-dispatch-code.sh @mission.md && echo done')"
if run_hook "$payload"; then
  fail "&& should not be treated as backgrounded"
else
  pass "&& correctly not treated as backgrounded"
fi

# ================================================================
# 17. Trailing-& regex precision: &> redirect must NOT be background
# ================================================================
payload="$(make_payload 'bash leadv2-dispatch-code.sh @mission.md &> /dev/null')"
if run_hook "$payload"; then
  fail "&> should not be treated as backgrounded"
else
  pass "&> correctly not treated as backgrounded"
fi

# ================================================================
# 18. nohup ... & → ALLOW
# ================================================================
payload="$(make_payload 'nohup bash leadv2-dispatch-code.sh @mission.md &')"
run_hook "$payload" && pass "nohup & allowed" \
  || fail "nohup & should be allowed"

# ================================================================
# 19. setsid → ALLOW
# ================================================================
payload="$(make_payload 'setsid bash leadv2-dispatch-code.sh @mission.md')"
run_hook "$payload" && pass "setsid allowed" \
  || fail "setsid should be allowed"

# ================================================================
# 20. hooks.json is valid JSON and hook is registered
# ================================================================
if python3 -m json.tool "$HOOKS_JSON" >/dev/null 2>&1; then
  if grep -q 'leadv2-block-fg-dispatch.sh' "$HOOKS_JSON"; then
    pass "hooks.json valid and hook registered"
  else
    fail "hook not found in hooks.json"
  fi
else
  fail "hooks.json is invalid JSON"
fi

# ================================================================
# 21. status subcommand does not match path fragment (e.g. status-surface.sh)
# ================================================================
payload="$(make_payload 'bash leadv2-status-surface.sh --task x')"
if run_hook "$payload"; then
  pass "status-surface.sh not confused with status subcommand"
else
  fail "status-surface.sh should not match status subcommand exemption"
fi

printf -- '\n[fg-dispatch-guard] PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1
