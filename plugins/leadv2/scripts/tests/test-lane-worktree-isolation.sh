#!/usr/bin/env bash
# tests/test-lane-worktree-isolation.sh — LANE-WORKTREE-ISOLATION-01 DoD test.
#
# DoD (docs/handoff/supervisor-scope/TASK-SPEC-worktree-isolation.md): two
# heavy lanes run concurrently, each committing to docs/tasks.yaml in the same
# minute, and BOTH changes survive — verified by reading the merged file, not
# either lane's status line. Removing isolation must make the same test fail.
#
# This exercises the real pieces end to end in a scratch repo:
#   1. leadv2-lane-worktree.sh ensure  -- creates lane A/B worktrees+branches
#      (the (a) fix: what leadv2-fanout.sh now calls before every launch).
#   2. Each lane edits a DIFFERENT row of docs/tasks.yaml and commits with
#      `git commit <path>` (pathspec form -- (d), never `git commit -a`).
#   3. Both lanes land via a ff-only rebase+merge sequence -- the same shape
#      leadv2-deploy-merge.sh already uses ((b): reviewed merge, conflict
#      loudly on overlap, never silently pick one side).
#
# Tests:
#   1. bash -n syntax check on leadv2-lane-worktree.sh.
#   2. ensure() creates two DISTINCT worktree dirs on branches worktree-A/-B.
#   3. Lane A's row survives after Lane A lands.
#   4. Lane B's row ALSO survives after Lane B lands on top of A (both rows
#      present in the same file -- the actual clobber this task fixes).
#   5. A genuine overlapping edit (same row, both lanes) is REFUSED loudly
#      (non-zero rc, no silent pick-one-side) rather than merged.
#
# Run: bash scripts/tests/test-lane-worktree-isolation.sh

set -euo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANE_SH="${SCRIPT_DIR}/../leadv2-lane-worktree.sh"

PASS=0
FAIL=0
ERRORS=()

log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# ── syntax check ─────────────────────────────────────────────────────────────
if bash -n "$LANE_SH" 2>/dev/null; then
  pass "bash -n syntax check"
else
  fail "bash -n syntax check"
fi

# ── build a scratch git repo ─────────────────────────────────────────────────
SCRATCH="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '${SCRATCH}'" EXIT

git -C "$SCRATCH" init -q -b main
git -C "$SCRATCH" config user.email "test@test"
git -C "$SCRATCH" config user.name "test"

mkdir -p "$SCRATCH/docs"
cat > "$SCRATCH/docs/tasks.yaml" <<'YAML'
tasks:
  - id: rowA
    status: queued
  - id: rowB
    status: queued
YAML
git -C "$SCRATCH" add docs/tasks.yaml
git -C "$SCRATCH" commit -q -m "seed tasks.yaml"

export LEADV2_PROJECT_ROOT="$SCRATCH"
export LEADV2_LANE_WORKTREE_ERRF="$SCRATCH/.lane-worktree.err"

# ── test 2: ensure() creates two distinct worktrees ─────────────────────────
laneA_dir="$(bash "$LANE_SH" ensure taskA heavy)"
laneB_dir="$(bash "$LANE_SH" ensure taskB heavy)"

if [[ -n "$laneA_dir" && -n "$laneB_dir" && "$laneA_dir" != "$laneB_dir" ]]; then
  pass "ensure() creates two distinct lane worktrees"
else
  fail "ensure() distinct worktrees (laneA='$laneA_dir' laneB='$laneB_dir')"
fi

if [[ "$laneA_dir" == "$SCRATCH/.claude/worktrees/taskA" ]] \
   && git -C "$SCRATCH" rev-parse --verify -q worktree-taskA >/dev/null 2>&1; then
  pass "lane A worktree path + branch match EnterWorktree/deploy-merge.sh convention"
else
  fail "lane A path/branch convention (got '$laneA_dir')"
fi

