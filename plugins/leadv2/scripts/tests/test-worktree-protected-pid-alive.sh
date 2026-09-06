#!/usr/bin/env bash
# run-all-triggers: leadv2-worktree-protected.sh
# test-worktree-protected-pid-alive.sh — D2-M4 (D2-SINGLE-LIVENESS-VERDICT §5/§6)
#
# lib/leadv2-worktree-protected.sh's active.yaml scan used to catch bare
# `except (TypeError, ValueError, OSError)` -- PermissionError subclasses
# OSError, collapsing EPERM (pid exists, owned by another user) into the
# same "dead" branch as ESRCH (D2 brief #9/#14).
#
# NOTE ON SCOPE: this tests the pid_alive(0|1) column lv2_wt_protect_prime
# emits into LV2_WT_PROTECT_SESSIONS directly -- NOT lv2_worktree_protected's
# rc contract. rc3 (live_pid) is unreachable for this column in practice:
# _lv2_wt_session_row(id, wt) (checked first, returns rc1 on any tid==id
# match) and _lv2_wt_pid_alive(id) (the only consumer of the alive column)
# match on the IDENTICAL tid==id condition, so any row that would make
# _lv2_wt_pid_alive report "alive" already made _lv2_wt_session_row report
# "protected" first. The alive column itself is still computed and part of
# the file's documented output contract (its own header names the exact
# format), so this is a genuine, honestly-scoped unit test -- not a claim
# that a live sweeper incident is prevented by this fix today.
#
# C1: EPERM pid (1) -> alive column reads "1", not "0".
# C2: genuinely dead (ESRCH) pid -> alive column reads "0" (unchanged).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_SH="${SCRIPT_DIR}/../lib/leadv2-worktree-protected.sh"
STATE_PATH_SH="${SCRIPT_DIR}/../leadv2-state-path.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

CLEANUP_DIRS=()
cleanup() { local d; for d in "${CLEANUP_DIRS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup EXIT

_new_fixture() {
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/lv-wtprot-repo.XXXXXX")"
  CLEANUP_DIRS+=("$root")
  (cd "$root" && git init -q)
  mkdir -p "$root/docs/leadv2"
  printf '%s' "$root"
}

# _alive_col <root> <pid> -> the alive(0|1) column for task_id=T1
# active.yaml is NOT under <root>/docs/leadv2 -- leadv2-state-path.sh
# resolves the real control-plane file (shared state dir, keyed off the
# fixture root's basename), so write there instead of guessing the path.
_alive_col() {
  local root="$1" pid="$2" out active_path
  active_path="$(PROJECT_ROOT="$root" bash "$STATE_PATH_SH" --no-link active.yaml)"
  CLEANUP_DIRS+=("$(dirname "$active_path")")
  mkdir -p "$(dirname "$active_path")"
  printf 'sessions:\n  - task_id: T1\n    pid: %s\n' "$pid" > "$active_path"
  out="$(bash -c '
    source "'"$LIB_SH"'"
    lv2_wt_protect_prime "'"$root"'"
    printf "%s" "$LV2_WT_PROTECT_SESSIONS"
  ')"
  # S-line format (prefix already stripped): task_id \t worktree \t pid \t birth \t alive
  printf '%s' "$out" | awk -F'\t' '$1=="T1"{print $5}'
}

section() { printf -- '\n== %s ==\n' "$1"; }

# ── C1: EPERM pid (1) -> alive=1 ─────────────────────────────────────────────
section "C1 — EPERM pid (1) must read alive=1, not 0"
if [[ "$(id -u)" == "0" ]]; then
  log "SKIP C1: running as root, kill(1,0) would not raise EPERM here"
else
  root="$(_new_fixture)"
  col="$(_alive_col "$root" 1)"
  if [[ "$col" == "1" ]]; then
    pass "C1: EPERM pid (1) reads alive=1"
  else
    fail "C1: expected alive=1, got '${col}'"
  fi
fi

# ── C2: genuinely dead pid -> alive=0 ────────────────────────────────────────
section "C2 — a genuinely dead (ESRCH) pid must still read alive=0"
root="$(_new_fixture)"
col="$(_alive_col "$root" 999999)"
if [[ "$col" == "0" ]]; then
  pass "C2: a genuinely dead (ESRCH) pid reads alive=0"
else
  fail "C2: expected alive=0, got '${col}'"
fi

printf -- '\n=== test-worktree-protected-pid-alive.sh: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
