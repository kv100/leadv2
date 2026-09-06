#!/usr/bin/env bash
# run-all-triggers: leadv2-task-anchor.sh
# test-task-anchor-dead-pid-worktree-fallback.sh —
# TASK-ANCHOR-DEAD-PID-SKIPS-WORKTREE-FALLBACK-01
#
# hooks/leadv2-task-anchor.sh's active.yaml scan used to `continue`
# (exclude from worktree-fallback matching) for EVERY session row whose
# pid is not one of this process's own ancestors, regardless of whether
# that pid was alive or dead -- both the `try` body (alive) and the
# `except (ProcessLookupError, PermissionError)` (dead/foreign) branches
# ended in `continue`. The comment directly above the code says the
# intent is to exclude only a LIVE different session ("Never select it by
# worktree fallback" -- referring to "A valid PID belonging to a
# different live process tree"); a genuinely dead pid (ESRCH) is not a
# live foreign session and its row should fall through to worktree
# matching instead.
#
# C1: a session row with a genuinely dead pid (ESRCH) and worktree == cwd
#     must still be selected as the active task via worktree fallback.
# C2 (regression sanity): a session row with an ALIVE foreign pid (not our
#     own ancestor) and worktree == cwd must NOT be selected -- the
#     original exclusion for a live foreign session is unaffected.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK_SH="${PLUGIN_DIR}/hooks/leadv2-task-anchor.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

CLEANUP_DIRS=()
cleanup() { local d; for d in "${CLEANUP_DIRS[@]:-}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done; }
trap cleanup EXIT

_new_fixture() {
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/lv-anchor-repo.XXXXXX")"
  CLEANUP_DIRS+=("$root")
  (cd "$root" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed)
  mkdir -p "$root/docs/leadv2" "$root/docs/handoff"
  printf '%s' "$root"
}

_find_unused_pid() {
  local p=999999
  while kill -0 "$p" 2>/dev/null; do p=$((p + 1)); done
  echo "$p"
}

_run_hook() {  # <root> <tid> <pid> -> stdout
  printf '{"cwd":"%s"}' "$1" | CLAUDE_PROJECT_DIR="$1" bash "${HOOK_SH}"
}

section() { printf -- '\n== %s ==\n' "$1"; }

# ── C1: genuinely dead pid + worktree==cwd -> still selected ────────────────
section "C1 — a dead (ESRCH) session pid must not block worktree-fallback selection"
root="$(_new_fixture)"
dead_pid="$(_find_unused_pid)"
cat > "${root}/docs/leadv2/active.yaml" <<YAML
sessions:
  - task_id: ANCHOR-C1-DEAD-PID
    pid: ${dead_pid}
    worktree: "${root}"
    started_at: "2020-01-01T00:00:00Z"
    phase: build
YAML
out="$(_run_hook "${root}")"
if [[ "${out}" == *'ACTIVE TASK: ANCHOR-C1-DEAD-PID'* ]]; then
  pass "C1: a dead-pid row with matching worktree is selected via fallback"
else
  fail "C1: expected ACTIVE TASK: ANCHOR-C1-DEAD-PID in output, got: ${out}"
fi

# ── C2 (regression sanity): alive foreign pid + worktree==cwd -> excluded ───
section "C2 — an alive foreign-session pid must still be excluded (unchanged)"
root="$(_new_fixture)"
# A real, alive pid that is NOT this test process's ancestor: a short-lived
# background sleep, still running while we invoke the hook.
sleep 30 &
live_pid=$!
cat > "${root}/docs/leadv2/active.yaml" <<YAML
sessions:
  - task_id: ANCHOR-C2-LIVE-FOREIGN-PID
    pid: ${live_pid}
    worktree: "${root}"
    started_at: "2020-01-01T00:00:00Z"
    phase: build
YAML
out="$(_run_hook "${root}")"
kill "${live_pid}" 2>/dev/null
wait "${live_pid}" 2>/dev/null
if [[ "${out}" != *'ACTIVE TASK: ANCHOR-C2-LIVE-FOREIGN-PID'* ]]; then
  pass "C2: a live foreign-session row is still excluded from worktree fallback"
else
  fail "C2: an alive foreign pid's row was wrongly selected: ${out}"
fi

printf -- '\n=== test-task-anchor-dead-pid-worktree-fallback.sh: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
