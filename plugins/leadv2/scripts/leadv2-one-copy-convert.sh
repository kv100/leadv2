#!/usr/bin/env bash
# leadv2-one-copy-convert.sh — PLUGIN-ONE-COPY-01
#
# Converts the shared trees (~/.claude/leadv2-shared/scripts,
# ~/.claude/agents-shared) from real copies into per-file symlinks pointing
# at this canonical repo, so "fix once in ~/Projects/leadv2" is actually true
# on disk. Reversible: --revert restores real copies from the backup this
# script makes before touching anything.
#
# HARD PRECONDITION: refuses to run --apply while LIVENESS-SELF-DESTRUCT-01
# is open (leadv2-lane-liveness.sh overwrites itself when run --all --json).
# Symlinking a self-deleting script makes the destruction reach this repo's
# HEAD instead of a disposable working copy. See architect prepass §0.
#
# Usage:
#   leadv2-one-copy-convert.sh --check           # dry-run: report only, exit 1 if any REGRESSION
#   leadv2-one-copy-convert.sh --apply           # convert (refuses if precondition unmet)
#   leadv2-one-copy-convert.sh --revert          # restore real copies from the newest backup
#
# Exit codes: 0 = clean/converted, 1 = violations found (--check) or refused
# (--apply precondition unmet), 2 = usage error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANONICAL_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BACKUP_DIR="${LEADV2_ONE_COPY_BACKUP_DIR:-${HOME}/.claude/leadv2-one-copy-backups}"
LOCK_FILE="${HOME}/.claude/.one-copy.lock"

# shared-root canonical-root pairs (architect prepass §3a)
declare -a ROOTS=(
  "${HOME}/.claude/leadv2-shared/scripts|${CANONICAL_ROOT}/plugins/leadv2/scripts"
  "${HOME}/.claude/agents-shared|${CANONICAL_ROOT}/plugins/leadv2/agents"
)

MODE=""
case "${1:-}" in
  --check) MODE=check ;;
  --apply) MODE=apply ;;
  --revert) MODE=revert ;;
  *) printf 'usage: %s --check|--apply|--revert\n' "$(basename "$0")" >&2; exit 2 ;;
esac

log() { printf '[one-copy] %s\n' "$1"; }

# is_skip <relpath> -> 0 if this path is a known shared-only, never-linked entry
is_skip() {
  case "$1" in
    docs/*|node_modules/*|__pycache__/*|*/__pycache__/*|.mypy_cache/*|*/.mypy_cache/*) return 0 ;;
    *) return 1 ;;
  esac
}

# enumerate_pairs -> prints "shared_root<TAB>canonical_root<TAB>relpath" for
# every regular file under each shared root (top level + lib/ + tests/,
# matching architect prepass §3a's pairing rule).
enumerate_pairs() {
  local pair shared_root canonical_root f relpath
  for pair in "${ROOTS[@]}"; do
    shared_root="${pair%%|*}"; canonical_root="${pair#*|}"
    [[ -d "$shared_root" ]] || continue
    while IFS= read -r -d '' f; do
      relpath="${f#"${shared_root}"/}"
      printf '%s\t%s\t%s\n' "$shared_root" "$canonical_root" "$relpath"
    done < <(find "$shared_root" \( -path "*/node_modules" -o -path "*/__pycache__" -o -path "*/.mypy_cache" \) -prune -o -type f -print0)
  done
}

precondition_ok() {
  local lines
  git -C "$CANONICAL_ROOT" diff --quiet HEAD -- plugins/leadv2/scripts/leadv2-lane-liveness.sh || {
    log "PRECONDITION FAIL: leadv2-lane-liveness.sh has uncommitted changes (dirty vs HEAD)"
    return 1
  }
  lines="$(git -C "$CANONICAL_ROOT" show HEAD:plugins/leadv2/scripts/leadv2-lane-liveness.sh 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${lines:-0}" -lt 332 ]]; then
    log "PRECONDITION FAIL: HEAD's leadv2-lane-liveness.sh is only ${lines:-0} lines (need >=332)"
    return 1
  fi
  git -C "$CANONICAL_ROOT" log --oneline -20 -- plugins/leadv2/scripts/leadv2-lane-liveness.sh \
    | grep -qiE 'self-destruct|LIVENESS-SELF-DESTRUCT' || {
    log "PRECONDITION FAIL: no self-destruct fix commit found in last 20 leadv2-lane-liveness.sh commits"
    return 1
  }
  return 0
}

