#!/usr/bin/env bash
# test-codex-quota-guardrails.sh — CODEX-QUOTA-GUARDRAILS-01
#
# Tests: (a) effort pinned on every spawn path, (b) xhigh only with --tier top
# + --reason, (c) circuit-open on usage-limit, (d) direct-exec hook,
# (e) resolver-unreachable fail-closed, (e2) quota reader missing fail-open.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
CODEX_TASK_SH="${SCRIPTS_DIR}/codex-task.sh"
PLANNER_SH="${SCRIPTS_DIR}/leadv2-codex-planner.sh"
RUNNER_SH="${SCRIPTS_DIR}/leadv2-codex-session-runner.sh"
CIRCUIT_LIB="${SCRIPTS_DIR}/lib/leadv2-codex-circuit.sh"
QUOTA_GATE_LIB="${SCRIPTS_DIR}/lib/leadv2-codex-quota-gate.sh"
HOOK_SH="${PLUGIN_ROOT}/hooks/leadv2-codex-direct-exec-guard.sh"

PASS=0
FAIL=0
pass() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/codex-grd.XXXXXX")"
trap 'rm -rf "$BASE"' EXIT

# ── shared stubs ───────────────────────────────────────────────────────────
STUBBIN="$BASE/stubbin"
mkdir -p "$STUBBIN"

# Stub `codex` to record argv and exit 0.
cat > "$STUBBIN/codex" <<'EOF'
#!/usr/bin/env bash
echo "ARGS: $*" >> "$CODEX_ARGV_LOG"
exit 0
EOF
chmod +x "$STUBBIN/codex"

# Stub `node` so codex-task.sh can find a companion and exit fast.
ISOLATED_HOME="$BASE/home"
mkdir -p "$ISOLATED_HOME/.claude/plugins/cache/openai-codex/codex/1.0.4/scripts"
printf 'process.exit(0);\n' > "$ISOLATED_HOME/.claude/plugins/cache/openai-codex/codex/1.0.4/scripts/codex-companion.mjs"

# Temp project root for planner tests — codex_enabled: true so the policy
# check passes and the planner reaches tier resolution / --print-model.
PLANNER_ROOT="$BASE/planner-root"
mkdir -p "$PLANNER_ROOT/.claude/leadv2-overrides"
printf 'codex_enabled: true\n' > "$PLANNER_ROOT/.claude/leadv2-overrides/codex-policy.yaml"

cat > "$STUBBIN/node" <<'EOF'
#!/usr/bin/env bash
echo "[fake-node] argv=$*" >> "${CODEX_ARGV_LOG:-/dev/null}"
exit 0
EOF
chmod +x "$STUBBIN/node"

# ── iso_now helper ─────────────────────────────────────────────────────────
iso_now() {
  python3 -c 'import datetime; print(datetime.datetime.now(datetime.UTC).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ"))'
}
iso_offset() { # $1=hours
  python3 -c 'import sys,datetime; print((datetime.datetime.now(datetime.UTC).replace(microsecond=0)+datetime.timedelta(hours=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"
}

# ═══════════════════════════════════════════════════════════════════════════
# Group A: effort pinned on every spawn path
# ═══════════════════════════════════════════════════════════════════════════

# a1: no --tier → effort=medium (standard default)
ARGV_LOG="$BASE/a1.argv"
HOME="$ISOLATED_HOME" PATH="$STUBBIN:$PATH" CODEX_ARGV_LOG="$ARGV_LOG" \
  CODEX_SKIP_QUOTA_GATE=1 \
  bash "$CODEX_TASK_SH" task "a1-probe" --cwd "$BASE" >/dev/null 2>&1 || true
if grep -q -- '--effort medium' "$ARGV_LOG" 2>/dev/null; then
  pass "a1 no-tier → --effort medium"
else
  fail "a1 no-tier → --effort medium (argv=$(cat "$ARGV_LOG" 2>/dev/null))"
fi

# a2: --tier standard → effort=medium
ARGV_LOG="$BASE/a2.argv"
HOME="$ISOLATED_HOME" PATH="$STUBBIN:$PATH" CODEX_ARGV_LOG="$ARGV_LOG" \
  CODEX_SKIP_QUOTA_GATE=1 \
  bash "$CODEX_TASK_SH" task "a2-probe" --tier standard --cwd "$BASE" >/dev/null 2>&1 || true
