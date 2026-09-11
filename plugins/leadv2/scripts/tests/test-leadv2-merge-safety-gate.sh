#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-deploy-merge.sh leadv2-dispatch-product-close.sh
# test-leadv2-merge-safety-gate.sh — LANE-MERGE-SILENTLY-REVERTS-MAIN-01
#
# Hermetic git-sandbox fixtures for leadv2-merge-safety-gate.sh. This suite
# pins the gate's NO-FALSE-POSITIVE and FAIL-CLOSED behaviour under the
# merged-tree discriminator (tip-diff semantics were replaced 2026-09-10:
# the gate now computes the would-be merge TREE and refuses only paths the
# merge would change that no lane commit ever named -- see the gate header
# for why a branch-tip comparison both over- and under-fires). The
# refusal path itself -- the five-incident `merge -s ours` wholesale shape
# -- is owned by test-merge-safety-reverts-main.sh; the wiring through
# leadv2-deploy-merge.sh end to end is owned by
# test-merge-does-not-regress-main.sh.
#
# Every clean case below is belt-and-suspenders: the gate must say rc 0
# AND the real `git merge --no-ff` must land what the merge tree
# predicted, so a verdict is never trusted off the gate's own arithmetic.
#
# Each fixture is a from-scratch `git init` in a mktemp -d scratch dir --
# never `git worktree add` (founder lesson, 2026-08-22): a plain temp repo
# registers nothing in the real repo's .git/worktrees/ and is prune-safe by
# construction.
#
# Bash 3.2 compatible: no associative arrays, no ${x^^}, no readarray.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${SCRIPT_DIR}/../leadv2-merge-safety-gate.sh"

PASS=0
FAIL=0

_ok()   { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
_fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }

_mk_repo() {
  local tmp
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  git -C "$tmp" config user.email t@t.example
  git -C "$tmp" config user.name t
  printf '%s\n' "$tmp"
}
# bash-guard: allow

