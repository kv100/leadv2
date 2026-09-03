#!/usr/bin/env bash
# leadv2-guard-verdict.sh — GUARDS-MUST-PROVE-THEY-FIRE-01
#
# The one cheap runtime record a guard leaves so the census can tell
# never-ran / ran-never-fired / fires-log-only / blocking apart FROM
# BEHAVIOUR, never from a guard's self-description.
#
# Usage inside a guard:
#   . "$(dirname "$0")/lib/leadv2-guard-verdict.sh"
#   leadv2_gv_init Stop              # records a `ran` row, arms the bail trap
#   ...guard decision logic...
#   leadv2_gv_verdict block|log|allow|nap ["detail"]
#   leadv2_gv_bail "reason"          # explicit bail (missing dep, bad input)
#
# Journal: one TSV line per record under
#   ${LEADV2_GUARD_VERDICT_DIR:-${CLAUDE_PROJECT_DIR:-$HOME}/.claude/cache/guard-verdicts}/journal.tsv
#   <iso-ts>\t<guard>\t<event>\t<kind>\t<detail>
#
# Cost: two >> appends on the full path (ran + verdict), one `date` fork per
# record, zero other subprocesses. A write failure is swallowed — recording
# must never turn a working guard into a failing one.
#
# Bail semantics: gv_init installs an EXIT trap. If the guard exits without
# having recorded a verdict, the trap records `bail` with the exit code. A
# SIGKILL from an external timeout skips the trap — the CENSUS records that
# bail itself (see leadv2-guard-census.sh), so the fact is never silently
# absent.
#
# Bash 3.2 only. Safe under `set -u`.

LEADV2_GV_RECORDED=0
GV_HOOK_EVENT="unknown"

leadv2_gv_dir() {
  printf '%s' "${LEADV2_GUARD_VERDICT_DIR:-${CLAUDE_PROJECT_DIR:-$HOME}/.claude/cache/guard-verdicts}"
}

_leadv2_gv_append() { # $1 kind  $2 detail
  local dir
  dir="$(leadv2_gv_dir)" || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown-ts)" \
    "${LEADV2_GV_GUARD_NAME:-$(basename "${0:-unknown-guard}")}" \
    "$GV_HOOK_EVENT" "$1" "$2" \
    >> "$dir/journal.tsv" 2>/dev/null || return 0
  return 0
}

_leadv2_gv_bail_on_exit() {
  local rc=$?
  [ "${LEADV2_GV_RECORDED:-0}" -eq 1 ] && return 0
  _leadv2_gv_append bail "exited-without-verdict rc=$rc"
  return 0
}

leadv2_gv_init() { # $1 hook event (PreToolUse, Stop, ...)
  GV_HOOK_EVENT="${1:-unknown}"
  LEADV2_GV_RECORDED=0
  _leadv2_gv_append ran "-"
  # Install AFTER the ran row so a failure to even record `ran` is visible as
  # a bail; a guard that later installs its own EXIT trap replaces ours (fine:
  # it should call leadv2_gv_verdict/leadv2_gv_bail on its paths).
  trap '_leadv2_gv_bail_on_exit' EXIT
  return 0
}

leadv2_gv_verdict() { # $1 block|log|allow|nap  [$2 detail]
  LEADV2_GV_RECORDED=1
  _leadv2_gv_append verdict "$1${2:+:$2}"
  return 0
}

leadv2_gv_bail() { # $1 reason
  LEADV2_GV_RECORDED=1
  _leadv2_gv_append bail "$1"
  return 0
}
