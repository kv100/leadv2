#!/usr/bin/env bash
# test-glm-stall-activity.sh — GLM-STALL-ACTIVITY-01.
# Exercises the real watchdog functions without starting claude (the full GLM
# harness uses a process substitution which is unavailable in some sandboxes).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${HERE}/glm-coder.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/glm-stall.XXXXXX")"
trap 'kill "${PIDS[@]:-}" 2>/dev/null || true; rm -rf "${WORK}"' EXIT
PIDS=()
PASS=0; FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

extract_watchdog() { # <source> <destination>
  sed -n '/^stream_state_get() {/,/^# DISPATCH-DEADHAND-01/p' "$1" | sed '$d' > "$2"
}

run_open_tool_case() { # <source> <expect alive|reaped>
  local source="$1" expect="$2" funcs run child watcher now
  funcs="${WORK}/funcs-$(basename "$source")-${expect}.sh"
  extract_watchdog "$source" "$funcs"
  # shellcheck source=/dev/null
  source "$funcs"
  run="${WORK}/run-${expect}-$(basename "$source")"
  mkdir -p "$run"
  now="$(date +%s)"
  printf 'turns=0\nlast_progress_ts=%s\nopen_tool_calls=1\n' "$((now - 10))" > "$run/.stream_state"
  : > "$run/journal.jsonl"; : > "$run/progress.log"
  sleep 30 & child=$!; PIDS+=("$child")
  watchdog_loop "$child" 20 "$run" 1 120 3 & watcher=$!; PIDS+=("$watcher")
  sleep 4
  if kill -0 "$child" 2>/dev/null && [[ ! -f "$run/.stalled" ]]; then
    [[ "$expect" == alive ]] && return 0
  elif [[ -f "$run/.stalled" ]]; then
    [[ "$expect" == reaped ]] && return 0
  fi
  return 1
}

PRE="${WORK}/glm-pre.sh"
git -C "$(cd "${HERE}/../../.." && pwd)" show HEAD:plugins/leadv2/scripts/glm-coder.sh > "$PRE"
if run_open_tool_case "$PRE" reaped && run_open_tool_case "$TARGET" alive; then
  ok "open tool stdout-idle is RED pre-fix -> GREEN post-fix"
else
  bad "open tool stdout-idle control"
fi

# No open invocation and no recent stream/progress activity must still kill,
# with the terminal reason that distinguishes this from a generic hang.
FUNCS="${WORK}/funcs-current.sh"; extract_watchdog "$TARGET" "$FUNCS"; source "$FUNCS"
RUN="${WORK}/run-dead"; mkdir -p "$RUN"; NOW="$(date +%s)"
printf 'turns=0\nlast_progress_ts=%s\nopen_tool_calls=0\n' "$((NOW - 10))" > "$RUN/.stream_state"
: > "$RUN/journal.jsonl"; : > "$RUN/progress.log"
sleep 30 & CHILD=$!; PIDS+=("$CHILD")
watchdog_loop "$CHILD" 20 "$RUN" 1 120 3 & WATCHER=$!; PIDS+=("$WATCHER")
sleep 6
if [[ -f "$RUN/.stalled" ]] && grep -q 'stall_kill=idle_no_activity' "$RUN/progress.log" && [[ "$(cat "$RUN/.bound_reason")" == idle_no_activity ]]; then
  ok "genuinely idle worker is killed and labelled stall_kill=idle_no_activity"
else
  bad "genuinely idle worker was not correctly labelled and reaped"
fi

echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
