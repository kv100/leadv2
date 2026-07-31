#!/usr/bin/env bash
# tests/test-supervisor-mode-reinject.sh — SUPERVISOR-HARDENING-01 item 1 test
# for hooks/leadv2-supervisor-mode-reinject.sh (the PostCompact reinject hook).
#
# Drives the hook against a throwaway fixture repo (never the real
# .supervise-active sentinel, never the real control-plane state dir):
#   • no sentinel          → empty stdout, rc 0
#   • dead PID in sentinel → empty stdout (fail-closed, no partial block)
#   • live PID in sentinel → stdout carries the SUPERVISOR-MODE role block
#                             and the docs/supervisor-role.md pointer
#   • malformed / empty    → empty stdout, rc 0 (fail-closed)
#
# Isolation: LEADV2_STATE_ROOT points the resolver at a tmp state dir; the
# resolver is copied into the fixture's .claude/scripts/ so the hook finds it
# via PROJECT_ROOT; CLAUDE_PROJECT_DIR is unset so the hook never resolves the
# ambient real project. Run: bash scripts/tests/test-supervisor-mode-reinject.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/leadv2-supervisor-mode-reinject.sh"
RESOLVER="${SCRIPT_DIR}/leadv2-state-path.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

# Alive sleep PIDs we own — reaped on EXIT so no test leaks a sleep 30.
_REAP_PIDS=()
cleanup() { for p in "${_REAP_PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

if bash -n "${HOOK}" 2>/dev/null; then pass "bash -n reinject hook"; else fail "bash -n reinject hook"; fi
[[ -x "$RESOLVER" ]] || { fail "resolver not executable — cannot stage fixture"; }

# ── Fixture repo + isolated control-plane state dir ────────────────────────
FIXTURE="$(lv2_mktemp_dir reinject-fx)/repo"
mkdir -p "$FIXTURE/.claude/scripts"
( cd "$FIXTURE" && git init -q && git config user.email t@t.com && git config user.name t )
lv2_assert_scratch_repo "$FIXTURE"
# The hook discovers the resolver at <root>/.claude/scripts/leadv2-state-path.sh
cp "$RESOLVER" "$FIXTURE/.claude/scripts/leadv2-state-path.sh"
chmod +x "$FIXTURE/.claude/scripts/leadv2-state-path.sh"

STATE_ROOT="$(lv2_mktemp_dir reinject-state)"
mkdir -p "$STATE_ROOT"
SENTINEL="${STATE_ROOT}/.supervise-active"

# Invoke the hook with a `{"cwd":...}` payload on stdin (the PostCompact shape).
# CLAUDE_PROJECT_DIR is unset so _ROOT comes from the stdin cwd, not the real
# project the test happens to run from. LEADV2_STATE_ROOT forces the resolver
# to land the sentinel under our throwaway state dir.
run_hook() {  # <stdin-json>
  env -u CLAUDE_PROJECT_DIR \
      LEADV2_STATE_ROOT="$STATE_ROOT" \
      LEADV2_SUPERVISOR_REINJECT=1 \
      HOME="${HOME}" \
      bash "$HOOK" <<<"$1"
}
payload() { printf '{"cwd":"%s"}' "$FIXTURE"; }

# ── Case 1: no sentinel → empty stdout, rc 0 ───────────────────────────────
rm -f "$SENTINEL"
out="$(run_hook "$(payload)")"; rc=$?
if [[ "$rc" == "0" ]]; then pass "case 1 (no sentinel): rc 0"; else fail "case 1: expected rc 0, got $rc"; fi
if [[ -z "$out" ]]; then pass "case 1 (no sentinel): empty stdout"; else fail "case 1: expected empty stdout, got: $out"; fi

# ── Case 2: dead PID → empty stdout (fail-closed) ──────────────────────────
# Spawn, reap, reuse — the pid is genuinely dead before we write the sentinel.
# Reap by polling (not `wait <pid>`): bash emits a noisy job-control diagnostic
# for a child killed out from under the wait, which would dirty test output.
sleep 2 & dead_pid=$!; kill "$dead_pid" 2>/dev/null
for _ in $(seq 1 40); do kill -0 "$dead_pid" 2>/dev/null || break; sleep 0.05; done
if kill -0 "$dead_pid" 2>/dev/null; then
  fail "case 2: precondition — reaped pid still alive, skip"
else
  printf '{"pid":%s,"started_at":"now"}' "$dead_pid" >"$SENTINEL"
  out="$(run_hook "$(payload)")"; rc=$?
  if [[ "$rc" == "0" ]]; then pass "case 2 (dead pid): rc 0"; else fail "case 2: expected rc 0, got $rc"; fi
  if [[ -z "$out" ]]; then pass "case 2 (dead pid): empty stdout (fail-closed)"; else fail "case 2: expected empty stdout, got: $out"; fi
fi

# ── Case 3: live PID → role block + supervisor-role.md pointer ─────────────
sleep 30 & live_pid=$!; _REAP_PIDS+=("$live_pid")
kill -0 "$live_pid" 2>/dev/null && printf '{"pid":%s,"started_at":"now"}' "$live_pid" >"$SENTINEL"
out="$(run_hook "$(payload)")"; rc=$?
if [[ "$rc" == "0" ]]; then pass "case 3 (live pid): rc 0"; else fail "case 3: expected rc 0, got $rc"; fi
if printf '%s' "$out" | grep -q 'SUPERVISOR MODE IS ON'; then
  pass "case 3 (live pid): SUPERVISOR-MODE role block emitted"
else
  fail "case 3: role block missing; stdout was: $out"
fi
if printf '%s' "$out" | grep -q 'supervisor-role.md'; then
  pass "case 3 (live pid): docs/supervisor-role.md pointer present"
else
  fail "case 3: supervisor-role.md pointer missing"
fi

# ── Case 4a: malformed sentinel → empty stdout, rc 0 ───────────────────────
printf 'this is not json' >"$SENTINEL"
out="$(run_hook "$(payload)")"; rc=$?
if [[ "$rc" == "0" ]]; then pass "case 4a (malformed): rc 0"; else fail "case 4a: expected rc 0, got $rc"; fi
if [[ -z "$out" ]]; then pass "case 4a (malformed): empty stdout (fail-closed)"; else fail "case 4a: expected empty stdout, got: $out"; fi

# ── Case 4b: empty sentinel file → empty stdout, rc 0 ──────────────────────
: >"$SENTINEL"
out="$(run_hook "$(payload)")"; rc=$?
if [[ "$rc" == "0" ]]; then pass "case 4b (empty): rc 0"; else fail "case 4b: expected rc 0, got $rc"; fi
if [[ -z "$out" ]]; then pass "case 4b (empty): empty stdout (fail-closed)"; else fail "case 4b: expected empty stdout, got: $out"; fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
[[ "$FAIL" -eq 0 ]]
