#!/usr/bin/env bash
# Hermetic checks for the in-session founder-status wake watcher.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/leadv2-temp.sh"

WATCH_SH="${SCRIPT_DIR}/leadv2-pulse-watch.sh"
ARM_SH="${PLUGIN_DIR}/hooks/leadv2-pulse-watch-arm.sh"
PASS=0; FAIL=0; ERRORS=()
log() { printf '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir pulse-watch)"
REPO="$TMP/proj"
STATE="$TMP/state"
mkdir -p "$REPO/docs/leadv2" "$STATE"
git -C "$REPO" init -q
lv2_assert_scratch_repo "$REPO"
STATUS="$REPO/docs/leadv2/founder-status.md"

watch() {
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$STATE" \
    LEADV2_PULSE_WATCH_INTERVAL_S=5 "$@"
}

# T1/T3: a pre-existing unchanged file never emits, including first observation.
printf 'initial header\nbody\n' >"$STATUS"
OUT1="$TMP/out1"
watch bash "$WATCH_SH" --emit-loop --max-iters 2 >"$OUT1" 2>"$TMP/err1"
if [[ ! -s "$OUT1" ]]; then pass 'T1/T3: unchanged pre-existing fixture stays silent'; else fail "T1/T3: unexpected output: $(cat "$OUT1")"; fi

# T2: a rewrite after arming emits exactly the first line once.
OUT2="$TMP/out2"
watch bash "$WATCH_SH" --emit-loop --max-iters 2 >"$OUT2" 2>"$TMP/err2" &
PID=$!
sleep 2
printf 'changed header\nbody\n' >"$STATUS"
wait "$PID"
if [[ "$(cat "$OUT2")" == 'changed header' && "$(wc -l <"$OUT2" | tr -d ' ')" == 1 ]]; then pass 'T2: rewrite emits one first-header line'; else fail "T2: expected changed header once, got: $(cat "$OUT2")"; fi

# T4: absence at arm then creation is a beat.
rm -f "$STATUS"
OUT4="$TMP/out4"
watch bash "$WATCH_SH" --emit-loop --max-iters 2 >"$OUT4" 2>"$TMP/err4" &
PID=$!
sleep 2
printf 'created header\n' >"$STATUS"
wait "$PID"
if [[ "$(cat "$OUT4")" == 'created header' ]]; then pass 'T4: creation after arm wakes'; else fail "T4: expected created header, got: $(cat "$OUT4")"; fi

# T5: empty first line yields a nonblank fallback.
OUT5="$TMP/out5"
watch bash "$WATCH_SH" --emit-loop --max-iters 2 >"$OUT5" 2>"$TMP/err5" &
PID=$!
sleep 2
printf '\nbody\n' >"$STATUS"
wait "$PID"
if grep -q '\[BROAD_STATUS\]' "$OUT5" && [[ -s "$OUT5" ]]; then pass 'T5: empty header emits fallback'; else fail "T5: missing fallback: $(cat "$OUT5")"; fi

# T6/T7: switch silences both modes; print is a safe canonical command.
PRINT_OFF="$(env LEADV2_PULSE_WATCH=0 LEADV2_PROJECT_ROOT="$REPO" bash "$WATCH_SH" --print)"
LOOP_OFF="$(env LEADV2_PULSE_WATCH=0 LEADV2_PROJECT_ROOT="$REPO" bash "$WATCH_SH" --emit-loop --max-iters 1)"; LOOP_RC=$?
if [[ -z "$PRINT_OFF" && -z "$LOOP_OFF" && "$LOOP_RC" -eq 0 ]]; then pass 'T6: kill switch is silent and successful'; else fail 'T6: kill switch did not fully silence'; fi
PRINT="$(env CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" LEADV2_PROJECT_ROOT="$REPO" bash "$WATCH_SH" --print)"
if [[ "$(printf '%s\n' "$PRINT" | wc -l | tr -d ' ')" == 1 && "$PRINT" == *'--emit-loop' && "$PRINT" != *'codex-task.sh'* ]]; then pass 'T7: print is one safe watcher command'; else fail "T7: invalid print: $PRINT"; fi

# T8–T10: arm only a main-checkout lead, not a worker/subagent.
LEAD_OUT="$(printf '{"session_id":"pulse-test","cwd":"%s"}' "$REPO" | env CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$ARM_SH")"
if python3 -c 'import json,sys; d=json.load(sys.stdin); c=d["hookSpecificOutput"]["additionalContext"]; assert "PULSE-WAKE" in c and "persistent=true" in c' <<<"$LEAD_OUT"; then pass 'T8: lead arm output is valid persistent PULSE-WAKE JSON'; else fail "T8: invalid arm output: $LEAD_OUT"; fi
SUB_OUT="$(printf '{"agent_type":"developer","cwd":"%s"}' "$REPO" | env CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$ARM_SH")"
if [[ -z "$SUB_OUT" ]]; then pass 'T9: subagent is gated out'; else fail "T9: subagent output: $SUB_OUT"; fi
WORKER="$REPO/.claude/worktrees/lane"
mkdir -p "$WORKER"
WORK_OUT="$(printf '{"cwd":"%s"}' "$WORKER" | env CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$ARM_SH")"
if [[ -z "$WORK_OUT" ]]; then pass 'T10: worktree is gated out'; else fail "T10: worktree output: $WORK_OUT"; fi

# T11/T12: malformed interval falls back without an error; both files parse.
MALFORMED_OUT="$(env LEADV2_PROJECT_ROOT="$REPO" LEADV2_PULSE_WATCH_INTERVAL_S=abc bash "$WATCH_SH" --emit-loop --max-iters 1)"; MALFORMED_RC=$?
if [[ -z "$MALFORMED_OUT" && "$MALFORMED_RC" -eq 0 ]]; then pass 'T11: malformed interval falls back safely'; else fail 'T11: malformed interval failed'; fi
if bash -n "$WATCH_SH" && bash -n "$ARM_SH"; then pass 'T12: new shell files parse'; else fail 'T12: bash -n failed'; fi

rm -rf "$TMP"
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then printf '%s\n' "${ERRORS[@]}"; exit 1; fi
