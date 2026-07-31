#!/usr/bin/env bash
# test-codex-quota-gate.sh — CODEX-GATE-01 item 4
#
# Unit-tests the codex quota launch gate (_codex_quota_gate in codex-task.sh) plus
# the post-launch watcher's idempotency. Drives the REAL codex-task.sh against an
# isolated HOME so the founder's real lockout file, codex job store, and account
# are never touched or seeded.
#
# Isolation contract — the gate reads three things, all redirectable:
#   _CODEX_LOCKOUT_FILE = $HOME/.claude/cache/codex-lockout.state   -> overridden via HOME
#   routing yaml        = LEADV2_ROUTING_YAML                        -> overridden per case
#   quota reader        = LEADV2_QUOTA_READ (python3 <reader> codex) -> stubbed per case
# The companion resolution at the top of codex-task.sh (`find ... codex-companion.mjs`)
# is HOME-relative, so the isolated HOME carries a mirrored copy of the real companion
# file (find succeeds); a fake `node` on PATH makes any "proceed" case fail fast
# instead of launching real Codex.
#
# Cases (each asserts BOTH the stderr marker AND the exit code):
#   q1  future lockout        -> refused: CODEX_REFUSED_QUOTA reason=lockout + marker, rc 2, NO job dir
#   q2  past lockout          -> proceeds: no marker, rc != 2
#   q3  reader hangs > deadline -> fail-open proceeds: 'quota-gate FAIL-OPEN', rc != 2
#   q4  reader prints 99      -> refused: reason=threshold used=99 + marker, rc 2, NO job dir
#   q5  watcher rerun         -> exactly ONE lockout line after two runs (idempotent)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_TASK_SH="${HERE}/codex-task.sh"

REAL_COMPANION="$(find "${HOME}/.claude/plugins/cache/openai-codex" -name codex-companion.mjs -path '*/scripts/*' 2>/dev/null | sort -V | tail -1)"
if [[ -z "${REAL_COMPANION}" ]]; then
  echo "SKIP: codex-companion.mjs not found (openai-codex plugin not installed) -- cannot run this test"
  exit 0
fi

PASS=0
FAIL=0
pass() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT

# A stable fake `node` so any "proceed" case fails fast (rc 7) instead of spawning
# real Codex. The gate has already returned by then, so rc 7 is the observable for
# "the gate did NOT refuse" (rc 2). Created once, reused per case.
STUBBIN="$BASE/stubbin"
mkdir -p "$STUBBIN"
cat > "$STUBBIN/node" <<'EOF'
#!/usr/bin/env bash
echo "[fake-node] no real codex launch" >&2
exit 7
EOF
chmod +x "$STUBBIN/node"

# Real founder lockout file -- captured once, asserted unchanged at the end.
REAL_LOCKOUT="${HOME}/.claude/cache/codex-lockout.state"
REAL_LOCKOUT_MT=""
[[ -f "$REAL_LOCKOUT" ]] && REAL_LOCKOUT_MT="$(stat -f '%m' "$REAL_LOCKOUT" 2>/dev/null || stat -c '%Y' "$REAL_LOCKOUT" 2>/dev/null || echo '')"

# Build an isolated HOME. Echoes nothing; sets globals HOME_DIR / STATE_ROOT / LOCKOUT.
build_home() {
  HOME_DIR="$BASE/home.${1}"
  rm -rf "$HOME_DIR"
  mkdir -p "$HOME_DIR/.claude/cache"
  # mirrored companion so `find` at the top of codex-task.sh resolves COMPANION.
  mkdir -p "$HOME_DIR/.claude/plugins/cache/openai-codex/codex/1.0.4/scripts"
  cp "$REAL_COMPANION" "$HOME_DIR/.claude/plugins/cache/openai-codex/codex/1.0.4/scripts/codex-companion.mjs"
  # isolated, EMPTY job store -- "no job dir created" asserts against this.
  STATE_ROOT="$HOME_DIR/.claude/plugins/data/codex-openai-codex/state"
  mkdir -p "$STATE_ROOT"
  LOCKOUT="$HOME_DIR/.claude/cache/codex-lockout.state"
}