if grep -q -- '--effort medium' "$ARGV_LOG" 2>/dev/null; then
  pass "a2 --tier standard → --effort medium"
else
  fail "a2 --tier standard → --effort medium (argv=$(cat "$ARGV_LOG" 2>/dev/null))"
fi

# a3: --tier volume → effort=low
ARGV_LOG="$BASE/a3.argv"
HOME="$ISOLATED_HOME" PATH="$STUBBIN:$PATH" CODEX_ARGV_LOG="$ARGV_LOG" \
  CODEX_SKIP_QUOTA_GATE=1 \
  bash "$CODEX_TASK_SH" task "a3-probe" --tier volume --cwd "$BASE" >/dev/null 2>&1 || true
if grep -q -- '--effort low' "$ARGV_LOG" 2>/dev/null; then
  pass "a3 --tier volume → --effort low"
else
  fail "a3 --tier volume → --effort low (argv=$(cat "$ARGV_LOG" 2>/dev/null))"
fi

# a4: spawn gate passes when circuit closed
A4_CIRCUIT="$BASE/a4-circuit.json"
A4_COOLDOWN="$BASE/a4-cooldown"
mkdir -p "$A4_COOLDOWN"
A4_RC=0
LEADV2_CODEX_CIRCUIT_FILE="$A4_CIRCUIT" LEADV2_ARM_COOLDOWN_DIR="$A4_COOLDOWN" \
  bash -c "source '$QUOTA_GATE_LIB'; codex_spawn_gate exec" 2>/dev/null || A4_RC=$?
if [[ $A4_RC -eq 0 ]]; then
  pass "a4 spawn gate passes when circuit closed"
else
  fail "a4 spawn gate passes when circuit closed (rc=$A4_RC)"
fi

# a5: planner --print-model (no tier) → effort=medium
# Use real HOME so python3 can import yaml; LEADV2_PROJECT_ROOT overrides the
# policy-file lookup path.
PLANNER_OUT="$BASE/a5.out"
PATH="$STUBBIN:$PATH" \
  LEADV2_PROJECT_ROOT="$PLANNER_ROOT" \
  bash "$PLANNER_SH" --print-model >"$PLANNER_OUT" 2>&1 || true
if grep -q 'effort=medium' "$PLANNER_OUT" 2>/dev/null; then
  pass "a5 planner default tier → effort=medium"
else
  fail "a5 planner default tier → effort=medium (out=$(cat "$PLANNER_OUT" 2>/dev/null))"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Group B: xhigh only with --tier top + --reason
# ═══════════════════════════════════════════════════════════════════════════

# b1a: codex-task --tier top without --reason → refused rc 2
B1A_RC=0
HOME="$ISOLATED_HOME" PATH="$STUBBIN:$PATH" CODEX_SKIP_QUOTA_GATE=1 \
  bash "$CODEX_TASK_SH" task "b1-probe" --tier top --cwd "$BASE" >/dev/null 2>&1 || B1A_RC=$?
if [[ $B1A_RC -eq 2 ]]; then
  pass "b1a codex-task --tier top without --reason → refused rc 2"
else
  fail "b1a codex-task --tier top without --reason → refused rc 2 (rc=$B1A_RC)"
fi

# b1b: planner --tier top without --reason → refused rc 2
B1B_RC=0
PATH="$STUBBIN:$PATH" \
  LEADV2_PROJECT_ROOT="$PLANNER_ROOT" \
  bash "$PLANNER_SH" --print-model --tier top >/dev/null 2>&1 || B1B_RC=$?
if [[ $B1B_RC -eq 2 ]]; then
  pass "b1b planner --tier top without --reason → refused rc 2"
else
  fail "b1b planner --tier top without --reason → refused rc 2 (rc=$B1B_RC)"
fi

# b2: --tier top --reason → permitted (xhigh or high)
ARGV_LOG="$BASE/b2.argv"
HOME="$ISOLATED_HOME" PATH="$STUBBIN:$PATH" CODEX_ARGV_LOG="$ARGV_LOG" \
  CODEX_SKIP_QUOTA_GATE=1 \
  bash "$CODEX_TASK_SH" task "b2-probe" --tier top --reason "heavy arch plan" --cwd "$BASE" >/dev/null 2>&1 || true
if grep -qE -- '--effort (xhigh|high)' "$ARGV_LOG" 2>/dev/null; then
  pass "b2 --tier top --reason → xhigh/high permitted"