# ── edit each lane's OWN row, commit via pathspec form only ─────────────────
python3 - "$laneA_dir/docs/tasks.yaml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("id: rowA\n    status: queued", "id: rowA\n    status: done")
open(p, "w").write(s)
PY
git -C "$laneA_dir" commit docs/tasks.yaml -m "lane A: rowA -> done" -q

python3 - "$laneB_dir/docs/tasks.yaml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("id: rowB\n    status: queued", "id: rowB\n    status: done")
open(p, "w").write(s)
PY
git -C "$laneB_dir" commit docs/tasks.yaml -m "lane B: rowB -> done" -q

# ── land both lanes (ff-only rebase+merge, mirrors leadv2-deploy-merge.sh) ──
land() {
  local lane_dir="$1" branch="$2"
  git -C "$lane_dir" rebase main >/dev/null 2>&1 || return 1
  git -C "$SCRATCH" merge --ff-only "$branch" >/dev/null 2>&1 || return 1
}

if land "$laneA_dir" worktree-taskA; then
  pass "lane A lands ff-only onto main"
else
  fail "lane A ff-only land"
fi

if grep -q "id: rowA" "$SCRATCH/docs/tasks.yaml" && grep -A1 "id: rowA" "$SCRATCH/docs/tasks.yaml" | grep -q "status: done"; then
  pass "lane A's row survives in the merged file"
else
  fail "lane A's row missing/reverted after its own land"
fi

if land "$laneB_dir" worktree-taskB; then
  pass "lane B lands ff-only onto main (after A, same minute)"
else
  fail "lane B ff-only land"
fi

# ── DoD: both rows present in the SAME merged file, read fresh from disk ────
merged="$(cat "$SCRATCH/docs/tasks.yaml")"
if grep -A1 "id: rowA" <<<"$merged" | grep -q "status: done" \
   && grep -A1 "id: rowB" <<<"$merged" | grep -q "status: done"; then
  pass "DoD: both lanes' changes survive in the merged docs/tasks.yaml"
else
  fail "DoD: merged file is missing one lane's change (the exact clobber this task fixes)"
fi

# ── overlap case: both lanes edit the SAME row -> must conflict loudly ─────
SCRATCH2="$(mktemp -d)"
git -C "$SCRATCH2" init -q -b main
git -C "$SCRATCH2" config user.email "test@test"
git -C "$SCRATCH2" config user.name "test"
mkdir -p "$SCRATCH2/docs"
printf 'tasks:\n  - id: rowX\n    status: queued\n' > "$SCRATCH2/docs/tasks.yaml"
git -C "$SCRATCH2" add docs/tasks.yaml
git -C "$SCRATCH2" commit -q -m seed

export LEADV2_PROJECT_ROOT="$SCRATCH2"
laneC_dir="$(bash "$LANE_SH" ensure taskC heavy)"
laneD_dir="$(bash "$LANE_SH" ensure taskD heavy)"
sed -i.bak 's/status: queued/status: done-by-C/' "$laneC_dir/docs/tasks.yaml" && rm -f "$laneC_dir/docs/tasks.yaml.bak"
git -C "$laneC_dir" commit docs/tasks.yaml -m "lane C: rowX -> done-by-C" -q
sed -i.bak 's/status: queued/status: done-by-D/' "$laneD_dir/docs/tasks.yaml" && rm -f "$laneD_dir/docs/tasks.yaml.bak"
git -C "$laneD_dir" commit docs/tasks.yaml -m "lane D: rowX -> done-by-D" -q

land "$laneC_dir" worktree-taskC >/dev/null 2>&1 || true
before_overlap="$(cat "$SCRATCH2/docs/tasks.yaml")"
if land "$laneD_dir" worktree-taskD; then
  fail "overlapping edit silently landed instead of conflicting loudly"
else
  after_overlap="$(cat "$SCRATCH2/docs/tasks.yaml")"
  if [[ "$before_overlap" == "$after_overlap" ]]; then
    pass "overlapping row edit is REFUSED loudly (rc!=0), main left untouched -- never a silent pick-one-side"
  else
    fail "overlapping edit rejected but main was mutated anyway"
  fi
