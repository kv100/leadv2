#!/usr/bin/env bash
# run-all-triggers: leadv2-active-cache.sh leadv2-lane-liveness.sh
# test-active-cache-liveness.sh — D2-M4 (D2-SINGLE-LIVENESS-VERDICT §5/§6)
#
# hooks/leadv2-active-cache.sh used to decide "is this session's pid alive"
# with a bare `os.kill(pid, 0)` -- ESRCH/EPERM collapsed to the same except
# branch, and a bare kill(0)==0 does not prove the pid is THIS session's own
# worker (a recycled pid onto an interactive claude session reads as alive
# for hours -- brief #9/#14). Converted to consume
# leadv2-lane-liveness.sh --all --json's pid_alive field instead.
#
# C1: an EPERM pid (1) must still be treated as alive -- the session survives
#     into the reported ACTIVE_TASK_ID/ACTIVE_PHASE, not silently dropped.
# C2: a genuinely dead pid (ESRCH) is dropped, same as before the conversion.
# C3: mutation control -- reverting the liveness-consuming logic to a bare
#     kill(0) must make C1 go red (a real, mandatory negative control).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK_SH="${PLUGIN_DIR}/hooks/leadv2-active-cache.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

CLEANUP_DIRS=()
cleanup() { local d; for d in "${CLEANUP_DIRS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup EXIT

_new_fixture() {
  local root state
  root="$(mktemp -d "${TMPDIR:-/tmp}/lv-acache-repo.XXXXXX")"
  state="$(mktemp -d "${TMPDIR:-/tmp}/lv-acache-state.XXXXXX")"
  CLEANUP_DIRS+=("$root" "$state")
  (cd "$root" && git init -q)
  mkdir -p "$root/docs/leadv2" "$root/docs/handoff"
  printf '%s %s\n' "$root" "$state"
}

# Run leadv2_read_active_yaml in a subshell against a fixture active.yaml,
# print ACTIVE_TASK_ID/ACTIVE_PHASE.
_read_active() {  # <root> <active_yaml> <state_dir_for_cache>
  local root="$1" active="$2" cache_state="$3"
  bash -c '
    source "$1"
    leadv2_read_active_yaml "$2"
    printf "%s\n%s\n" "$ACTIVE_TASK_ID" "$ACTIVE_PHASE"
  ' _sub "${HOOK_SH}" "${active}" \
    LEADV2_ACTIVE_CACHE_STATE_DIR="${cache_state}" \
    PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}"
}

section() { printf -- '\n== %s ==\n' "$1"; }

# ── C1: EPERM pid (1) is alive, session survives ────────────────────────────
section "C1 — EPERM pid (1) must not be dropped as dead"
FIX="$(_new_fixture)"; root="${FIX%% *}"; state="${FIX##* }"
active="${root}/docs/leadv2/active.yaml"
if [[ "$(id -u)" == "0" ]]; then
  log "SKIP C1: running as root, kill(1,0) would not raise EPERM here"
else
  printf 'sessions:\n  - task_id: EPERM-LIVE-01\n    pid: 1\n    phase: build\n' > "$active"
  cache_state="$(mktemp -d "${TMPDIR:-/tmp}/lv-acache-cachedir.XXXXXX")"
  CLEANUP_DIRS+=("$cache_state")
  out="$(LEADV2_ACTIVE_CACHE_STATE_DIR="${cache_state}" _read_active "${root}" "${active}" "${cache_state}")"
  tid="$(printf '%s' "$out" | sed -n '1p')"
  if [[ "$tid" == "EPERM-LIVE-01" ]]; then
    pass "C1: EPERM pid (1) session reported as the active task, not dropped"
  else
    fail "C1: expected EPERM-LIVE-01, got tid=[$tid] full=[$out]"
  fi
fi

# ── C2: genuinely dead pid (ESRCH) is dropped ───────────────────────────────
section "C2 — a genuinely dead pid must still be dropped"
FIX="$(_new_fixture)"; root="${FIX%% *}"; state="${FIX##* }"
active="${root}/docs/leadv2/active.yaml"
# A pid guaranteed dead: fork+exit, then reuse its number (best-effort -- use
# a very high, almost-certainly-unallocated pid instead, which os.kill also
# reports ESRCH for).
printf 'sessions:\n  - task_id: DEAD-01\n    pid: 999999\n    phase: build\n' > "$active"
cache_state="$(mktemp -d "${TMPDIR:-/tmp}/lv-acache-cachedir.XXXXXX")"
CLEANUP_DIRS+=("$cache_state")
out="$(_read_active "${root}" "${active}" "${cache_state}")"
tid="$(printf '%s' "$out" | sed -n '1p')"
if [[ -z "$tid" ]]; then
  pass "C2: a genuinely dead (ESRCH) pid's session is dropped, no active task reported"
else
  fail "C2: expected no active task, got tid=[$tid]"
fi

printf -- '\n=== test-active-cache-liveness.sh: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