else
  fail "b2 --tier top --reason → xhigh/high permitted (argv=$(cat "$ARGV_LOG" 2>/dev/null))"
fi

# b3: standard tier does not emit xhigh
ARGV_LOG="$BASE/b3.argv"
HOME="$ISOLATED_HOME" PATH="$STUBBIN:$PATH" CODEX_ARGV_LOG="$ARGV_LOG" \
  CODEX_SKIP_QUOTA_GATE=1 \
  bash "$CODEX_TASK_SH" task "b3-probe" --tier standard --cwd "$BASE" >/dev/null 2>&1 || true
if grep -q -- 'xhigh' "$ARGV_LOG" 2>/dev/null; then
  fail "b3 standard tier emitted xhigh (argv=$(cat "$ARGV_LOG" 2>/dev/null))"
else
  pass "b3 standard tier does not emit xhigh"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Group C: circuit-open on usage-limit
# ═══════════════════════════════════════════════════════════════════════════

# c1: parse "try again at Aug 8th, 2026 08:49 AM" → 2026-08-08T08:49:00Z
C1_OUT="$(printf 'You'\''ve hit your usage limit. Please try again at Aug 8th, 2026 08:49 AM' \
  | bash -c "source '$CIRCUIT_LIB'; codex_circuit_parse_until" 2>/dev/null)"
if [[ "$C1_OUT" == "2026-08-08T08:49:00Z" ]]; then
  pass "c1 parse usage-limit date → 2026-08-08T08:49:00Z"
else
  fail "c1 parse usage-limit date → 2026-08-08T08:49:00Z (got: $C1_OUT)"
fi

# c2: unparseable → parser returns empty → open defaults to now+24h (±120s).
# Drives the real two-step the session-runner now performs (M5): parse_until on
# fixture log → empty → codex_circuit_open with empty first arg.
C2_CIRCUIT="$BASE/c2-circuit.json"
C2_JOURNAL="$BASE/c2.journal"
C2_LOG="$BASE/c2-fixture.log"
printf '%s\n' \
  '{"type":"thread.started","thread_id":"th_c2"}' \
  "Codex error: rate limit exceeded, retry soon" > "$C2_LOG"
# step 1 — real parser on real unparseable provider text ⇒ rc 1, empty stdout
C2_UNTIL="$(cat "$C2_LOG" | bash -c "source '$CIRCUIT_LIB'; codex_circuit_parse_until" 2>/dev/null || true)"
# step 2 — feed that empty result to the real opener
LEADV2_CODEX_CIRCUIT_FILE="$C2_CIRCUIT" \
  bash -c "source '$CIRCUIT_LIB'; codex_circuit_open '$C2_UNTIL' 'test'" 2>"$C2_JOURNAL"
C2_STATE="$(LEADV2_CODEX_CIRCUIT_FILE="$C2_CIRCUIT" bash -c "source '$CIRCUIT_LIB'; codex_circuit_state" 2>/dev/null)"
C2_CHECK="$(python3 -c '
import sys, datetime
parts = sys.argv[1].split()
until_str = parts[1] if len(parts) > 1 else ""
try:
    now = datetime.datetime.now(datetime.UTC)
    until = datetime.datetime.strptime(until_str, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.UTC)
    diff = (until - now).total_seconds()
    print("ok" if 86280 <= diff <= 86520 else "bad:%d" % diff)
except Exception as e:
    print("err:%s" % e)
' "$C2_STATE" 2>/dev/null)"
if [[ -z "$C2_UNTIL" ]] && [[ "$C2_CHECK" == "ok" ]]; then
  pass "c2 unparseable → parser declined + until ≈ now+24h"
else
  fail "c2 unparseable → parser declined + until ≈ now+24h (until='$C2_UNTIL', state=$C2_STATE, check=$C2_CHECK)"
fi

# c3: while open → gate refuses, rc 2, no codex argv
C3_CIRCUIT="$BASE/c3-circuit.json"
C3_COOLDOWN="$BASE/c3-cooldown"
mkdir -p "$C3_COOLDOWN"
printf '{"until":"%s","opened_at":"%s","source":"test","reason":"usage_limit"}' \
  "$(iso_offset 12)" "$(iso_now)" > "$C3_CIRCUIT"
C3_RC=0
LEADV2_CODEX_CIRCUIT_FILE="$C3_CIRCUIT" LEADV2_ARM_COOLDOWN_DIR="$C3_COOLDOWN" \
  bash -c "source '$QUOTA_GATE_LIB'; codex_spawn_gate exec" 2>/tmp/c3.err || C3_RC=$?
