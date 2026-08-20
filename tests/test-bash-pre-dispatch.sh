#!/usr/bin/env bash
# Regression/performance coverage for the merged PreToolUse:Bash dispatcher.
# Compatible with macOS Bash 3.2 and BSD userland.

set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TEST_DIR/.." && pwd)"
PLUGIN_ROOT="$ROOT/plugins/leadv2"
HOOK_DIR="$PLUGIN_ROOT/hooks"
DISPATCHER="$HOOK_DIR/leadv2-bash-pre-dispatch.sh"
FAILURES=0

TEST_TMP="$(mktemp -d "$ROOT/.test-bash-pre-dispatch.XXXXXX")" || exit 1
cleanup() {
  case "$TEST_TMP" in
    "$ROOT"/.test-bash-pre-dispatch.*) rm -rf "$TEST_TMP" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TEST_TMP/home" "$TEST_TMP/tmp" "$TEST_TMP/work"
git -C "$TEST_TMP/work" init -q

export HOME="$TEST_TMP/home"
export TMPDIR="$TEST_TMP/tmp"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
export CLAUDE_PROJECT_ROOT="$TEST_TMP/work"
export LEADV2_PROJECT_ROOT="$TEST_TMP/work"
export LEADV2_DENY_PATTERNS_FILE="$PLUGIN_ROOT/config/leadv2-deny-patterns.yaml"
export LEADV2_SUPERVISE_GUARD=0
export LEADV2_SUPERVISE_BASH_GUARD=0
export LEADV2_SUPERVISOR_GUARD=0
export LEADV2_CODEX_NOPOLL=0
export LEADV2_DENY_FLOOR=1
export LEADV2_SKIP_CLOSE_GUARD=0
export LEADV2_ALLOW_FG_DISPATCH=0
export LEADV2_ALLOW_DIRECT_CODEX=0
export LEADV2_HOOK_PROFILE=0
export LEADV2_TASK_ID=""

# Dispatcher manifest order: exit-2 guards, deny-only stdout guards, then
# allow-emitting gates.  The reference path deliberately invokes all 11.
GUARDS='leadv2-deny-floor.sh
leadv2-block-bash-heredoc.sh
leadv2-block-fg-dispatch.sh
leadv2-codex-direct-exec-guard.sh
leadv2-codex-round-cap.sh
leadv2-codex-nopoll-guard.sh
leadv2-close-ritual-guard.sh
leadv2-context-glossary-close.sh
leadv2-bash-lint-pre-gate.sh
leadv2-env-audit-pre-gate.sh
leadv2-schema-audit-pre-gate.sh'

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

make_payload() {
  _payload_file="$1"
  _payload_command="$2"
  python3 - "$TEST_TMP/work" "$_payload_command" >"$_payload_file" <<'PY'
import json
import sys

print(json.dumps({
    "tool_name": "Bash",
    "cwd": sys.argv[1],
    "tool_input": {"command": sys.argv[2]},
}))
PY
}

run_dispatcher() {
  _payload_file="$1"
  (cd "$TEST_TMP/work" && "$DISPATCHER" <"$_payload_file")
}

run_originals() {
  _payload_file="$1"
  _first_out="$TEST_TMP/reference-first.out"
  _guard_out="$TEST_TMP/reference-guard.out"
  _guard_err="$TEST_TMP/reference-guard.err"
  _have_out=0
  : >"$_first_out"

  for _guard in $GUARDS; do
    : >"$_guard_out"
    : >"$_guard_err"
    (cd "$TEST_TMP/work" && "$HOOK_DIR/$_guard" <"$_payload_file") \
      >"$_guard_out" 2>"$_guard_err"
    _guard_rc=$?
    if [[ "$_guard_rc" -eq 2 ]]; then
      cat "$_guard_err" >&2
      return 2
    fi
    if [[ "$_have_out" -eq 0 && -s "$_guard_out" ]]; then
      if retain_first_json "$_guard_out" "$_first_out" && [[ -s "$_first_out" ]]; then
        _have_out=1
      else
        : >"$_first_out"
      fi
    fi
  done

  if [[ "$_have_out" -eq 1 ]]; then
    cat "$_first_out"
  fi
  return 0
}

run_direct_codex_guard() {
  _payload_file="$1"
  (cd "$TEST_TMP/work" && "$HOOK_DIR/leadv2-codex-direct-exec-guard.sh" <"$_payload_file")
}

retain_first_json() {
  _json_source="$1"
  _json_target="$2"
  python3 - "$_json_source" >"$_json_target" 2>/dev/null <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        raw = fh.read()
except Exception:
    sys.exit(1)

for candidate in [raw] + raw.splitlines(keepends=True):
    if not candidate.strip():
        continue
    try:
        json.loads(candidate)
    except Exception:
        continue
    sys.stdout.write(candidate)
    sys.exit(0)
sys.exit(1)
PY
}

capture() {
  _capture_name="$1"
  _capture_runner="$2"
  _capture_payload="$3"
  "$_capture_runner" "$_capture_payload" \
    >"$TEST_TMP/$_capture_name.out" 2>"$TEST_TMP/$_capture_name.err"
  printf '%s\n' "$?" >"$TEST_TMP/$_capture_name.rc"
}

verdict() {
  _verdict_name="$1"
  _verdict_rc="$(cat "$TEST_TMP/$_verdict_name.rc")"
  if [[ "$_verdict_rc" -eq 2 ]]; then
    printf 'BLOCK\n'
    return
  fi
  _decision="$(python3 - "$TEST_TMP/$_verdict_name.out" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        obj = json.load(fh)
    print((obj.get("hookSpecificOutput") or {}).get("permissionDecision") or "")
except Exception:
    print("")
PY
)"
  if [[ "$_decision" == "deny" ]]; then
    printf 'BLOCK\n'
  else
    printf 'ALLOW\n'
  fi
}

