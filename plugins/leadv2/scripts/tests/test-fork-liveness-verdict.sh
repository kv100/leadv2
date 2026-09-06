#!/usr/bin/env bash
# tests/test-fork-liveness-verdict.sh — FORK-SESSION-SCRIPT-HAS-NO-SUITES-01.
#
# Covers leadv2-fork-session.sh's cmd_postflight (Carve-out B: worktree
# reaping). Fresh authoring against the current positional CLI
# (postflight <task-id> [--self-spawn] [--force]) -- see
# test-fork-session-guard.sh's header for why the orphaned branch's suites
# are not ported.
#
# Tests:
#   1. bash -n syntax check.
#   2. no-op-safe: postflight on a task with no worktree at all exits 0
#      without error.
#   3. dirty-lane refusal: uncommitted changes in the lane -> exit 1, the
#      worktree is LEFT ON DISK (never silently discarded).
#   4. clean lane: postflight removes the worktree (no-op-safe idempotent
#      Phase 8 reap) -- committed work is not "dirty".
#   5. --force overrides the dirty refusal and reaps anyway.
#
# Run: bash scripts/tests/test-fork-liveness-verdict.sh
# run-all-triggers: leadv2-fork-session

set -euo pipefail
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FS_SH="${SCRIPT_DIR}/../leadv2-fork-session.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

if bash -n "$FS_SH" 2>/dev/null; then pass "syntax check"; else fail "syntax check"; fi

_new_sandbox() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -q -b main
  git -C "$d" config user.email "t@t.example"
  git -C "$d" config user.name "t"
  mkdir -p "$d/plugins/leadv2"
  printf '# plugin marker\n' > "$d/plugins/leadv2/.claude-plugin-marker"
  echo init > "$d/README.md"
  git -C "$d" add -A
  git -C "$d" commit -q -m init
  printf '%s' "$d"
}

# All postflight/cleanup calls run with cwd INSIDE the sandbox: leadv2-
# worktree-cleanup.sh resolves its own repo root via a bare
# `git rev-parse --show-toplevel` (cwd-based, not LEADV2_PROJECT_ROOT) --
# caught live: a call from outside the sandbox silently reaped/refused
# against the WRONG repo (this session's own persona-engine checkout).

# ── Test 2: no-op-safe on a task with no worktree ────────────────────────────
d="$(_new_sandbox)"
(cd "$d" && LEADV2_PROJECT_ROOT="$d" bash "$FS_SH" postflight never-existed) >/dev/null 2>"$d/.stderr" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "no-op-safe: postflight on a nonexistent lane exits 0"
else
  fail "no-op-safe (rc=$rc stderr='$(cat "$d/.stderr" 2>/dev/null)')"
fi

# ── Test 3: dirty-lane refusal (uncommitted changes, cmd_postflight's own gate)
d2="$(_new_sandbox)"
lane2="$(cd "$d2" && LEADV2_PROJECT_ROOT="$d2" bash "$FS_SH" preflight dirty-task 2>/dev/null)"
echo "uncommitted work" > "$lane2/scratch.txt"
(cd "$d2" && LEADV2_PROJECT_ROOT="$d2" bash "$FS_SH" postflight dirty-task) >/dev/null 2>"$d2/.stderr" && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && [[ -d "$lane2" ]] && [[ -f "$lane2/scratch.txt" ]]; then
  pass "dirty-lane refusal: exit 1, worktree and its untracked file left on disk"
else
  fail "dirty-lane refusal (rc=$rc lane_exists=$([[ -d "$lane2" ]] && echo yes || echo no))"
fi

# ── Test 4: a clean, LANDED lane is reaped ───────────────────────────────────
# Committed-but-unmerged is a DIFFERENT refusal (leadv2-worktree-cleanup.sh's
# own unmerged-commits gate, one layer below cmd_postflight's dirty check) --
# a lane only reaps cleanly once its branch is actually an ancestor of main.
d3="$(_new_sandbox)"
lane3="$(cd "$d3" && LEADV2_PROJECT_ROOT="$d3" bash "$FS_SH" preflight clean-task 2>/dev/null)"
echo "committed work" > "$lane3/work.txt"
git -C "$lane3" add work.txt
git -C "$lane3" commit -q -m "fork: committed work"
git -C "$d3" merge --no-ff -q worktree-clean-task -m "land clean-task"
(cd "$d3" && LEADV2_PROJECT_ROOT="$d3" bash "$FS_SH" postflight clean-task) >/dev/null 2>"$d3/.stderr" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && [[ ! -d "$lane3" ]]; then
  pass "a clean, landed lane is reaped (committed + merged, no longer dirty or unmerged)"
else
  fail "clean lane reap (rc=$rc lane_exists=$([[ -d "$lane3" ]] && echo yes || echo no) stderr='$(cat "$d3/.stderr" 2>/dev/null)')"