if [[ $C3_RC -eq 2 ]] \
   && grep -q 'LEADV2_DISPATCH_REFUSED: quota_gate' /tmp/c3.err \
   && grep -q 'reason=circuit' /tmp/c3.err; then
  pass "c3 gate refuses while circuit open (rc 2, marker)"
else
  fail "c3 gate refuses while circuit open (rc=$C3_RC, err=$(cat /tmp/c3.err 2>/dev/null))"
fi

# c4: until in the past → gate passes
C4_CIRCUIT="$BASE/c4-circuit.json"
printf '{"until":"%s","opened_at":"%s","source":"test","reason":"usage_limit"}' \
  "$(iso_offset -1)" "$(iso_offset -2)" > "$C4_CIRCUIT"
C4_RC=0
LEADV2_CODEX_CIRCUIT_FILE="$C4_CIRCUIT" LEADV2_ARM_COOLDOWN_DIR="$C3_COOLDOWN" \
  bash -c "source '$QUOTA_GATE_LIB'; codex_spawn_gate exec" 2>/dev/null || C4_RC=$?
if [[ $C4_RC -eq 0 ]]; then
  pass "c4 circuit expired → gate passes"
else
  fail "c4 circuit expired → gate passes (rc=$C4_RC)"
fi

# c5: second refusal while open → journal has exactly one codex_circuit_open line.
# Use a fixed until so both calls attempt the same timestamp — the second must
# be suppressed by the idempotency check (existing until >= new until).
C5_CIRCUIT="$BASE/c5-circuit.json"
rm -f "$C5_CIRCUIT"
C5_JOURNAL="$BASE/c5.journal"
C5_UNTIL="$(iso_offset 12)"
LEADV2_CODEX_CIRCUIT_FILE="$C5_CIRCUIT" \
  bash -c "source '$CIRCUIT_LIB'; codex_circuit_open '$C5_UNTIL' 'test'" 2>"$C5_JOURNAL"
LEADV2_CODEX_CIRCUIT_FILE="$C5_CIRCUIT" \
  bash -c "source '$CIRCUIT_LIB'; codex_circuit_open '$C5_UNTIL' 'test'" 2>>"$C5_JOURNAL"
C5_COUNT="$(grep -c 'codex_circuit_open' "$C5_JOURNAL" 2>/dev/null || true)"
C5_COUNT="$(printf '%s' "$C5_COUNT" | tr -d '[:space:]')"
if [[ "$C5_COUNT" == "1" ]]; then
  pass "c5 idempotent: exactly one codex_circuit_open journal line"
else
  fail "c5 idempotent: exactly one journal line (got '$C5_COUNT')"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Group D: hook tests
# ═══════════════════════════════════════════════════════════════════════════

hook_run() { # stdin=JSON, stdout captured
  bash "$HOOK_SH" 2>/dev/null
  return $?
}

# d1: codex exec → rc 2, deny
D1_RC=0
printf '{"tool_name":"Bash","tool_input":{"command":"codex exec \\"do work\\""}}' \
  | bash "$HOOK_SH" 2>/tmp/d1.err || D1_RC=$?
if [[ $D1_RC -eq 2 ]] && grep -q 'BLOCKED' /tmp/d1.err; then
  pass "d1 hook blocks bare codex exec (rc 2, deny line)"
else
  fail "d1 hook blocks bare codex exec (rc=$D1_RC, err=$(cat /tmp/d1.err 2>/dev/null))"
fi

# d2: LEADV2_CODEX_SANCTIONED is NOT an escape hatch (removed — hook procs never
# see a sibling's exports). Must still block.
D2_RC=0
printf '{"tool_name":"Bash","tool_input":{"command":"codex exec \\"x\\""}}' \
  | LEADV2_CODEX_SANCTIONED=1 bash "$HOOK_SH" 2>/tmp/d2.err || D2_RC=$?
if [[ $D2_RC -eq 2 ]] && grep -q 'BLOCKED' /tmp/d2.err; then
  pass "d2 hook blocks despite LEADV2_CODEX_SANCTIONED=1"
else
  fail "d2 hook blocks despite LEADV2_CODEX_SANCTIONED=1 (rc=$D2_RC, err=$(cat /tmp/d2.err 2>/dev/null))"
fi

