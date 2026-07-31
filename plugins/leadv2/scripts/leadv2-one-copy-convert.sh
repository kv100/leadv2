#!/usr/bin/env bash
# leadv2-one-copy-convert.sh — PLUGIN-ONE-COPY-01 / APPLY-ONE-COPY-01
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
#   leadv2-one-copy-convert.sh --check           # dry-run: report only, exit 1 on REGRESSION/BADLINK
#   leadv2-one-copy-convert.sh --apply           # convert (refuses if precondition unmet)
#   leadv2-one-copy-convert.sh --revert          # restore real copies from the newest backup's manifest
#
# Exit codes: 0 = clean/converted, 1 = violations found (--check) or refused
# (--apply precondition unmet), 2 = usage error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANONICAL_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BACKUP_DIR="${LEADV2_ONE_COPY_BACKUP_DIR:-${HOME}/.claude/leadv2-one-copy-backups}"
LOCK_FILE="${HOME}/.claude/.one-copy.lock"
EXCEPTIONS_FILE="${LEADV2_ONE_COPY_EXCEPTIONS_FILE:-${CANONICAL_ROOT}/plugins/leadv2/ref/one-copy-exceptions.txt}"

# shared-root canonical-root pairs (architect prepass §3a). Overridable so
# tests/test-one-copy-drift.sh can point --check at a disposable scratch
# fixture instead of the real ~/.claude shared trees (TEST-DESTROYS-
# PRODUCTION-SCRIPT-01 containment pattern — see that test's own comment).
# Root-key naming (root_key_for) still matches on the LAST path segments
# (".../agents-shared", ".../leadv2-shared/scripts"), so a scratch fixture
# must name its leaf directories the same way for the exception list to key
# correctly; only the prefix is overridable.
declare -a ROOTS=(
  "${LEADV2_ONE_COPY_SCRIPTS_SHARED_ROOT:-${HOME}/.claude/leadv2-shared/scripts}|${LEADV2_ONE_COPY_SCRIPTS_CANONICAL_ROOT:-${CANONICAL_ROOT}/plugins/leadv2/scripts}"
  "${LEADV2_ONE_COPY_AGENTS_SHARED_ROOT:-${HOME}/.claude/agents-shared}|${LEADV2_ONE_COPY_AGENTS_CANONICAL_ROOT:-${CANONICAL_ROOT}/plugins/leadv2/agents}"
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

# root_key_for <shared_root> -> "agents" | "scripts" | "unknown"
# Matches the ROOTS pairing so the exception list can key on a stable,
# repo-portable "<root-key>/<relpath>" string instead of an absolute path.
root_key_for() {
  case "$1" in
    */agents-shared) printf 'agents' ;;
    */leadv2-shared/scripts) printf 'scripts' ;;
    *) printf 'unknown' ;;
  esac
}

# root_key_to_subpath <root-key> -> path under ~/.claude for that root
root_key_to_subpath() {
  case "$1" in
    agents) printf 'agents-shared' ;;
    scripts) printf 'leadv2-shared/scripts' ;;
    *) return 1 ;;
  esac
}

declare -a EXCEPTIONS=()
load_exceptions() {
  EXCEPTIONS=()
  if [[ ! -f "$EXCEPTIONS_FILE" ]]; then
    log "WARN: exception list not found at $EXCEPTIONS_FILE — treating as empty"
    return 0
  fi
  local raw line
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line="${raw%%#*}"
    # trim leading/trailing whitespace without a subshell
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    EXCEPTIONS+=("$line")
  done < "$EXCEPTIONS_FILE"
}

is_exception() {
  local key="$1" e
  for e in "${EXCEPTIONS[@]:-}"; do
    [[ -n "$e" && "$e" == "$key" ]] && return 0
  done
  return 1
}

