#!/usr/bin/env bash
# tests/test-dispatch-product-close-exit-trap.sh — SUPERVISOR-AUDIT-01 tail (item C):
# regression coverage for leadv2-dispatch-product-close.sh's EXIT trap
# (_pc_exit_handler), carried debt from wave2b/2c.
#
# Drives the REAL leadv2-dispatch-product-close.sh (never a reimplementation of its
# trap logic). Both kill-switches (E2E_ON/REVIEW_ON, args 5/6) are set to 0 so neither
# subtest needs a real e2e entrypoint, git diff, or review-provider spawn -- exactly the
# shortcut the task calls for.
#
# Test (a): success path + simulated ledger write contention. The explicit
#   `_dl_note landed review_gate_disabled` call (REVIEW_ON=0 branch) has its FIRST
#   underlying ledger write dropped by a stub LEDGER_BIN (simulating a lock-wait
#   timeout) -- proving _PC_TERMINAL_STATE was captured regardless, so the EXIT trap's
#   own idempotent retry still lands the TRUE intended state (landed), never falling
#   through to the dead/crashed_unfinished default.
#
# Test (b): kill -TERM mid-run. AUTHOR=sonnet with a HANDLE pointing at a real,
#   long-lived background pid forces the script to block in its very first
#   substantive statement (`while kill -0 "$HANDLE"; do sleep 2; done`) -- BEFORE any
#   _dl_note call is ever reached. A SIGTERM delivered while blocked there is the
#   textbook SIGTERM-starved crash this ledger exists to catch: the trap's `dead
#   crashed_unfinished` fallback must fire, and (write-once) exactly one row must
#   result, never a race producing two.
#
# Portable: no GNU-only date/sed/timeout. Sandboxed via LEADV2_DISPATCH_TERMINAL_
# LEDGER_FILE / LEADV2_STATE_ROOT / LEADV2_DISPATCH_CACHE_DIR -- never touches the real
# repo's ledger or active.yaml.
# Run: bash scripts/tests/test-dispatch-product-close-exit-trap.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

PRODUCT_CLOSE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"
REAL_LEDGER_SH="${SCRIPTS_ROOT}/leadv2-dispatch-ledger.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

if bash -n "$PRODUCT_CLOSE_SH"; then
  pass "bash -n clean (leadv2-dispatch-product-close.sh)"
else
  fail "bash -n failed on leadv2-dispatch-product-close.sh"
fi

tmp="$(lv2_mktemp_dir "pc-exit-trap-test")"; trap 'rm -rf "$tmp"' EXIT
ROOT="$tmp/root"
STATE="$tmp/state"
CACHE="$tmp/cache"
mkdir -p "$ROOT" "$STATE" "$CACHE"

export LEADV2_PROJECT_ROOT="$ROOT"
export LEADV2_STATE_ROOT="$STATE"
export LEADV2_DISPATCH_CACHE_DIR="$CACHE"
export LEADV2_JOURNAL_BIN=/bin/true

# ── Test (a): success path survives simulated ledger write contention ──────────────
LEDGER_FILE_A="$tmp/ledger-a.jsonl"
SIG8_A="a1a1a1a1"
STUB_LEDGER_A="$tmp/stub-ledger-a.sh"
FIRST_CALL_MARKER_DIR="$tmp/first-call-markers"
mkdir -p "$FIRST_CALL_MARKER_DIR"
cat > "$STUB_LEDGER_A" <<STUB
#!/usr/bin/env bash
# Drops the FIRST write-terminal call for a given sig8 (simulated lock-wait
# contention: the caller's write attempt fails, nothing is written), forwards every
# call after that -- and every non-write-terminal call -- to the REAL ledger binary.
if [[ "\$1" == "write-terminal" ]]; then
  sig8="\$2"
  marker="${FIRST_CALL_MARKER_DIR}/\${sig8}.seen"
  if [[ ! -f "\$marker" ]]; then
    touch "\$marker"
    exit 1
  fi
fi
exec bash "${REAL_LEDGER_SH}" "\$@"
STUB
chmod +x "$STUB_LEDGER_A"

out_a="$(
  LEADV2_DISPATCH_LEDGER_BIN="$STUB_LEDGER_A" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGER_FILE_A" \
    bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIG8_A" codex "" 0 0 "" 2>&1
)"
rc_a=$?

if [[ "$rc_a" -eq 0 ]]; then
  pass "Test (a): success path (both kill-switches off) exits 0"
