#!/usr/bin/env bash
# tests/test-fork-session-guard.sh — FORK-SESSION-SCRIPT-HAS-NO-SUITES-01.
#
# leadv2-fork-session.sh landed on main (FORK-RUNS-A-SESSION-01) with zero
# test coverage. An orphaned branch (worktree-63e9aaff, 2026-08-17) carried
# three suites and a SKILL.md targeting a superseded flag-based CLI
# (--preflight/--root, LEADV2_FORK_SESSION=1-style stdout env lines) that no
# longer exists -- the live script is positional (preflight <task-id>
# [class]) and preflight prints exactly ONE line, the lane root. This suite
# is a fresh authoring against the CURRENT contract, not a port.
#
# Covers cmd_preflight + assert_isolated_lane (the H1 isolation predicate):
#   1. bash -n syntax check.
#   2. happy path: preflight creates a real worktree on branch
#      worktree-<task-id>, registers it in active.yaml, prints exactly the
#      lane root path and nothing else.
#   3. kill-switch: LEADV2_LANE_WORKTREE=off -> exit 1, no worktree created.
#   4. idempotent re-run: same task-id returns the identical lane root.
#   5. isolation check 4 (branch identity): after a valid lane exists, its
#      worktree HEAD is force-moved onto a different branch; a second
#      preflight call must refuse (exit 1) rather than silently accept a
#      lane on the wrong branch.
#
# Not covered, both documented rather than faked:
#   - isolation check 2 (expected-path mismatch, ensure's shared-root
#     fallback): the fallback path this check guards against is gated by
#     resurrection_allowed(), which fails OPEN (allowed) whenever the
#     calling process's own pid is alive -- true of any test process, so a
#     black-box sandbox cannot force ensure() into the degraded path this
#     check exists to catch without also faking process liveness.
#   - isolation check 3 (unregistered worktree): ensure() itself clears a
#     stray non-git directory at the expected path before assert_isolated_
#     lane ever runs (T11-D2's rm -rf of untracked leftovers), so this
#     failure mode is not reachable through the public preflight/commit CLI.
#
# Run: bash scripts/tests/test-fork-session-guard.sh
# run-all-triggers: leadv2-fork-session

set -euo pipefail

# BURN-GOVERNOR-01: default-on burn gate reads the host's real burn history.
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

# ── Test 2: happy path ───────────────────────────────────────────────────────
d="$(_new_sandbox)"
out="$(LEADV2_PROJECT_ROOT="$d" LEADV2_LANE_WORKTREE_ERRF="$d/.lw.err" \
  bash "$FS_SH" preflight fork-task-01 2>"$d/.stderr")" && rc=0 || rc=$?
nlines="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
if [[ "$rc" -eq 0 ]] && [[ "$nlines" -eq 1 ]] \
   && [[ "$out" == "$d/.claude/worktrees/fork-task-01" ]] \
   && [[ -d "$out/.git" || -f "$out/.git" ]]; then
  pass "happy path: preflight prints exactly one line, the lane root"
else
  fail "happy path (rc=$rc nlines=$nlines out='$out')"
fi

if git -C "$d" rev-parse --verify -q worktree-fork-task-01 >/dev/null 2>&1 \
   && [[ "$(git -C "$out" symbolic-ref --short HEAD 2>/dev/null)" == "worktree-fork-task-01" ]]; then
  pass "happy path: lane worktree is on branch worktree-<task-id>"
else
  fail "happy path: branch identity"
fi

if grep -q "fork-task-01" "$d/docs/leadv2/active.yaml" 2>/dev/null; then
  pass "happy path: task registered in active.yaml"
else
  fail "happy path: active.yaml registration (file: $(cat "$d/docs/leadv2/active.yaml" 2>/dev/null || echo MISSING))"
fi

# ── Test 3: kill-switch ──────────────────────────────────────────────────────
d2="$(_new_sandbox)"
LEADV2_PROJECT_ROOT="$d2" LEADV2_LANE_WORKTREE="off" \
  bash "$FS_SH" preflight killswitch-task >/dev/null 2>"$d2/.stderr" && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && [[ ! -d "$d2/.claude/worktrees/killswitch-task" ]]; then
  pass "kill-switch: LEADV2_LANE_WORKTREE=off refuses, no worktree created"
else
  fail "kill-switch (rc=$rc, dir exists=$([[ -d "$d2/.claude/worktrees/killswitch-task" ]] && echo yes || echo no))"
fi

