#!/usr/bin/env bash
# Portable temporary-file helper. BSD mktemp requires Xs at the end of its
# template, so create a randomized directory first and put the fixed suffix in
# the filename inside it. Callers must use lv2_rmtemp_file so both are removed.
lv2_mktemp_file() {
  local label="${1:?label required}" ext="${2:?extension required}" dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/leadv2.XXXXXX")" || return 1
  printf '%s/%s.%s\n' "$dir" "$label" "$ext"
}

# Remove a file returned by lv2_mktemp_file and its helper-owned parent.
lv2_rmtemp_file() {
  local file="${1:?temporary file required}" dir base
  dir="$(dirname -- "$file")"
  base="$(basename -- "$dir")"
  [[ "$base" == leadv2.* && "$dir" == "${TMPDIR:-/tmp}"/* ]] || return 1
  rm -rf -- "$dir"
}

lv2_mktemp_dir() {
  local label="${1:?label required}"
  mktemp -d "${TMPDIR:-/tmp}/${label}.XXXXXX"
}

# lv2_assert_scratch_repo <repo_path> — TEST SAFETY (root cause of the
# recurring B1 finding, SUPERVISOR-AUDIT-01 fix-round-2): tests that write
# through leadv2-state-path.sh (docs/leadv2/* control-plane symlinks) have
# TWICE, across two separate review rounds, re-targeted a REAL repo's live
# symlinks at a scratch state dir instead of a throwaway fixture's. Every
# such test MUST call this immediately after creating its fixture repo, and
# hard-abort (exit 1, never a soft warning) unless BOTH signals below prove
# the path is a throwaway fixture the test created itself. Either signal
# alone can be spoofed by accident (a real checkout can in theory lack a
# remote; TMPDIR could in theory be redirected) — both must hold.
lv2_assert_scratch_repo() {
  local repo="${1:?repo path required}" real_tmp resolved
  [[ -d "$repo" ]] || { printf -- '[TEST-SAFETY] ABORT: %s does not exist — cannot verify it is a throwaway fixture\n' "$repo" >&2; exit 1; }
  real_tmp="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  resolved="$(cd "$repo" && pwd -P)"
  case "$resolved" in
    "$real_tmp"/*) ;;
    *)
      printf -- '[TEST-SAFETY] ABORT: fixture root %s is not under the temp root (%s) — refusing to run a control-plane-touching test against a path that may be a real repo checkout. Never manipulate real docs/leadv2 links from a test.\n' "$resolved" "$real_tmp" >&2
      exit 1
      ;;
  esac
  if git -C "$repo" remote 2>/dev/null | grep -q .; then
    printf -- '[TEST-SAFETY] ABORT: fixture repo %s has a configured git remote — this is not a throwaway fixture (every real leadv2/persona-engine/m3-market/respiro-ios checkout has one; a scratch `git init` has none). Refusing to run.\n' "$repo" >&2
    exit 1
  fi
  if [[ -f "$repo/REAL-REPO" || -f "$repo/.git/leadv2-real-repo-marker" ]]; then
    printf -- '[TEST-SAFETY] ABORT: fixture repo %s carries a REAL-REPO marker — refusing to run.\n' "$repo" >&2
    exit 1
  fi
}