cmd_check() {
  local linked=0 regression=0 info=0 shared_root canonical_root relpath canon_file
  while IFS=$'\t' read -r shared_root canonical_root relpath; do
    if is_skip "$relpath"; then info=$((info + 1)); continue; fi
    canon_file="${canonical_root}/${relpath}"
    if [[ ! -e "$canon_file" && ! -L "$canon_file" ]]; then
      info=$((info + 1))
      continue
    fi
    if [[ -L "${shared_root}/${relpath}" ]]; then
      linked=$((linked + 1))
    else
      regression=$((regression + 1))
      log "REGRESSION: ${shared_root}/${relpath} is a real file (canonical: ${canon_file})"
    fi
  done < <(enumerate_pairs)
  log "tally: linked=${linked} regression=${regression} info(shared-only or no-canonical-counterpart)=${info}"
  [[ "$regression" -eq 0 ]]
}

cmd_apply() {
  precondition_ok || { log "REFUSING --apply: precondition unmet. Run --check only."; exit 1; }

  mkdir -p "$BACKUP_DIR"
  local stamp backup_path
  stamp="${LEADV2_ONE_COPY_STAMP:?LEADV2_ONE_COPY_STAMP must be set (UTC timestamp, e.g. from date -u +%Y%m%dT%H%M%SZ) — Date.now()/new Date() are unavailable in this execution context}"
  backup_path="${BACKUP_DIR}/leadv2-shared-${stamp}.tgz"
  tar -czf "$backup_path" -C "${HOME}/.claude" leadv2-shared agents-shared
  tar -tzf "$backup_path" >/dev/null || { log "backup verification failed: $backup_path"; exit 1; }
  log "backup: $backup_path"

  exec 9>"$LOCK_FILE"
  flock -n 9 || { log "REFUSING --apply: another one-copy run holds the lock"; exit 1; }

  local converted=0 skipped=0 shared_root canonical_root relpath canon_file shared_file
  while IFS=$'\t' read -r shared_root canonical_root relpath; do
    if is_skip "$relpath"; then continue; fi
    canon_file="${canonical_root}/${relpath}"
    shared_file="${shared_root}/${relpath}"
    [[ -e "$canon_file" || -L "$canon_file" ]] || continue
    if [[ -L "$shared_file" ]]; then continue; fi
    if ! cmp -s "$shared_file" "$canon_file"; then
      skipped=$((skipped + 1))
      log "SKIP (content differs, not overwritten): $shared_file"
      continue
    fi
    if [[ -x "$canon_file" && ! -x "$shared_file" ]] || [[ ! -x "$canon_file" && -x "$shared_file" ]]; then
      skipped=$((skipped + 1))
      log "SKIP (exec-bit mismatch, would need chmod-through-link): $shared_file"
      continue
    fi
    ln -sfn "$canon_file" "$shared_file"
    converted=$((converted + 1))
  done < <(enumerate_pairs)

  log "converted=${converted} skipped=${skipped}"
  [[ "$skipped" -eq 0 ]] || { log "PARTIAL: ${skipped} file(s) left as real copies — see SKIP lines above"; }
}

cmd_revert() {
  local latest
  latest="$(find "${BACKUP_DIR}" -maxdepth 1 -name 'leadv2-shared-*.tgz' -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null | head -1)"
  [[ -n "$latest" ]] || { log "no backup found under $BACKUP_DIR"; exit 1; }

  local pair shared_root
  for pair in "${ROOTS[@]}"; do
    shared_root="${pair%%|*}"
    find "$shared_root" -type l -delete 2>/dev/null || true
  done
  local remaining=0
  for pair in "${ROOTS[@]}"; do
    shared_root="${pair%%|*}"
    remaining=$((remaining + $(find "$shared_root" -type l 2>/dev/null | wc -l)))
  done
  [[ "$remaining" -eq 0 ]] || { log "revert aborted: ${remaining} symlink(s) survived the delete pass"; exit 1; }

  tar -xzf "$latest" -C "${HOME}/.claude"
  log "reverted from $latest"
}

case "$MODE" in
  check) cmd_check ;;
  apply) cmd_apply ;;
  revert) cmd_revert ;;
esac
