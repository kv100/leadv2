#!/usr/bin/env bash
# leadv2-status-watch.sh — SUPERVISOR-STATUS-SURFACE-02
#
# tmux consumer for leadv2-status-surface.sh. Opens (or re-attaches) a
# dedicated tmux session `leadv2-status` that refreshes the surface every 5s,
# so the supervisor state is always one keypress away regardless of which
# terminal is open. Idempotent by construction: a second run ATTACHES, it never
# spawns a second session.
#
# Fallbacks (no hard deps beyond a POSIX shell + the renderer):
#   - tmux present: dedicated session + watch -n5
#   - tmux absent but `watch` present: exec watch -n5 in THIS terminal
#   - neither (macOS default ships no `watch`): a clear/render/sleep loop here
#
# Usage: leadv2-status-watch.sh [--oneline]
#   --oneline is forwarded to the renderer (compact refresh).
#
# All comparisons use POSIX [ ]; no double-bracket tests (eval-adjacent glob hazard).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDERER="${SCRIPT_DIR}/leadv2-status-surface.sh"

if [ ! -x "$RENDERER" ] && [ ! -f "$RENDERER" ]; then
  printf 'leadv2-status-watch: renderer not found at %s\n' "$RENDERER" >&2
  exit 1
fi

SNAME="leadv2-status"
# build the refresh command; quote args for the tmux / watch invocation
RARGS="${1:-}"
if [ -n "$RARGS" ]; then
  RENDER_CMD="bash \"${RENDERER}\" ${RARGS}"
else
  RENDER_CMD="bash \"${RENDERER}\""
fi

# ── tmux path ──────────────────────────────────────────────────────────────
if command -v tmux >/dev/null 2>&1; then
  if tmux has-session -t "$SNAME" 2>/dev/null; then
    # already running -> attach (switch if inside tmux, attach if outside)
    if [ -n "${TMUX:-}" ]; then
      exec tmux switch-client -t "$SNAME"
    else
      exec tmux attach-session -t "$SNAME"
    fi
  fi
  # spawn detached, then attach
  if command -v watch >/dev/null 2>&1; then
    tmux new-session -d -s "$SNAME" "watch -n5 -t ${RENDER_CMD}"
  else
    # no watch: an in-session clear/render/sleep loop
    tmux new-session -d -s "$SNAME" "while :; do clear; ${RENDER_CMD}; sleep 5; done"
  fi
  if [ -n "${TMUX:-}" ]; then
    exec tmux switch-client -t "$SNAME"
  else
    exec tmux attach-session -t "$SNAME"
  fi
fi

# ── no tmux: fall back to this terminal ────────────────────────────────────
if command -v watch >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  exec watch -n5 -t bash "${RENDERER}" ${RARGS}
fi

# ── no tmux, no watch (macOS default) ──────────────────────────────────────
while :; do
  clear
  # shellcheck disable=SC2086
  bash "${RENDERER}" ${RARGS}
  sleep 5
done