# enumerate_pairs -> prints "shared_root<TAB>canonical_root<TAB>relpath" for
# every regular file OR symlink under each shared root (D1: -type f alone is
# blind to symlinks, so a converted tree enumerates as empty and cmd_check's
# `linked` counter is permanently 0 — see architect prepass §1 D1).
enumerate_pairs() {
  local pair shared_root canonical_root f relpath
  for pair in "${ROOTS[@]}"; do
    shared_root="${pair%%|*}"; canonical_root="${pair#*|}"
    [[ -d "$shared_root" ]] || continue
    while IFS= read -r -d '' f; do
      relpath="${f#"${shared_root}"/}"
      printf '%s\t%s\t%s\n' "$shared_root" "$canonical_root" "$relpath"
    done < <(find "$shared_root" \( -path "*/node_modules" -o -path "*/__pycache__" -o -path "*/.mypy_cache" \) -prune -o \( -type f -o -type l \) -print0)
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
  # The statusline-destroys-prober fix (STATUSLINE-DESTROYS-PROBER-01, 198265e)
  # never touches this file — the bug was in the statusline's write path, not
  # the prober itself — so grepping THIS file's own log for a fix-commit
  # message can never match. Check instead that the known-good fix commit is
  # an ancestor of HEAD (pre-existing defect found while running --apply live
  # this session; the grep-based check was unsatisfiable by construction).
  git -C "$CANONICAL_ROOT" merge-base --is-ancestor 198265e78196f4c54cd87bb45b489aabfed579f9 HEAD 2>/dev/null || {
    log "PRECONDITION FAIL: statusline-destroys-prober fix (198265e) is not in HEAD's history"
    return 1
  }
  return 0
}

cmd_check() {
  load_exceptions
  local linked=0 regression=0 badlink=0 expected_override=0 diverged=0 info=0
  local shared_root canonical_root relpath canon_file shared_file root_key key
  while IFS=$'\t' read -r shared_root canonical_root relpath; do
    if is_skip "$relpath"; then info=$((info + 1)); continue; fi
    canon_file="${canonical_root}/${relpath}"
    shared_file="${shared_root}/${relpath}"
    if [[ ! -e "$canon_file" && ! -L "$canon_file" ]]; then
      info=$((info + 1))
      continue
    fi
    root_key="$(root_key_for "$shared_root")"
    key="${root_key}/${relpath}"

    if [[ -L "$shared_file" ]]; then
      local target canon_resolved
      target="$(readlink -f "$shared_file" 2>/dev/null || true)"
      canon_resolved="$(readlink -f "$canon_file" 2>/dev/null || printf '%s' "$canon_file")"
      if [[ -z "$target" || "$target" != "$canon_resolved" ]]; then
        badlink=$((badlink + 1))
        log "BADLINK: ${shared_file} -> ${target:-<dangling>} (expected: ${canon_resolved})"
      else
        linked=$((linked + 1))
      fi
      continue
    fi

    if is_exception "$key"; then
      expected_override=$((expected_override + 1))
      log "EXPECTED-OVERRIDE: ${shared_file} (declared)"
      if cmp -s "$shared_file" "$canon_file"; then
        log "STALE-EXCEPTION: ${key} (identical to canonical — override no longer needed, consider deleting the exception-list line)"
      fi
      continue
    fi

    if cmp -s "$shared_file" "$canon_file"; then
      regression=$((regression + 1))
      log "REGRESSION: ${shared_file} is a real file, identical to canonical (${canon_file})"
    else
      diverged=$((diverged + 1))
      log "DIVERGED: ${shared_file} differs from canonical (${canon_file}) — not on exception list"
    fi
  done < <(enumerate_pairs)
  log "tally: linked=${linked} regression=${regression} badlink=${badlink} expected_override=${expected_override} diverged=${diverged} info(shared-only or no-canonical-counterpart)=${info}"
  [[ "$regression" -eq 0 && "$badlink" -eq 0 ]]
}

