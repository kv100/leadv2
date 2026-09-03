#!/usr/bin/env bash
# tests/test-close-chain.sh — T11 close-chain-owns-the-lane-end-to-end DoD test.
#
# Live incidents fixed (2026-08-26):
#   D1: lane 299f2bae got dispatch_terminal terminal=landed cause=review_verdict_pass
#       while main had NO merge. leadv2-dispatch-product-close.sh's PASS branch now
#       merges the lane branch to the default branch and verifies via
#       merge-base --is-ancestor before writing `landed`; anything short of that
#       writes the new `pass_unlanded` terminal instead.
#   D2: the sweeper deleted live lanes with no commits yet. leadv2-lane-worktree.sh
#       now clears stale non-git leftover dirs that were silently causing
#       `worktree add` to fall back to the shared tree.
#   D3: terminal lanes piled up because per-turn injectors dirty three well-known
#       noise paths and `git worktree remove` (no --force) refuses on ANY dirt.
#       leadv2-worktree-cleanup.sh now restores just those three paths first.
#
# T11 fix-round (2026-08-26), review FAIL on 15c2c41:
#   F1: the PASS/merged branch of leadv2-dispatch-product-close.sh stamped the
#       review phase and stopped -- no lane_deregister, no worktree removal.
#       It now calls lib/leadv2-lane-state.sh's lane_deregister and
#       leadv2-worktree-cleanup.sh --name after a verified merge, journaling
#       close_deregistered / close_worktree_removed|kept either way.
#   F2: the requested anchor commit was DROPPED entirely (leadv2-lane-worktree.sh
#       said so explicitly) and the D2 test only asserted `git log -1` is
#       non-empty -- true even with zero anchor, since a fresh branch always
#       has its base commit. `ensure` now stamps a real
#       `git commit --allow-empty -m "lane <id> anchor"`, and both
#       --sweep-dead and --name in leadv2-worktree-cleanup.sh recognize a sole
#       ahead=1 anchor-subject commit as still-empty, so the dead/untouched-lane
#       GC path this was dropped for is not regressed.
#
# Scope note: this suite exercises each defect's actual fixed code directly
# (the ledger schema, the branch-merge/is-ancestor primitives D1 relies on, the
# lane-worktree anchor+stale-cleanup fix, and the noise-restore+sweeper-gate
# fix) in scratch git repos, rather than driving the full multi-thousand-line
# leadv2-dispatch-product-close.sh end to end (that script assumes a live
# review-gate/handoff/reviewer-arm environment far beyond a unit test's reach).
# Run: bash scripts/tests/test-close-chain.sh

set -euo pipefail
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Guard against mktemp -t without XXX in template
GUARD_SCRIPT="${SCRIPTS_DIR}/lib/mktemp-guard.sh"
if [ -f "$GUARD_SCRIPT" ]; then
    source "$GUARD_SCRIPT"
else
    echo "Error: mktemp-guard.sh not found" >&2
    exit 1
fi
mktemp_guard

LEDGER_SH="${SCRIPTS_DIR}/leadv2-dispatch-ledger.sh"
LANE_SH="${SCRIPTS_DIR}/leadv2-lane-worktree.sh"
CLEANUP_SH="${SCRIPTS_DIR}/leadv2-worktree-cleanup.sh"
STATE_PATH_SH="${SCRIPTS_DIR}/leadv2-state-path.sh"
BRANCH_MERGED_SH="${SCRIPTS_DIR}/leadv2-branch-merged.sh"

PASS=0
FAIL=0
ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# ── syntax on all four T11-touched files ────────────────────────────────────
for f in "$LEDGER_SH" "${SCRIPTS_DIR}/leadv2-dispatch-product-close.sh" "$LANE_SH" "$CLEANUP_SH"; do
  if bash -n "$f" 2>/dev/null; then pass "bash -n $(basename "$f")"; else fail "bash -n $(basename "$f")"; fi
done

new_scratch() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -q -b main
  git -C "$d" config user.email test@test
  git -C "$d" config user.name test
  mkdir -p "$d/docs/leadv2"
  printf 'seed\n' > "$d/README.md"
  git -C "$d" add README.md && git -C "$d" commit -q -m seed
  printf '%s' "$d"
}

