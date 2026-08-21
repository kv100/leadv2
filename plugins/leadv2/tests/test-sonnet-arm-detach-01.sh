#!/usr/bin/env bash
# tests/test-sonnet-arm-detach-01.sh — regression test for SD-SONNET-ARM-DETACH-01.
#
# Defect: claude-subsession.sh's non-`--wait` (background/sonnet-arm) path backgrounded
# `run_subsession &` (which invokes `claude "${CLAUDE_ARGS[@]}"`) in the SAME process
# group as the invoking shell -- no setsid, unlike glm-coder.sh/kimi-coder.sh/codex-task.sh
# which all already use setsid_wrapper() for their own background workers. Any later
# unrelated Bash-tool call in the same session hitting its 2-minute timeout would send a
# group-directed SIGTERM that killed the still-running sonnet worker too, even though its
# caller had already received a PID and believed it detached. This is the identical class
# of bug CODEX-DETACH-01 fixed for the codex --background arm earlier the same day
# (2026-08-21); leadv2-dispatch-code.sh:2921's own comment claiming both launchers already
# "detach on their own" was false for the sonnet arm until this fix.
#
# Fix: the background spawn call site in claude-subsession.sh now routes the `claude`
# worker through the SAME os.setsid()+execvp() setsid_wrapper() idiom glm-coder.sh/
# kimi-coder.sh/codex-task.sh use, so $! is the pid of the ALREADY-detached `claude`
# process (own session/process-group) -- a SIGTERM to the launching shell's process group
# can no longer reach it. The sonnet arm's liveness check
# (leadv2-dispatch-code.sh:_dispatch_worker_liveness, `kill -0 "$pid"`) still works
# unchanged: setsid() does not break the parent-child relationship `wait $PID` and
# `kill -0 $PID` rely on, only session/process-group membership -- no reaper-side change
# was needed (unlike CODEX-DETACH-01, whose pid_alive() had to grow a killpg fallback
# because codex's job registry pid tracking broke differently).
#
# This test proves the mechanism directly (Part A: a child launched via claude-subsession
# .sh's actual setsid_wrapper() survives a group-directed SIGTERM aimed at its launcher's
# process group) and FALSIFIES it by reverting to the pre-fix "no detach" invocation and
# showing that one dies (Part A old-mode) -- plus a static source check that the
# background (non-`--wait`) spawn call site is routed through setsid_wrapper, and that the
# foreground `--wait` path (`run_subsession`, used synchronously) is untouched (Part B).
#
# Usage: bash tests/test-sonnet-arm-detach-01.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"
SUBSESSION_SH="${SCRIPTS_DIR}/claude-subsession.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

TMPD="$(mktemp -d)"
cleanup() { rm -rf "$TMPD" 2>/dev/null || true; }
trap cleanup EXIT

# ── Part A: process-group survival, exercising the REAL setsid_wrapper() ───
# Extract the actual function body from claude-subsession.sh (not a reimplementation)
# so the test dies if the function is renamed/removed without updating this test, and
# passes only when the real production code detaches correctly.
FUNCS_FILE="${TMPD}/funcs.sh"
sed -n '/^setsid_wrapper() {/,/^}$/p' "$SUBSESSION_SH" > "$FUNCS_FILE"
if [[ ! -s "$FUNCS_FILE" ]]; then
  fail "could not extract setsid_wrapper() from claude-subsession.sh -- has it been renamed/removed?"
else
  pass "extracted setsid_wrapper() from claude-subsession.sh ($(wc -l < "$FUNCS_FILE") lines)"
fi

