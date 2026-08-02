#!/usr/bin/env bash
# The old test proved two unbounded readers agreed on 2099.  This one proves
# the public status front-end and the real gate share a bounded policy.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCKOUT_SH="${SCRIPT_DIR}/leadv2-codex-lockout.sh"
CODEX_TASK_SH="${SCRIPT_DIR}/codex-task.sh"
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-cooldown.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
export HOME="$ROOT/home"
export LEADV2_ARM_COOLDOWN_DIR="$ROOT/cooldowns"
export LEADV2_ARM_COOLDOWN_NOW_EPOCH=1000000000
export LEADV2_QUOTA_LIVE="$ROOT/quota-live"
export GLM_BIN="$ROOT/glm" CODEX_BIN="$ROOT/codex"
mkdir -p "$HOME/.claude/plugins/cache/openai-codex/v1/scripts"
printf 'process.exit(0);\n' > "$HOME/.claude/plugins/cache/openai-codex/v1/scripts/codex-companion.mjs"
printf '#!/usr/bin/env bash\nprintf %s\\n '\''{"status":"ok","windows":[]} '\''\n' > "$LEADV2_QUOTA_LIVE"
chmod +x "$LEADV2_QUOTA_LIVE"

# N1B F5: a portable bounded runner so the agreement suite no longer depends on
# GNU coreutils `timeout` (absent from a clean macOS PATH). rc 124 on timeout
# matches GNU semantics. Uses ONLY `kill`, `wait`, `sleep` in the fallback --
# POSIX-mandated -- so if it cannot run the environment is broken and the suite
# fails loudly rather than skipping. The suite's `trap rm -rf "$ROOT"` covers
# the temp capture file on abort (R5).
_run_bounded() {
  local secs="$1"; shift
  local cap pid rc deadline now
  if command -v timeout >/dev/null 2>&1; then
    cap="$(timeout "$secs" "$@" 2>&1)"; rc=$?
    printf '%s' "$cap"
    return "$rc"
  fi
  cap="$ROOT/bounded.$$.out"; : > "$cap"
  "$@" >"$cap" 2>&1 &
  pid=$!
  deadline=$(( $(date +%s 2>/dev/null || printf '0') + secs ))
  while :; do
    kill -0 "$pid" 2>/dev/null || break
    now="$(date +%s 2>/dev/null || printf '0')"
    [ "$now" -ge "$deadline" ] && break
    sleep 0.2 2>/dev/null || sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    sleep 0.2 2>/dev/null || sleep 1
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null; rc=124
  else
    wait "$pid"; rc=$?
  fi
  cat "$cap"; rm -f "$cap" 2>/dev/null || true
  return "$rc"
}

if bash -n "$LOCKOUT_SH" && bash -n "$CODEX_TASK_SH"; then pass 'shell syntax'; else fail 'shell syntax'; fi

source "${SCRIPT_DIR}/lib/leadv2-arm-cooldown.sh"
arm_cooldown_record codex quota 2099-08-05T10:55:00Z >/dev/null
line="$(tail -n 1 "$LEADV2_ARM_COOLDOWN_DIR/codex.state")"
case "$line" in
  *'cooldown_s=900'*'advisory=ignored'*) pass 'policy: 2099 advisory is bounded to 900 seconds' ;;
  *) fail "policy: future advisory extended cooldown ($line)" ;;
esac

helper="$(bash "$LOCKOUT_SH")"
[ "$helper" = 'locked 2001-09-09T02:01:40Z' ] && pass 'front-end reports shared reprobe time' || fail "front-end (got: $helper)"

out="$(_run_bounded 20 env CODEX_AUTOREAP=0 bash "$CODEX_TASK_SH" task --cwd /tmp)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q 'reason=cooldown' \
  && printf '%s\n' "$out" | grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate'; then
  pass 'real gate refuses with unchanged quota_gate grammar'
else
  fail "real gate cooling refusal (rc=$rc, got: $out)"
fi

export LEADV2_ARM_COOLDOWN_NOW_EPOCH=1000000901
helper="$(bash "$LOCKOUT_SH")"
[ "$helper" = clear ] && pass 'front-end self-heals after reprobe time' || fail "expiry front-end (got: $helper)"
out="$(_run_bounded 20 env CODEX_AUTOREAP=0 bash "$CODEX_TASK_SH" task --cwd /tmp)"; rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -q 'reason=cooldown'; then
  pass 'real gate re-probes rather than preserving a remembered verdict'
else
  fail "expiry gate (rc=$rc, got: $out)"
fi

# F5: prove _run_bounded is portable. Its fallback branch (no `timeout` on PATH)
# enforces the SAME rc contract as GNU timeout using only POSIX kill/wait/sleep.
# We CANNOT re-exec the whole agreement suite under PATH=/usr/bin:/bin on this
# host: codex-task.sh also calls `node` (homebrew, outside that PATH) -- an
# unrelated host dependency, not a code one (codex-task.sh is already its own
# portable-timeout, see :1175). So we exercise the helper's two branches
# directly, which is exactly the code F5 ships.
export ROOT  # the fallback writes its capture file under $ROOT
# fast path (timeout present on this host): delegates, preserves output + rc.
fb1="$(_run_bounded 5 bash -c 'printf fast; exit 0')"; fb1rc=$?
if [ "$fb1" = fast ] && [ "$fb1rc" -eq 0 ]; then
  pass 'F5: _run_bounded fast path (timeout present) preserves stdout + rc'
else
  fail "F5: fast path (out=[$fb1] rc=$fb1rc)"
fi
# fast path must actually ENFORCE the bound via timeout -- a bare delegation
# (the Codex-caught regression) lets `sleep 3` run to completion under rc 0.
fb1b_start="$(date +%s 2>/dev/null || printf 0)"
_run_bounded 1 bash -c 'sleep 3' >/dev/null 2>&1; fb1brc=$?
fb1b_elapsed=$(( $(date +%s 2>/dev/null || printf 0) - fb1b_start ))
if [ "$fb1brc" -eq 124 ] && [ "$fb1b_elapsed" -lt 3 ]; then
  pass "F5: fast path enforces the deadline (rc=124 in ${fb1b_elapsed}s, not rc=0 after 3s)"
else
  fail "F5: fast path bound (rc=$fb1brc elapsed=${fb1b_elapsed}s -- timeout was not invoked)"
fi
# fallback path: exported into a restricted-PATH sub-bash so `command -v timeout`
# is false; it must still run the command, capture output, and honour rc.
fb2="$(export -f _run_bounded; env PATH=/usr/bin:/bin bash -c '_run_bounded 5 bash -c "printf slow; exit 0" 2>/dev/null')"; fb2rc=$?
if [ "$fb2" = slow ] && [ "$fb2rc" -eq 0 ]; then
  pass 'F5: _run_bounded fallback (no timeout on PATH) runs + captures output + rc 0'
else
  fail "F5: fallback run (out=[$fb2] rc=$fb2rc)"
fi
# fallback timeout: a hung command under a no-timeout PATH must yield rc 124
# (GNU semantics), proving the deadline is still enforced without coreutils.
fb3="$(export -f _run_bounded; env PATH=/usr/bin:/bin bash -c '_run_bounded 1 bash -c "sleep 5" 2>/dev/null')"; fb3rc=$?
if [ "$fb3rc" -eq 124 ]; then
  pass 'F5: _run_bounded fallback kills a hung command -> rc 124 (GNU contract)'
else
  fail "F5: fallback timeout (rc=$fb3rc, out=[$fb3])"
fi

printf '[TEST] === %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