# ── D1 schema: pass_unlanded is a valid, write-once TRUE terminal ──────────
# LEADV2_DISPATCH_TERMINAL_LEDGER_FILE (dispatch_terminal_ledger_file()'s first-checked
# override) pins the ledger to a private scratch file -- LEADV2_PROJECT_ROOT alone is NOT
# hermetic here: leadv2-state-path.sh's REPO_SLUG resolution can still land on the REAL
# checkout's control-plane state dir, silently sharing a persistent ledger across runs
# (a hardcoded sig8 like aaaa1111 would then falsely pass forever once poisoned).
S1="$(new_scratch)"
trap 'rm -rf "$S1"' RETURN
export LEADV2_PROJECT_ROOT="$S1"
export LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="${S1}/ledger-test.jsonl"
if bash "$LEDGER_SH" write-terminal aaaa1111 founder-a pass_unlanded merge_conflict "branch=worktree-x" >/dev/null 2>&1; then
  pass "(a/b groundwork) write-terminal accepts pass_unlanded"
else
  fail "(a/b groundwork) write-terminal rejects pass_unlanded"
fi
bash "$LEDGER_SH" write-terminal aaaa1111 founder-a landed review_verdict_pass "diff=deadbeef" >/dev/null 2>&1 || true
last_state="$(bash "$LEDGER_SH" state aaaa1111 2>/dev/null || true)"
if [[ "${last_state}" == "pass_unlanded" ]]; then
  pass "(a/b groundwork) write-once: a later landed never overwrites pass_unlanded for the same sig8"
else
  fail "(a/b groundwork) write-once: last state='${last_state}', expected pass_unlanded to survive"
fi
unset LEADV2_DISPATCH_TERMINAL_LEDGER_FILE
rm -rf "$S1"; trap - RETURN

# ── D1 primitive: successful merge -> is-ancestor true (scenario a shape) ──
S2="$(new_scratch)"
git -C "$S2" checkout -q -b worktree-lane
echo change > "$S2/f.txt"; git -C "$S2" add f.txt; git -C "$S2" commit -q -m "lane commit"
git -C "$S2" checkout -q main
source "$BRANCH_MERGED_SH"
if git -C "$S2" merge --no-edit --no-ff worktree-lane >/dev/null 2>&1 \
   && lv2_branch_merged "$S2" worktree-lane "$(lv2_default_branch "$S2")"; then
  pass "(a) clean lane branch merges + is-ancestor verifies true"
else
  fail "(a) clean lane branch merge/is-ancestor"
fi
rm -rf "$S2"

# ── D1 primitive: conflicting merge -> abort cleanly, never landed (scenario b) ──
S3="$(new_scratch)"
echo base > "$S3/f.txt"; git -C "$S3" add f.txt; git -C "$S3" commit -q -m base
git -C "$S3" checkout -q -b worktree-lane
echo lane-version > "$S3/f.txt"; git -C "$S3" commit -qam "lane edit"
git -C "$S3" checkout -q main
echo main-version > "$S3/f.txt"; git -C "$S3" commit -qam "main edit"
if git -C "$S3" merge --no-edit --no-ff worktree-lane >/dev/null 2>&1; then
  fail "(b) conflicting branches merged cleanly (test setup invalid)"
else
  git -C "$S3" merge --abort >/dev/null 2>&1 || true
  if [[ -z "$(git -C "$S3" status --porcelain)" ]] && ! lv2_branch_merged "$S3" worktree-lane "$(lv2_default_branch "$S3")"; then
    pass "(b) conflicting merge aborts clean, branch stays unmerged -> pass_unlanded path"
  else
    fail "(b) merge --abort left repo dirty or branch falsely merged"
  fi
fi
rm -rf "$S3"

# ── F2: ensure() stamps a REAL anchor commit (ahead-by-exactly-1, subject
# "lane <id> anchor"), and that anchor merges to main cleanly ───────────────
S4="$(new_scratch)"
export LEADV2_PROJECT_ROOT="$S4"
# Kept OUTSIDE the repo -- an errf inside $S4 is untracked and would show up
# in the `git status --porcelain` clean-merge check below.
export LEADV2_LANE_WORKTREE_ERRF="$(mktemp "${TMPDIR:-/tmp}/lane-err.XXXXXX")"
lane_dir="$(bash "$LANE_SH" ensure taskAnchor heavy)"
anchor_ahead="$(git -C "$S4" rev-list --count "main..worktree-taskAnchor" 2>/dev/null || echo -1)"
anchor_subj="$(git -C "$S4" log -1 --format='%s' "main..worktree-taskAnchor" 2>/dev/null || true)"
if [[ "$anchor_ahead" == "1" && "$anchor_subj" == "lane taskAnchor anchor" ]]; then
  pass "(F2) fresh lane worktree is ahead-by-exactly-1 with subject 'lane taskAnchor anchor'"
