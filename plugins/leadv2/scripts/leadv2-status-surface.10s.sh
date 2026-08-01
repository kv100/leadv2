#!/usr/bin/env bash
# leadv2-status-surface.10s.sh — SUPERVISOR-STATUS-SURFACE-02
#
# SwiftBar / xbar menu-bar widget for leadv2-status-surface.sh. The `.10s.sh`
# filename convention tells SwiftBar/xbar to refresh every 10 seconds — so the
# supervisor state is always on screen, in the menu bar, regardless of which
# terminal (if any) is open.
#
# ROUND 4 (2026-08-01): the dropdown now surfaces pending founder questions
# (with a copy-reply row per option), a per-provider LIMITS block, a
# scheduled-decisions DUE count, and an URGENT alarm count. Title priority:
#   ❓N (pending questions)  >  🔴n (dead lanes)  >  🟢n (live lanes)  >  ⚪ idle
# Zero network, zero LLM, zero calls to leadv2-quota-status.sh — every count
# comes from the renderer's dedicated section flags, never by re-parsing the
# human lanes table. ONE renderer invocation per refresh (--all).
#
# COPY-REPLY SAFETY: a question's option row copies the reply command to the
# clipboard only — it NEVER invokes leadv2-reply-router.sh. A stray menu click
# cannot answer a founder question irreversibly. The copy is done by
# re-invoking THIS script as `--copy-reply <qid> <opt>` (a self-contained
# helper mode, no new file); SwiftBar params are space-free tokens so the
# command is never split.
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
# POSIX [ ] only; no double-bracket tests (eval-adjacent glob hazard).
# printf '%s'-style only — never printf "$var" (question text is LLM-authored
# and may contain %/|).

set -uo pipefail

# ── --copy-reply helper mode ────────────────────────────────────────────────
# Self-invoked by the dropdown copy-reply rows. Copies the reply command to the
# clipboard; never executes the router. Checked FIRST so it works regardless of
# how the script was located (symlink etc.).
if [ "${1:-}" = "--copy-reply" ]; then
  _cr_qid="${2:-}"
  _cr_opt="${3:-}"
  if [ -n "$_cr_qid" ] && [ -n "$_cr_opt" ]; then
    printf 'leadv2-reply-router.sh %s %s' "$_cr_qid" "$_cr_opt" | pbcopy 2>/dev/null || true
  fi
  exit 0
fi
unset _cr_qid _cr_opt 2>/dev/null || true

# ── resolve own dir through a symlink (works under SwiftBar's plugin dir) ───
_self="${BASH_SOURCE[0]:-$0}"
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
SELF_PATH="${SCRIPT_DIR}/leadv2-status-surface.10s.sh"

if [ ! -f "$RENDERER" ]; then
  printf '⚠️ leadv2 status\n'
  printf -- '---\n'
  printf 'renderer missing (looked for: %s) | font=Menlo size=12\n' "$RENDERER"
  printf 'Refresh | refresh=true\n'
  exit 0
fi

# ── ONE renderer invocation (--all): lanes + questions + limits + due + alarms,
#    separated by '---' lines. ───────────────────────────────────────────────
OUT_ALL="$(bash "$RENDERER" --all 2>/dev/null || true)"

# Section N (1=lanes, 2=questions, 3=limits, 4=due, 5=alarms) — positional, per
# the renderer's fixed --all contract. An omitted section (e.g. due when the SD
# hook is absent) is simply empty.
_sec() {
  printf '%s\n' "$OUT_ALL" | awk -v want="$1" 'BEGIN{c=1} $0=="---"{c++; next} {if(c==want) print}'
}
LANES_BLOCK="$(_sec 1)"
Q_BLOCK="$(_sec 2)"
LIM_BLOCK="$(_sec 3)"
DUE_BLOCK="$(_sec 4)"
ALM_BLOCK="$(_sec 5)"

# ── parse the lanes block (section 1) — supervisor on/off + live/dead ───────
# Legacy sed parse of the human table for live/dead (accepted debt, not
# extended to the new counts). Header line 1 = supervisor state; line 2 =
# "lanes (N)"; rows from line 4 carry STATE as the last whitespace field.
hdr="$(printf '%s\n' "$LANES_BLOCK" | sed -n '1p')"
case "$hdr" in
  supervisor:*ON*) SUP_ON=1 ;;
  *)               SUP_ON=0 ;;