fi

# ── W-1: direct-dispatch path-of must resolve pinned, even from a nested cwd ─
# R2 (architect prepass §1.3): leadv2-dispatch-code.sh:1169 called `path-of`
# without pinning LEADV2_PROJECT_ROOT, so cwd inside a lane worktree made
# resolve_root() pick the WORKTREE as root -- lane_dir() then computed
# <worktree>/.claude/worktrees (never exists) and path-of silently returned
# empty. Reproduce the bug unpinned, then prove the pin (what the fix now
# does at every call site) resolves correctly from the same cwd.
CLEANUP_SH="${SCRIPT_DIR}/../leadv2-worktree-cleanup.sh"

# SUPERSEDED 2026-08-22 by NESTED-LANE-WORKTREES-01. This case used to assert the
# BUG still reproduced (unpinned path-of returning empty from a nested cwd). The
# root-resolution fix in leadv2-lane-worktree.sh cures it at the source: an
# unpinned call now normalizes to the main checkout via --git-common-dir and finds
# the lane. Asserting the old empty result would now pin a bug that no longer
# exists — so the assertion is inverted, and the pin case below still guards the
# call-site contract independently.
( cd "$laneA_dir" && unset LEADV2_PROJECT_ROOT && bash "$LANE_SH" path-of taskA 2>/dev/null > "$SCRATCH/unpinned.out" )
unpinned_out="$(cat "$SCRATCH/unpinned.out" 2>/dev/null)"
if [[ "$(cd "$unpinned_out" 2>/dev/null && pwd -P)" == "$(cd "$laneA_dir" 2>/dev/null && pwd -P)" ]]; then
  pass "R2 cured: path-of from inside a lane worktree resolves the lane even UNPINNED"
else
  fail "R2 cured: unpinned path-of should resolve '$laneA_dir', got '$unpinned_out'"
fi

pinned_out="$(cd "$laneA_dir" && LEADV2_PROJECT_ROOT="$SCRATCH" bash "$LANE_SH" path-of taskA 2>/dev/null)"
if [[ "$pinned_out" == "$laneA_dir" ]]; then
  pass "R2 fix: path-of from the SAME nested cwd resolves correctly when LEADV2_PROJECT_ROOT is pinned"
else
  fail "R2 fix: pinned path-of mismatch (got '$pinned_out', want '$laneA_dir')"
fi

# ── W-1: leadv2-worktree-cleanup.sh --sweep-dead ─────────────────────────────
SCRATCH3="$(mktemp -d)"
git -C "$SCRATCH3" init -q -b main
git -C "$SCRATCH3" config user.email "test@test"
git -C "$SCRATCH3" config user.name "test"
printf 'seed\n' > "$SCRATCH3/seed.txt"
git -C "$SCRATCH3" add seed.txt
git -C "$SCRATCH3" commit -q -m seed

export LEADV2_PROJECT_ROOT="$SCRATCH3"
export LEADV2_LANE_WORKTREE_ERRF="$SCRATCH3/.lane-worktree.err"

# SWEEPER-LANE-SAFETY-01: --sweep-dead consults the lane-protection gate, so
# the fixture carries its own control plane (empty active.yaml — a MISSING one
# fails closed and protects everything) and disables the 48h age probe (these
# fixture worktrees are young by definition). --name ignores the gate.
mkdir -p "${SCRATCH3}/state"
printf 'sessions: []\n' > "${SCRATCH3}/state/active.yaml"
export LEADV2_STATE_ROOT="${SCRATCH3}/state"
export LEADV2_SWEEP_MIN_AGE_H=0