# Count job files under the isolated state root (0 == no job launched).
count_jobs() {
  find "$STATE_ROOT" -name '*.json' -path '*/jobs/*' 2>/dev/null | wc -l | tr -d ' '
}

# Run codex-task.sh under the isolated HOME. $1=case-label, rest forwarded.
# Sets RUN_RC / RUN_ERR. PATH gets the fake node prepended.
run_case() {
  local _label="$1"; shift
  local _err="$BASE/${_label}.err"
  RUN_RC=0
  HOME="$HOME_DIR" PATH="$STUBBIN:$PATH" bash "$CODEX_TASK_SH" "$@" >"$BASE/${_label}.out" 2>"$_err" || RUN_RC=$?
  RUN_ERR="$_err"
}

iso_now() { # $1=hours-offset-from-now
  python3 -c 'import sys,datetime
print((datetime.datetime.now(datetime.UTC).replace(microsecond=0)+datetime.timedelta(hours=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"
}

# ── q1: future lockout -> refused, no job dir ──────────────────────────────
build_home q1
printf '%s CODEX_JOB_FAILED_QUOTA until=%s job=x-1 src=parsed\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(iso_now 2)" > "$LOCKOUT"
run_case q1 task "q1-probe" --cwd "$BASE"
if grep -q 'CODEX_REFUSED_QUOTA reason=lockout' "$RUN_ERR" \
   && grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' "$RUN_ERR" \
   && [[ "$RUN_RC" -eq 2 ]] && [[ "$(count_jobs)" -eq 0 ]]; then
  pass "q1 future lockout refused (marker + rc 2) before any job launch"
else
  fail "q1 future lockout refused (marker + rc 2) before any job launch (rc=$RUN_RC, jobs=$(count_jobs))"
fi

# ── q2: past lockout -> proceeds (no marker, rc != 2) ──────────────────────
build_home q2
printf '%s CODEX_JOB_FAILED_QUOTA until=%s job=x-1 src=parsed\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(iso_now -2)" > "$LOCKOUT"
# no LEADV2_ROUTING_YAML threshold -> gate skips live-quota check and proceeds.
run_case q2 task "q2-probe" --cwd "$BASE"
if [[ "$RUN_RC" -ne 2 ]] && ! grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' "$RUN_ERR"; then
  pass "q2 past lockout proceeds (no marker, rc=$RUN_RC != 2)"
else
  fail "q2 past lockout proceeds (rc=$RUN_RC, marker present?)"
fi

# ── q3: reader hangs past deadline -> fail-open, proceeds ──────────────────
build_home q3
cat > "$BASE/reader_hang.py" <<'EOF'
import time
time.sleep(120)
EOF
cat > "$BASE/routing.yaml" <<'EOF'
codex_quota_gate:
  build_threshold_pct: 80
EOF
HOME="$HOME_DIR" PATH="$STUBBIN:$PATH" \
LEADV2_ROUTING_YAML="$BASE/routing.yaml" \
LEADV2_QUOTA_READ="$BASE/reader_hang.py" \
LEADV2_QUOTA_READ_TIMEOUT=2 \
  bash "$CODEX_TASK_SH" task "q3-probe" --cwd "$BASE" >"$BASE/q3.out" 2>"$BASE/q3.err" || RUN_RC=$?
if grep -q 'quota-gate FAIL-OPEN' "$BASE/q3.err" \
   && [[ "${RUN_RC:-0}" -ne 2 ]] \
   && ! grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' "$BASE/q3.err"; then
  pass "q3 reader-deadline fails open and proceeds (rc=${RUN_RC:-0})"
else
  fail "q3 reader-deadline fails open and proceeds (rc=${RUN_RC:-0})"
fi

# ── q4: reader prints 99, threshold 80 -> refused, no job dir ──────────────
build_home q4
cat > "$BASE/reader99.py" <<'EOF'
import json
print(json.dumps({"status":"ok","binding_window":"weekly","windows":[{"kind":"weekly","used_percent":99}]}))
EOF
cat > "$BASE/routing.yaml" <<'EOF'
codex_quota_gate:
  build_threshold_pct: 80
  review_threshold_pct: 80
EOF
HOME="$HOME_DIR" PATH="$STUBBIN:$PATH" \
LEADV2_ROUTING_YAML="$BASE/routing.yaml" \
LEADV2_QUOTA_READ="$BASE/reader99.py" \
  bash "$CODEX_TASK_SH" task "q4-probe" --cwd "$BASE" >"$BASE/q4.out" 2>"$BASE/q4.err" || RUN_RC=$?
RUN_ERR="$BASE/q4.err"
if grep -q 'CODEX_REFUSED_QUOTA reason=threshold used=99' "$RUN_ERR" \
   && grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' "$RUN_ERR" \
   && [[ "${RUN_RC:-0}" -eq 2 ]] && [[ "$(count_jobs)" -eq 0 ]]; then
  pass "q4 over-threshold refused (reason=threshold used=99 + rc 2) before any job launch"
else
  fail "q4 over-threshold refused (reason=threshold used=99 + rc 2) before any job launch (rc=${RUN_RC:-0}, jobs=$(count_jobs))"
fi

# ── q5: watcher idempotent across two reruns -> exactly ONE lockout line ───
build_home q5
WS="$STATE_ROOT/ws/jobs"
mkdir -p "$WS"
printf '{"status":"failed","id":"job-q5-99999"}' > "$WS/job-q5-99999.json"
printf 'Codex error: You have hit your usage limit. Please try again at Aug 5th, 2026 10:55 AM.\n' > "$WS/job-q5-99999.log"
# run the watcher twice (separate processes -- the hard case; the EXIT trap
# removes the per-job mkdir lock between runs, so idempotency must come from
# the record-side dedupe, not the lock).
HOME="$HOME_DIR" CODEX_WATCH_POLL_S=1 CODEX_WATCH_MAX_S=10 \
  bash "$CODEX_TASK_SH" __quota-watch job-q5-99999 >/dev/null 2>&1 || true
HOME="$HOME_DIR" CODEX_WATCH_POLL_S=1 CODEX_WATCH_MAX_S=10 \
  bash "$CODEX_TASK_SH" __quota-watch job-q5-99999 >/dev/null 2>&1 || true
Q5_COUNT=0
[[ -f "$LOCKOUT" ]] && Q5_COUNT="$(grep -c 'CODEX_JOB_FAILED_QUOTA until=' "$LOCKOUT" 2>/dev/null || echo 0)"
if [[ "$Q5_COUNT" -eq 1 ]]; then
  pass "q5 watcher writes exactly one lockout line across two reruns (idempotent)"
else
  fail "q5 watcher idempotency (expected 1 line, got $Q5_COUNT)"
fi

# ── isolation guard: real lockout file untouched (NOT counted toward PASS;
#    a violation flips the run to failed, success does not increment pass) ──
if [[ -n "$REAL_LOCKOUT_MT" && -f "$REAL_LOCKOUT" ]]; then
  _after="$(stat -f '%m' "$REAL_LOCKOUT" 2>/dev/null || stat -c '%Y' "$REAL_LOCKOUT" 2>/dev/null || echo '')"
  if [[ "$_after" != "$REAL_LOCKOUT_MT" ]]; then
    printf '[TEST] FAIL: isolation violated -- real lockout mtime %s -> %s\n' "$REAL_LOCKOUT_MT" "$_after"
    FAIL=$((FAIL + 1))
  fi
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
