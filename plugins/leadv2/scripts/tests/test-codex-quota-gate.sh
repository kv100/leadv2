#!/usr/bin/env bash
# test-codex-quota-gate.sh — CODEX-GATE-01 item 4
#
# Unit-tests the codex quota launch gate (_codex_quota_gate in codex-task.sh) plus
# the post-launch watcher's idempotency. Drives the REAL codex-task.sh against an
# isolated HOME so the founder's real lockout file, codex job store, and account
# are never touched or seeded.
#
# Isolation contract — the gate reads cooldown memory + circuit + routing + reader,
# all redirectable:
#   arm-cooldown store  = $HOME/.claude/cache/arm-cooldown/codex.state -> overridden via HOME
#   codex circuit file  = LEADV2_CODEX_CIRCUIT_FILE (test seam)        -> set per case (q9)
#   routing yaml        = LEADV2_ROUTING_YAML                          -> overridden per case
#   quota reader        = LEADV2_QUOTA_READ (python3 <reader> codex)   -> stubbed per case
# The companion resolution at the top of codex-task.sh (`find ... codex-companion.mjs`)
# is HOME-relative, so the isolated HOME carries a mirrored copy of the real companion
# file (find succeeds); a fake `node` on PATH makes any "proceed" case fail fast
# instead of launching real Codex.
#
# Cases (each asserts BOTH the stderr marker AND the exit code):
#   q1  live cooldown         -> refused: CODEX_REFUSED_QUOTA reason=cooldown + marker, rc 2, NO job dir
#   q2  past cooldown expires -> proceeds: no marker, rc != 2 (genuinely exercises arm-cooldown expiry)
#   q3  reader hangs > deadline -> fail-open proceeds: 'quota-gate FAIL-OPEN', rc != 2
#   q4  reader prints 99      -> refused: reason=threshold used=99 + marker, rc 2, NO job dir
#   q5  watcher rerun         -> exactly ONE cooldown line after two runs (idempotent)
#   q6  queued-stall (D1)     -> exactly ONE reason=queued_stall cooldown line + job-log line (idempotent)
#   q7  dispatch while cooling (D2) -> refused: marker + rc 2
#   q8  started job past stall threshold does NOT record a queued_stall cooldown
#   q9  queued stall then terminal quota death still records the quota cooldown (+ circuit)
#   q10 blind reader + recent stall (C) -> one WARN line, dispatch proceeds (rc != 2)
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
  # CODEX-QUOTA-GUARDRAILS-01 moved the cooldown memory to arm-cooldown/codex.state
  # (ARM_COOLDOWN arm=codex reason=<r> ...). The gate reads it via codex_spawn_gate;
  # queued-stall cases (CODEX-QUOTA-BLIND-SPOT-01) also write here.
  mkdir -p "$HOME_DIR/.claude/cache/arm-cooldown"
  ARM_CD="$HOME_DIR/.claude/cache/arm-cooldown/codex.state"
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

