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
CACHE_KEY="${PWD//\//_}"
[[ -z "$CACHE_KEY" ]] && CACHE_KEY="default"
LAST_KNOWN_FILE="${TMPDIR:-/tmp}/leadv2-statusline-last-known-${CACHE_KEY}"
REFRESH_LOCK="${TMPDIR:-/tmp}/leadv2-statusline-refresh-lock-${CACHE_KEY}"
TAIL_SCRIPT="${SCRIPT_DIR}/leadv2-lane-status-line-tail.sh"

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
  printf ' \033[34m| lanes ?\033[0m\n'
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
