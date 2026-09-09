#!/usr/bin/env bash
# run-all-triggers: leadv2-deploy-merge.sh
# test-merge-does-not-regress-main.sh — LANE-MERGE-SILENTLY-REVERTS-MAIN-01
# + the writing half of RECORD-THE-LANDING-DONT-INFER-IT-01 (531da1c7d042).
#
# Exercises leadv2-deploy-merge.sh END TO END -- real temp repo, bare origin,
# the real merge-queue lock, the real migration-apply -- never an extracted
# helper. The previous gate (leadv2-merge-safety-gate.sh, 57de5a5b) passed
# its own suite while being committed 100644, so its `[[ -x ]]` call site
# never ran it once: a gate that existed only in a commit message. These
# tests therefore bind to the script's own exit behaviour, the only thing
# that proves a gate exists on the running path.
#
# Case 1 (the brief's fixture): main receives fileX.txt after the lane
# branched; the lane's mid-flight wholesale merge resolution reverts it (a
# clean `git merge` would land exit 0 with fileX gone -- the five
# 2026-09-03 incidents). deploy-merge must REFUSE: rc!=0, fileX named on
# stderr, merge-blocker.flag written, origin/main untouched.
# Case 2: --allow-main-regression prints the full revert list and proceeds:
# merge lands, origin/main really loses fileX (the override is real, not
# cosmetic), and the landed commit carries Landed-lane:/Landed-branch:
# trailers (git log -1 --format=%B).
# Case 3 (no false positive): a lane that simply branched early and never
# merged main lands CLEAN -- a plain 3-way merge keeps a file added only on
# main, so fileX survives on origin/main; trailers present.
#
# Hermetic: every fixture is a from-scratch `git init` in a mktemp -d
# scratch dir (never `git worktree add`), control plane redirected via
# LEADV2_STATE_ROOT, handoff via LEADV2_PROJECT_ROOT. Bash 3.2 compatible.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_MERGE="${SCRIPT_DIR}/../leadv2-deploy-merge.sh"
# CLAUDE_PLUGIN_ROOT must be the plugin root (the dir containing scripts/),
# matching how the runtime sets it -- the script reaches the merge queue as
# ${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-merge-queue.sh.
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TASK_ID="regtest-0aa1"

PASS=0
FAIL=0
SCRATCH=""

_ok()   { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
_fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }

_cleanup() { [[ -n "$SCRATCH" ]] && rm -rf "$SCRATCH"; }
trap _cleanup EXIT

_mk_repo() {
  # $1 = scratch root. Prints the repo path. Sets up: main branch with a
  # base commit, lane branch "worktree-<TASK_ID>" with one work commit,
  # bare origin already holding main.
  local root="$1" repo
  repo="${root}/repo"
  git init -q --bare "${root}/origin.git"
  git init -q "$repo"
  git -C "$repo" config user.email t@t.example
  git -C "$repo" config user.name t
  git -C "$repo" remote add origin "${root}/origin.git"
  echo base > "${repo}/shared.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm base
  git -C "$repo" branch -m main
  git -C "$repo" push -q origin main
  printf '%s\n' "$repo"
}

_main_gains_fileX() {
  local repo="$1"
  git -C "$repo" checkout -q main
  seq 1 221 > "${repo}/fileX.txt"   # 221 lines: the worst measured incident
  git -C "$repo" add -A && git -C "$repo" commit -qm "other lane lands fileX"
  git -C "$repo" push -q origin main
}

_lane_wholesale_merges_main() {
  # The incident shape: the lane merges main mid-flight and resolves
  # wholesale to its own side. The merge commit carries main's ANCESTRY but
  # the lane's TREE, so fileX.txt is silently gone from the lane -- and no
  # lane commit ever names it (merge commits emit no --name-only patch).
  local repo="$1"
  git -C "$repo" checkout -q "worktree-${TASK_ID}"
  git -C "$repo" merge -s ours main -m "merge main mid-flight (wholesale resolution)"
  git -C "$repo" checkout -q main
}

_run_deploy() {
  # $1 = repo, remaining args pass through. Runs the real script from the
  # repo dir with all state redirected into the scratch root; combined
  # output to $OUT_FILE.
  local repo="$1"; shift
  (
    cd "$repo" || exit 99
    exec env \
      LEADV2_TASK_ID="${TASK_ID}" \
      LEADV2_PROJECT_ROOT="$repo" \
      LEADV2_STATE_ROOT="${SCRATCH}/state" \
      CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
      CLAUDE_PROJECT_ROOT="$repo" \
      LEADV2_MERGE_POLL_SEC=0.1 \
      LEADV2_MERGE_TIMEOUT_SEC=30 \
      bash "$DEPLOY_MERGE" "$@"
  ) >"$OUT_FILE" 2>&1
}

