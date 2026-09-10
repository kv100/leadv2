#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-merge-safety-gate.sh leadv2-deploy-merge.sh leadv2-land.sh leadv2-dispatch-product-close.sh
# test-merge-safety-reverts-main.sh — LANE-MERGE-SILENTLY-REVERTS-MAIN-01
#
# The refusal path of the merged-tree gate. Reproduces the five measured
# 2026-09-03 incidents in a real scratch repo: a lane forks, other lanes
# land files on main, the lane merges main mid-flight with a WHOLESALE
# resolution (`git merge -s ours main`) -- main's ancestry, the lane's
# tree -- and the eventual merge is clean, exits 0, and silently deletes
# those files. The gate must refuse BEFORE the merge, name every path,
# and never assume clean when it cannot verify.
#
# This suite is the negative-control target: mutating the gate body to
# return "clean" unconditionally MUST turn cases 1-2 red here (pasted to
# docs/handoff/<lane>/round1-red.txt). The no-false-positive and
# fail-closed-on-bad-args legs live in test-leadv2-merge-safety-gate.sh;
# the end-to-end wire through leadv2-deploy-merge.sh (real script, real
# merge queue, real blocker flag) lives in test-merge-does-not-regress-main.sh.
#
# Hermetic: every fixture is a from-scratch `git init` in a mktemp -d
# scratch dir (never `git worktree add`). Bash 3.2 compatible.
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
  echo base > "${tmp}/shared.txt"
  git -C "$tmp" add -A && git -C "$tmp" commit -qm base
  git -C "$tmp" branch -m main >/dev/null 2>&1 || true
  printf '%s\n' "$tmp"
}

# The incident shape, verbatim from the 2026-09-03 measurement: the lane
# merges main mid-flight and resolves wholesale to its own side. The merge
# commit carries main's ANCESTRY but the lane's TREE, so the landed file
# is silently gone from the lane -- and no lane commit ever names it
# (merge commits emit no --name-only patch).
_wholesale_merge_main() {
  local repo="$1"
  git -C "$repo" checkout -q laneB
  git -C "$repo" merge -s ours main -m "merge main mid-flight (wholesale resolution)" >/dev/null 2>&1
  git -C "$repo" checkout -q main
}
# bash-guard: allow

