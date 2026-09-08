#!/usr/bin/env bash
# CLOSE-GATE-CALLS-A-COMMITTED-LANE-no_work-01: the phase-8 close gate
# refused a lane whose work was fully COMMITTED ("no_work") because
# lv2_lane_diff_is_empty measured only working-tree-vs-HEAD. The predicate
# now counts committed lane work (diff merge-base main..HEAD) alongside
# uncommitted and untracked; empty = all three empty. An unresolvable base
# (no `main` / failed merge-base) falls back to the HEAD-only comparison --
# never to 'empty'. rc contract unchanged: 0=empty, 1=non-empty,
# 2=undeterminable (caller treats as non-empty).
# run-all-triggers: leadv2-helpers
#
# No existing suite sources leadv2-helpers.sh directly (it sets errexit at
# line 8, which would eat every rc1 assertion below), so this suite defines
# its own convention: source once, immediately `set +e`, and read every
# predicate rc from probe's stdout.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=leadv2-helpers.sh
source "${SCRIPT_DIR}/leadv2-helpers.sh"
set +e

PASS=0; FAIL=0; SKIP=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
expect_rc() { # <want> <got> <label>
  if [[ "$2" == "$1" ]]; then ok "$3"; else bad "$3 (got=$2 want=$1)"; fi
}
TMP="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-lane-diff.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT INT TERM

# probe: run the predicate, echo its rc on stdout (rc-capture that survives
# even if a future editor re-enables errexit above).
probe() { # <repo> [writes_csv] -> stdout rc
  local _rc=0
  lv2_lane_diff_is_empty "$1" "${2:-}" || _rc=$?
  printf '%s' "${_rc}"
}

GITC() { git -C "$1" -c user.email=lane@local -c user.name=lane-test "${@:2}"; }

# mkrepo <dir> <base_branch>: repo whose base branch carries file_a/file_b
# (plus committed docs noise, to exercise the excludes), and a `lane` branch
# off it standing in for the lane worktree's checkout.
mkrepo() { # <dir> <base_branch>
  git init -q "$1"
  git -C "$1" symbolic-ref HEAD "refs/heads/$2"
  echo base > "$1/file_a"; echo base > "$1/file_b"
  mkdir -p "$1/docs/leadv2" "$1/docs/handoff"
  echo base > "$1/docs/leadv2/state.md"; echo base > "$1/docs/handoff/note.md"
  GITC "$1" add -A
  GITC "$1" commit -qm base
  git -C "$1" checkout -q -b lane
}

# ── 1. THE bug: committed work counts (clean tree, everything committed) ───
mkrepo "$TMP/committed" main; r="$TMP/committed"
echo work > "$r/file_a"; GITC "$r" add file_a; GITC "$r" commit -qm "lane work"
expect_rc 1 "$(probe "$r" file_a)"          "committed declared write -> non-empty"
expect_rc 1 "$(probe "$r" "")"              "committed work, whole-tree fallback -> non-empty"
expect_rc 0 "$(probe "$r" file_b)"          "untouched declared write stays empty (per-path precision)"
expect_rc 1 "$(probe "$r" file_a,file_b)"   "committed write inside a csv -> non-empty"

# committed DELETION of a declared write is work too
rm "$r/file_b"; GITC "$r" add -A; GITC "$r" commit -qm "remove file_b"
expect_rc 1 "$(probe "$r" file_b)"          "committed deletion of declared write -> non-empty"

# ── 2. Existing behaviour kept: uncommitted / untracked still count ────────
mkrepo "$TMP/dirty" main; r="$TMP/dirty"
echo wip > "$r/file_a"
expect_rc 1 "$(probe "$r" file_a)"          "uncommitted declared write -> non-empty"
echo wip > "$r/new_file"
expect_rc 1 "$(probe "$r" new_file)"        "untracked declared write -> non-empty"
expect_rc 1 "$(probe "$r" "")"              "untracked file, whole-tree -> non-empty"

# ── 3. Genuinely empty lane is still refused (no commits ahead of base) ────
mkrepo "$TMP/empty" main; r="$TMP/empty"
expect_rc 0 "$(probe "$r" file_a)"          "no commits ahead + clean tree + declared write -> empty"
expect_rc 0 "$(probe "$r" "")"              "no commits ahead + clean tree, whole-tree -> empty"
# ...even when the working-tree dirt is only docs noise the lane never owns
echo noise > "$r/docs/leadv2/report.md"; echo noise > "$r/docs/handoff/n.md"
expect_rc 0 "$(probe "$r" "")"              "docs-only untracked noise, whole-tree -> empty"
rm "$r/docs/leadv2/report.md" "$r/docs/handoff/n.md"
# ...and committed docs-only noise is excluded from the committed range too
mkrepo "$TMP/docsnoise" main; r="$TMP/docsnoise"
echo noise > "$r/docs/leadv2/report.md"; echo noise > "$r/docs/handoff/n.md"
GITC "$r" add -A; GITC "$r" commit -qm "docs only"
expect_rc 0 "$(probe "$r" "")"              "committed docs-only noise, whole-tree -> empty"

# ── 4. Unresolvable base falls back to HEAD-only (never to 'empty') ────────
# Repo with an unusual default branch (`trunk`): `main` does not exist, so the
# merge-base cannot resolve. Work in the tree must still count -- a `return 0`
# here would silently no_work every lane in such a repo.
mkrepo "$TMP/nomain" trunk; r="$TMP/nomain"
echo wip > "$r/file_a"
expect_rc 1 "$(probe "$r" file_a)"          "no main + uncommitted write (fallback) -> non-empty"
echo wip > "$r/new_file"
expect_rc 1 "$(probe "$r" new_file)"        "no main + untracked write (fallback) -> non-empty"
expect_rc 1 "$(probe "$r" "")"              "no main + dirty tree, whole-tree -> non-empty"
# Deliberately NOT asserted: no-main + clean tree + nothing anywhere. The
# mission pins the fallback to the HEAD-only comparison, whose empty verdict
# then stands; over-pinning that here would freeze an interpretation the
# mission did not settle.

# ── 5. rc2 contract preserved ───────────────────────────────────────────────
mkdir -p "$TMP/notgit"
expect_rc 2 "$(probe "$TMP/notgit" "")"     "non-git dir -> undeterminable (rc2)"
expect_rc 2 "$(probe "$TMP/notgit" file_a)" "non-git dir + declared write -> rc2"
expect_rc 2 "$(probe "$TMP/no_such_dir" "")" "nonexistent repo path -> rc2"

printf '[TEST] RESULT: pass=%s fail=%s skip=%s\n' "${PASS}" "${FAIL}" "${SKIP}"
[[ ${FAIL} -eq 0 ]]
