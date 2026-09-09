#!/usr/bin/env bash
# changed-scope triggers, self-registered (discovered by scan_suite_triggers):
# run-all-triggers: leadv2-lane-salvage.sh
# test-lane-salvage-exit-codes.sh — SALVAGE-EXITS-ZERO-ON-CONFLICT-01
#
# Pins the salvage tool's EXIT-CODE contract (the header's "Exit codes"
# block, which --help prints since this lane):
#   0 = salvaged_green | nothing_to_salvage
#   1 = salvaged_red
#   3 = conflict
#   2 = usage / environment error (no verdict)
# The 2026-09-04 defect this suite exists for: a loop over 17 B1 lanes
# reported 17 OK while every conflict lane had printed verdict=conflict into
# stdout and exited 0. Every case here therefore captures the tool's rc
# UNPIPED (output to a file, never through a pipe — pipes and zsh mask a
# red rc as 0) and asserts BOTH the rc and the verdict= token. E8 re-derives
# the expected rc FROM the printed verdict through a case mirroring the
# contract, so rc and stdout cannot disagree silently.
#
# Mandatory negative control (see the lane report): mutate main()'s
# `conflict) return 3 ;;` arm to `return 0 ;;` — E1, E2 and E8 must go red
# with `rc=0 (want 3)` in the FAIL line.
#
# Hermetic: every case is a from-scratch `git init` scratch repo with a
# committed stub tests/run-all.sh whose exit code the case controls — never
# a worktree of the real repo. Bash 3.2 compatible.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SALVAGE="${SCRIPT_DIR}/../leadv2-lane-salvage.sh"

PASS=0
FAIL=0

_ok()   { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
_fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }

# Fixture: scratch repo whose main carries a stub tests/run-all.sh exiting
# <stub_rc>, plus a src/feat.txt the conflict cases fight over.
_mk_repo() { # <stub_rc> -> stdout: fixture repo path
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/salvage-rc-fixture.XXXXXX")"
  git -C "$tmp" init -q
  git -C "$tmp" config user.email t@t.example
  git -C "$tmp" config user.name t
  mkdir -p "$tmp/src" "$tmp/tests"
  printf 'base\n' > "$tmp/src/feat.txt"
  printf '#!/usr/bin/env bash\necho "STUB-RUN-ALL scope=$*"\nexit %s\n' "$1" > "$tmp/tests/run-all.sh"
  git -C "$tmp" add -A && git -C "$tmp" commit -qm "base"
  git -C "$tmp" branch -m main >/dev/null 2>&1 || true
  printf '%s\n' "$tmp"
}

# Run the tool inside fixture repo $1 for lane $2; output to $3; stdout: rc.
# No pipe anywhere near $? — file capture, not $(... | ...).
_run_salvage() { # <repo> <lane> <outfile>
  local repo="$1" lane="$2" out="$3" rc
  (cd "$repo" && bash "$SALVAGE" "$lane" --suite-timeout 60) > "$out" 2>&1
  rc=$?
  printf '%s' "$rc"
}

_expect_rc() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then _ok "$1: exit $3"
  else _fail "$1: rc=$3 (want $2)"; fi
}

_expect_out() { # <label> <pattern> <outfile>
  if grep -q -- "$2" "$3"; then _ok "$1"
  else _fail "$1: pattern '$2' not in output: $(tail -3 "$3" | tr '\n' ' ')"; fi
}

# The contract, mirrored: printed verdict -> required exit code. One case,
# kept in lockstep with leadv2-lane-salvage.sh's own exit-code case.
_rc_for_verdict() { # <verdict> -> stdout: rc
  case "$1" in
    salvaged_green|nothing_to_salvage) printf '0' ;;
    salvaged_red)                      printf '1' ;;
    conflict)                          printf '3' ;;
    *)                                 printf '?' ;;
  esac
}