# ---------------------------------------------------------------------------
# Case 1: plain fork, no mid-flight merge -- main adds fileX after the lane
# branched; the lane's commits never mention it. A real 3-way merge KEEPS a
# path added only on the "ours" side, so the merge tree matches main on
# fileX and the gate must say rc 0. (The old tip-diff gate refused this --
# blocking every lane that forked before main moved. The refusal that
# matters is the `merge -s ours` shape, covered in
# test-merge-safety-reverts-main.sh.)
# ---------------------------------------------------------------------------
test_plain_fork_is_clean_and_merge_keeps_file() {
  local repo rc
  repo="$(_mk_repo)"

  echo base > "${repo}/shared.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm base
  git -C "$repo" branch -m main >/dev/null 2>&1 || true

  git -C "$repo" checkout -qb laneB

  git -C "$repo" checkout -q main
  printf 'line1\nline2\nline3\n' > "${repo}/fileX.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane A adds fileX"

  git -C "$repo" checkout -q laneB
  echo "laneB work" >> "${repo}/shared.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "laneB work"

  bash "$GATE" "$repo" laneB main >/tmp/mgs-case1.out 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    _ok "case 1: plain fork is clean under merged-tree semantics (rc=0)"
  else
    _fail "case 1: plain fork wrongly refused (rc=$rc): $(cat /tmp/mgs-case1.out)"
  fi

  # Belt-and-suspenders: the real merge lands clean and fileX survives --
  # the gate's rc 0 matched git's actual behaviour.
  git -C "$repo" checkout -q main
  if git -C "$repo" merge --no-edit --no-ff laneB >/tmp/mgs-case1-merge.out 2>&1 \
     && [[ -f "${repo}/fileX.txt" ]]; then
    _ok "case 1: real merge exit 0 and fileX.txt survives (gate agreed with git)"
  else
    _fail "case 1: real merge failed or deleted fileX.txt -- $(cat /tmp/mgs-case1-merge.out)"
  fi

  rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# Case 2: two files land on main after the fork (WORKER-OUTLIVES round-3
# shape) -- still clean while the lane never wholesale-merged main: the
# merge tree keeps both, and so does the real merge.
# ---------------------------------------------------------------------------
test_multi_file_plain_fork_is_clean() {
  local repo rc
  repo="$(_mk_repo)"

  echo base > "${repo}/shared.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm base
  git -C "$repo" branch -m main >/dev/null 2>&1 || true
  git -C "$repo" checkout -qb laneB

  git -C "$repo" checkout -q main
  printf 'a\nb\n' > "${repo}/test-suite-one.sh"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane A lands test-suite-one.sh"
  printf 'c\nd\n' > "${repo}/test-suite-two.sh"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane C lands test-suite-two.sh"

  git -C "$repo" checkout -q laneB
  echo "laneB work" >> "${repo}/shared.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "laneB work"

  bash "$GATE" "$repo" laneB main >/tmp/mgs-case2.out 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    _ok "case 2: multi-file plain fork is clean (rc=0)"
  else
    _fail "case 2: wrongly refused (rc=$rc): $(cat /tmp/mgs-case2.out)"
  fi

  git -C "$repo" checkout -q main
  if git -C "$repo" merge --no-edit --no-ff laneB >/tmp/mgs-case2-merge.out 2>&1 \
     && [[ -f "${repo}/test-suite-one.sh" && -f "${repo}/test-suite-two.sh" ]]; then
    _ok "case 2: real merge keeps both concurrently-landed files (gate agreed with git)"
  else
    _fail "case 2: real merge lost a file -- $(cat /tmp/mgs-case2-merge.out)"
  fi

  rm -rf "$repo"
}
# bash-guard: allow

# ---------------------------------------------------------------------------
# Case 3: negative control -- a lane that deliberately deletes its OWN file
# (existed at the merge-base, untouched by main) must always land: its
# commit NAMES the path, so the merge-tree change is the lane's decision.
# ---------------------------------------------------------------------------
test_intentional_own_deletion_always_lands() {
  local repo rc
  repo="$(_mk_repo)"

  echo base > "${repo}/shared.txt"
  echo "to be removed by the lane" > "${repo}/obsolete.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm base
  git -C "$repo" branch -m main >/dev/null 2>&1 || true
  git -C "$repo" checkout -qb laneD

  git -C "$repo" rm -q obsolete.txt
  git -C "$repo" commit -qm "laneD removes obsolete.txt as part of its own work"

  bash "$GATE" "$repo" laneD main >/tmp/mgs-case3.out 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    _ok "case 3: lane's own deletion of its own file is allowed to land"
  else
    _fail "case 3: intentional deletion wrongly refused (rc=$rc): $(cat /tmp/mgs-case3.out)"
  fi

  # Confirm it is real: a real merge into main also lands clean and the file
  # is genuinely gone (the deletion was not a false negative).
  git -C "$repo" checkout -q main
  if git -C "$repo" merge --no-edit --no-ff laneD >/tmp/mgs-case3-merge.out 2>&1; then
    if [[ ! -f "${repo}/obsolete.txt" ]]; then
      _ok "case 3: real merge lands clean and obsolete.txt is genuinely gone"
    else
      _fail "case 3: real merge did not remove obsolete.txt"
    fi
  else
    _fail "case 3: real merge unexpectedly failed -- $(cat /tmp/mgs-case3-merge.out)"
  fi

  rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# Case 4: reverse direction -- a lane deliberately deletes a file that main
# ALSO advanced on unrelated paths in the meantime. The lane is genuinely
# behind main on other files, but its own named deletion must still be
# trusted AND the unrelated main file must survive the merge -- both legs
# hold under merged-tree semantics (the merge tree keeps what main added;
# it drops only what the lane named).
# ---------------------------------------------------------------------------
test_intentional_deletion_lands_even_while_lane_is_behind() {
  local repo rc
  repo="$(_mk_repo)"

  echo base > "${repo}/shared.txt"
  echo "to be removed by the lane" > "${repo}/obsolete.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm base
  git -C "$repo" branch -m main >/dev/null 2>&1 || true
  git -C "$repo" checkout -qb laneE

  git -C "$repo" rm -q obsolete.txt
  git -C "$repo" commit -qm "laneE removes obsolete.txt as part of its own work"

  # Meanwhile main lands an unrelated new file (a concurrent lane) -- laneE
  # never touches it.
  git -C "$repo" checkout -q main
  printf 'x\ny\n' > "${repo}/unrelated-new-file.sh"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane F lands unrelated-new-file.sh"

  git -C "$repo" checkout -q laneE

  bash "$GATE" "$repo" laneE main >/tmp/mgs-case4.out 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    _ok "case 4: behind-main lane with its own named deletion is clean (rc=0)"
  else
    _fail "case 4: wrongly refused (rc=$rc): $(cat /tmp/mgs-case4.out)"
  fi

  # The real merge must land BOTH intents: the lane's deletion AND main's
  # unrelated addition.
  git -C "$repo" checkout -q main
  if git -C "$repo" merge --no-edit --no-ff laneE >/tmp/mgs-case4-merge.out 2>&1; then
    if [[ ! -f "${repo}/obsolete.txt" && -f "${repo}/unrelated-new-file.sh" ]]; then
      _ok "case 4: real merge lands the deletion AND keeps unrelated-new-file.sh (gate agreed with git)"
    else
      _fail "case 4: real merge lost one of the two intents -- $(cat /tmp/mgs-case4-merge.out)"
    fi
  else
    _fail "case 4: real merge unexpectedly failed -- $(cat /tmp/mgs-case4-merge.out)"
  fi

  rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# Case 5: usage / error handling -- unresolvable lane branch is a hard
# error (rc=2), never a silent pass.
# ---------------------------------------------------------------------------
test_unresolvable_branch_is_usage_error() {
  local repo rc
  repo="$(_mk_repo)"
  echo base > "${repo}/shared.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm base
  git -C "$repo" branch -m main >/dev/null 2>&1 || true

  bash "$GATE" "$repo" does-not-exist main >/tmp/mgs-case5.out 2>&1
  rc=$?
  if [[ $rc -eq 2 ]]; then
    _ok "case 5: unresolvable lane branch is rc=2, not a silent pass"
  else
    _fail "case 5: expected rc=2 for unresolvable branch, got rc=$rc: $(cat /tmp/mgs-case5.out)"
  fi

  rm -rf "$repo"
}

test_plain_fork_is_clean_and_merge_keeps_file
test_multi_file_plain_fork_is_clean
test_intentional_own_deletion_always_lands
test_intentional_deletion_lands_even_while_lane_is_behind
test_unresolvable_branch_is_usage_error

rm -f /tmp/mgs-case*.out /tmp/mgs-case*-*.out

printf -- '--- %d passed, %d failed ---\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
# bash-guard: allow
