#!/usr/bin/env bash
# tests/test-codex-detach-01.sh — regression test for CODEX-DETACH-01.
#
# Defect: codex-task.sh's `task`/`review` --background path spawned
# `node "$COMPANION" ... --background` (directly, or under `timeout`/
# `gtimeout`) in the SAME process group as the invoking shell. When any
# later unrelated Bash-tool call in the same session hit its 2-minute
# timeout, the harness's group-directed SIGTERM killed the still-running
# background worker too, even though it had already returned a jobId and
# was believed detached (4/4 lanes reaped worker_process_died /
# worker_died_stale, 2026-08-21).
#
# Fix: `_run_node()` in codex-task.sh now routes --background invocations
# through the same os.setsid()+execvp() mechanism glm-coder.sh/kimi-
# coder.sh already use for their own background workers (setsid_wrapper()),
# so the spawned process gets its own session/process-group and survives a
# SIGTERM aimed at the launching group.
#
# This test proves the mechanism directly (Part A: a child launched via
# codex-task.sh's actual detach code path survives a group-directed
# SIGTERM aimed at its launcher's process group) and FALSIFIES it by
# reverting to the pre-fix "no detach" invocation and showing that one
# dies (Part A old-mode) — plus a static source check that a --background
# _run_node call, and only that call, is routed through the detach
# mechanism (Part B).
#
# Usage: bash tests/test-codex-detach-01.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"
CODEX_TASK_SH="${SCRIPTS_DIR}/codex-task.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

TMPD="$(mktemp -d)"
cleanup() { rm -rf "$TMPD" 2>/dev/null || true; }
trap cleanup EXIT

# ── Part A: process-group survival, exercising the REAL setsid_wrapper() ───
# Extract the actual function body from codex-task.sh (not a reimplementation)
# so the test dies if the function is renamed/removed without updating this
# test, and passes only when the real production code detaches correctly.
FUNCS_FILE="${TMPD}/funcs.sh"
sed -n '/^setsid_wrapper() {/,/^}$/p' "$CODEX_TASK_SH" > "$FUNCS_FILE"
if [[ ! -s "$FUNCS_FILE" ]]; then
  fail "could not extract setsid_wrapper() from codex-task.sh -- has it been renamed/removed?"
else
  pass "extracted setsid_wrapper() from codex-task.sh ($(wc -l < "$FUNCS_FILE") lines)"
fi

# _test_new_session_bg <cmd...> -- background <cmd...> into a NEW OS session
# (pid == pgid) standing in for "the harness's own process group" so Part A
# can SIGTERM it from outside, same idiom as test-fanout-lane-detach.sh.
_test_new_session_bg() {
  ( exec python3 -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@" ) &
  _TNS_PID=$!
}

run_group_survival_test() {
  # $1 = "fixed" (use setsid_wrapper()) | "old" (verbatim pre-fix pattern:
  # the worker launched directly in the caller's own process group, exactly
  # what codex-task.sh's --background path did before CODEX-DETACH-01).
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
      pass "fixed: setsid_wrapper-launched worker (pid=${spawned_pid}) SURVIVES a SIGTERM to its launcher's process group"
    else
      fail "old: undetached worker (pid=${spawned_pid}) survived group SIGTERM -- expected it to die (test setup contradicts the documented bug)"
    fi
    kill -TERM "$spawned_pid" 2>/dev/null || true
  else
    if [[ "$mode" == "fixed" ]]; then
      fail "fixed: setsid_wrapper-launched worker (pid=${spawned_pid}) died with its launcher's group -- CODEX-DETACH-01 NOT fixed"
    else
      pass "old (pre-fix pattern): undetached worker died with its launcher's process group, reproducing the original bug -- this is the RED baseline the fix corrects"
    fi
  fi
}

run_group_survival_test fixed
run_group_survival_test old

# ── Part B: static wiring check — --background _run_node calls are routed
# through the detach mechanism, and ONLY --background calls (foreground/
# --wait calls must stay exactly as before: they are meant to die with the
# caller, and detaching them would silently defeat _run_node's own timeout
# enforcement contract for blocking callers). ─────────────────────────────
if grep -q '"\$_TIMEOUT_CMD" "\$_CODEX_TIMEOUT" python3 -c' "$CODEX_TASK_SH" \
   && grep -q 'setsid_wrapper node "\$COMPANION" "\$@" &' "$CODEX_TASK_SH"; then
  pass "both _run_node code paths (timeout-bound and portable-fallback) route --background through a setsid detach"
else
  fail "did not find the expected --background detach wiring in _run_node (timeout-bound python3 inline, or setsid_wrapper in the fallback branch)"
fi

if grep -A2 '"\$_TIMEOUT_CMD" "\$_CODEX_TIMEOUT" node "\$COMPANION" "\$@" || _exit_code=\$?' "$CODEX_TASK_SH" >/dev/null 2>&1; then
  pass "the non-background timeout-bound branch is untouched (plain node invocation, no detach)"
else
  fail "could not find the untouched non-background timeout-bound branch -- verify no drive-by change to foreground/--wait dispatch"
fi

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[[ "$FAIL" -eq 0 ]]