iso_min() { # $1=minutes-offset-from-now
  python3 -c 'import sys,datetime
print((datetime.datetime.now(datetime.UTC).replace(microsecond=0)+datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"
}

# ── q1: live cooldown -> refused, no job dir ───────────────────────────────
build_home q1
# CODEX-QUOTA-GUARDRAILS-01: the cooldown memory is arm-cooldown/codex.state
# (ARM_COOLDOWN arm=codex reason=…). A future reprobe_at => codex_spawn_gate
# refuses with reason=cooldown before any launch.
printf '%s ARM_COOLDOWN arm=codex reason=quota reprobe_at=%s cooldown_s=7200 advisory_until=%s advisory=ignored src=parsed job=x-1\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(iso_now 2)" "$(iso_now 2)" > "$ARM_CD"
run_case q1 task "q1-probe" --cwd "$BASE"
if grep -q 'CODEX_REFUSED_QUOTA reason=cooldown' "$RUN_ERR" \
   && grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' "$RUN_ERR" \
   && [[ "$RUN_RC" -eq 2 ]] && [[ "$(count_jobs)" -eq 0 ]]; then
  pass "q1 live cooldown refused (marker + rc 2) before any job launch"
else
  fail "q1 live cooldown refused (marker + rc 2) before any job launch (rc=$RUN_RC, jobs=$(count_jobs))"
fi

# ── q2: past cooldown expires -> proceeds (no marker, rc != 2) ─────────────
build_home q2
# CODEX-QUOTA-BLIND-SPOT-01 FIX2: seed the arm-cooldown store (NOT the dead
# legacy $LOCKOUT file) with a PAST reprobe_at, mirroring q1's line format but
# with a distinct job tag. A reprobe_at 2h ago (and past advisory_until) means
# codex_spawn_gate's cooldown has EXPIRED (leadv2-arm-cooldown.sh:184-189: a
# record is cooling only while reprobe_at > now), so the gate reaches the reader
# and -- no threshold yaml -- proceeds. This now genuinely exercises expiry;
# the old $LOCKOUT seed was read by nothing, so q2 passed vacuously.
printf '%s ARM_COOLDOWN arm=codex reason=quota reprobe_at=%s cooldown_s=7200 advisory_until=%s advisory=ignored src=parsed job=q2-1\n' \
  "$(iso_now -2)" "$(iso_now -2)" "$(iso_now -2)" > "$ARM_CD"
# no LEADV2_ROUTING_YAML threshold -> gate skips live-quota check and proceeds.
run_case q2 task "q2-probe" --cwd "$BASE"
if [[ "$RUN_RC" -ne 2 ]] && ! grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' "$RUN_ERR"; then
  pass "q2 past cooldown expires -> proceeds (no marker, rc=$RUN_RC != 2)"
else
  fail "q2 past cooldown expires -> proceeds (rc=$RUN_RC, marker present?)"
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
[[ -f "$ARM_CD" ]] && Q5_COUNT="$(grep -c 'ARM_COOLDOWN arm=codex reason=quota' "$ARM_CD" 2>/dev/null || echo 0)"
if [[ "$Q5_COUNT" -eq 1 ]]; then
  pass "q5 watcher writes exactly one cooldown line across two reruns (idempotent)"
else
  fail "q5 watcher idempotency (expected 1 cooldown line, got $Q5_COUNT)"
fi

# ── q6 (CODEX-QUOTA-BLIND-SPOT-01 D1): queued job past the stall threshold ─
# records a bounded cooldown exactly once across two sequential watcher reruns,
# and writes a CODEX_QUEUED_STALL line to the job's own log.
build_home q6
WS="$STATE_ROOT/ws/jobs"; mkdir -p "$WS"
JID="job-q6-22222"
printf '{"status":"queued","id":"%s","createdAt":"%s"}' "$JID" "$(iso_min -30)" > "$WS/$JID.json"
printf 'queued — waiting for slot\n' > "$WS/$JID.log"
run_watch() { # $1=jid  -- sequential reruns; the per-job mkdir lock is released
  # by the EXIT trap between runs, so idempotency must come from the
  # record-side dedupe (reason=queued_stall AND job=<jid>), not the lock.
  HOME="$HOME_DIR" LEADV2_ARM_COOLDOWN_DIR="$HOME_DIR/.claude/cache/arm-cooldown" \
  CODEX_QUEUED_STALL_MIN=10 CODEX_WATCH_POLL_S=1 CODEX_WATCH_MAX_S=5 \
    bash "$CODEX_TASK_SH" __quota-watch "$1" "$BASE" >/dev/null 2>&1 || true
}
run_watch "$JID"
run_watch "$JID"
D1_COUNT="$(grep -E "reason=queued_stall .* job=${JID}" "$ARM_CD" 2>/dev/null | wc -l | tr -d ' ')"
D1_LOG=0; grep -q 'CODEX_QUEUED_STALL' "$WS/$JID.log" 2>/dev/null && D1_LOG=1
if [[ "$D1_COUNT" -eq 1 ]] && [[ "$D1_LOG" -eq 1 ]]; then
  pass "q6 queued-stall records one cooldown line + one job-log line across two reruns (idempotent)"
else
  fail "q6 queued-stall idempotency (cooldown lines=$D1_COUNT, job-log line=$D1_LOG)"
fi

# ── q7 (D2): the very next dispatch while q6's stall cooldown is live is ───
# turned away on stderr by the quota gate (same HOME_DIR -> q6's cooldown).
run_case q7 task "q7-probe" --cwd "$BASE"
if [[ "$RUN_RC" -eq 2 ]] && grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' "$RUN_ERR"; then
  pass "q7 next dispatch during live queued_stall cooldown refused (rc 2 + marker)"
else
  fail "q7 next dispatch during live queued_stall cooldown refused (rc=$RUN_RC)"
fi

# ── q8 (FIX2): a `started` job past the stall threshold must NOT trip a ────
# queued_stall cooldown. FIX2 split the case arm so only `queued` records; a
# started job has pid/log-progress signals and wall-clock age alone must not
# condemn it. Fresh HOME; startedAt 30 min in the past (>= CODEX_QUEUED_STALL_MIN).
build_home q8-started
WS="$STATE_ROOT/ws/jobs"; mkdir -p "$WS"
JID="job-q8s-33333"
printf '{"status":"started","id":"%s","startedAt":"%s"}' "$JID" "$(iso_min -30)" > "$WS/$JID.json"
printf 'running...\n' > "$WS/$JID.log"
HOME="$HOME_DIR" LEADV2_ARM_COOLDOWN_DIR="$HOME_DIR/.claude/cache/arm-cooldown" \
CODEX_QUEUED_STALL_MIN=10 CODEX_WATCH_POLL_S=1 CODEX_WATCH_MAX_S=3 \
  bash "$CODEX_TASK_SH" __quota-watch "$JID" "$BASE" >/dev/null 2>&1 || true
Q8S_COUNT=0
[[ -f "$ARM_CD" ]] && Q8S_COUNT="$(grep -E "reason=queued_stall .* job=${JID}" "$ARM_CD" 2>/dev/null | wc -l | tr -d ' ')"
Q8S_LOG=0; grep -q 'CODEX_QUEUED_STALL' "$WS/$JID.log" 2>/dev/null && Q8S_LOG=1
if [[ "$Q8S_COUNT" -eq 0 ]] && [[ "$Q8S_LOG" -eq 0 ]]; then
  pass "q8 started job past stall threshold does NOT record a queued_stall cooldown"
else
  fail "q8 started job past stall threshold does NOT record a queued_stall cooldown (cooldown lines=$Q8S_COUNT, job-log line=$Q8S_LOG)"
fi

# ── q9 (FIX2): a queued stall recorded, THEN the job dies on a real usage ──
# limit -> the terminal-state handler STILL records the quota cooldown (and
# opens the circuit). This is the whole point of FIX2 (no `return 0` on stall):
# the watcher keeps polling, so a genuine later usage-limit death reaches
# failed|terminated -> _codex_quota_watch_record -> codex_circuit_open, which
# the bare `return 0` previously made unreachable. Requires the quota recorder's
# dedupe to be reason-scoped (a prior queued_stall line must not suppress the
# quota record) -- also fixed under FIX2. Fresh HOME; job queued + 30 min old.
build_home q9
WS="$STATE_ROOT/ws/jobs"; mkdir -p "$WS"
JID="job-q9-44444"
printf '{"status":"queued","id":"%s","createdAt":"%s"}' "$JID" "$(iso_min -30)" > "$WS/$JID.json"
printf 'queued — waiting for slot\n' > "$WS/$JID.log"
# Flipper: after 3 s, flip the job to failed + a usage-limit signature so the
# watcher's later poll hits the terminal quota arm.
( sleep 3; \
  printf '{"status":"failed","id":"%s","createdAt":"%s"}' "$JID" "$(iso_min -30)" > "$WS/$JID.json"; \
  printf 'Codex error: You have hit your usage limit. Please try again at Aug 5th, 2026 10:55 AM.\n' > "$WS/$JID.log" \
) &
Q9_FLIPPER=$!
HOME="$HOME_DIR" \
LEADV2_ARM_COOLDOWN_DIR="$HOME_DIR/.claude/cache/arm-cooldown" \
LEADV2_CODEX_CIRCUIT_FILE="$HOME_DIR/.claude/cache/codex-circuit.json" \
CODEX_QUEUED_STALL_MIN=10 CODEX_WATCH_POLL_S=1 CODEX_WATCH_MAX_S=20 \
  bash "$CODEX_TASK_SH" __quota-watch "$JID" "$BASE" >/dev/null 2>&1 || true
wait "$Q9_FLIPPER" 2>/dev/null || true
Q9_STALL="$(grep -E "reason=queued_stall .* job=${JID}" "$ARM_CD" 2>/dev/null | wc -l | tr -d ' ')"
Q9_QUOTA="$(grep -E "reason=quota .* job=${JID}" "$ARM_CD" 2>/dev/null | wc -l | tr -d ' ')"
Q9_CIRCUIT=0; [[ -s "$HOME_DIR/.claude/cache/codex-circuit.json" ]] && Q9_CIRCUIT=1
if [[ "$Q9_STALL" -eq 1 ]] && [[ "$Q9_QUOTA" -eq 1 ]] && [[ "$Q9_CIRCUIT" -eq 1 ]]; then
  pass "q9 queued stall then terminal quota death still records the quota cooldown (+ circuit)"
else
  fail "q9 queued stall then terminal quota death still records the quota cooldown (stall=$Q9_STALL, quota=$Q9_QUOTA, circuit=$Q9_CIRCUIT)"
fi

# ── q10 (C): empty reader + a queued_stall recorded <24h ago (cooldown ────
# EXPIRED so the gate reaches the reader instead of refusing) -> one WARN line
# naming the blind spot, dispatch still proceeds (fail-open policy unchanged).
build_home q10-blind
cat > "$BASE/reader_empty.py" <<'EOF'
import sys; sys.exit(0)
EOF
cat > "$BASE/routing.yaml" <<'EOF'
codex_quota_gate:
  build_threshold_pct: 80
EOF
printf '%s ARM_COOLDOWN arm=codex reason=queued_stall reprobe_at=%s cooldown_s=1 advisory_until=na advisory=ignored src=default job=old-1\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(iso_min -5)" > "$ARM_CD"
HOME="$HOME_DIR" PATH="$STUBBIN:$PATH" \
LEADV2_ROUTING_YAML="$BASE/routing.yaml" LEADV2_QUOTA_READ="$BASE/reader_empty.py" \
  bash "$CODEX_TASK_SH" task "q10-probe" --cwd "$BASE" >"$BASE/q10.out" 2>"$BASE/q10.err" || RUN_RC=$?
if grep -q 'codex quota reader blind + recent queued_stall' "$BASE/q10.err" \
   && [[ "${RUN_RC:-0}" -ne 2 ]]; then
  pass "q10 blind reader + recent queued_stall -> one WARN line, dispatch proceeds (rc=${RUN_RC:-0})"
else
  fail "q10 blind reader + recent queued_stall -> WARN + proceed (rc=${RUN_RC:-0})"
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