else
  fail "(F2) anchor not real: ahead=${anchor_ahead} subj='${anchor_subj}' (expected ahead=1, subj='lane taskAnchor anchor')"
fi
if git -C "$S4" merge --no-edit --no-ff worktree-taskAnchor >/dev/null 2>&1 \
   && [[ -z "$(git -C "$S4" status --porcelain -- . ':!.claude')" ]]; then
  pass "(F2) anchor-only branch merges to main cleanly (no conflict, no leftover)"
else
  fail "(F2) anchor-only branch failed to merge cleanly into main"
fi
git -C "$S4" reset -q --hard HEAD~1 2>/dev/null || true
# Simulate a crashed prior attempt: state dir with no .git left behind.
rm -rf "$lane_dir"
mkdir -p "$lane_dir/docs"; echo leftover > "$lane_dir/docs/stale.txt"
lane_dir2="$(bash "$LANE_SH" ensure taskAnchor heavy)"
active_yaml_branch="$(git -C "$lane_dir2" symbolic-ref --short HEAD 2>/dev/null || echo MISSING)"
if [[ "$active_yaml_branch" == worktree-taskAnchor ]]; then
  pass "(D2) stale non-git leftover no longer forces shared-tree fallback"
else
  fail "(D2) stale leftover still causes fallback (branch=${active_yaml_branch})"
fi
rm -rf "$S4"

# ── D3: noise-only dirt is restored+removed; real dirt is kept ─────────────
S5="$(new_scratch)"
# leadv2-worktree-cleanup.sh is a top-level executable (no function guard) --
# sourcing it whole would run its arg-parser and `exit`. Extract just the one
# function under test instead of sourcing the file.
eval "$(sed -n '/^_LV2_WT_NOISE_PATHS=/p;/^_lv2_wt_restore_noise() {/,/^}/p' "$CLEANUP_SH")"
mkdir -p "$S5/docs/leadv2"
printf 'noise\n' > "$S5/docs/leadv2/open-threads.md"
printf 'noise\n' > "$S5/docs/LEAD_V2_STATE.md"
printf 'tasks: []\n' > "$S5/docs/tasks.yaml"
git -C "$S5" add docs && git -C "$S5" commit -q -m "seed noise paths"
printf 'dirtied-by-injector\n' >> "$S5/docs/leadv2/open-threads.md"
remaining="$(_lv2_wt_restore_noise "$S5")"
if [[ -z "$remaining" ]]; then
  pass "(e) noise-only dirt (open-threads.md) fully restored"
else
  fail "(e) noise-only dirt not restored: '${remaining}'"
fi
printf 'real user edit\n' > "$S5/real.txt"
git -C "$S5" add real.txt >/dev/null 2>&1 || true
printf 'dirtied-by-injector-again\n' >> "$S5/docs/leadv2/open-threads.md"
remaining2="$(_lv2_wt_restore_noise "$S5")"
if [[ -n "$remaining2" ]] && printf '%s' "$remaining2" | grep -q real.txt \
   && ! printf '%s' "$remaining2" | grep -q open-threads.md; then
  pass "(e) real dirt kept, noise dirt still cleared alongside it"
else
  fail "(e) real-dirt-kept / noise-cleared mix: '${remaining2}'"
fi
rm -rf "$S5"

