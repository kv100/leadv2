#!/usr/bin/env bash
# Watch the rendered founder status and emit a bounded wake token on each rewrite.
# The caller places this loop in a persistent in-session Monitor; it is not a daemon.

set -uo pipefail

MODE="--print"
MAX_ITERS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --print|--emit-loop) MODE="$1"; shift ;;
    --max-iters)
      MAX_ITERS="${2:-}"
      shift 2
      ;;
    --help|-h)
      printf '%s\n' 'usage: leadv2-pulse-watch.sh [--print|--emit-loop] [--max-iters N]'
      exit 0
      ;;
    *)
      printf '[leadv2-pulse-watch] ignoring unknown argument: %s\n' "$1" >&2
      shift
      ;;
  esac
done

[[ "${LEADV2_SINGLE_LEAD_BEAT:-1}" == "0" ]] && exit 0
[[ "${LEADV2_PULSE_WATCH:-1}" == "0" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

if [[ "$MODE" == "--print" ]]; then
  SCRIPT_PATH=""
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-pulse-watch.sh" ]]; then
    SCRIPT_PATH="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-pulse-watch.sh"
  elif [[ -n "$SCRIPT_DIR" && -r "${SCRIPT_DIR}/leadv2-pulse-watch.sh" && "$SCRIPT_DIR" != *"/.claude/worktrees/"* ]]; then
    SCRIPT_PATH="${SCRIPT_DIR}/leadv2-pulse-watch.sh"
  fi

  if [[ -z "$SCRIPT_PATH" ]]; then
    printf '[leadv2-pulse-watch] cannot resolve a stable watcher script path\n' >&2
    exit 0
  fi

  # Single-quote safely: Monitor consumes this line verbatim as a shell command.
  QUOTED_PATH="$(printf '%s' "$SCRIPT_PATH" | sed "s/'/'\\\"'\\\"'/g")"
  printf "bash '%s' --emit-loop\n" "$QUOTED_PATH"
  exit 0
fi

INTERVAL="${LEADV2_PULSE_WATCH_INTERVAL_S:-60}"
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]]; then
  printf '[leadv2-pulse-watch] invalid LEADV2_PULSE_WATCH_INTERVAL_S=%s; using 60\n' "$INTERVAL" >&2
  INTERVAL=60
fi
if [[ "$INTERVAL" -lt 5 ]]; then INTERVAL=5; fi
if [[ "$INTERVAL" -gt 3600 ]]; then INTERVAL=3600; fi

if ! [[ -z "$MAX_ITERS" || "$MAX_ITERS" =~ ^[0-9]+$ ]]; then
  printf '[leadv2-pulse-watch] invalid --max-iters=%s; ignoring\n' "$MAX_ITERS" >&2
  MAX_ITERS=""
fi

PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)}}"
[[ -n "$PROJECT_ROOT" ]] || exit 0
FOUNDER_STATUS_PATH="${LEADV2_FOUNDER_STATUS_PATH:-${PROJECT_ROOT}/docs/leadv2/founder-status.md}"

mtime() {
  local file="$1" value=""
  [[ -e "$file" ]] || return 1
  value="$(stat -f %m "$file" 2>/dev/null || true)"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    value="$(stat -c %Y "$file" 2>/dev/null || true)"
  fi
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$value"
}

PREV=""
ARMED=0
ITERS=0
while :; do
  [[ "${LEADV2_PULSE_WATCH:-1}" == "0" ]] && exit 0
  CURRENT="$(mtime "$FOUNDER_STATUS_PATH" 2>/dev/null || true)"

  if [[ "$ARMED" -eq 0 ]]; then
    PREV="$CURRENT"
    ARMED=1
  elif [[ -n "$CURRENT" && "$CURRENT" != "$PREV" ]]; then
    LINE="$(head -n 1 "$FOUNDER_STATUS_PATH" 2>/dev/null | tr -d '\000' | cut -c1-500 || true)"
    if [[ -n "$LINE" ]]; then
      printf '%s\n' "$LINE"
    else
      printf '[BROAD_STATUS] beat mtime=%s path=%s (line 1 empty)\n' "$CURRENT" "$FOUNDER_STATUS_PATH"
    fi
    PREV="$CURRENT"
  fi

  ITERS=$((ITERS + 1))
  if [[ -n "$MAX_ITERS" && "$ITERS" -ge "$MAX_ITERS" ]]; then
    exit 0
  fi
  sleep "$INTERVAL"
done