# _test_new_session_bg <cmd...> -- background <cmd...> into a NEW OS session
# (pid == pgid) standing in for "the harness's own process group" so Part A
# can SIGTERM it from outside, same idiom as test-codex-detach-01.sh /
# test-fanout-lane-detach.sh.
_test_new_session_bg() {
  ( exec python3 -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@" ) &
  _TNS_PID=$!
}

run_group_survival_test() {
  # $1 = "fixed" (use setsid_wrapper()) | "old" (verbatim pre-fix pattern: the worker
  # launched directly in the caller's own process group via a plain `&`, exactly what
  # claude-subsession.sh's non-`--wait` path did before SD-SONNET-ARM-DETACH-01).
  local mode="$1"
  local outf="${TMPD}/${mode}.out" markerf="${TMPD}/${mode}.marker"
  : > "$outf"
  if [[ "$mode" == "fixed" ]]; then
    _test_new_session_bg bash -c "
      source '$FUNCS_FILE'
      setsid_wrapper bash -c 'echo alive > \"$markerf\"; sleep 20' &
      echo \$! > '$outf'
    "
  else
    _test_new_session_bg bash -c "
      bash -c 'echo alive > \"$markerf\"; sleep 20' &
      echo \$! > '$outf'
    "
  fi
  local harness_pid=$_TNS_PID

  local waited=0
  while [[ ! -s "$outf" && "$waited" -lt 50 ]]; do sleep 0.1; waited=$(( waited + 1 )); done
  local spawned_pid; spawned_pid="$(cat "$outf" 2>/dev/null)"
  waited=0
  while [[ ! -f "$markerf" && "$waited" -lt 50 ]]; do sleep 0.1; waited=$(( waited + 1 )); done

  if [[ -z "$spawned_pid" ]]; then
    fail "${mode}: spawner never reported a pid"
    return
  fi

  # The exact action the harness performs on a timed-out Bash tool call.
  kill -TERM -- "-${harness_pid}" 2>/dev/null || true
  sleep 1

  if kill -0 "$spawned_pid" 2>/dev/null; then
    if [[ "$mode" == "fixed" ]]; then
      pass "fixed: setsid_wrapper-launched sonnet worker (pid=${spawned_pid}) SURVIVES a SIGTERM to its launcher's process group"
    else
      fail "old: undetached worker (pid=${spawned_pid}) survived group SIGTERM -- expected it to die (test setup contradicts the documented bug)"
    fi
    kill -TERM "$spawned_pid" 2>/dev/null || true
  else
    if [[ "$mode" == "fixed" ]]; then
      fail "fixed: setsid_wrapper-launched sonnet worker (pid=${spawned_pid}) died with its launcher's group -- SD-SONNET-ARM-DETACH-01 NOT fixed"
    else
      pass "old (pre-fix pattern): undetached worker died with its launcher's process group, reproducing the original bug -- this is the RED baseline the fix corrects"
    fi
  fi
}

run_group_survival_test fixed
run_group_survival_test old

# ── Part B: static wiring check — the background (non-`--wait`) spawn call site is
# routed through setsid_wrapper, and the foreground `--wait` path (`run_subsession`,
# called synchronously so it must die with its caller -- that IS `--wait`'s contract) is
# untouched. ─────────────────────────────────────────────────────────────────────────
if grep -q 'setsid_wrapper claude "${CLAUDE_ARGS\[@\]}" </dev/null > "$STREAM_OUT" 2>&1 &' "$SUBSESSION_SH"; then
  pass "background spawn call site routes the claude worker through setsid_wrapper"
else
  fail "did not find the expected setsid_wrapper-wrapped background claude invocation in claude-subsession.sh"
fi

# The synchronous --wait path (`run_subsession` called plain, no trailing `&`, no
# setsid_wrapper) must be byte-identical to before this fix -- detaching a blocking
# caller's own worker would defeat --wait's contract.
if grep -q '^  run_subsession$' "$SUBSESSION_SH"; then
  pass "the foreground --wait path (plain 'run_subsession' call) is untouched -- no detach applied to a blocking caller"
else
  fail "could not find the untouched foreground --wait 'run_subsession' call -- verify no drive-by change to synchronous dispatch"
fi

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[[ "$FAIL" -eq 0 ]]
