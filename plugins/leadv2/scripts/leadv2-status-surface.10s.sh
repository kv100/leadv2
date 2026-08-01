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
RENDERER="${LEADV2_STATUS_RENDERER:-${SCRIPT_DIR}/leadv2-status-surface.sh}"
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
_ss_err="$(mktemp -t leadv2-ss-err)"
OUT_ALL="$(bash "$RENDERER" --all 2>"$_ss_err")"
_ss_rc=$?

# A crashed/empty renderer must never render as a confident 🟢/🔴 zero — that
# zero is indistinguishable from "no lanes" (the lying-green shape). Fail loud
# instead, replacing the whole title/dropdown, and still exit 0 so SwiftBar
# renders the ⚠️ title at all.
if [ "$_ss_rc" -ne 0 ] || [ -z "$OUT_ALL" ]; then
  _ss_msg="$(head -1 "$_ss_err" 2>/dev/null)"
  [ -z "$_ss_msg" ] && _ss_msg="renderer exited $_ss_rc with no output"
  _ss_msg="$(printf '%s' "$_ss_msg" | cut -c1-120)"
  printf '⚠️ renderer failed\n'
  printf -- '---\n'
  printf 'rc=%s | %s | font=Menlo size=12\n' "$_ss_rc" "$_ss_msg"
  printf 'renderer: %s | font=Menlo size=12\n' "$RENDERER"
  printf -- '---\n'
  printf 'Refresh | refresh=true\n'
  rm -f "$_ss_err"
  exit 0
fi
rm -f "$_ss_err"

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
# STATUS-SURFACE-R5-01 round 2: when active.yaml could not be read the renderer
# turns the lanes header into 'lanes (⚠ ...)' (no count). Detect that glyph and
# raise a ⚠ title -- a broken lane read must never render as a confident 🟢/🔴
# zero (the lying-green shape). Highest title priority: the lane data is suspect.
LANES_BROKEN=0
case "$lane_line" in *⚠*) LANES_BROKEN=1 ;; esac
# SWIFTBAR-LIVE-01 round 3 (§2.4): the renderer's header (leadv2-status-surface.sh,
# emit_lanes_table) is now the SOLE producer of live/dead/done counts -- this badge
# used to RE-DERIVE its own LIVE_N/DEAD_N by awk-slicing the rendered human table
# (guessing the cause-column start from whether a PROJ header was present), so the
# two independently-computed numbers disagreed: "🔴 3 / 🟢 0" in the title vs "1 live"
# in the very same table's own header. Two derivations of one quantity always drift.
# Parse header line 2 directly instead -- one anchored sed per field, keyed on the
# numeral's position relative to its label word, never on word order (so Russian
# labels stay free to reorder without breaking the parse).
LIVE_N=0
DEAD_N=0
DONE_N=0
_hdr_parse_ok=1
LIVE_N="$(printf '%s' "$lane_line" | sed -n 's/.*[^0-9]\([0-9][0-9]*\) live.*/\1/p')"
DEAD_N="$(printf '%s' "$lane_line" | sed -n 's/.*[^0-9]\([0-9][0-9]*\) dead.*/\1/p')"
DONE_N="$(printf '%s' "$lane_line" | sed -n 's/.*[^0-9]\([0-9][0-9]*\) done.*/\1/p')"
case "$LIVE_N" in ''|*[!0-9]*) LIVE_N=0; _hdr_parse_ok=0 ;; esac
case "$DEAD_N" in ''|*[!0-9]*) DEAD_N=0; _hdr_parse_ok=0 ;; esac
case "$DONE_N" in ''|*[!0-9]*) DONE_N=0; _hdr_parse_ok=0 ;; esac
# R4: an absent/non-numeric parse must never render as a confident 0 -- that's the
# lying-green shape (indistinguishable from "no lanes"). Route it through the same
# ⚠ LANES_BROKEN path a bad active.yaml read already uses (set above from this same
# line), unless it's already set.
if [ "$_hdr_parse_ok" -eq 0 ] && [ "$LANES_BROKEN" -eq 0 ]; then
  LANES_BROKEN=1
fi

# ── parse the questions block (section 2) — pending count + rows ────────────
Q_N=0
_q_hdr="$(printf '%s\n' "$Q_BLOCK" | sed -n '1p')"
Q_N="$(printf '%s' "$_q_hdr" | sed -n 's/^questions (\([0-9]*\)).*/\1/p')"
case "$Q_N" in ''|*[!0-9]*) Q_N=0 ;; esac

# ── line 1: menu-bar title (priority ⚠ > ❓ > 🔴 > 🟢 > ⚪) ──────────────────
# Regression contract: supervisor OFF + no pending questions keeps the
# `⚪ sup OFF · ` prefix.
_prefix=""
if [ "$SUP_ON" -eq 0 ] && [ "$Q_N" -eq 0 ]; then
  _prefix="⚪ sup OFF · "
fi
if [ "$LANES_BROKEN" -eq 1 ]; then
  # R5-01 round 2: unreadable active.yaml — lane counts are unreliable, so the
  # title leads with ⚠ instead of a confident 🟢/🔴 figure. Pending questions
  # still ride along (they come from a separate, readable source).
  printf '%s⚠️ lanes не прочитаны' "$_prefix"
  [ "$Q_N" -gt 0 ] && printf ' · ❓%d' "$Q_N"
  printf '\n'
elif [ "$Q_N" -gt 0 ]; then
  printf '%s❓%d · 🟢 %d / 🔴 %d\n' "$_prefix" "$Q_N" "$LIVE_N" "$DEAD_N"
elif [ "$DEAD_N" -gt 0 ]; then
  printf '%s🔴 %d / 🟢 %d\n' "$_prefix" "$DEAD_N" "$LIVE_N"
elif [ "$LIVE_N" -gt 0 ]; then
  printf '%s🟢 %d / 🔴 %d\n' "$_prefix" "$LIVE_N" "$DEAD_N"
elif [ "$DONE_N" -gt 0 ]; then
  printf '%s✅ %d\n' "$_prefix" "$DONE_N"
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