# d3: LEADV2_ALLOW_DIRECT_CODEX=1 → rc 0 + logged line
D3_RC=0
printf '{"tool_name":"Bash","tool_input":{"command":"codex exec \\"x\\""}}' \
  | LEADV2_ALLOW_DIRECT_CODEX=1 bash "$HOOK_SH" 2>/tmp/d3.err || D3_RC=$?
if [[ $D3_RC -eq 0 ]] && grep -q 'ALLOWED' /tmp/d3.err; then
  pass "d3 hook allows LEADV2_ALLOW_DIRECT_CODEX=1 + logged"
else
  fail "d3 hook allows LEADV2_ALLOW_DIRECT_CODEX=1 (rc=$D3_RC, err=$(cat /tmp/d3.err))"
fi

# d4: bash .../codex-task.sh task "x" → rc 0
D4_RC=0
printf '{"tool_name":"Bash","tool_input":{"command":"bash ~/.claude/scripts/codex-task.sh task \\"x\\""}}' \
  | bash "$HOOK_SH" 2>/dev/null || D4_RC=$?
if [[ $D4_RC -eq 0 ]]; then
  pass "d4 hook allows codex-task.sh invocation"
else
  fail "d4 hook allows codex-task.sh invocation (rc=$D4_RC)"
fi

# d5: ls, git status, malformed JSON, empty stdin → rc 0
D5_PASS=1
printf '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash "$HOOK_SH" 2>/dev/null || D5_PASS=0
printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | bash "$HOOK_SH" 2>/dev/null || D5_PASS=0
printf 'not json' | bash "$HOOK_SH" 2>/dev/null || D5_PASS=0
printf '' | bash "$HOOK_SH" 2>/dev/null || D5_PASS=0
if [[ $D5_PASS -eq 1 ]]; then
  pass "d5 hook rc 0 on ls/git status/malformed/empty"
else
  fail "d5 hook rc 0 on ls/git status/malformed/empty"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Group E: fail-closed / fail-open contract
# ═══════════════════════════════════════════════════════════════════════════

# e1: unparseable circuit marker → gate refuses (fail-closed)
E1_DIR="$BASE/e1-circuit"
mkdir -p "$E1_DIR"
printf 'NOT VALID JSON{{{' > "$E1_DIR/codex-circuit.json"
E1_COOLDOWN="$BASE/e1-cool"
mkdir -p "$E1_COOLDOWN"
E1_RC=0
LEADV2_CODEX_CIRCUIT_FILE="$E1_DIR/codex-circuit.json" LEADV2_ARM_COOLDOWN_DIR="$E1_COOLDOWN" \
  bash -c "source '$QUOTA_GATE_LIB'; codex_spawn_gate exec" 2>/tmp/e1.err || E1_RC=$?
if [[ $E1_RC -eq 2 ]] && grep -q 'circuit-unknown' /tmp/e1.err; then
  pass "e1 unparseable circuit marker → gate refuses (fail-closed)"
else
  fail "e1 unparseable circuit marker → gate refuses (rc=$E1_RC, err=$(cat /tmp/e1.err))"
fi

# e2: quota reader missing → still fail-OPEN (regression guard)
E2_RC=0
HOME="$BASE/e2-home" PATH="$STUBBIN:$PATH" \
  LEADV2_QUOTA_READ="/nonexistent-reader.py" \
  CODEX_SKIP_QUOTA_GATE=0 \
  bash "$CODEX_TASK_SH" task "e2-probe" --cwd "$BASE" >/dev/null 2>/tmp/e2.err 2>&1 || E2_RC=$?
if [[ $E2_RC -ne 2 ]]; then
  pass "e2 quota reader missing → fail-OPEN (rc=$E2_RC != 2)"
else
  fail "e2 quota reader missing → fail-OPEN (got rc=2, err=$(cat /tmp/e2.err 2>/dev/null))"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Group F: session-runner ↔ gate integration tests (C2)
# ═══════════════════════════════════════════════════════════════════════════

# flock stub — always stub (tests use private TASK_DIR / lock files under $BASE).
cat > "$STUBBIN/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUBBIN/flock"

# Shared progress-fingerprint stub — prints a constant (avoids git).
F_PROGRESS="$BASE/f-progress.sh"
printf '#!/usr/bin/env bash\nprintf "f-constant"\n' > "$F_PROGRESS"
chmod +x "$F_PROGRESS"

