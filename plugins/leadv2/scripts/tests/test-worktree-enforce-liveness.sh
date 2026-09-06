#!/usr/bin/env bash
# run-all-triggers: leadv2-worktree-enforce.sh leadv2-lane-liveness.sh
# test-worktree-enforce-liveness.sh — D2-M4 (D2-SINGLE-LIVENESS-VERDICT §5/§6)
#
# hooks/leadv2-worktree-enforce.sh used to decide "is there a live /leadv2
# task" with a bare os.kill(pid, 0) loop over active.yaml's sessions --
# ESRCH/EPERM collapsed to the same except branch (D2 brief #9/#14).
# Converted to consume leadv2-lane-liveness.sh --all --json's pid_alive.
#
# C1: an EPERM pid (1) session must still be treated as live -- a main-repo
#     code edit is BLOCKED (rc=2), same as before the conversion.
# C2: a genuinely dead (ESRCH) pid session must not block -- the edit is
#     allowed (rc=0).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK_SH="${PLUGIN_DIR}/hooks/leadv2-worktree-enforce.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

CLEANUP_DIRS=()
cleanup() { local d; for d in "${CLEANUP_DIRS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup EXIT

_new_fixture() {
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/lv-wtenf-repo.XXXXXX")"
  CLEANUP_DIRS+=("$root")
  (cd "$root" && git init -q)
  mkdir -p "$root/docs/leadv2" "$root/docs/handoff"
  printf '%s' "$root"
}

_run_hook() {  # <root> <active_yaml_content> <file_path> -> rc
  local root="$1" active_content="$2" file_path="$3"
  printf '%s' "$active_content" > "${root}/docs/leadv2/active.yaml"
  # The hook checks $PWD/docs/leadv2/active.yaml BEFORE
  # $CLAUDE_PROJECT_ROOT/docs/leadv2/active.yaml -- cd into the fixture root
  # so $PWD resolves there too, or a real active.yaml elsewhere on this
  # machine wins by candidate-order and this test silently exercises the
  # wrong fixture.
  ( cd "${root}" && printf '{"tool_input":{"file_path":"%s"}}' "$file_path" | \
    CLAUDE_PROJECT_ROOT="${root}" bash "${HOOK_SH}" >/dev/null 2>"${root}/.stderr" )
  echo $?
}

section() { printf -- '\n== %s ==\n' "$1"; }

# ── C1: EPERM pid (1) still blocks a main-repo code edit ────────────────────
section "C1 — EPERM pid (1) must still be treated as a live task (block)"
root="$(_new_fixture)"
if [[ "$(id -u)" == "0" ]]; then
  log "SKIP C1: running as root, kill(1,0) would not raise EPERM here"
else
  # NOT under $root (mktemp roots live under /tmp or /var/folders, both
  # whitelisted by the hook itself) -- a fabricated path is fine, the hook
  # never checks the file exists, only its FILE_PATH string.
  rc="$(_run_hook "${root}" 'sessions:
  - task_id: EPERM-LIVE-01
    pid: 1
' "/Users/fixture/fake-main-repo/somefile.py")"
  if [[ "${rc}" == "2" ]]; then
    pass "C1: EPERM pid (1) live task still blocks a main-repo code edit (rc=2)"
  else
    fail "C1: expected rc=2, got rc=${rc}, stderr=$(cat "${root}/.stderr" 2>/dev/null)"
  fi
fi

# ── C2: genuinely dead pid (ESRCH) does not block ───────────────────────────
section "C2 — a genuinely dead pid must not block (no live task)"
root="$(_new_fixture)"
rc="$(_run_hook "${root}" 'sessions:
  - task_id: DEAD-01
    pid: 999999
' "/Users/fixture/fake-main-repo/somefile.py")"
if [[ "${rc}" == "0" ]]; then
  pass "C2: a genuinely dead (ESRCH) pid's session does not block (rc=0)"
else
  fail "C2: expected rc=0, got rc=${rc}, stderr=$(cat "${root}/.stderr" 2>/dev/null)"
fi

printf -- '\n=== test-worktree-enforce-liveness.sh: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
