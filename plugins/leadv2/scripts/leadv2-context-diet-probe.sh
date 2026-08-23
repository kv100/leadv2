#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/leadv2-temp.sh"
# leadv2-context-diet-probe.sh — WORKER-CONTEXT-DIET-01 measurement probe.
#
# Spawns two trivial one-turn `critic` workers per config (flags-on /
# flags-off; mission "reply DONE") via the REAL claude-subsession.sh in a
# scratch project root, parses each worker's stream-json for the FIRST
# usage block's cache_creation_input_tokens + cache_read_input_tokens, and
# prints a 4-row table plus the on/off delta. This is proof, not vibes: run
# it and paste the table into the close notes (design §2c / §D-D). The probe
# only reports -- it never flips LEADV2_SUBSESSION_SLIM_MCP /
# LEADV2_SUBSESSION_EXCLUDE_DYNAMIC defaults itself.
#
# Each spawn is a REAL, BILLED `claude -p` session (not LEADV2_DRY_RUN) --
# this is deliberate; a dry run cannot measure real cache_creation tokens.
#
# Usage: bash leadv2-context-diet-probe.sh [--role <role>] [--project-root <dir>]
#
# Exit codes:
#   0 — 4/4 rows parsed, table + delta printed
#   1 — at least one spawn produced no parseable first-turn usage block;
#       prints the rows it has and "PROBE INCOMPLETE: <n>/4 rows" (no delta)
#   2 — table printed, but delta < 10000 tokens: "VERDICT: delta <10K — do
#       not ship default-on" (§D-D: a human decision, not a self-flip)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBSESSION_SH="${SCRIPT_DIR}/claude-subsession.sh"

ROLE="critic"
PROJECT_ROOT_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT_ARG="$2"; shift 2 ;;
    *) echo "[context-diet-probe] unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "$PROJECT_ROOT_ARG" ]]; then
  SCRATCH_ROOT="$PROJECT_ROOT_ARG"
  mkdir -p "$SCRATCH_ROOT"
else
  SCRATCH_ROOT="$(lv2_mktemp_dir "context-diet-probe")"
fi

mkdir -p "$SCRATCH_ROOT/.claude/agents"
cat > "$SCRATCH_ROOT/.claude/agents/${ROLE}.md" <<ROLEEOF
---
model: sonnet
---
Probe worker. Reply with exactly the single word DONE and nothing else.
ROLEEOF
printf 'Reply with exactly the single word DONE and nothing else.\n' > "$SCRATCH_ROOT/mission.md"

# _first_usage_tokens <stream_file> — prints "cache_creation cache_read" for
# the FIRST usage block found (first assistant turn), or nothing if none
# parses. A one-turn "reply DONE" worker has one assistant turn, so first ==
# only, but we deliberately do not take a max across turns here (unlike the
# cost-telemetry parser in claude-subsession.sh) -- the probe measures the
# fresh spawn context, not the whole conversation.
_first_usage_tokens() {
  local stream_file="$1"
  python3 - "$stream_file" <<'PYEOF'
import sys, json

stream_file = sys.argv[1]
try:
    with open(stream_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            usage = obj.get("usage") or (obj.get("message", {}) or {}).get("usage") or {}
            if not usage:
                continue
            if "cache_creation_input_tokens" not in usage and "cache_read_input_tokens" not in usage:
                continue
            cw = int(usage.get("cache_creation_input_tokens", 0))
            cr = int(usage.get("cache_read_input_tokens", 0))
            print(f"{cw} {cr}")
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
PYEOF
}

# _run_spawn <task_id> <slim_mcp 0|1> <exclude_dynamic 0|1>
# Prints "cache_creation cache_read" or nothing on failure to parse.
_run_spawn() {
  local task_id="$1" slim_mcp="$2" exclude_dynamic="$3"
  (
    export PROJECT_ROOT="$SCRATCH_ROOT"
    export LEADV2_ROUTE_BANDIT=0
    export LEADV2_SUBSESSION_SLIM_MCP="$slim_mcp"
    export LEADV2_SUBSESSION_EXCLUDE_DYNAMIC="$exclude_dynamic"
    "$SUBSESSION_SH" --role "$ROLE" --model sonnet \
      --task-id "$task_id" --mission-file "$SCRATCH_ROOT/mission.md" --wait \
      >/dev/null 2>&1
  )
  local stream_file="$SCRATCH_ROOT/docs/handoff/${task_id}/${ROLE}.stream.jsonl"
  _first_usage_tokens "$stream_file"
}

echo "[context-diet-probe] scratch project root: $SCRATCH_ROOT" >&2
echo "[context-diet-probe] role: $ROLE" >&2

declare -a ROWS_LABEL=("flags-on run 1" "flags-on run 2" "flags-off run 1" "flags-off run 2")
declare -a ROWS_TASKID=("probe-on-1" "probe-on-2" "probe-off-1" "probe-off-2")
declare -a ROWS_SLIM=(1 1 0 0)
declare -a ROWS_EXCL=(1 1 0 0)
declare -a ROWS_RESULT

PARSED=0
for i in 0 1 2 3; do
  echo "[context-diet-probe] spawning: ${ROWS_LABEL[$i]} (task=${ROWS_TASKID[$i]})" >&2
  result="$(_run_spawn "${ROWS_TASKID[$i]}" "${ROWS_SLIM[$i]}" "${ROWS_EXCL[$i]}")"
  ROWS_RESULT[$i]="$result"
  if [[ -n "$result" ]]; then
    PARSED=$((PARSED + 1))
  fi
done

printf '\n%-16s %-14s %-14s %-14s\n' "config" "run" "cache_creation" "cache_read"
printf -- '-%.0s' {1..60}; printf '\n'
for i in 0 1 2 3; do
  cfg="flags-off"
  [[ ${ROWS_SLIM[$i]} -eq 1 ]] && cfg="flags-on"
  run_n=$(( (i % 2) + 1 ))
  if [[ -n "${ROWS_RESULT[$i]}" ]]; then
    cw="${ROWS_RESULT[$i]%% *}"
    cr="${ROWS_RESULT[$i]##* }"
    printf '%-16s %-14s %-14s %-14s\n' "$cfg" "run $run_n" "$cw" "$cr"
  else
    printf '%-16s %-14s %-14s %-14s\n' "$cfg" "run $run_n" "UNPARSEABLE" "UNPARSEABLE"
  fi
done

if [[ $PARSED -lt 4 ]]; then
  echo ""
  echo "PROBE INCOMPLETE: ${PARSED}/4 rows"
  exit 1
fi

on_avg=$(( (${ROWS_RESULT[0]%% *} + ${ROWS_RESULT[1]%% *}) / 2 ))
off_avg=$(( (${ROWS_RESULT[2]%% *} + ${ROWS_RESULT[3]%% *}) / 2 ))
delta=$(( off_avg - on_avg ))
delta_pct=0
if [[ $off_avg -gt 0 ]]; then
  delta_pct=$(( delta * 100 / off_avg ))
fi

echo ""
echo "avg cache_creation flags-on:  ${on_avg}"
echo "avg cache_creation flags-off: ${off_avg}"
echo "delta: ${delta} tokens (${delta_pct}%)"

if [[ $delta -lt 10000 ]]; then
  echo ""
  echo "VERDICT: delta <10K — do NOT ship default-on"
  exit 2
fi

exit 0