# f1 — pre-opened circuit ⇒ exit 2, zero codex invocations.
F1_ROOT="$BASE/f1-root"; mkdir -p "$F1_ROOT"
F1_CIRCUIT="$BASE/f1-circuit.json"
F1_COOLDOWN="$BASE/f1-cooldown"; mkdir -p "$F1_COOLDOWN"
F1_BIN="$BASE/f1-bin"; mkdir -p "$F1_BIN"
F1_ARGV="$BASE/f1.argv"
cat > "$F1_BIN/codex" <<'STUB'
#!/usr/bin/env bash
echo "INVOKED" >> "$F1_ARGV_LOG"
exit 0
STUB
chmod +x "$F1_BIN/codex"
printf '{"until":"%s","opened_at":"%s","source":"test","reason":"usage_limit"}' \
  "$(iso_offset 12)" "$(iso_now)" > "$F1_CIRCUIT"
F1_RC=0
PATH="$STUBBIN:$PATH" \
  LEADV2_TASK_ID="f1-task" \
  LEADV2_PROJECT_ROOT="$F1_ROOT" \
  LEADV2_CODEX_BIN="$F1_BIN/codex" \
  LEADV2_CODEX_SKIP_LOGIN_CHECK=1 \
  LEADV2_CODEX_CIRCUIT_FILE="$F1_CIRCUIT" \
  LEADV2_ARM_COOLDOWN_DIR="$F1_COOLDOWN" \
  LEADV2_COMPLETION_RECEIPT="$BASE/f1-receipt.json" \
  LEADV2_RUNNER_MAX_ATTEMPTS=1 \
  LEADV2_RUNNER_RETRY_SLEEP_S=0 \
  LEADV2_PROGRESS_FINGERPRINT="$F_PROGRESS" \
  F1_ARGV_LOG="$F1_ARGV" \
  bash "$RUNNER_SH" >/dev/null 2>/tmp/f1.err || F1_RC=$?
if [[ $F1_RC -eq 2 ]] \
   && [[ ! -s "$F1_ARGV" ]] \
   && grep -q 'refused by quota gate' /tmp/f1.err; then
  pass "f1 pre-opened circuit → exit 2, zero codex invocations"
else
  fail "f1 pre-opened circuit → exit 2, zero codex invocations (rc=$F1_RC, argv=$(cat "$F1_ARGV" 2>/dev/null), err=$(cat /tmp/f1.err))"
fi

# f2 — stubbed codex emits the usage-limit line ⇒ circuit marker appears with
# the parsed horizon. Proves the runner DETECTS the wall and OPENS the circuit.
# The horizon must be in the FUTURE so codex_circuit_state still reads "open"
# when we assert; a hardcoded past date auto-closes and gives a false fail.
F2_HORIZON_ISO="$(python3 -c '
import datetime
now = datetime.datetime.now(datetime.UTC).replace(microsecond=0, second=0)
print((now + datetime.timedelta(hours=12)).strftime("%Y-%m-%dT%H:%M:%SZ"))
')"
F2_HORIZON_TEXT="$(python3 -c '
import datetime, sys
dt = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")
print(dt.strftime("%b %d, %Y %I:%M %p"))
' "$F2_HORIZON_ISO" 2>/dev/null)"
F2_ROOT="$BASE/f2-root"; mkdir -p "$F2_ROOT"
F2_CIRCUIT="$BASE/f2-circuit.json"
F2_COOLDOWN="$BASE/f2-cooldown"; mkdir -p "$F2_COOLDOWN"
F2_BIN="$BASE/f2-bin"; mkdir -p "$F2_BIN"
F2_ARGV="$BASE/f2.argv"
cat > "$F2_BIN/codex" <<STUB
#!/usr/bin/env bash
echo "INVOKED" >> "\$F2_ARGV_LOG"
printf '{"type":"thread.started","thread_id":"th_f2"}\n'
printf "Codex error: You've hit your usage limit. Please try again at ${F2_HORIZON_TEXT}\n"
exit 1
STUB
chmod +x "$F2_BIN/codex"
F2_RC=0
PATH="$STUBBIN:$PATH" \
  LEADV2_TASK_ID="f2-task" \
  LEADV2_PROJECT_ROOT="$F2_ROOT" \
  LEADV2_CODEX_BIN="$F2_BIN/codex" \
  LEADV2_CODEX_SKIP_LOGIN_CHECK=1 \
  LEADV2_CODEX_CIRCUIT_FILE="$F2_CIRCUIT" \
  LEADV2_ARM_COOLDOWN_DIR="$F2_COOLDOWN" \
  LEADV2_COMPLETION_RECEIPT="$BASE/f2-receipt.json" \
  LEADV2_RUNNER_MAX_ATTEMPTS=1 \
  LEADV2_RUNNER_RETRY_SLEEP_S=0 \
  LEADV2_PROGRESS_FINGERPRINT="$F_PROGRESS" \
  F2_ARGV_LOG="$F2_ARGV" \
  bash "$RUNNER_SH" >/dev/null 2>/tmp/f2.err || F2_RC=$?