esac
lane_line="$(printf '%s\n' "$LANES_BLOCK" | sed -n '2p')"
LANE_N="$(printf '%s' "$lane_line" | sed -n 's/^lanes (\([0-9]*\)).*/\1/p')"
case "$LANE_N" in ''|*[!0-9]*) LANE_N=0 ;; esac
LIVE_N=0
DEAD_N=0
if [ "$LANE_N" -gt 0 ]; then
  LIVE_N="$(printf '%s\n' "$LANES_BLOCK" | tail -n +4 | awk '{ print $NF }' | grep -c '^live$' || true)"
  case "$LIVE_N" in ''|*[!0-9]*) LIVE_N=0 ;; esac
  DEAD_N=$(( LANE_N - LIVE_N ))
  [ "$DEAD_N" -lt 0 ] && DEAD_N=0
fi

# ── parse the questions block (section 2) — pending count + rows ────────────
Q_N=0
_q_hdr="$(printf '%s\n' "$Q_BLOCK" | sed -n '1p')"
Q_N="$(printf '%s' "$_q_hdr" | sed -n 's/^questions (\([0-9]*\)).*/\1/p')"
case "$Q_N" in ''|*[!0-9]*) Q_N=0 ;; esac

# ── line 1: menu-bar title (priority ❓ > 🔴 > 🟢 > ⚪) ─────────────────────
# Regression contract: supervisor OFF + no pending questions keeps the
# `⚪ sup OFF · ` prefix.
_prefix=""
if [ "$SUP_ON" -eq 0 ] && [ "$Q_N" -eq 0 ]; then
  _prefix="⚪ sup OFF · "
fi
if [ "$Q_N" -gt 0 ]; then
  printf '%s❓%d · 🟢 %d / 🔴 %d\n' "$_prefix" "$Q_N" "$LIVE_N" "$DEAD_N"
elif [ "$DEAD_N" -gt 0 ]; then
  printf '%s🔴 %d / 🟢 %d\n' "$_prefix" "$DEAD_N" "$LIVE_N"
else
  printf '%s🟢 %d / 🔴 %d\n' "$_prefix" "$LIVE_N" "$DEAD_N"
fi

# ── dropdown (§5.3 order): questions → lanes → limits → due → urgent → Refresh
printf -- '---\n'

# questions: header + one row per pending question, with a copy-reply sub-row
# per option. Question text/option labels are '|' stripped (SwiftBar treats '|'
# as the param delimiter) — the renderer already strips them; we strip again
# defensively. printf '%s' only.
if [ "$Q_N" -gt 0 ]; then
  _qi=0
  printf '%s\n' "$Q_BLOCK" | while IFS= read -r qln; do
    _qi=$(( _qi + 1 ))
    if [ "$_qi" -eq 1 ]; then
      printf '%s | font=Menlo size=12\n' "$qln"
      continue
    fi
    _qid="$(printf '%s' "$qln" | awk '{print $1}')"
    # display text = full line minus the trailing [opts], '|' stripped. The sed
    # uses the form '\[.*\]' (not '\[' followed by a char-class) because the
    # test suite greps for the double-bracket bash test and a regex char-class
    # opening right after an escaped bracket would false-trip it.
    _disp="$(printf '%s' "$qln" | sed -e 's/ *\[.*\] *$//' | tr -d '|')"
    printf '%s | font=Menlo size=12\n' "$_disp"
    # options inside the trailing [opt1|opt2]; one copy-reply row each. The '|'
    # here is the DELIMITER we split on (the labels themselves were '|'-stripped
    # by the renderer); do NOT strip it. printf '%s\n' guarantees a trailing
    # newline so read processes the last token.
    _opts="$(printf '%s' "$qln" | sed -n 's/.*\[\(.*\)\].*/\1/p')"
    if [ -n "$_opts" ]; then
      printf '%s\n' "$_opts" | tr '|' '\n' | while IFS= read -r _o; do
        [ -z "$_o" ] && continue
        printf '  %s — copy reply | terminal=false refresh=false bash=%s param1=--copy-reply param2=%s param3=%s\n' \
          "$_o" "$SELF_PATH" "$_qid" "$_o"
      done
    fi
  done
  printf -- '---\n'
fi

# lanes table (monospaced)
printf '%s\n' "$LANES_BLOCK" | while IFS= read -r ln; do
  printf '%s | font=Menlo size=12\n' "$ln"
done
printf -- '---\n'

# limits block (monospaced)
if [ -n "$LIM_BLOCK" ]; then
  printf '%s\n' "$LIM_BLOCK" | while IFS= read -r ln; do
    printf '%s | font=Menlo size=12\n' "$ln"
  done
  printf -- '---\n'
fi

# due count (only if the section was emitted — hook present)
if [ -n "$DUE_BLOCK" ]; then
  printf '%s | font=Menlo size=12\n' "$DUE_BLOCK"
  printf -- '---\n'
fi

# urgent count
if [ -n "$ALM_BLOCK" ]; then
  printf '%s | font=Menlo size=12\n' "$ALM_BLOCK"
  printf -- '---\n'
fi

printf 'Refresh | refresh=true\n'