# ── Test 4: idempotent re-run ────────────────────────────────────────────────
d3="$(_new_sandbox)"
out1="$(LEADV2_PROJECT_ROOT="$d3" bash "$FS_SH" preflight idem-task 2>/dev/null)"
out2="$(LEADV2_PROJECT_ROOT="$d3" bash "$FS_SH" preflight idem-task 2>/dev/null)"
if [[ -n "$out1" ]] && [[ "$out1" == "$out2" ]]; then
  pass "idempotent re-run returns the identical lane root"
else
  fail "idempotent re-run (out1='$out1' out2='$out2')"
fi

# ── Test 5: isolation check 4 -- branch identity on a re-run ────────────────
d5="$(_new_sandbox)"
lane5="$(LEADV2_PROJECT_ROOT="$d5" bash "$FS_SH" preflight branch-task 2>/dev/null)"
git -C "$d5" branch drift-branch main >/dev/null 2>&1
git -C "$lane5" symbolic-ref HEAD refs/heads/drift-branch
LEADV2_PROJECT_ROOT="$d5" bash "$FS_SH" preflight branch-task >/dev/null 2>"$d5/.stderr" && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && grep -qi "expected 'worktree-branch-task'" "$d5/.stderr"; then
  pass "isolation check 4: a lane whose branch drifted is refused, not silently accepted"
else
  fail "isolation check 4 (rc=$rc stderr='$(cat "$d5/.stderr" 2>/dev/null)')"
fi

# ── Mutation control: the branch-identity check (isolation check 4) ────────
# Mutate the comparison in assert_isolated_lane so a drifted branch is wrongly
# accepted. Numeric/string equality only -- never a bare `[[ expr ]]`
# truthiness trap (s4's finding: `[[ false ]]` is a non-empty-string test,
# always true).
# The mutant MUST live next to the real script (SCRIPT_DIR-relative sibling
# resolution: it locates leadv2-lane-worktree.sh etc. via its OWN
# ${SCRIPT_DIR}, so a copy elsewhere fails with "No such file or directory"
# on every sibling call, not on the mutated line -- caught live).
MUTANT="${SCRIPT_DIR}/../.fork-session-mutant-$$.sh"
trap 'rm -f "$MUTANT"' EXIT
cp "$FS_SH" "$MUTANT"
python3 - "$MUTANT" <<'PYEOF' && mutate_rc=0 || mutate_rc=$?
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = '  if [[ "$branch" != "worktree-${task_id}" ]]; then'
assert anchor in s, "mutation anchor not found: " + anchor
mutant = s.replace(anchor, '  if [[ 1 -eq 0 ]]; then', 1)
assert mutant != s
open(p, "w", encoding="utf-8").write(mutant)
PYEOF
if [[ "$mutate_rc" -ne 0 ]]; then
  fail "mutation anchor not found in leadv2-fork-session.sh -- source drifted, control cannot run"
else
  if grep -qF '  if [[ "$branch" != "worktree-${task_id}" ]]; then' "$MUTANT"; then
    fail "mutation did not land (anchor still present)"
  else
    pass "mutation landed inside assert_isolated_lane's body"
  fi

  d6="$(_new_sandbox)"
  lane6="$(LEADV2_PROJECT_ROOT="$d6" bash "$MUTANT" preflight branch-task 2>/dev/null)"
  git -C "$d6" branch drift-branch main >/dev/null 2>&1
  git -C "$lane6" symbolic-ref HEAD refs/heads/drift-branch
  LEADV2_PROJECT_ROOT="$d6" bash "$MUTANT" preflight branch-task >/dev/null 2>/dev/null && mrc=0 || mrc=$?
  if [[ "$mrc" -eq 0 ]]; then
    pass "RED with the mutation: a drifted branch is wrongly accepted (exit 0)"
  else
    fail "RED with the mutation: expected exit 0, got $mrc"
  fi

  d7="$(_new_sandbox)"
  lane7="$(LEADV2_PROJECT_ROOT="$d7" bash "$FS_SH" preflight branch-task 2>/dev/null)"
  git -C "$d7" branch drift-branch main >/dev/null 2>&1
  git -C "$lane7" symbolic-ref HEAD refs/heads/drift-branch
  LEADV2_PROJECT_ROOT="$d7" bash "$FS_SH" preflight branch-task >/dev/null 2>/dev/null && grc=0 || grc=$?
  if [[ "$grc" -eq 1 ]]; then
    pass "GREEN without the mutation: the real script still refuses the drifted branch"
  else
    fail "GREEN regreen: expected exit 1, got $grc"
  fi
fi

echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