cmd_apply() {
  precondition_ok || { log "REFUSING --apply: precondition unmet. Run --check only."; exit 1; }

  local stamp
  stamp="${LEADV2_ONE_COPY_STAMP:?LEADV2_ONE_COPY_STAMP must be set (UTC timestamp, e.g. from date -u +%Y%m%dT%H%M%SZ) — Date.now()/new Date() are unavailable in this execution context}"

  # R4: take the lock before any write (backup included), not after.
  local flock_bin
  flock_bin="$(command -v flock || true)"
  if [[ -n "$flock_bin" ]]; then
    exec 9>"$LOCK_FILE"
    "$flock_bin" -n 9 || { log "REFUSING --apply: another one-copy run holds the lock"; exit 1; }
  else
    log "WARN: flock unavailable on PATH — proceeding without a lock (R6)"
  fi

  mkdir -p "$BACKUP_DIR"
  local backup_path manifest_path
  backup_path="${BACKUP_DIR}/leadv2-shared-${stamp}.tgz"
  manifest_path="${BACKUP_DIR}/leadv2-shared-${stamp}.manifest"
  tar -czf "$backup_path" -C "${HOME}/.claude" leadv2-shared agents-shared
  tar -tzf "$backup_path" >/dev/null || { log "backup verification failed: $backup_path"; exit 1; }
  : > "$manifest_path"
  log "backup: $backup_path"
  log "manifest: $manifest_path"

  load_exceptions

  local converted=0 skipped=0 exempted=0
  local shared_root canonical_root relpath canon_file shared_file root_key key
  while IFS=$'\t' read -r shared_root canonical_root relpath; do
    if is_skip "$relpath"; then continue; fi
    canon_file="${canonical_root}/${relpath}"
    shared_file="${shared_root}/${relpath}"
    [[ -e "$canon_file" || -L "$canon_file" ]] || continue
    if [[ -L "$shared_file" ]]; then continue; fi

    root_key="$(root_key_for "$shared_root")"
    key="${root_key}/${relpath}"

    # exception list is a hard skip BEFORE the cmp -s guard (belt-and-braces —
    # never depend on content-inequality alone to protect a founder override).
    if is_exception "$key"; then
      exempted=$((exempted + 1))
      log "SKIP (declared exception): $shared_file"
      continue
    fi

    if ! cmp -s "$shared_file" "$canon_file"; then
      skipped=$((skipped + 1))
      log "SKIP (content differs, not overwritten): $shared_file"
      continue
    fi
    # No exec-bit guard: once this is a symlink, `-x`/shebang execution always
    # resolves through the target, so canonical's mode bit governs regardless
    # of what the (about-to-be-replaced) real copy's own bit was — measured
    # live this session (a 644 copy of a 755 canonical, symlinked, tests -x
    # true and runs). A prior version of this script skipped on mismatch here
    # as "would need chmod-through-link"; that concern doesn't apply to a
    # symlink scheme and left 21 identical files stuck as permanent REGRESSION.
    ln -sfn "$canon_file" "$shared_file"
    printf '%s\n' "$key" >> "$manifest_path"
    converted=$((converted + 1))
  done < <(enumerate_pairs)

  log "converted=${converted} skipped=${skipped} exempted=${exempted}"
  [[ "$skipped" -eq 0 ]] || { log "PARTIAL: ${skipped} file(s) left as real copies — see SKIP lines above"; }
}