else
  fail "Test (a): expected exit 0, got rc=${rc_a} -- out=${out_a}"
fi

rows_a="$(grep -c "\"task_sig\":\"${SIG8_A}\"" "$LEDGER_FILE_A" 2>/dev/null || echo 0)"
if [[ "$rows_a" -eq 1 ]]; then
  pass "Test (a): exactly one terminal row survives the dropped first write + trap retry"
else
  fail "Test (a): expected exactly 1 row for sig=${SIG8_A}, got ${rows_a} -- $(grep "\"${SIG8_A}\"" "$LEDGER_FILE_A" 2>/dev/null)"
fi
row_a="$(grep "\"task_sig\":\"${SIG8_A}\"" "$LEDGER_FILE_A" 2>/dev/null)"
if grep -q '"terminal":"landed"' <<<"$row_a"; then
  pass "Test (a): the surviving row records the intended 'landed' state, not a downgrade"
else
  fail "Test (a): row is not 'landed' -- $row_a"
fi
if grep -q '"terminal":"dead"' <<<"$row_a"; then
  fail "Test (a): row was downgraded to 'dead' (crashed_unfinished default won instead of the intended state) -- $row_a"
else
  pass "Test (a): row was never downgraded to 'dead'/crashed_unfinished"
fi

# ── Test (b): kill -TERM mid-run -> dead crashed_unfinished, exactly once ──────────
LEDGER_FILE_B="$tmp/ledger-b.jsonl"
SIG8_B="b2b2b2b2"

sleep 30 & LONG_LIVED_PID=$!
disown "$LONG_LIVED_PID" 2>/dev/null || true

out_b_file="$tmp/out-b.log"
# Backgrounded DIRECTLY (no wrapping `( ... ) &` subshell) so `$!` is the REAL
# leadv2-dispatch-product-close.sh process itself -- an earlier version of this test
# wrapped the invocation in its own subshell and sent SIGTERM to THAT subshell's pid
# instead, which bash's default (untrapped) TERM handling kills immediately while
# leaving the actual child process it was waiting on to run on, orphaned and
# unsignaled: rc never got captured because the wrapper died before writing it.
LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGER_FILE_B" \
  bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIG8_B" sonnet "$LONG_LIVED_PID" 0 0 "" \
  > "$out_b_file" 2>&1 &
pc_pid=$!

# Give the script time to install its traps and enter the HANDLE wait-loop -- this is
# its very first substantive statement (before any e2e/review code, before any
# _dl_note call), so a short, generous sleep reliably lands the SIGTERM inside it
# without needing lockstep synchronization.
sleep 0.5
if kill -0 "$pc_pid" 2>/dev/null; then
  kill -TERM "$pc_pid" 2>/dev/null
else
  fail "Test (b) setup: product-close process exited before SIGTERM could be sent (finished too fast to prove mid-run kill) -- out=$(cat "$out_b_file" 2>/dev/null)"
fi
wait "$pc_pid" 2>/dev/null
rc_b=$?
kill "$LONG_LIVED_PID" 2>/dev/null; wait "$LONG_LIVED_PID" 2>/dev/null

if [[ "$rc_b" == "143" ]]; then
  pass "Test (b): SIGTERM converted to 'exit 143' (trap 'exit 143' TERM), EXIT trap guaranteed to run"
else
  fail "Test (b): expected rc=143 (TERM->exit 143), got rc=${rc_b} -- out=$(cat "$out_b_file" 2>/dev/null)"
fi

rows_b="$(grep -c "\"task_sig\":\"${SIG8_B}\"" "$LEDGER_FILE_B" 2>/dev/null || echo 0)"
if [[ "$rows_b" -eq 1 ]]; then
  pass "Test (b): exactly one terminal row recorded for the SIGTERM-killed run (write-once held)"
else
  fail "Test (b): expected exactly 1 row for sig=${SIG8_B}, got ${rows_b} -- $(grep "\"${SIG8_B}\"" "$LEDGER_FILE_B" 2>/dev/null)"
fi
row_b="$(grep "\"task_sig\":\"${SIG8_B}\"" "$LEDGER_FILE_B" 2>/dev/null)"
if grep -q '"terminal":"dead"' <<<"$row_b" && grep -q '"cause":"crashed_unfinished"' <<<"$row_b"; then
  pass "Test (b): the recorded terminal is dead/crashed_unfinished, exactly the SIGTERM-starved shape"
else
  fail "Test (b): row is not dead/crashed_unfinished -- $row_b"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
