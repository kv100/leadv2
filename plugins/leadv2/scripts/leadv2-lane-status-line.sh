#!/usr/bin/env bash
# scripts/leadv2-lane-status-line.sh — statusLine renderer (T-j,
# SUPERVISOR-AUDIT-01 mission-c).
#
# COMPOSES, never replaces: BUG (2026-07-29) — an earlier version was wired
# as persona-engine's project-level `statusLine`, which fully OVERRODE the
# founder's user-level `~/.claude/settings.json` one (Claude Code does not
# deep-merge this key), so his model/context-% line vanished. Fix: this
# script (a) reads the user-level statusLine.command out of
# ~/.claude/settings.json and re-runs THAT command with the SAME stdin
# payload as the base segment; (b) if no user-level command is configured,
# self-renders the standard segments (model, cwd, context-remaining %, git
# branch) straight from the same JSON — never guessed; (c) appends
# " | lanes N/cap | <task-id>:<phase>:<silence-age> ..." from active.yaml.
#
# Claude Code pipes ONE JSON payload on stdin, schema:
#   model.display_name, workspace.current_dir, output_style.name,
#   context_window.remaining_percentage, transcript_path
# (see ~/.claude/burn/statusline.sh, the founder's existing command). This
# is a DIFFERENT shape from the PreToolUse/UserPromptSubmit hook payload
# (tool_name/cwd/session_id) — do not conflate the two.
#
# ROLLBACK FLAG (fix round 1, BLOCKING batch item #14): LEADV2_STATUS_LINE=0
# is a pure passthrough straight to the founder's own ~/.claude/settings.json
# statusLine.command, with the identical stdin — no lane segment, no
# self-render, no caching. One flip restores the exact pre-plugin status
# line in every installed repo without touching settings.json.
#
# B13 FIX-ROUND-4 (SUPERVISOR-AUDIT-01, review-verdict-4.md): fix-round-3
# still measured 5/6 cold (fresh-cache-dir) renders over 300ms (up to
# 371.7ms), ALL returning the bare "? | lanes ?" fallback — proof that no
# synchronous process spawn, however tightly `timeout`-wrapped, can be
# trusted to land under a 300ms UI deadline on every machine: a jq/bash/
# python3 fork+exec that "normally" costs ~8ms is not a bound, and the
# reviewer's cold path paid for SIX of them (2 jq reads, 1 wrapped user
# command, 1 git branch fallback, 1 state-path resolver, 1 python3+PyYAML)
# before the outer 250ms timeout fired and discarded all of that work.
#
# This script now performs ZERO synchronous subprocess spawns in its main
# path. It always does exactly one of two things instantly:
#   1. A cached last-known-good line exists → `cat` it. One stat-free read,
#      no spawn.
#   2. No cache exists yet (first-ever call for this cwd) → build a minimal
#      static line ("<model> in <cwd> | lanes ?") using ONLY bash builtin
#      regex matching (`[[ =~ ]]`) against the raw stdin JSON — no jq, no
#      python3, no external process of any kind.
# Either way, it then (best-effort, lockfile-throttled so repeated calls
# within LEADV2_STATUSLINE_REFRESH_MIN_INTERVAL_S don't pile up spawns) fires
# ONE detached background refresher that runs the full tail script — both jq
# reads, the wrapped user command, git-branch fallback, and the lane calc —
# and atomically writes its result into the cache file for the NEXT paint.
# The refresher is detached (setsid when available, else plain background +
# disown, both redirected off any tty) so it survives this process exiting
# and never makes the current render wait on it. A stale-but-real line beats
# a hung one; the cache self-heals within one or two repaints because Claude
# Code re-invokes the statusLine command every few seconds.
#
# SILENCE-AGE SOURCE (fix round 1, BLOCKING #11): the lane segment (computed
# in the tail script, see there) derives age from the newest of
# docs/handoff/<task_id>/{session.log,fanout.log} by mtime — never from
# active.yaml's self-reported log_path/pulse_log.
# FIX5c (SUPERVISOR-AUDIT-01): shared colorized base-line renderer — used by
# BOTH this script's own cache-miss static fallback below AND the tail
# script's post-timeout/post-failure fallback (sourced from there), so a
# genuine burn failure never yields a grey, uncolored line and both fallback
# paths can never drift apart. Prints (no trailing newline)
# "<model> in <cwd> [<style>] <remaining>% ctx".
_leadv2_render_colored_base() {
  local model="${1:-?}" cwd="${2:-}" style="${3:-}" remaining="${4:-}"
  [[ -z "$cwd" ]] && cwd="$PWD"
  # BUG: `~` on the REPLACEMENT side of `${var/#pat/~}` tilde-EXPANDS back to
  # $HOME before the substitution lands, silently re-inserting the full path
  # and no-op'ing the shortening on every call — escape it as `\~`.
  cwd="${cwd/#$HOME/\~}"
  printf '\033[36m%s\033[0m in \033[32m%s\033[0m' "$model" "$cwd"
  [[ -n "$style" && "$style" != "null" ]] && printf ' [\033[33m%s\033[0m]' "$style"
  [[ -n "$remaining" && "$remaining" != "null" ]] && printf ' \033[35m%s%% ctx\033[0m' "$remaining"
}