cmd_revert() {
  local latest
  latest="$(find "${BACKUP_DIR}" -maxdepth 1 -name 'leadv2-shared-*.tgz' -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null | head -1)"
  [[ -n "$latest" ]] || { log "no backup found under $BACKUP_DIR"; exit 1; }

  # R1: verify before deleting anything.
  tar -tzf "$latest" >/dev/null || { log "revert aborted: backup archive failed integrity check: $latest"; exit 1; }

  local manifest="${latest%.tgz}.manifest"
  local tmp
  tmp="$(mktemp -d)"
  tar -xzf "$latest" -C "$tmp"

  if [[ -f "$manifest" ]]; then
    local key rk rp sub
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      rk="${key%%/*}"; rp="${key#*/}"
      sub="$(root_key_to_subpath "$rk")" || { log "revert aborted: unknown root-key in manifest: $key"; rm -rf "$tmp"; exit 1; }
      if [[ ! -e "${tmp}/${sub}/${rp}" ]]; then
        log "revert aborted: manifest entry missing from backup: ${key}"; rm -rf "$tmp"; exit 1
      fi
    done < "$manifest"
  else
    log "WARN: no manifest for $latest — falling back to whole-tree restore for both shared roots"
  fi

  # R2+R3, corrected: delete and restore are scoped to EXACTLY this manifest's
  # entries, one shared_file at a time — never a tree-wide `find -type l`
  # delete. A tree-wide delete removes symlinks made by an EARLIER --apply run
  # too (they also resolve into CANONICAL_ROOT), but this revert only restores
  # the CURRENT manifest's paths, so anything converted by a prior run and not
  # in this manifest would be deleted and never restored — silent data loss.
  # Caught live this session: a first --apply converted 262 files, a second
  # --apply converted 21 more with its own manifest, and reverting from the
  # second backup deleted all 283 symlinks (regex: "resolves into canonical")
  # but restored only the 21 in its manifest, leaving 262 files missing
  # entirely until restored by hand from the first backup's full tar.
  if [[ -f "$manifest" ]]; then
    local key rk rp sub shared_file dest target
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      rk="${key%%/*}"; rp="${key#*/}"
      sub="$(root_key_to_subpath "$rk")"
      shared_file="${HOME}/.claude/${sub}/${rp}"
      if [[ -L "$shared_file" ]]; then
        target="$(readlink -f "$shared_file" 2>/dev/null || true)"
        case "$target" in
          "${CANONICAL_ROOT}"/*) rm -f "$shared_file" ;;
          *)
            log "revert: leaving unmanaged symlink (target outside canonical root, manifest said otherwise): $shared_file"
            continue
            ;;
        esac
      fi
      dest="$shared_file"
      mkdir -p "$(dirname "$dest")"
      cp -p "${tmp}/${sub}/${rp}" "$dest"
    done < "$manifest"
    log "reverted $(wc -l < "$manifest" | tr -d ' ') manifest entr(y/ies) from $latest"
  else
    # No manifest: this backup predates APPLY-ONE-COPY-01's manifest write, so
    # there is no scoped list to revert against. Fall back to the old
    # whole-tree behaviour (still scoped to canonical-resolving symlinks only,
    # per R2), since that is the only backup available. Warn loudly — a
    # concurrent later --apply's conversions are NOT distinguished here.
    log "WARN: no manifest for $latest — falling back to whole-tree restore (R2-scoped delete, full tar restore) for both shared roots"
    local pair shared_root f target
    for pair in "${ROOTS[@]}"; do
      shared_root="${pair%%|*}"
      [[ -d "$shared_root" ]] || continue
      while IFS= read -r -d '' f; do
        target="$(readlink -f "$f" 2>/dev/null || true)"
        case "$target" in
          "${CANONICAL_ROOT}"/*) rm -f "$f" ;;
          *) log "revert: leaving unmanaged symlink (target outside canonical root): $f" ;;
        esac
      done < <(find "$shared_root" -type l -print0 2>/dev/null)
    done
    cp -a "${tmp}/leadv2-shared/." "${HOME}/.claude/leadv2-shared/"
    cp -a "${tmp}/agents-shared/." "${HOME}/.claude/agents-shared/"
    log "reverted (whole-tree fallback, no manifest) from $latest"
  fi

  rm -rf "$tmp"
}

case "$MODE" in
  check) cmd_check ;;
  apply) cmd_apply ;;
  revert) cmd_revert ;;
esac