# ── D2/D3 sweeper gate: registered live lane survives, unregistered dead one is swept ──
# F2 regression check folded in: the dead lane now carries a genuine anchor
# commit (git worktree add alone leaves it commit-less, unlike a real
# LANE_SH-created lane) -- --sweep-dead must still remove it despite ahead=1,
# proving the anchor-tolerance fix in leadv2-worktree-cleanup.sh works, not
# just that an untouched lane happens to be ahead=0.
S6="$(new_scratch)"
export LEADV2_PROJECT_ROOT="$S6"
mkdir -p "$S6/.claude/worktrees"
git -C "$S6" worktree add -q -b worktree-live "$S6/.claude/worktrees/live-lane" main >/dev/null 2>&1
git -C "$S6" worktree add -q -b worktree-dead "$S6/.claude/worktrees/dead-lane" main >/dev/null 2>&1
git -C "$S6/.claude/worktrees/dead-lane" commit -q --allow-empty -m "lane dead-lane anchor"
# The protection gate (lv2_wt_protect_prime) reads active.yaml via the SAME
# canonical resolver the real code uses (leadv2-state-path.sh --no-link),
# which for a git-initialized scratch repo resolves OUTSIDE the repo tree
# (an .ephemeral control-plane dir keyed by the scratch dir's basename), not
# docs/leadv2/active.yaml inside it. Writing only the repo-relative path made
# the resolver come back active-yaml-missing -> fail-closed -> both lanes
# "protected", so a prior version of this assertion silently proved nothing
# about registration recognition. Resolve the real path and write there too.
_s6_active_path="$(PROJECT_ROOT="$S6" bash "$STATE_PATH_SH" --no-link active.yaml)"
mkdir -p "$(dirname "$_s6_active_path")"
cat > "$_s6_active_path" <<YAML
meta: {}
sessions:
  - task_id: live-lane
    lead_session_id: s1
    worktree: $S6/.claude/worktrees/live-lane
    phase: build
    pid: 1
    dead_at: null
YAML
if [[ -x "$CLEANUP_SH" ]]; then
  # REPO_ROOT inside leadv2-worktree-cleanup.sh is `git rev-parse --show-toplevel`
  # of the CALLER's cwd, not LEADV2_PROJECT_ROOT -- cd into the scratch repo so
  # the sweep actually targets $S6 instead of silently operating on the real
  # checkout this test happens to run from.
  (cd "$S6" && LEADV2_SWEEP_MIN_AGE_S=0 bash "$CLEANUP_SH" --sweep-dead >/dev/null 2>&1) || true
else
  bash "$CLEANUP_SH" 2>&1 | true
fi
if [[ -d "$S6/.claude/worktrees/live-lane" ]]; then
  pass "(c) active.yaml-registered lane survives a --sweep-dead pass"
else
  fail "(c) registered live lane was swept"
fi
if [[ ! -d "$S6/.claude/worktrees/dead-lane" ]]; then
  pass "(F2) dead lane with ONLY the anchor commit (ahead=1) is still swept, not falsely kept"
else
  fail "(F2) dead+anchor-only lane survived --sweep-dead (ahead-tolerance fix not working)"
fi
rm -rf "$S6" "$(dirname "$_s6_active_path")"

# ── F1: close-chain completes merge -> deregister -> remove for a landed lane ──
S7="$(new_scratch)"
export LEADV2_PROJECT_ROOT="$S7"
export LEADV2_LANE_WORKTREE_ERRF="$(mktemp "${TMPDIR:-/tmp}/lane-err.XXXXXX")"
lane7_dir="$(bash "$LANE_SH" ensure taskF1 heavy)"
echo "real work" > "$lane7_dir/work.txt"
git -C "$lane7_dir" add work.txt && git -C "$lane7_dir" commit -q -m "taskF1 real commit"
if git -C "$S7" merge --no-edit --no-ff worktree-taskF1 >/dev/null 2>&1; then
  pass "(F1) landed lane's branch merges cleanly into main"
else
  fail "(F1) landed lane's branch failed to merge into main"
fi
# shellcheck source=lib/leadv2-lane-state.sh
source "${SCRIPTS_DIR}/lib/leadv2-lane-state.sh"
lane_register taskF1 lead-s1 "$lane7_dir" build "$$" >/dev/null 2>&1 || true
if lane_deregister taskF1 close_landed >/dev/null 2>&1 && ! lane_alive taskF1 >/dev/null 2>&1; then
  pass "(F1) lane_deregister marks the lane dead in the registry"
else
  fail "(F1) lane_deregister did not mark the lane dead"
fi
# cd into the scratch repo -- REPO_ROOT in leadv2-worktree-cleanup.sh is
# `git rev-parse --show-toplevel` of the caller's cwd, not LEADV2_PROJECT_ROOT.
if (cd "$S7" && bash "$CLEANUP_SH" --name taskF1 >/dev/null 2>&1) && [[ ! -d "$lane7_dir" ]]; then
  pass "(F1) worktree-cleanup --name removes the now-merged, deregistered lane worktree"
else
  fail "(F1) worktree-cleanup --name did not remove the merged lane worktree"
fi
rm -rf "$S7"

log ""
log "=== T11 close-chain results: ${PASS} passed, ${FAIL} failed ==="
if (( FAIL > 0 )); then
  for e in "${ERRORS[@]}"; do log "$e"; done
  exit 1
fi
exit 0