# E1-E5 each append "verdict<TAB>rc" here; E8 checks the agreement.
PAIRS="$(mktemp "${TMPDIR:-/tmp}/salvage-rc-pairs.XXXXXX")"
_record() { # <outfile> <rc>
  local v
  v="$(grep -o 'verdict=[a-z_]*' "$1" | head -1 | cut -d= -f2)"
  [[ -n "$v" ]] && printf '%s\t%s\n' "$v" "$2" >> "$PAIRS"
  return 0
}

# ---------------------------------------------------------------------------
# E1: the FIRST pick conflicts on a non-run-all file — the 2026-09-04 shape.
# Nothing carried, the empty-prefix salvage branch is dropped, and a loop
# that only checks $? must NOT see 0.
# ---------------------------------------------------------------------------
e1_conflict_first_pick() {
  local repo out rc
  repo="$(_mk_repo 0)"
  out="$(mktemp)"
  git -C "$repo" checkout -qb worktree-SALVTEST
  printf 'lane-side\n' > "$repo/src/feat.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane: edits feat"
  git -C "$repo" checkout -q main
  printf 'main-side\n' > "$repo/src/feat.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "main: edits feat"
  rc="$(_run_salvage "$repo" SALVTEST "$out")"
  _expect_out "E1 verdict=conflict carried=0/1, branch dropped" \
    'verdict=conflict lane=SALVTEST branch=- carried=0/1' "$out"
  _record "$out" "$rc"
  _expect_rc "E1 conflict at first pick" 3 "$rc"
  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# E2: one clean carry, THEN a conflicting pick. The carried prefix keeps the
# salvage branch alive (branch=salvage/...), and rc is still 3 — the
# branch-drop at carried=0 must not change the exit status.
# ---------------------------------------------------------------------------
e2_conflict_after_carried() {
  local repo out rc
  repo="$(_mk_repo 0)"
  out="$(mktemp)"
  git -C "$repo" checkout -qb worktree-SALVTEST
  printf 'lane only\n' > "$repo/src/only-on-lane.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane: new file"
  printf 'lane-side\n' > "$repo/src/feat.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane: edits feat"
  git -C "$repo" checkout -q main
  printf 'main-side\n' > "$repo/src/feat.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "main: edits feat"
  rc="$(_run_salvage "$repo" SALVTEST "$out")"
  _expect_out "E2 verdict=conflict carried=1/2, prefix branch kept" \
    'verdict=conflict lane=SALVTEST branch=salvage/SALVTEST carried=1/2' "$out"
  _record "$out" "$rc"
  _expect_rc "E2 conflict after one carried pick" 3 "$rc"
  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# E3: clean carry, stub suite green -> salvaged_green, exit 0.
# ---------------------------------------------------------------------------
e3_green() {
  local repo out rc
  repo="$(_mk_repo 0)"
  out="$(mktemp)"
  git -C "$repo" checkout -qb worktree-SALVTEST
  printf 'lane only\n' > "$repo/src/only-on-lane.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane: new work"
  git -C "$repo" checkout -q main
  rc="$(_run_salvage "$repo" SALVTEST "$out")"
  _expect_out "E3 verdict=salvaged_green" \
    'verdict=salvaged_green lane=SALVTEST branch=salvage/SALVTEST carried=1/1 suite_rc=0' "$out"
  _record "$out" "$rc"
  _expect_rc "E3 salvaged_green" 0 "$rc"
  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# E4: clean carry, stub suite exits 7 -> salvaged_red suite_rc=7, exit 1 —
# a red suite is a failure, not a success.
# ---------------------------------------------------------------------------
e4_red_suite() {
  local repo out rc
  repo="$(_mk_repo 7)"
  out="$(mktemp)"
  git -C "$repo" checkout -qb worktree-SALVTEST
  printf 'lane only\n' > "$repo/src/only-on-lane.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm "lane: new work"
  git -C "$repo" checkout -q main
  rc="$(_run_salvage "$repo" SALVTEST "$out")"
  _expect_out "E4 verdict=salvaged_red suite_rc=7" \
    'verdict=salvaged_red lane=SALVTEST branch=salvage/SALVTEST carried=1/1 suite_rc=7' "$out"
  _record "$out" "$rc"
  _expect_rc "E4 salvaged_red" 1 "$rc"
  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# E5: lane branch == main, no work commits -> nothing_to_salvage carried=0/0,
# exit 0 — "nothing to carry" is a correct success.
# ---------------------------------------------------------------------------
e5_nothing_to_salvage() {
  local repo out rc
  repo="$(_mk_repo 0)"
  out="$(mktemp)"
  git -C "$repo" checkout -qb worktree-SALVTEST   # branch at main tip, no commits
  git -C "$repo" checkout -q main
  rc="$(_run_salvage "$repo" SALVTEST "$out")"
  _expect_out "E5 verdict=nothing_to_salvage carried=0/0" \
    'verdict=nothing_to_salvage lane=SALVTEST branch=- carried=0/0' "$out"
  _record "$out" "$rc"
  _expect_rc "E5 nothing_to_salvage" 0 "$rc"
  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# E6: unresolvable lane id -> FATAL on stderr, NO SALVAGE_RESULT line, exit 2
# (operator error must never masquerade as a verdict).
# ---------------------------------------------------------------------------
e6_unknown_lane() {
  local repo out rc
  repo="$(_mk_repo 0)"
  out="$(mktemp)"
  rc="$(_run_salvage "$repo" NOSUCHLANE "$out")"
  _expect_out "E6 unknown lane: FATAL" 'FATAL' "$out"
  if grep -q 'SALVAGE_RESULT' "$out"; then
    _fail "E6 unknown lane printed a SALVAGE_RESULT line: $(tail -1 "$out")"
  else
    _ok "E6 unknown lane: no SALVAGE_RESULT line"
  fi
  _expect_rc "E6 unknown lane" 2 "$rc"
  rm -rf "$repo" "$out"
}

# ---------------------------------------------------------------------------
# E7: --help prints the exit-code table — the contract must be discoverable
# from the tool itself, not only from this suite.
# ---------------------------------------------------------------------------
e7_help_lists_exit_codes() {
  local out rc code
  out="$(bash "$SALVAGE" --help 2>&1)"; rc=$?
  for code in '0 = salvaged_green' '1 = salvaged_red' '3 = conflict' '2 = usage'; do
    if printf '%s\n' "$out" | grep -qF -- "$code"; then
      _ok "E7 --help lists '$code'"
    else
      _fail "E7 --help missing '$code': $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
    fi
  done
  _expect_rc "E7 --help" 0 "$rc"
}

# ---------------------------------------------------------------------------
# E8: rc-vs-stdout agreement over every verdict run above. The expected rc is
# derived FROM the printed verdict (a `return 0`-on-conflict mutation makes
# the two recorded conflict rows disagree here as well as reddening E1/E2).
# ---------------------------------------------------------------------------
e8_rc_agrees_with_verdict() {
  local n=0 v rc want bad=0
  while IFS=$'\t' read -r v rc; do
    n=$((n + 1))
    want="$(_rc_for_verdict "$v")"
    if [[ "$want" != "$rc" ]]; then
      _fail "E8 verdict=$v exited rc=$rc (want $want)"
      bad=1
    fi
  done < "$PAIRS"
  if [[ "$n" -ne 5 ]]; then
    _fail "E8 expected 5 recorded verdict runs, recorded $n"
    return
  fi
  if [[ "$bad" -eq 0 ]]; then
    _ok "E8 exit code agrees with printed verdict (5/5 runs)"
  fi
}

if ! bash -n "$SALVAGE"; then
  _fail "bash -n leadv2-lane-salvage.sh"
else
  _ok "bash -n leadv2-lane-salvage.sh (incl. 3.2)"
fi

e1_conflict_first_pick
e2_conflict_after_carried
e3_green
e4_red_suite
e5_nothing_to_salvage
e6_unknown_lane
e7_help_lists_exit_codes
e8_rc_agrees_with_verdict

rm -f "$PAIRS"
printf 'salvage-exit-codes: pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