fi

# ── Test 5: --force overrides the unmerged-commits refusal ──────────────────
d4="$(_new_sandbox)"
lane4="$(cd "$d4" && LEADV2_PROJECT_ROOT="$d4" bash "$FS_SH" preflight force-task 2>/dev/null)"
echo "unlanded work" > "$lane4/work.txt"
git -C "$lane4" add work.txt
git -C "$lane4" commit -q -m "fork: never lands"
(cd "$d4" && LEADV2_PROJECT_ROOT="$d4" bash "$FS_SH" postflight force-task) >/dev/null 2>/dev/null && rc=0 || rc=$?
if [[ "$rc" -ne 1 ]] || [[ ! -d "$lane4" ]]; then
  fail "--force precondition: expected the un-forced call to refuse first (rc=$rc)"
else
  pass "--force precondition: an unlanded lane is refused without --force"
fi
(cd "$d4" && LEADV2_PROJECT_ROOT="$d4" bash "$FS_SH" postflight force-task --force) >/dev/null 2>"$d4/.stderr" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && [[ ! -d "$lane4" ]]; then
  pass "--force overrides the unmerged-commits refusal and reaps the worktree"
else
  fail "--force reap (rc=$rc lane_exists=$([[ -d "$lane4" ]] && echo yes || echo no) stderr='$(cat "$d4/.stderr" 2>/dev/null)')"
fi

# ── Mutation control: preflight's own envelope must not count as dirty ──────
# cmd_postflight drops fork-lane.env (preflight's own bookkeeping, not fork
# work) BEFORE the dirty check -- "an otherwise-clean lane is not refused
# for carrying its own address label" (leadv2-fork-session.sh's own
# comment). Mutate that rm away: a fully-landed lane whose only residual
# file is fork-lane.env must now be wrongly refused as dirty.
MUTANT="${SCRIPT_DIR}/../.fork-liveness-mutant-$$.sh"
trap 'rm -f "$MUTANT"' EXIT
cp "$FS_SH" "$MUTANT"
python3 - "$MUTANT" <<'PYEOF' && mutate_rc=0 || mutate_rc=$?
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = '  rm -f "${lane_root}/docs/handoff/${task_id}/fork-lane.env" 2>/dev/null || true'
assert anchor in s, "mutation anchor not found: " + anchor
mutant = s.replace(anchor, '  : # mutated away', 1)
assert mutant != s
open(p, "w", encoding="utf-8").write(mutant)
PYEOF
if [[ "$mutate_rc" -ne 0 ]]; then
  fail "mutation anchor not found in leadv2-fork-session.sh -- source drifted, control cannot run"
else
  pass "mutation landed inside cmd_postflight's fork-lane.env drop"

  d5="$(_new_sandbox)"
  lane5="$(cd "$d5" && LEADV2_PROJECT_ROOT="$d5" bash "$MUTANT" preflight mut-task 2>/dev/null)"
  echo landed > "$lane5/landed.txt"; git -C "$lane5" add landed.txt; git -C "$lane5" commit -q -m "land it"
  git -C "$d5" merge --no-ff -q worktree-mut-task -m "land mut-task"
  (cd "$d5" && LEADV2_PROJECT_ROOT="$d5" bash "$MUTANT" postflight mut-task) >/dev/null 2>/dev/null && mrc=0 || mrc=$?
  if [[ "$mrc" -ne 0 ]] && [[ -d "$lane5" ]]; then
    pass "RED with the mutation: preflight's own leftover envelope wrongly blocks the reap"
  else
    fail "RED with the mutation: expected a refusal (rc!=0, lane kept), got rc=$mrc lane_exists=$([[ -d "$lane5" ]] && echo yes || echo no)"
  fi

  d6="$(_new_sandbox)"
  lane6="$(cd "$d6" && LEADV2_PROJECT_ROOT="$d6" bash "$FS_SH" preflight mut-task 2>/dev/null)"
  echo landed > "$lane6/landed.txt"; git -C "$lane6" add landed.txt; git -C "$lane6" commit -q -m "land it"
  git -C "$d6" merge --no-ff -q worktree-mut-task -m "land mut-task"
  (cd "$d6" && LEADV2_PROJECT_ROOT="$d6" bash "$FS_SH" postflight mut-task) >/dev/null 2>/dev/null && grc=0 || grc=$?
  if [[ "$grc" -eq 0 ]] && [[ ! -d "$lane6" ]]; then
    pass "GREEN without the mutation: the real script drops its own envelope and reaps cleanly"
  else
    fail "GREEN regreen: expected rc=0 + reaped, got rc=$grc lane_exists=$([[ -d "$lane6" ]] && echo yes || echo no)"
  fi
fi

echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
