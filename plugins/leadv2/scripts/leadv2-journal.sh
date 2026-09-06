#!/usr/bin/env bash
# leadv2-journal.sh — durable per-task journal ("context is cache, disk is truth").
# Usage:
#   leadv2-journal.sh append <task-id> <type> <text...>
#   leadv2-journal.sh tail   <task-id> [N]   (N default 10)
#   leadv2-journal.sh path   <task-id>        (print the resolved journal.md path)
#
# LIVE-LANES-RUN-WITHOUT-A-JOURNAL-01: the journal path used to be
# ${PROJECT_ROOT}/${leadv2_dir}/tasks/<task-id>/journal.md, where PROJECT_ROOT
# fell back to `git rev-parse --show-toplevel`. Inside a worktree that
# returns the WORKTREE, not the checkout -- so a worker running in a worktree
# and a reader rooted at the checkout (or at a different worktree of the same
# repo) disagreed about where the journal lives, even though both were
# "correct" by their own resolution rule. Fixed by routing through
# leadv2-state-path.sh's canonical control-plane root, which resolves via
# `git rev-parse --git-common-dir` -- IDENTICAL from every worktree of the
# same repo. `path` is the resolver both this writer and any external reader
# (e.g. persona-engine's scripts/anti-silence-pulse.sh, via the symlinked
# copy of this same script) must call, so there is exactly one address per
# task, computed by exactly one function, everywhere.
#
# Falls back to the pre-fix per-checkout layout only if leadv2-state-path.sh
# is missing or errors -- a worker must never be left unable to write.

set -euo pipefail
trap 'exit 0' ERR

SCRIPT_NAME="leadv2-journal"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# TESTS-POLLUTE-REAL-JOURNAL-01: LEADV2_PROJECT_ROOT is the variable the rest of
# leadv2 uses to pin a root, and this chain never consulted it -- so a caller who
# pinned it (every suite that isolates itself, and any script following the
# documented convention) fell through to cwd and wrote into the REAL checkout.
# Measured: docs/leadv2/tasks/dispatch-WSOTEST2/journal.md in the live tree,
# written by test-writeset-pending-overlap.sh, which pins LEADV2_PROJECT_ROOT on
# every one of its call sites and was ignored.
# The rung goes AFTER both CLAUDE_* ones and BEFORE the cwd fallback, so the
# production path -- which sets CLAUDE_PROJECT_ROOT deliberately, to keep a
# foreign-root dispatch out of the losing repo's journal -- does not change by a
# byte. Only the case that used to reach cwd is affected.
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}}"

log_err() {
  printf -- '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
}

# ── resolve leadv2_dir from state-paths.yaml (mirrors leadv2-pre-compact-checkpoint.sh) ──
_lv2_sp_yaml="${PROJECT_ROOT}/.claude/leadv2-overrides/state-paths.yaml"
_lv2_leadv2_dir=$(grep -E "^[[:space:]]*leadv2_dir[[:space:]]*:" "$_lv2_sp_yaml" 2>/dev/null | head -1 | sed -E "s/^[[:space:]]*leadv2_dir[[:space:]]*:[[:space:]]*//" | sed -E "s/^['\"']//; s/['\"'][[:space:]]*$//" | tr -d '\r' || true)
[[ -z "$_lv2_leadv2_dir" || "$_lv2_leadv2_dir" == "null" || "$_lv2_leadv2_dir" == "~" ]] && _lv2_leadv2_dir="docs/leadv2"

# ── argument validation ────────────────────────────────────────────────────────
if [[ $# -lt 2 ]]; then
  log_err "Usage: $0 append <task-id> <type> <text...> | $0 tail <task-id> [N] | $0 path <task-id>"
  exit 1
fi

MODE="$1"
RAW_TASK_ID="$2"
shift 2

# Sanitize task-id: keep only [A-Za-z0-9._-] (strips slashes, spaces, etc.)
TASK_ID="$(printf -- '%s' "$RAW_TASK_ID" | tr -cd 'A-Za-z0-9._-')"
if [[ -z "$TASK_ID" ]]; then
  log_err "task-id must not be empty after sanitization"
  exit 1
fi

# ── resolve TASK_DIR via the canonical, worktree-invariant control-plane
# root (LIVE-LANES-RUN-WITHOUT-A-JOURNAL-01) ────────────────────────────────
_STATE_PATH_SH="${SCRIPT_DIR}/leadv2-state-path.sh"
TASK_DIR=""
if [[ -x "$_STATE_PATH_SH" ]]; then
  if [[ -n "${CLAUDE_PROJECT_ROOT:-}" ]]; then
    TASK_DIR="$(PROJECT_ROOT="$CLAUDE_PROJECT_ROOT" "$_STATE_PATH_SH" --no-link "tasks/${TASK_ID}" 2>/dev/null)" || TASK_DIR=""
  elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    TASK_DIR="$(PROJECT_ROOT="$CLAUDE_PROJECT_DIR" "$_STATE_PATH_SH" --no-link "tasks/${TASK_ID}" 2>/dev/null)" || TASK_DIR=""
  elif [[ -n "${LEADV2_PROJECT_ROOT:-}" ]]; then
    # Same rung as line ~30, same reason (TESTS-POLLUTE-REAL-JOURNAL-01): last
    # before the cwd fallback, never ahead of an explicit CLAUDE_* pin.
    TASK_DIR="$(PROJECT_ROOT="$LEADV2_PROJECT_ROOT" "$_STATE_PATH_SH" --no-link "tasks/${TASK_ID}" 2>/dev/null)" || TASK_DIR=""
  else
    TASK_DIR="$("$_STATE_PATH_SH" --no-link "tasks/${TASK_ID}" 2>/dev/null)" || TASK_DIR=""
  fi
fi
if [[ -z "$TASK_DIR" ]]; then
  # Resolver missing or errored -- degrade to the pre-fix per-checkout
  # layout rather than leaving a worker unable to write its journal.
  TASK_DIR="${PROJECT_ROOT}/${_lv2_leadv2_dir}/tasks/${TASK_ID}"
fi
JOURNAL_FILE="${TASK_DIR}/journal.md"

case "$MODE" in
  append)
    if [[ $# -lt 2 ]]; then
      log_err "Usage: $0 append <task-id> <type> <text...>"
      exit 1
    fi
    TYPE="$1"
    shift
    TEXT="$*"

    # Type whitelist: phase decision finding error note; anything else -> note.
    case "$TYPE" in
      phase|decision|finding|error|note) ;;
      *) TYPE="note" ;;
    esac

    mkdir -p "$TASK_DIR"
    UTC_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf -- '- %s [%s] %s\n' "$UTC_ISO" "$TYPE" "$TEXT" >> "$JOURNAL_FILE"
    ;;
  tail)
    N="${1:-10}"
    [[ "$N" =~ ^[0-9]+$ ]] || N=10
    if [[ ! -f "$JOURNAL_FILE" ]]; then
      exit 0
    fi
    tail -n "$N" "$JOURNAL_FILE"
    ;;
  path)
    printf -- '%s\n' "$JOURNAL_FILE"
    ;;
  *)
    log_err "Unknown mode: $MODE (expected 'append', 'tail', or 'path')"
    exit 1
    ;;
esac