F2_STATE=""
[[ -f "$F2_CIRCUIT" ]] && F2_STATE="$(LEADV2_CODEX_CIRCUIT_FILE="$F2_CIRCUIT" \
  bash -c "source '$CIRCUIT_LIB'; codex_circuit_state" 2>/dev/null || true)"
F2_JOURNAL_COUNT="$(grep -c "codex_circuit_open until=${F2_HORIZON_ISO}" /tmp/f2.err 2>/dev/null || true)"
F2_JOURNAL_COUNT="$(printf '%s' "$F2_JOURNAL_COUNT" | tr -d '[:space:]')"
F2_SPAWN_COUNT="$(wc -l < "$F2_ARGV" 2>/dev/null | tr -d '[:space:]')"
if [[ $F2_RC -eq 2 ]] \
   && [[ "$F2_STATE" == "open ${F2_HORIZON_ISO} session-runner" ]] \
   && [[ "$F2_JOURNAL_COUNT" == "1" ]] \
   && [[ "$F2_SPAWN_COUNT" == "1" ]]; then
  pass "f2 codex usage-limit → circuit opened with parsed horizon, 1 spawn"
else
  fail "f2 codex usage-limit → circuit opened with parsed horizon, 1 spawn (rc=$F2_RC, state='$F2_STATE', jcount='$F2_JOURNAL_COUNT', spawns='$F2_SPAWN_COUNT', err=$(head -5 /tmp/f2.err 2>/dev/null))"
fi

# f3 — fail-closed when the gate is unavailable ⇒ exit 2, no spawn.
# Copy runner + lib/ into scratch, delete quota-gate lib, run the copy.
F3_ROOT="$BASE/f3-root"; mkdir -p "$F3_ROOT"
F3_COOLDOWN="$BASE/f3-cooldown"; mkdir -p "$F3_COOLDOWN"
F3_SCRATCH="$BASE/f3-scratch"
mkdir -p "$F3_SCRATCH/lib"
cp "$RUNNER_SH" "$F3_SCRATCH/"
cp "$SCRIPTS_DIR/lib/"* "$F3_SCRATCH/lib/" 2>/dev/null || true
rm -f "$F3_SCRATCH/lib/leadv2-codex-quota-gate.sh"
F3_RC=0
PATH="$STUBBIN:$PATH" \
  LEADV2_TASK_ID="f3-task" \
  LEADV2_PROJECT_ROOT="$F3_ROOT" \
  LEADV2_CODEX_BIN="$STUBBIN/codex" \
  LEADV2_CODEX_SKIP_LOGIN_CHECK=1 \
  LEADV2_CODEX_CIRCUIT_FILE="$BASE/f3-circuit.json" \
  LEADV2_ARM_COOLDOWN_DIR="$F3_COOLDOWN" \
  LEADV2_COMPLETION_RECEIPT="$BASE/f3-receipt.json" \
  LEADV2_RUNNER_MAX_ATTEMPTS=1 \
  LEADV2_RUNNER_RETRY_SLEEP_S=0 \
  LEADV2_PROGRESS_FINGERPRINT="$F_PROGRESS" \
  CODEX_SKIP_QUOTA_GATE=0 \
  bash "$F3_SCRATCH/leadv2-codex-session-runner.sh" >/dev/null 2>/tmp/f3.err || F3_RC=$?
if [[ $F3_RC -eq 2 ]] \
   && grep -q 'quota gate unavailable' /tmp/f3.err; then
  pass "f3 gate unavailable → exit 2, no spawn"
else
  fail "f3 gate unavailable → exit 2, no spawn (rc=$F3_RC, err=$(cat /tmp/f3.err 2>/dev/null))"
fi

# ═══════════════════════════════════════════════════════════════════════════
printf '\n[CODEX-QUOTA-GUARDRAILS] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