# dead + empty -> must be swept
dead_empty_dir="$(bash "$LANE_SH" ensure deadEmpty standard)"
# dead + dirty -> must be kept
dead_dirty_dir="$(bash "$LANE_SH" ensure deadDirty standard)"
printf 'uncommitted\n' > "$dead_dirty_dir/scratch.txt"
# dead + unmerged commit -> must be kept
dead_unmerged_dir="$(bash "$LANE_SH" ensure deadUnmerged standard)"
printf 'work\n' > "$dead_unmerged_dir/work.txt"
git -C "$dead_unmerged_dir" add work.txt
git -C "$dead_unmerged_dir" commit -q -m "unmerged work"
# alive + empty -> must be kept (liveness wins over emptiness)
alive_empty_dir="$(bash "$LANE_SH" ensure aliveEmpty standard)"
mkdir -p "$SCRATCH3/docs/handoff/aliveEmpty"
: > "$SCRATCH3/docs/handoff/aliveEmpty/developer.stream.jsonl"

sweep_out="$(cd "$SCRATCH3" && bash "$CLEANUP_SH" --sweep-dead 2>&1)"

wt_list="$(git -C "$SCRATCH3" worktree list --porcelain | awk '/^worktree /{print $2}')"
if ! grep -qF "$dead_empty_dir" <<<"$wt_list"; then
  pass "sweep-dead: dead+empty lane worktree removed"
else
  fail "sweep-dead: dead+empty lane worktree NOT removed"
fi
if grep -qF "$dead_dirty_dir" <<<"$wt_list"; then
  pass "sweep-dead: dead+dirty lane worktree KEPT"
else
  fail "sweep-dead: dead+dirty lane worktree was removed (should be kept)"
fi
if grep -qF "$dead_unmerged_dir" <<<"$wt_list"; then
  pass "sweep-dead: dead+unmerged-commits lane worktree KEPT"
else
  fail "sweep-dead: dead+unmerged lane worktree was removed (should be kept)"
fi
if grep -qF "$alive_empty_dir" <<<"$wt_list"; then
  pass "sweep-dead: alive lane worktree KEPT even though empty (liveness wins)"
else
  fail "sweep-dead: alive lane worktree was removed (should be kept)"
fi
if grep -q "^sweep-dead: [0-9]* removed / [0-9]* kept$" <<<"$sweep_out"; then
  pass "sweep-dead: prints a removed/kept tally"
else
  fail "sweep-dead: missing removed/kept tally line (got: $sweep_out)"
fi

# ── W-1: leadv2-worktree-cleanup.sh --name refuses an unmerged lane ─────────
if ( cd "$SCRATCH3" && bash "$CLEANUP_SH" --name deadUnmerged >/dev/null 2>&1 ); then
  fail "--name removed a worktree with unmerged commits without --force"
else
  pass "--name refuses to reap a worktree with unmerged commits (no --force)"
fi
if git -C "$SCRATCH3" worktree list --porcelain | grep -qF "$dead_unmerged_dir"; then
  pass "--name refusal left the unmerged worktree intact"
else
  fail "--name refusal removed the worktree anyway"
fi
if ( cd "$SCRATCH3" && bash "$CLEANUP_SH" --name deadUnmerged --force >/dev/null 2>&1 ); then
  pass "--name --force overrides the unmerged-commits refusal"
else
  fail "--name --force failed to remove the unmerged worktree"
fi

# ── W-1: leadv2-worktree-cleanup.sh --name refuses on merge-blocker.flag ────
blocked_dir="$(bash "$LANE_SH" ensure blockedLane standard)"
mkdir -p "$SCRATCH3/docs/handoff/blockedLane"
printf 'merge_blocked: true\nreason: ff_only_conflict\n' > "$SCRATCH3/docs/handoff/blockedLane/merge-blocker.flag"
if ( cd "$SCRATCH3" && bash "$CLEANUP_SH" --name blockedLane >/dev/null 2>&1 ); then
  fail "--name removed a worktree carrying merge-blocker.flag without --force"
else
  pass "--name refuses to reap a worktree carrying merge-blocker.flag (no --force)"
fi
if git -C "$SCRATCH3" worktree list --porcelain | grep -qF "$blocked_dir"; then
  pass "merge-blocker.flag refusal left the worktree intact"