# ---------------------------------------------------------------------------
# Case 1 — the brief's fixture: main gains fileX.txt (221 lines: the worst
# measured incident) after the lane forked; the lane's wholesale mid-flight
# merge reverts it. The gate must REFUSE (rc=1) and name fileX.txt; the
# real merge on the same repo must then land exit 0 WITH fileX DELETED --
# proving the danger is real and the gate's verdict matches git's actual
# behaviour, not a heuristic.
# ---------------------------------------------------------------------------
test_accidental_revert_refused_and_real() {
  local repo rc
  repo="$(_mk_repo)"
  git -C "$repo" checkout -qb laneB
  echo "lane work" > "${repo}/lane_file.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane work"

  git -C "$repo" checkout -q main
  seq 1 221 > "${repo}/fileX.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "other lane lands fileX"

  _wholesale_merge_main "$repo"

  bash "$GATE" "$repo" laneB main >/tmp/msr-case1.out 2>&1
  rc=$?
  if [[ $rc -eq 1 ]] && grep -q 'fileX.txt' /tmp/msr-case1.out; then
    _ok "case 1: gate refuses (rc=1) and names fileX.txt"
  else
    _fail "case 1: expected rc=1 naming fileX.txt, got rc=$rc: $(cat /tmp/msr-case1.out)"
  fi

  # Belt-and-suspenders: the merge the gate just refused is clean, exit 0,
  # and REALLY deletes fileX -- the incident, reproduced on the live git.
  git -C "$repo" checkout -q main
  git -C "$repo" merge --no-edit --no-ff laneB >/tmp/msr-case1-merge.out 2>&1
  rc=$?
  if [[ $rc -eq 0 && ! -f "${repo}/fileX.txt" ]]; then
    _ok "case 1: real merge exit 0 and fileX.txt really deleted (gate verdict matched git)"
  else
    _fail "case 1: real merge rc=$rc, fileX present=$([[ -f ${repo}/fileX.txt ]] && echo yes || echo no): $(cat /tmp/msr-case1-merge.out)"
  fi

  rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# Case 2 — the multi-file shape (two concurrent lanes land two files before
# the wholesale merge): the gate names BOTH.
# ---------------------------------------------------------------------------
test_multi_file_revert_names_both() {
  local repo rc
  repo="$(_mk_repo)"
  git -C "$repo" checkout -qb laneB
  echo "lane work" > "${repo}/lane_file.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane work"

  git -C "$repo" checkout -q main
  printf 'a\nb\n' > "${repo}/test-suite-one.sh"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane A lands test-suite-one.sh"
  printf 'c\nd\n' > "${repo}/test-suite-two.sh"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane C lands test-suite-two.sh"

  _wholesale_merge_main "$repo"

  bash "$GATE" "$repo" laneB main >/tmp/msr-case2.out 2>&1
  rc=$?
  if [[ $rc -eq 1 ]] && grep -q 'test-suite-one.sh' /tmp/msr-case2.out && grep -q 'test-suite-two.sh' /tmp/msr-case2.out; then
    _ok "case 2: refuses and names both concurrently-landed files"
  else
    _fail "case 2: expected rc=1 naming both files, got rc=$rc: $(cat /tmp/msr-case2.out)"
  fi
  # The lane's OWN file must never be named: it is the lane's decision.
  if ! grep -q 'lane_file.txt' /tmp/msr-case2.out; then
    _ok "case 2: lane's own named file not flagged"
  else
    _fail "case 2: lane's own file wrongly flagged as a revert"
  fi

  rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# Case 3 — negative control: the SAME fork, but the lane merged main with
# a REAL resolution instead of -s ours. Nothing reverts; the gate must be
# clean. (The discriminator punishes the wholesale resolution, not the
# mere fact of being behind main.)
# ---------------------------------------------------------------------------
test_real_midflight_merge_is_clean() {
  local repo rc
  repo="$(_mk_repo)"
  git -C "$repo" checkout -qb laneB
  echo "lane work" > "${repo}/lane_file.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane work"

  git -C "$repo" checkout -q main
  seq 1 221 > "${repo}/fileX.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "other lane lands fileX"

  git -C "$repo" checkout -q laneB
  git -C "$repo" merge --no-edit main >/tmp/msr-case3-merge.out 2>&1
  if [[ $? -ne 0 ]]; then
    _fail "case 3: fixture merge failed -- $(cat /tmp/msr-case3-merge.out)"
    rm -rf "$repo"
    return
  fi

  bash "$GATE" "$repo" laneB main >/tmp/msr-case3.out 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    _ok "case 3: real mid-flight merge flips the gate green (rc=0)"
  else
    _fail "case 3: wrongly refused after a real resolution (rc=$rc): $(cat /tmp/msr-case3.out)"
  fi

  rm -rf "$repo"
}
# bash-guard: allow

# ---------------------------------------------------------------------------
# Case 4 — fail CLOSED on an unresolvable base: unrelated histories (an
# orphan root) leave `git merge-tree` unable to compute a merge. The gate
# must refuse (rc=2), never assume clean.
# ---------------------------------------------------------------------------
test_unresolvable_base_refuses() {
  local repo rc
  repo="$(_mk_repo)"
  git -C "$repo" checkout -q --orphan stranger
  git -C "$repo" rm -rqf . >/dev/null 2>&1
  echo stranger > "${repo}/stranger.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "independent root"

  bash "$GATE" "$repo" stranger main >/tmp/msr-case4.out 2>&1
  rc=$?
  if [[ $rc -eq 2 ]]; then
    _ok "case 4: no merge base -> rc=2 (fail closed), not a silent pass"
  else
    _fail "case 4: expected rc=2 for unrelated histories, got rc=$rc: $(cat /tmp/msr-case4.out)"
  fi

  rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# Case 5 — fail CLOSED on an unresolvable lane branch (rc=2).
# ---------------------------------------------------------------------------
test_unresolvable_lane_refuses() {
  local repo rc
  repo="$(_mk_repo)"
  bash "$GATE" "$repo" does-not-exist main >/tmp/msr-case5.out 2>&1
  rc=$?
  if [[ $rc -eq 2 ]]; then
    _ok "case 5: unresolvable lane branch -> rc=2 (fail closed)"
  else
    _fail "case 5: expected rc=2, got rc=$rc: $(cat /tmp/msr-case5.out)"
  fi
  rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# Case 6 — wiring: the gate must exist on every landing path, not only in
# the commit message. These pins exist because the 57de5a5b gate was wired
# behind `[[ -x ]]` while being committed 100644 -- it never ran once.
# ---------------------------------------------------------------------------
test_gate_is_wired_into_landing_paths() {
  local scripts="${SCRIPT_DIR}/.."
  if grep -qF 'source "${SCRIPT_DIR}/leadv2-merge-safety-gate.sh"' "${scripts}/leadv2-deploy-merge.sh"; then
    _ok "case 6a: deploy-merge sources the gate (single discriminator)"
  else
    _fail "case 6a: deploy-merge no longer sources the gate -- probe drifted out of sync"
  fi
  if grep -qF 'lv2_merge_tree_regressions "$(pwd)"' "${scripts}/leadv2-deploy-merge.sh"; then
    _ok "case 6b: deploy-merge probe delegates to the gate core"
  else
    _fail "case 6b: deploy-merge probe no longer delegates to the gate core"
  fi
  if grep -qF 'bash "${SCRIPT_DIR}/leadv2-merge-safety-gate.sh"' "${scripts}/leadv2-land.sh"; then
    _ok "case 6c: leadv2-land runs the gate CLI (bash-invoked, no exec-bit dependency)"
  else
    _fail "case 6c: leadv2-land no longer runs the gate"
  fi
  if grep -qF 'bash "${_T11_MERGE_GATE}"' "${scripts}/leadv2-dispatch-product-close.sh" \
     && ! grep -qF 'if [[ -x "${_T11_MERGE_GATE}" ]]' "${scripts}/leadv2-dispatch-product-close.sh" \
     && grep -qF 'if [[ ! -f "${_T11_MERGE_GATE}" ]]' "${scripts}/leadv2-dispatch-product-close.sh"; then
    _ok "case 6d: product-close T11 runs the gate fail-closed (bash + missing-file refusal, no dead -x guard)"
  else
    _fail "case 6d: product-close T11 gate wiring regressed (dead -x guard or fail-open restored)"
  fi
}

test_accidental_revert_refused_and_real
test_multi_file_revert_names_both
test_real_midflight_merge_is_clean
test_unresolvable_base_refuses
test_unresolvable_lane_refuses
test_gate_is_wired_into_landing_paths

rm -f /tmp/msr-case*.out /tmp/msr-case*-*.out

printf -- '--- %d passed, %d failed ---\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
# bash-guard: allow
