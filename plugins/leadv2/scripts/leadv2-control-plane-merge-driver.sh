#!/usr/bin/env bash
# leadv2-control-plane-merge-driver.sh — CONTROL-PLANE-FILES-CONFLICT-ON-EVERY-OLD-BRANCH-01
#
# Two modes:
#
#   1. MERGE DRIVER (registered as merge=leadv2-control-plane, args %O %A %B %P):
#      keeps OURS unconditionally for the pinned control-plane paths. The
#      tree's entry is a symlink into ~/.claude/leadv2-state/leadv2/ (the live
#      state of running sessions); an old branch carries the pre-control-plane
#      regular file. The symlink must always win — neither take-theirs nor a
#      content merge is ever correct here.
#      NOTE (measured, scratch repo 2026-09-04): when the two sides differ in
#      TYPE (symlink vs regular file), git raises a "distinct types" conflict
#      and NEVER invokes any merge driver; ours stays a symlink and theirs is
#      parked at "<path>~<branch>". Finishing that merge mechanically is the
#      job of leadv2-merge-old-branch.sh.
#
#   2. --verify (the guard): fails loudly when the control-plane invariant is
#      broken. Invariant: every pinned path is a symlink, and the total
#      symlink count under docs/leadv2 (maxdepth 1) equals the expected count
#      (16; override with LEADV2_CP_EXPECTED_LINKS). Exit 0 = ok,
#      exit 1 = broken (with a named offender on stderr/stdout).
#
# Registration (not committable — lives in .git/config, shared by all
# worktrees of the repo):
#   git config merge.leadv2-control-plane.driver \
#     '<abs-path-to-this-script> %O %A %B %P'
# leadv2-merge-old-branch.sh self-registers the driver if it is missing.
#
# Exit codes: 0 ok · 1 guard failed · 2 usage/environment error.
set -uo pipefail

DRIVER_NAME="leadv2-control-plane"
CP_DIR="docs/leadv2"
EXPECTED_LINKS="${LEADV2_CP_EXPECTED_LINKS:-16}"

_log()  { printf '[cp-driver] %s\n' "$*"; }
_die()  { printf 'leadv2-control-plane-merge-driver: GUARD FAIL %s\n' "$*" >&2; exit 1; }
_fatal(){ printf 'leadv2-control-plane-merge-driver: FATAL %s\n' "$*" >&2; exit 2; }

# Pinned paths: read from .gitattributes, never duplicated here.
# A pinned line looks like:  docs/leadv2/active.yaml  merge=leadv2-control-plane
pinned_paths() { # -> stdout: one path per line
  git rev-parse --show-toplevel >/dev/null 2>&1 || _fatal "not inside a git repository"
  local root
  root="$(git rev-parse --show-toplevel)"
  awk -v attr="merge=${DRIVER_NAME}" '$1 !~ /^#/ && $2 == attr { print $1 }' "${root}/.gitattributes" 2>/dev/null
}

link_count() { # -> stdout: N symlinks under CP_DIR (maxdepth 1)
  local root
  root="$(git rev-parse --show-toplevel)"
  if [[ -d "${root}/${CP_DIR}" ]]; then
    find "${root}/${CP_DIR}" -maxdepth 1 -type l | wc -l | tr -d ' '
  else
    printf '0'
  fi
}

# ── mode 2: the guard ─────────────────────────────────────────────────────────
guard_verify() {
  local root n p
  root="$(git rev-parse --show-toplevel)" || _fatal "not inside a git repository"
  [[ -d "${root}/${CP_DIR}" ]] || _die "dir_missing ${CP_DIR}"
  n="$(link_count)"
  if [[ "${n}" -ne "${EXPECTED_LINKS}" ]]; then
    _die "symlink_count=${n} expected=${EXPECTED_LINKS} in ${CP_DIR}"
  fi
  local bad=""
  while IFS= read -r p; do
    [[ -z "${p}" ]] && continue
    if [[ ! -L "${root}/${p}" ]]; then
      bad+="${p} "
    fi
  done < <(pinned_paths)
  if [[ -n "${bad}" ]]; then
    _die "pinned path(s) not symlinks: ${bad%% }"
  fi
  _log "control_plane_ok symlinks=${n} pinned=$(pinned_paths | grep -c . || true)"
  return 0
}

# ── mode 1: the merge driver ──────────────────────────────────────────────────
# Usage: <this> %O %A %B %P   (%A already CONTAINS the ours version — keeping
# ours means leaving it untouched.)
driver_keep_ours() {
  local base="" result="" theirs="" path=""
  base="$1"; result="$2"; theirs="$3"; path="${4:-}"
  [[ -n "${result}" ]] || _fatal "driver invoked without %A"
  # Guard: the worktree symlink count must be at most one short of expected.
  # One short is legitimate mid-merge: the path currently being resolved can
  # be materialized as a regular file until git writes our result. Any deeper
  # deficit means the tree's control plane is being destroyed — refuse loudly
  # and the merge fails rather than silently "succeeding".
  local n expected_min
  n="$(link_count)"
  expected_min=$((EXPECTED_LINKS - 1))
  if [[ "${n}" -lt "${expected_min}" ]]; then
    _die "symlink_count=${n} < ${expected_min} mid-merge (path=${path:-?}) — control plane is being destroyed"
  fi
  _log "kept_ours path=${path:-?} symlinks=${n}"
  exit 0
}

# ── driver self-registration (for leadv2-merge-old-branch.sh) ─────────────────
cmd_register() {
  local self
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  git config "merge.${DRIVER_NAME}.driver" "${self} %O %A %B %P" \
    || _fatal "git config failed"
  _log "registered merge.${DRIVER_NAME}.driver = ${self} %O %A %B %P"
  return 0
}

case "${1:-}" in
  --verify) shift; guard_verify "$@" ;;
  --register) shift; cmd_register "$@" ;;
  --help|-h)
    sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") _fatal "usage: $0 %O %A %B %P | --verify | --register" ;;
  *) driver_keep_ours "$@" ;;
esac
