#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-deploy-merge.sh leadv2-dispatch-product-close.sh
# test-leadv2-merge-safety-gate.sh — LANE-MERGE-SILENTLY-REVERTS-MAIN-01
#
# Hermetic git-sandbox fixtures for leadv2-merge-safety-gate.sh. Reproduces
# the measured shape (a lane branched before another lane landed a file on
# main; the lane's own commits never touch that file; a plain merge would
# make it vanish with no conflict and exit 0) and both required negative
# controls: the accidental case flips red -> green once main is merged into
# the lane, and a lane that deliberately deletes its OWN file always lands
# clean, in both directions.
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

# ---------------------------------------------------------------------------
# Case 1: accidental revert. laneB forks from base. main (another lane, A)
# then adds fileX. laneB's own commits never mention fileX. The gate must
# refuse and name fileX. Merging main into laneB must flip it green.
# ---------------------------------------------------------------------------
test_accidental_revert_refused_then_fixed() {
  local repo
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
  local rc=$?
  if [[ $rc -eq 1 ]] && grep -q 'fileX.txt' /tmp/mgs-case1.out; then
    _ok "case 1: refuses and names fileX.txt (rc=$rc)"
  else
    _fail "case 1: expected rc=1 naming fileX.txt, got rc=$rc: $(cat /tmp/mgs-case1.out)"
  fi

  # Real merge would in fact still preserve fileX (a plain 3-way merge keeps
  # a path added only on the "ours" side) -- confirm the gate's refusal
  # tracks the diff-stat shape a human would see, not a false claim about
  # git's merge algorithm.
  git -C "$repo" checkout -q main
  if git -C "$repo" merge --no-edit --no-ff laneB >/tmp/mgs-case1-merge.out 2>&1; then
    if [[ -f "${repo}/fileX.txt" ]]; then
      _ok "case 1: real merge exit 0 and fileX.txt would in fact survive (belt-and-suspenders confirmed)"
    else
      _fail "case 1: real merge deleted fileX.txt -- $(cat /tmp/mgs-case1-merge.out)"
    fi
  else
    _fail "case 1: real merge unexpectedly failed -- $(cat /tmp/mgs-case1-merge.out)"
  fi

  # Fix path: merge main into laneB, then retry -- must go green.
  git -C "$repo" checkout -q laneB
  git -C "$repo" merge --no-edit main >/tmp/mgs-case1-fix.out 2>&1 || {
    _fail "case 1 fix: merge main into laneB failed -- $(cat /tmp/mgs-case1-fix.out)"
    rm -rf "$repo"
    return
  }
  bash "$GATE" "$repo" laneB main >/tmp/mgs-case1-fixed.out 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    _ok "case 1 fix: merge main into laneB flips the gate green"
  else
    _fail "case 1 fix: still refused after merging main in: $(cat /tmp/mgs-case1-fixed.out)"
  fi

  rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# Case 2: two files land after fork (WORKER-OUTLIVES round-3 shape) -- the
# gate names BOTH.
# ---------------------------------------------------------------------------
test_multi_file_accidental_revert_names_both() {
  local repo
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
  local rc=$?
  if [[ $rc -eq 1 ]] && grep -q 'test-suite-one.sh' /tmp/mgs-case2.out && grep -q 'test-suite-two.sh' /tmp/mgs-case2.out; then
    _ok "case 2: refuses and names both concurrently-landed files"
  else
    _fail "case 2: expected rc=1 naming both files, got rc=$rc: $(cat /tmp/mgs-case2.out)"
  fi

  rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# Case 3: negative control -- a lane that deliberately deletes its OWN file
# (existed at the merge-base, untouched by main) must always land. Direction
# A: main never touches the file at all.
# ---------------------------------------------------------------------------
test_intentional_own_deletion_always_lands() {
  local repo
  repo="$(_mk_repo)"

  echo base > "${repo}/shared.txt"
  echo "to be removed by the lane" > "${repo}/obsolete.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm base
  git -C "$repo" branch -m main >/dev/null 2>&1 || true
  git -C "$repo" checkout -qb laneD

  git -C "$repo" rm -q obsolete.txt
  git -C "$repo" commit -qm "laneD removes obsolete.txt as part of its own work"

  bash "$GATE" "$repo" laneD main >/tmp/mgs-case3.out 2>&1
  local rc=$?
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
# Case 4: negative control, reverse direction -- a lane deliberately deletes
# a file that main ALSO advanced on unrelated paths in the meantime (so the
# lane is genuinely behind main on other files, but its own deletion of ITS
# file must still be trusted and land).
# ---------------------------------------------------------------------------
test_intentional_deletion_lands_even_while_lane_is_behind() {
  local repo
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
  local rc=$?
  # Must refuse (unrelated-new-file.sh is genuinely missing from laneE, and
  # laneE never touched it) but must name ONLY the accidental file, never
  # the lane's own intentional deletion.
  if [[ $rc -eq 1 ]] && grep -q 'unrelated-new-file.sh' /tmp/mgs-case4.out && ! grep -q 'obsolete.txt' /tmp/mgs-case4.out; then
    _ok "case 4: refuses on the accidental file only, never on the lane's own deletion"
  else
    _fail "case 4: expected rc=1 naming only unrelated-new-file.sh, got rc=$rc: $(cat /tmp/mgs-case4.out)"
  fi

  # Fix path, then confirm the lane's own deletion still lands (the whole
  # point of item 3: an intended deletion must survive the fix too).
  git -C "$repo" merge --no-edit main >/tmp/mgs-case4-fix.out 2>&1 || {
    _fail "case 4 fix: merge main into laneE failed -- $(cat /tmp/mgs-case4-fix.out)"
    rm -rf "$repo"
    return
  }
  bash "$GATE" "$repo" laneE main >/tmp/mgs-case4-fixed.out 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    _ok "case 4 fix: green after merging main in, obsolete.txt still absent (lane's intent preserved)"
  else
    _fail "case 4 fix: still refused after merging main in: $(cat /tmp/mgs-case4-fixed.out)"
  fi
  if [[ ! -f "${repo}/obsolete.txt" ]]; then
    _ok "case 4 fix: laneE's own deletion of obsolete.txt survived the main-merge"
  else
    _fail "case 4 fix: obsolete.txt reappeared after merging main in"
  fi

  rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# Case 5: usage / error handling -- unresolvable lane branch is a hard
# error (rc=2), never a silent pass.
# ---------------------------------------------------------------------------
test_unresolvable_branch_is_usage_error() {
  local repo
  repo="$(_mk_repo)"
  echo base > "${repo}/shared.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm base
  git -C "$repo" branch -m main >/dev/null 2>&1 || true

  bash "$GATE" "$repo" does-not-exist main >/tmp/mgs-case5.out 2>&1
  local rc=$?
  if [[ $rc -eq 2 ]]; then
    _ok "case 5: unresolvable lane branch is rc=2, not a silent pass"
  else
    _fail "case 5: expected rc=2 for unresolvable branch, got rc=$rc: $(cat /tmp/mgs-case5.out)"
  fi

  rm -rf "$repo"
}

test_accidental_revert_refused_then_fixed
test_multi_file_accidental_revert_names_both
test_intentional_own_deletion_always_lands
test_intentional_deletion_lands_even_while_lane_is_behind
test_unresolvable_branch_is_usage_error

rm -f /tmp/mgs-case*.out /tmp/mgs-case*-*.out

printf -- '--- %d passed, %d failed ---\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
