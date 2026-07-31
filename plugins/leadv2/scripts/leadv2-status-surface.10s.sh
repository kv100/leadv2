#!/usr/bin/env bash
# leadv2-status-surface.10s.sh — SUPERVISOR-STATUS-SURFACE-02
#
# SwiftBar / xbar menu-bar widget for leadv2-status-surface.sh. The `.10s.sh`
# filename convention tells SwiftBar/xbar to refresh every 10 seconds — so the
# supervisor state is always on screen, in the menu bar, regardless of which
# terminal (if any) is open. This is the "always visible" half of the surface;
# the tmux watch (`leadv2-status-watch.sh`) is the "dig in" half.
#
# Line 1 (menu bar): compact emoji summary — 🟢 n live / 🔴 n dead, prefixed
#   with `⚪ sup OFF · ` when no supervisor is running. Then `---`, the full
#   multi-line table (one menu row per line, monospaced), then a Refresh row.
#
# INSTALL (manual — by design, no auto-install into the plugin dir):
#   1. Install SwiftBar (brew install --cask swiftbar) or xbar.
#   2. Point SwiftBar/xbar at a plugins directory.
#   3. Symlink this file into that dir so it always tracks the live script:
#        ln -s "<repo>/plugins/leadv2/scripts/leadv2-status-surface.10s.sh" \
#              "<SwiftBar Plugins>/leadv2-status-surface.10s.sh"
#      A symlink is required (not a copy): a copy will drift the moment the
#      renderer is updated — the same lying-stale disease this surface exists
#      to kill.
#
# Must run correctly when symlinked: it resolves its OWN directory via a
# readlink-chase on $0, then locates the renderer as a sibling. If the sibling
# is missing it prints `⚠️ leadv2 status` + the resolved path in the dropdown
# and never exits silently.
#
# POSIX [ ] only; no double-bracket tests (eval-adjacent glob hazard).

set -uo pipefail

# ── resolve own dir through a symlink (works under SwiftBar's plugin dir) ───
_self="${BASH_SOURCE[0]:-$0}"
# chase symlinks: readlink -f is GNU; emulate for BSD readlink
_resolve() {
  local p="$1" dir
  while [ -L "$p" ]; do
    dir="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in
      /*) ;;
      *)  p="${dir}/${p}" ;;
    esac
  done
  cd "$(dirname "$p")" 2>/dev/null && pwd -P
}
SCRIPT_DIR="$(_resolve "$_self")"
RENDERER="${SCRIPT_DIR}/leadv2-status-surface.sh"

if [ ! -f "$RENDERER" ]; then
  printf '⚠️ leadv2 status\n'
  printf '---\n'
  printf 'renderer missing (looked for: %s) | font=Menlo size=12\n' "$RENDERER"
  printf 'Refresh | refresh=true\n'
  exit 0
fi

# ── capture the renderer's default table ───────────────────────────────────
OUT="$(bash "$RENDERER" 2>/dev/null || true)"

# header line tells us supervisor on/off + the lane count
hdr="$(printf '%s\n' "$OUT" | sed -n '1p')"
case "$hdr" in
  supervisor:*ON*) SUP_ON=1 ;;
  *)               SUP_ON=0 ;;
esac
lane_line="$(printf '%s\n' "$OUT" | sed -n '2p')"
# "lanes (N)" -> N
LANE_N="$(printf '%s' "$lane_line" | sed -n 's/^lanes (\([0-9]*\)).*/\1/p')"
case "$LANE_N" in ''|*[!0-9]*) LANE_N=0 ;; esac

# live/dead counts come from the table STATE column (5th space-field in rows)
# table rows start at line 4 (line 3 is the column header). A row's STATE word
# is "live" or anything-else (dead/done/stale/warn).
rows_from=4
LIVE_N=0
DEAD_N=0
if [ "$LANE_N" -gt 0 ]; then
  # extract rows, take the last whitespace field (STATE)
  LIVE_N="$(printf '%s\n' "$OUT" | tail -n +$rows_from | awk '{ print $NF }' | grep -c '^live$' || true)"
  case "$LIVE_N" in ''|*[!0-9]*) LIVE_N=0 ;; esac
  DEAD_N=$(( LANE_N - LIVE_N ))
  [ "$DEAD_N" -lt 0 ] && DEAD_N=0
fi

# ── line 1: menu-bar summary ───────────────────────────────────────────────
if [ "$SUP_ON" -eq 1 ]; then
  printf '🟢 %d / 🔴 %d\n' "$LIVE_N" "$DEAD_N"
else
  printf '⚪ sup OFF · 🟢 %d / 🔴 %d\n' "$LIVE_N" "$DEAD_N"
fi

# ── dropdown: the full table, monospaced ───────────────────────────────────
printf '---\n'
printf '%s\n' "$OUT" | while IFS= read -r ln; do
  printf '%s | font=Menlo size=12\n' "$ln"
done
printf '---\n'
printf 'Refresh | refresh=true\n'