else
  fail "merge-blocker.flag refusal removed the worktree anyway"
fi

# ── W-1a §3.1: dispatch-code.sh reaps a no-worker lane worktree on EXIT ──────
# The direct-dispatch path (backlog/supervisor pump) reaches dispatch-code.sh's own
# EXIT trap, not the fanout launcher's reap. _reap_lane_worktree_if_unused must reap an
# orphaned empty worktree, KEEP a dirty one, and NEVER touch the tree of a lane that
# spawned a live worker. Source the REAL function text from dispatch-code.sh (not a copy).
DISPATCH_SH="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
REAP_FN="$(sed -n '/^_reap_lane_worktree_if_unused() {/,/^}$/p' "$DISPATCH_SH")"
if [[ -n "$REAP_FN" ]]; then
  SCRATCH4="$(mktemp -d)"
  git -C "$SCRATCH4" init -q -b main
  git -C "$SCRATCH4" config user.email "test@test"; git -C "$SCRATCH4" config user.name "test"
  printf 'seed\n' > "$SCRATCH4/seed.txt"; git -C "$SCRATCH4" add seed.txt; git -C "$SCRATCH4" commit -q -m seed
  export LEADV2_PROJECT_ROOT="$SCRATCH4"
  export LEADV2_LANE_WORKTREE_ERRF="$SCRATCH4/.lane-worktree.err"

  # define the real reap fn in this shell; it resolves cleanup.sh via ${SCRIPT_DIR},
  # which inside dispatch-code.sh is the scripts/ dir -- repoint SCRIPT_DIR there for
  # the reap calls (this test's SCRIPT_DIR is scripts/tests/), then restore it.
  eval "$REAP_FN"
  PROJECT_ROOT="$SCRATCH4"
  _SAVED_SD="$SCRIPT_DIR"; SCRIPT_DIR="${SCRIPT_DIR}/.."

  reap_empty="$(bash "$LANE_SH" ensure reapEmpty standard)"   # no-worker + empty
  reap_dirty="$(bash "$LANE_SH" ensure reapDirty standard)"   # no-worker + dirty
  reap_live="$(bash "$LANE_SH" ensure reapLive standard)"     # worker-live (kept)
  printf 'uncommitted\n' > "$reap_dirty/scratch.txt"

  WORK_ROOT="$reap_live"; founder_task_id="reapLive"; _DISPATCH_WORKER_LIVE=1
  _reap_lane_worktree_if_unused
  WORK_ROOT="$reap_empty"; founder_task_id="reapEmpty"; _DISPATCH_WORKER_LIVE=0
  ( cd "$SCRATCH4" && _reap_lane_worktree_if_unused )
  WORK_ROOT="$reap_dirty"; founder_task_id="reapDirty"; _DISPATCH_WORKER_LIVE=0
  ( cd "$SCRATCH4" && _reap_lane_worktree_if_unused )

  wt4="$(git -C "$SCRATCH4" worktree list --porcelain | awk '/^worktree /{print $2}')"
  if ! grep -qF "$reap_empty" <<<"$wt4"; then
    pass "dispatch-reap: no-worker + empty lane worktree reaped on EXIT"
  else
    fail "dispatch-reap: no-worker + empty lane worktree NOT reaped (should be gone)"
  fi
  if grep -qF "$reap_dirty" <<<"$wt4"; then
    pass "dispatch-reap: no-worker + dirty lane worktree KEPT (never forced)"
  else
    fail "dispatch-reap: dirty lane worktree was reaped (should be kept)"
  fi
  if grep -qF "$reap_live" <<<"$wt4"; then
    pass "dispatch-reap: live-worker lane worktree KEPT (never reaped on success)"
  else
    fail "dispatch-reap: live-worker lane worktree was reaped (must survive for the worker)"
  fi
  SCRIPT_DIR="$_SAVED_SD"
else
  fail "dispatch-reap: could not extract _reap_lane_worktree_if_unused from dispatch-code.sh"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  printf -- '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