compare_case() {
  _case_name="$1"
  _case_command="$2"
  _case_expected="$3"
  _case_payload="$TEST_TMP/$_case_name.json"
  make_payload "$_case_payload" "$_case_command"
  capture "$_case_name-dispatch" run_dispatcher "$_case_payload"
  capture "$_case_name-originals" run_originals "$_case_payload"
  _dispatch_verdict="$(verdict "$_case_name-dispatch")"
  _original_verdict="$(verdict "$_case_name-originals")"

  if [[ "$_dispatch_verdict" == "$_original_verdict" ]]; then
    pass "$_case_name dispatcher verdict matches all 13 originals ($_dispatch_verdict)"
  else
    fail "$_case_name dispatcher=$_dispatch_verdict originals=$_original_verdict"
  fi
  if [[ "$_dispatch_verdict" == "$_case_expected" ]]; then
    pass "$_case_name expected verdict $_case_expected"
  else
    fail "$_case_name expected=$_case_expected actual=$_dispatch_verdict"
  fi
}

for _guard in $GUARDS; do
  [[ -x "$HOOK_DIR/$_guard" ]] || fail "guard is not executable: $_guard"
done
[[ -x "$DISPATCHER" ]] || fail "dispatcher is not executable"

compare_case echo_hi 'echo hi' ALLOW
if [[ ! -s "$TEST_TMP/echo_hi-dispatch.out" && "$(cat "$TEST_TMP/echo_hi-dispatch.rc")" -eq 0 ]]; then
  pass 'echo hi is a silent exit 0'
else
  fail 'echo hi must be a silent exit 0'
fi

LEADV2_DISPATCH_TRACE=1 run_dispatcher "$TEST_TMP/echo_hi.json" \
  >"$TEST_TMP/echo-trace.out" 2>"$TEST_TMP/echo-trace.err"
_trace_rc=$?
_expected_trace='leadv2-deny-floor.sh
leadv2-env-audit-pre-gate.sh'
_actual_trace="$(cat "$TEST_TMP/echo-trace.err")"
if [[ "$_trace_rc" -eq 0 && "$_actual_trace" == "$_expected_trace" ]]; then
  pass 'echo hi trace invokes only the 2 ALWAYS guards'
else
  fail "echo hi trace mismatch: ${_actual_trace:-<empty>}"
fi

_heredoc_command="cat <<'EOF'"
_i=0
while [[ "$_i" -lt 220 ]]; do
  _heredoc_command="${_heredoc_command}
0123456789abcdef"
  _i=$((_i + 1))
done
_heredoc_command="${_heredoc_command}
EOF"
compare_case heredoc "$_heredoc_command" BLOCK
if grep -q 'leadv2-block-bash-heredoc' "$TEST_TMP/heredoc-dispatch.err"; then
  pass 'heredoc block forwards the guard message on stderr'
else
  fail 'heredoc block did not forward the guard message'
fi

compare_case codex_exec "codex exec --full-auto 'review this'" BLOCK
capture codex-standalone run_direct_codex_guard "$TEST_TMP/codex_exec.json"
if [[ "$(verdict codex_exec-dispatch)" == "$(verdict codex-standalone)" ]]; then
  pass 'codex exec matches the standalone direct-exec guard verdict'
else
  fail 'codex exec differs from the standalone direct-exec guard verdict'
fi

compare_case close_push \
  'git commit -m "chore: close PERF-HOOK-999" && git push origin main' BLOCK
if [[ "$(python3 - "$TEST_TMP/close_push-dispatch.out" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        print((json.load(fh).get("hookSpecificOutput") or {}).get("permissionDecision") or "")
except Exception:
    print("")
PY
)" == "deny" ]]; then
  pass 'close-ritual/git-push-shaped command forwards deny JSON'
else
  fail 'close-ritual/git-push-shaped command did not forward deny JSON'
fi

now_ms() {
  python3 -c 'import time; print(int(time.monotonic() * 1000))'
}

_bench_runs="${LEADV2_DISPATCH_BENCH_RUNS:-5}"
_start_ms="$(now_ms)"
_i=0
while [[ "$_i" -lt "$_bench_runs" ]]; do
  run_dispatcher "$TEST_TMP/echo_hi.json" >/dev/null 2>/dev/null
  _i=$((_i + 1))
done
_dispatch_ms=$(( $(now_ms) - _start_ms ))

_start_ms="$(now_ms)"
_i=0
while [[ "$_i" -lt "$_bench_runs" ]]; do
  run_originals "$TEST_TMP/echo_hi.json" >/dev/null 2>/dev/null
  _i=$((_i + 1))
done
_original_ms=$(( $(now_ms) - _start_ms ))

_dispatch_avg="$(awk -v total="$_dispatch_ms" -v runs="$_bench_runs" 'BEGIN { printf "%.1f", total / runs }')"
_original_avg="$(awk -v total="$_original_ms" -v runs="$_bench_runs" 'BEGIN { printf "%.1f", total / runs }')"
printf 'TIMING echo_hi runs=%s dispatcher=%sms_total/%sms_avg originals=%sms_total/%sms_avg\n' \
  "$_bench_runs" "$_dispatch_ms" "$_dispatch_avg" "$_original_ms" "$_original_avg"

if [[ "$FAILURES" -ne 0 ]]; then
  printf 'FAILED %s assertion(s)\n' "$FAILURES" >&2
  exit 1
fi

printf 'ALL TESTS PASSED\n'