# ---------------------------------------------------------------------------
# Case 1: the brief's fixture -- probe must REFUSE with rc!=0 and name X.
# ---------------------------------------------------------------------------
test_accidental_revert_refused() {
  local root repo rc out
  root="$(mktemp -d)"; SCRATCH="$root"
  OUT_FILE="${root}/case1.out"
  repo="$(_mk_repo "$root")"
  git -C "$repo" checkout -qb "worktree-${TASK_ID}"
  echo "lane work" > "${repo}/lane_file.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane work"
  _main_gains_fileX "$repo"
  _lane_wholesale_merges_main "$repo"
  local main_before
  main_before="$(git -C "$root/origin.git" rev-parse main)"

  _run_deploy "$repo"; rc=$?
  out="$(cat "$OUT_FILE")"

  if [[ $rc -ne 0 ]] && grep -q 'MERGE_REFUSED' "$OUT_FILE" && grep -q 'fileX.txt' "$OUT_FILE"; then
    _ok "case 1: refused rc=$rc, names fileX.txt"
  else
    _fail "case 1: expected rc!=0 + MERGE_REFUSED naming fileX.txt, got rc=$rc: $out"
  fi
  if [[ -f "${repo}/docs/handoff/${TASK_ID}/merge-blocker.flag" ]] \
     && grep -q 'revert' "${repo}/docs/handoff/${TASK_ID}/merge-blocker.flag"; then
    _ok "case 1: merge-blocker.flag written"
  else
    _fail "case 1: merge-blocker.flag missing or wrong: $(cat "${repo}/docs/handoff/${TASK_ID}/merge-blocker.flag" 2>/dev/null)"
  fi
  if [[ "$(git -C "$root/origin.git" rev-parse main)" == "$main_before" ]] \
     && git -C "$root/origin.git" cat-file -e main:fileX.txt; then
    _ok "case 1: origin/main untouched, fileX.txt still there"
  else
    _fail "case 1: origin/main moved or lost fileX.txt"
  fi
  _cleanup; SCRATCH=""
}

# ---------------------------------------------------------------------------
# Case 2: --allow-main-regression prints the full list, proceeds, lands with
# trailers -- and the revert is real (origin/main loses fileX).
# ---------------------------------------------------------------------------
test_allow_override_lands_with_trailers() {
  local root repo rc
  root="$(mktemp -d)"; SCRATCH="$root"
  OUT_FILE="${root}/case2.out"
  repo="$(_mk_repo "$root")"
  git -C "$repo" checkout -qb "worktree-${TASK_ID}"
  echo "lane work" > "${repo}/lane_file.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane work"
  _main_gains_fileX "$repo"
  _lane_wholesale_merges_main "$repo"

  _run_deploy "$repo" --allow-main-regression; rc=$?

  if grep -q 'ALLOW-MAIN-REGRESSION' "$OUT_FILE" && grep -q 'fileX.txt' "$OUT_FILE"; then
    _ok "case 2: override prints the full revert list"
  else
    _fail "case 2: expected ALLOW-MAIN-REGRESSION list naming fileX.txt, got: $(cat "$OUT_FILE")"
  fi
  # The run must get PAST the gate: merge+push happen, then the missing
  # deploy override blocks -- that terminal BLOCK is the proof it proceeded.
  if [[ $rc -eq 1 ]] && grep -q 'deploy.sh not found' "$OUT_FILE"; then
    _ok "case 2: proceeded past the gate (terminal deploy-override BLOCK, rc=$rc)"
  else
    _fail "case 2: expected to proceed to the deploy-override BLOCK (rc=1), got rc=$rc: $(cat "$OUT_FILE")"
  fi
  local body
  body="$(git -C "$root/origin.git" log -1 --format=%B main)"
  if grep -qxF "Landed-lane: ${TASK_ID}" <<<"$body" \
     && grep -qxF "Landed-branch: worktree-${TASK_ID}" <<<"$body"; then
    _ok "case 2: landed commit carries Landed-lane/Landed-branch trailers"
  else
    _fail "case 2: trailers missing from landed commit: $body"
  fi
  if git -C "$root/origin.git" cat-file -e main:lane_file.txt \
     && ! git -C "$root/origin.git" cat-file -e main:fileX.txt 2>/dev/null; then
    _ok "case 2: override landed the lane AND really reverted fileX (honest override)"
  else
    _fail "case 2: landed tree not as declared (lane_file present, fileX gone expected)"
  fi
  _cleanup; SCRATCH=""
}

# ---------------------------------------------------------------------------
# Case 3: no false positive -- an ordinary early-branched lane lands clean,
# fileX SURVIVES on origin/main (3-way keeps main-only adds), trailers land.
# ---------------------------------------------------------------------------
test_clean_lane_lands_and_fileX_survives() {
  local root repo rc body
  root="$(mktemp -d)"; SCRATCH="$root"
  OUT_FILE="${root}/case3.out"
  repo="$(_mk_repo "$root")"
  git -C "$repo" checkout -qb "worktree-${TASK_ID}"
  echo "lane work" > "${repo}/lane_file.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane work"
  _main_gains_fileX "$repo"   # lane never merges main; deploy's rebase carries X

  _run_deploy "$repo"; rc=$?

  if ! grep -q 'MERGE_REFUSED' "$OUT_FILE"; then
    _ok "case 3: clean lane not refused"
  else
    _fail "case 3: FALSE POSITIVE -- clean lane refused: $(cat "$OUT_FILE")"
  fi
  if [[ $rc -eq 1 ]] && grep -q 'deploy.sh not found' "$OUT_FILE"; then
    _ok "case 3: reached the terminal deploy-override BLOCK (rc=$rc)"
  else
    _fail "case 3: expected deploy-override BLOCK rc=1, got rc=$rc: $(cat "$OUT_FILE")"
  fi
  if git -C "$root/origin.git" cat-file -e main:fileX.txt \
     && git -C "$root/origin.git" cat-file -e main:lane_file.txt; then
    _ok "case 3: fileX.txt SURVIVED the landing (no silent revert)"
  else
    _fail "case 3: fileX.txt lost on origin/main"
  fi
  body="$(git -C "$root/origin.git" log -1 --format=%B main)"
  if grep -qxF "Landed-lane: ${TASK_ID}" <<<"$body"; then
    _ok "case 3: trailers on the clean landing too"
  else
    _fail "case 3: trailers missing: $body"
  fi
  _cleanup; SCRATCH=""
}

test_accidental_revert_refused
test_allow_override_lands_with_trailers
test_clean_lane_lands_and_fileX_survives

printf 'test-merge-does-not-regress-main: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