# The tail script sources this file for the function above only — never run
# this script's own main body (stdin read, cache emit, refresher spawn) when
# sourced, that would double-consume stdin and mis-fire a second refresher.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0 2>/dev/null || exit 0
fi

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"

SETTINGS_JSON="${HOME}/.claude/settings.json"

# ---- rollback: pure passthrough to the founder's own command, nothing else ----
# No tight budget here by design: LEADV2_STATUS_LINE=0 explicitly opts OUT of
# this script's deadline enforcement to restore the exact prior behaviour.
if [[ "${LEADV2_STATUS_LINE:-1}" == "0" ]]; then
  USER_CMD_ONLY="$(jq -r '(.statusLine.command // "")' "$SETTINGS_JSON" 2>/dev/null || true)"
  if [[ -n "$USER_CMD_ONLY" ]]; then
    printf '%s' "$INPUT" | timeout 2 bash -c "$USER_CMD_ONLY" 2>/dev/null || true
  fi
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANE_CACHE_TTL_S="${LEADV2_STATUSLINE_LANE_CACHE_TTL_S:-3}"
REFRESH_MIN_INTERVAL_S="${LEADV2_STATUSLINE_REFRESH_MIN_INTERVAL_S:-2}"
STATE_PATH_SH="${SCRIPT_DIR}/leadv2-state-path.sh"
TAIL_SCRIPT="${SCRIPT_DIR}/leadv2-lane-status-line-tail.sh"

# Resolve the cwd this paint is for (statusLine payload current_dir/cwd), used
# both to resolve the supervisor sentinel and to key the cache per-repo.
PAINT_CWD="$PWD"
if [[ "$INPUT" =~ \"current_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  PAINT_CWD="${BASH_REMATCH[1]}"
elif [[ "$INPUT" =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  PAINT_CWD="${BASH_REMATCH[1]}"
fi
[[ -z "$PAINT_CWD" ]] && PAINT_CWD="$PWD"
BASE_KEY="${PAINT_CWD//\//_}"
[[ -z "$BASE_KEY" ]] && BASE_KEY="default"

# ── Item 4a: supervisor-only gate ─────────────────────────────────────────
# The lanes digest is for a SUPERVISING session only. A plain /leadv2 session
# in the same repo must see the founder's own line, never a supervisor-painted
# lanes segment. Detection is memoised (TTL 30s): the hot path is read-memo +
# one `date +%s` + two builtins (`[[ -f $sentinel ]]`, `kill -0 $pid`); a cold
# memo pays one state-path resolve + one PID probe. When the memo'd pid is dead
# (session ended OR a new session took over), the cold resolve re-runs.
_leadv2_statusline_sup_active() {
  local memo="${TMPDIR:-/tmp}/leadv2-statusline-supmode-${BASE_KEY}"
  local sentinel="" pid="" epoch=0 now
  if [[ -f "$memo" ]]; then
    { IFS=$'\t' read -r sentinel pid epoch < "$memo"; } 2>/dev/null || true
    now="$(date +%s)"
    if (( now - epoch < 30 )); then
      # Within TTL: trust the memo'd verdict, re-checked by sentinel+pid builtins.
      [[ -n "$pid" && -n "$sentinel" && -f "$sentinel" ]] && kill -0 "$pid" 2>/dev/null && return 0
      return 1
    fi
  fi
  # Cold / TTL-expired: resolve once and memo.
  sentinel="$(PROJECT_ROOT="$PAINT_CWD" "$STATE_PATH_SH" --no-link .supervise-active 2>/dev/null || true)"
  pid=""
  if [[ -n "$sentinel" && -f "$sentinel" ]]; then
    pid="$(python3 -c '
import sys, json, os
try:
    d = json.load(open(sys.argv[1])) or {}
    p = d.get("pid")
    if p is not None:
        os.kill(int(p), 0); print(int(p))
except Exception:
    pass
' "$sentinel" 2>/dev/null || true)"
  fi
  printf '%s\t%s\t%s' "$sentinel" "${pid:-}" "$(date +%s)" >"$memo" 2>/dev/null || true
  [[ -n "$pid" ]] && return 0
  return 1
}

IS_SUPERVISOR=0
{ _leadv2_statusline_sup_active && IS_SUPERVISOR=1; } || true

# Fold supervisor-state into the cache key so a supervisor-painted line is
# never served to a non-supervisor session in the same repo dir (and vice-
# versa) — the shared-PWD cache-poisoning defence. Either this OR a gate
# before every cache read+write is mandatory; this does both.
CACHE_KEY="${BASE_KEY}_sup${IS_SUPERVISOR}"
LAST_KNOWN_FILE="${TMPDIR:-/tmp}/leadv2-statusline-last-known-${CACHE_KEY}"
REFRESH_LOCK="${TMPDIR:-/tmp}/leadv2-statusline-refresh-lock-${CACHE_KEY}"

# Non-supervisor session (gate enabled): render ONLY the founder's own
# statusLine.command and exit — no lanes digest, no refresher spawn, no cache
# write. LEADV2_STATUSLINE_SUPERVISOR_ONLY=0 restores lanes-for-everyone.
if [[ "${LEADV2_STATUSLINE_SUPERVISOR_ONLY:-1}" == "1" && "$IS_SUPERVISOR" == "0" ]]; then
  # ── R4 (fix round 3): append a live-lane summary to the base line ──────
  # The lanes digest used to be supervisor-only, so a plain session that had
  # dispatched workers saw NOTHING. Now: if the status-surface renderer reports
  # any LIVE lane, append its oneline (<=120 chars) to the founder's normal
  # line. A quiet machine shows the base line only, unchanged. Foreground is
  # builtins only ([[ ]], read, stat, case, ${v:0:120}); the only spawn is the
  # already-idiomatic detached refresher (setsid/nohup, never awaited) -- the
  # <100ms budget is preserved by construction. Memo: 5s TTL, write-tmp-then-
  # mv (atomic) so two sessions sharing CACHE_KEY never see a torn line.
  SURFACE="${SCRIPT_DIR}/leadv2-status-surface.sh"
  MEMO="${TMPDIR:-/tmp}/leadv2-status-oneline-${CACHE_KEY}"
  _now_r4="${EPOCHSECONDS:-$(date +%s)}"
  _surf_oneline=""
  if [[ -f "$MEMO" ]]; then
    _memo_mtime="$(stat -f %m "$MEMO" 2>/dev/null || stat -c %Y "$MEMO" 2>/dev/null || echo 0)"
    if (( _now_r4 - _memo_mtime < 5 )); then
      # read returns non-zero at EOF-without-newline (the normal case here, the
      # surface prints one line); do NOT gate on its exit status, same caveat as
      # the sidecar read above.
      IFS= read -r _surf_oneline < "$MEMO" 2>/dev/null || true
    fi
  fi
  # ANTI-SILENCE-STATUSLINE-01 round 3: this segment used to only fire when
  # the surface oneline literally CONTAINED the substring "live" -- but that
  # substring match hit the human-readable cause text ("0s live(pid 6136)"),
  # never the lane's actual class, so a repaint whose lanes were ALL
  # dead/silent/done (the exact scenario the founder hit: three lanes ran,
  # he saw none) produced a _surf_oneline with no "live" anywhere and the
  # whole segment was silently dropped -- the opposite of "silent lane is
  # the most prominent field". emit_oneline() (leadv2-status-surface.sh) now
  # always returns a non-empty line ("lanes 0" when there truly are none),
  # is already width-budgeted and sorts non-live lanes first, so this side
  # only needs a defensive re-clamp for a memo cached at a wider width than
  # THIS repaint's COLUMNS. Every emitted token is single-word (no embedded
  # spaces), so a boundary cut is always safe.
  _surf_budget="${LEADV2_STATUSLINE_WIDTH:-${COLUMNS:-80}}"
  _surf_tail=""
  if [[ -n "$_surf_oneline" ]]; then
    _surf_trimmed="${_surf_oneline:0:$_surf_budget}"
    if [[ "$_surf_trimmed" != "$_surf_oneline" ]]; then
      [[ "$_surf_trimmed" == *" "* ]] && _surf_trimmed="${_surf_trimmed% *}"
      _surf_dropped_rest="${_surf_oneline:${#_surf_trimmed}}"
      _surf_dropped_n="$(printf '%s' "$_surf_dropped_rest" | tr -s ' ' '\n' | grep -c . || true)"
      _surf_trimmed="${_surf_trimmed% }"
      (( _surf_dropped_n > 0 )) && _surf_trimmed="${_surf_trimmed} +${_surf_dropped_n}"
    fi
    _surf_tail="$_surf_trimmed "
  fi
  USER_CMD="$(jq -r '(.statusLine.command // "")' "$SETTINGS_JSON" 2>/dev/null || true)"
  if [[ -n "$USER_CMD" ]]; then
    _base_out="$(printf '%s' "$INPUT" | timeout 2 bash -c "$USER_CMD" 2>/dev/null || true)"
    # Item 4: lanes own the budget first; the founder's own command (quotas,
    # model, ctx%) is composed-in, not authored here, so the only lever this
    # script has is to shrink what's KEPT of its output once lanes are live
    # -- cut on the visible-character budget remaining after the lane
    # segment, never before it.
    if [[ -n "$_surf_tail" ]]; then
      _base_visible_budget=$(( _surf_budget - ${#_surf_tail} ))
      (( _base_visible_budget < 0 )) && _base_visible_budget=0
      # Strip ANSI FIRST, then slice by visible chars -- slicing the raw
      # (color-coded) string at a visible-length offset can land mid escape
      # sequence and leave a dangling color code bleeding into the rest of
      # the terminal line.
      _base_out_plain="$(printf '%s' "$_base_out" | sed -E $'s/\x1b\\[[0-9;]*m//g')"
      if (( ${#_base_out_plain} > _base_visible_budget )); then
        _base_out="${_base_out_plain:0:$_base_visible_budget}"
      fi
    fi
    printf '%s%s\n' "$_surf_tail" "$_base_out"
  else
    # No user command configured: emit a minimal base line (no lanes segment)
    # so the status line is never blank for a non-supervisor session.
    _BM="?" _BC="$PAINT_CWD"
    [[ "$INPUT" =~ \"display_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && _BM="${BASH_REMATCH[1]}"
    printf '%s' "$_surf_tail"
    _leadv2_render_colored_base "$_BM" "$_BC" "" ""
    printf '\n'
  fi
  # Detached refresh of the memo (fire-and-forget). A missing renderer is a
  # silent no-op -- never a broken statusline. LEADV2_STATUSLINE_WIDTH is
  # exported explicitly because the refresher is detached from any tty --
  # $COLUMNS does not survive into a backgrounded, disowned child, so
  # without this the refresher would always budget against emit_oneline's
  # own 80-col default regardless of the terminal that triggered it.
  if [[ -x "$SURFACE" || -f "$SURFACE" ]]; then
    if command -v setsid >/dev/null 2>&1; then
      ( LEADV2_STATUSLINE_WIDTH="$_surf_budget" setsid bash "$SURFACE" --oneline >"$MEMO".tmp 2>/dev/null && mv -f "$MEMO".tmp "$MEMO"; ) </dev/null >/dev/null 2>&1 &
    else
      ( LEADV2_STATUSLINE_WIDTH="$_surf_budget" nohup bash "$SURFACE" --oneline >"$MEMO".tmp 2>/dev/null && mv -f "$MEMO".tmp "$MEMO"; ) </dev/null >/dev/null 2>&1 &
    fi
    disown -a 2>/dev/null || true
  fi
  exit 0
fi

# ---- instant emit: cache hit (no spawn) or pure-builtin static line ----
if [[ -s "$LAST_KNOWN_FILE" ]]; then
  cat "$LAST_KNOWN_FILE" 2>/dev/null || printf '? | lanes ?\n'
else
  MODEL="?"
  DISP_CWD="$PWD"
  STYLE=""
  REMAINING=""
  if [[ "$INPUT" =~ \"display_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    MODEL="${BASH_REMATCH[1]}"
  fi
  if [[ "$INPUT" =~ \"current_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    DISP_CWD="${BASH_REMATCH[1]}"
  elif [[ "$INPUT" =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    DISP_CWD="${BASH_REMATCH[1]}"
  fi
  [[ -z "$DISP_CWD" ]] && DISP_CWD="$PWD"
  # output_style.name and context_window.remaining_percentage, pure bash
  # regex (no jq) — same fields ~/.claude/burn/statusline.sh reads via jq.
  if [[ "$INPUT" =~ \"output_style\"[[:space:]]*:[[:space:]]*\{[^\}]*\"name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    STYLE="${BASH_REMATCH[1]}"
  fi
  if [[ "$INPUT" =~ \"remaining_percentage\"[[:space:]]*:[[:space:]]*([0-9.]+) ]]; then
    REMAINING="${BASH_REMATCH[1]}"
  fi
  # printf builtin only — zero spawns (the shared renderer above is a bash
  # function, not a subprocess).
  _leadv2_render_colored_base "$MODEL" "$DISP_CWD" "$STYLE" "$REMAINING"
  # D4 (STATUSLINE fix round 2): the tail script writes a count-only sidecar
  # (COUNT_SIDECAR_FILE) immediately after every liveness read, specifically
  # so THIS cold-cache path can render a real number instead of the literal
  # "lanes ?" — but nothing here ever read it. `read` is a bash builtin, zero
  # spawns, so it costs nothing against the B13 no-subprocess contract. Same
  # CACHE_KEY formula as the tail script's own COUNT_SIDECAR_FILE derivation
  # (both from CWD, here $PWD == the tail script's CWD_FROM_INPUT on a
  # cache-miss first call) — a mismatch here would silently fall back to
  # "lanes ?" forever, so this must track that formula exactly.
  _sidecar_lanes=""
  _count_sidecar="${TMPDIR:-/tmp}/leadv2-statusline-lanecount-${CACHE_KEY}"
  if [[ -s "$_count_sidecar" ]]; then
    # `read` returns non-zero at EOF without a trailing newline -- and the
    # sidecar is written via Python's plain fh.write(), which never adds
    # one. It still populates _sidecar_lanes correctly before returning
    # that status, so the exit code must NOT gate whether the read counts:
    # `read ... || _sidecar_lanes=""` would clobber a perfectly good read on
    # every single call, since EOF-without-newline is the normal case here,
    # not a failure. `[[ -z ]]` right below is what actually detects a
    # missing/unreadable sidecar.
    IFS= read -r _sidecar_lanes < "$_count_sidecar" 2>/dev/null
  fi
  # An unreadable/missing sidecar is UNKNOWN, never a confident zero — render
  # "lanes ?", the same as before this fix, rather than fabricate a count.
  [[ -z "$_sidecar_lanes" ]] && _sidecar_lanes="lanes ?"
  printf ' \033[34m| %s\033[0m\n' "$_sidecar_lanes"
fi

# ---- fire-and-forget: one throttled detached refresher, never awaited ----
# Best-effort lock: a plain mtime check, not a hard mutex — a rare double
# spawn under a race just costs one extra background render, never a
# blocked foreground one, so it is not worth an atomic-create dance here.
_now="${EPOCHSECONDS:-$(date +%s)}"
_should_refresh=1
if [[ -f "$REFRESH_LOCK" ]]; then
  _lock_mtime="$(stat -f %m "$REFRESH_LOCK" 2>/dev/null || stat -c %Y "$REFRESH_LOCK" 2>/dev/null || echo 0)"
  _lock_age=$(( _now - _lock_mtime ))
  (( _lock_age < REFRESH_MIN_INTERVAL_S )) && _should_refresh=0
fi

if [[ "$_should_refresh" == "1" && ( -x "$TAIL_SCRIPT" || -f "$TAIL_SCRIPT" ) ]]; then
  : > "$REFRESH_LOCK" 2>/dev/null || true
  if command -v setsid >/dev/null 2>&1; then
    ( setsid bash "$TAIL_SCRIPT" "$INPUT" "$SETTINGS_JSON" "$SCRIPT_DIR" "$LANE_CACHE_TTL_S" "$LAST_KNOWN_FILE" \
        </dev/null >/dev/null 2>&1 & ) 2>/dev/null
  else
    ( nohup bash "$TAIL_SCRIPT" "$INPUT" "$SETTINGS_JSON" "$SCRIPT_DIR" "$LANE_CACHE_TTL_S" "$LAST_KNOWN_FILE" \
        </dev/null >/dev/null 2>&1 & ) 2>/dev/null
  fi
  disown -a 2>/dev/null || true
fi

exit 0
