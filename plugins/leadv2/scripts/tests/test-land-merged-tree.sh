#!/usr/bin/env bash
# test-land-merged-tree.sh — W-LEAD-LAST-MILE-01 §1
# run-all-triggers: leadv2-land
#
# The merged-tree instrument inside land_safety_gate: `git merge-tree
# --write-tree` is the only honest answer to "would merging this lane
# delete or revert main files outside its write set". Acceptance §1: a
# lane whose merged-tree deletes a main file outside its write set is
# REFUSED with a non-zero code and a line naming the file; the SAME lane
# without the deletion passes — both on ONE fixture (the no-deletion lane
# is the deletion lane's parent: identical work, minus the rm commit).
#
# Declared negative control (acceptance §4): removing the
# `land_merged_tree_check "${LAND_TIP}"` call line inside land_safety_gate
# (marked MERGED-TREE-INSTRUMENT) must redden cases m1 and m5.
#
# Hermetic: from-scratch git init + bare origin + copied real scripts per
# case, under mktemp -d. Bash 3.2 compatible.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0
DIRS=()

_ok()   { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
_fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }
assert() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then _ok "${desc}"; else _fail "${desc}"; fi
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1 (expected [$2], got [$3])"; fi
}
assert_contains() {
  case "$2" in
    *"$3"*) _ok "$1" ;;
    *) _fail "$1 (missing [$3] in [$(printf '%.160s' "$2")])" ;;
  esac
}

_suite_cleanup() {
  local d
  for d in ${DIRS[@]+"${DIRS[@]}"}; do rm -rf "$d" 2>/dev/null || true; done
}
trap _suite_cleanup EXIT

_mk_case() { # <name> — sets CASE, REPO, ORIGIN, STATE, LEDGER, LAND
  local name="$1" base f
  CASE="$name"
  base="$(mktemp -d "${TMPDIR:-/tmp}/land-mt-${name}.XXXXXX")"
  DIRS=(${DIRS[@]+"${DIRS[@]}"} "$base")
  REPO="${base}/repo"
  ORIGIN="${base}/origin.git"
  STATE="${base}/state"
  git init -q "$REPO"
  git -C "$REPO" checkout -q -b main
  mkdir -p "${REPO}/plugins/leadv2/scripts"
  for f in leadv2-land.sh leadv2-branch-merged.sh leadv2-merge-queue.sh \
           leadv2-merge-safety-gate.sh leadv2-state-path.sh \
           leadv2-portable-lock.sh; do
    cp "${SRC_DIR}/${f}" "${REPO}/plugins/leadv2/scripts/${f}"
  done
  LAND="${REPO}/plugins/leadv2/scripts/leadv2-land.sh"
  mkdir -p "${REPO}/src"
  echo "base $CASE" > "${REPO}/README"
  echo "keep me on main" > "${REPO}/src/keep.txt"
  echo "victim on main" > "${REPO}/src/victim.txt"
  echo "other on main" > "${REPO}/src/other.txt"
  git -C "$REPO" add -A
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m base
  git init -q --bare "$ORIGIN"
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q -u origin main
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
  git -C "$REPO" remote set-head origin main
  SLUG="$(basename "$REPO")"
  LEDGER="${STATE}/${SLUG}/land-ledger/${SLUG}.jsonl"
}

# ONE fixture shape for every case: lane-mt does declared work; lane-mt-del
# is that SAME lane plus one commit deleting src/victim.txt (a main file
# outside the declared write set).
_mk_lane_pair() {
  git -C "$REPO" checkout -q -b lane-mt main
  echo "lane work" > "${REPO}/src/lane.txt"
  git -C "$REPO" add src/lane.txt
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m "lane work"
  git -C "$REPO" checkout -q -b lane-mt-del lane-mt
  git -C "$REPO" rm -q src/victim.txt
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m "accidentally deletes a main file"
  git -C "$REPO" checkout -q main
}

_run_land() { # <lane> [VAR=VAL...] -> stderr of land
  local lane="$1"; shift
  ( cd "$REPO" && env "$@" LEADV2_STATE_BASE="$STATE" LEADV2_MERGE_TIMEOUT_SEC=30 \
      bash "$LAND" "$lane" 2>&1 >/dev/null )
}
_rc_land() { # <lane> [VAR=VAL...] -> rc of land
  local lane="$1"; shift
  ( cd "$REPO" && env "$@" LEADV2_STATE_BASE="$STATE" LEADV2_MERGE_TIMEOUT_SEC=30 \
      bash "$LAND" "$lane" >/dev/null 2>&1 )
  return $? # explicit: not inside $( ) — rc must survive (measurement artifact)
}
_field() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())[sys.argv[1]])' "$2" 2>/dev/null; }
_remote_tip() { git -C "$REPO" ls-remote origin refs/heads/main 2>/dev/null | awk '{print $1}'; }

# ── m1: declared write set; merged-tree deletes a main file outside it ──────
case_m1() {
  _mk_case m1
  _mk_lane_pair
  local ws="src/lane.txt"
  assert "m1: setup victim.txt exists on main" test -f "${REPO}/src/victim.txt"
  local err rc
  _rc_land lane-mt-del LEADV2_LAND_WRITE_SET="$ws"
  rc=$?
  err="$(_run_land lane-mt-del LEADV2_LAND_WRITE_SET="$ws")"
  assert_eq "m1: rc=1 on outside-write-set deletion" 1 "$rc"
  assert_contains "m1: refusal names the file" "$err" "merged-tree deletes main file outside the lane write set: src/victim.txt"
  assert_contains "m1: refusal reason" "$err" "reason=merged_tree_outside_write_set"
  assert "m1: main did not move (victim still tracked)" \
    test "$(git -C "$REPO" cat-file -e main:src/victim.txt && echo yes)" = yes
  local row; row="$(tail -n 1 "$LEDGER" 2>/dev/null)"
  assert_contains "m1: ledger row reason" "$(_field "$row" reason)" "merged_tree_outside_write_set"
}

# ── m2: the SAME lane without the deletion, same declared set — lands ───────
case_m2() {
  _mk_case m2
  _mk_lane_pair
  local rc
  _rc_land lane-mt LEADV2_LAND_WRITE_SET="src/lane.txt"
  rc=$?
  assert_eq "m2: rc=0 on the same lane minus the deletion" 0 "$rc"
  assert "m2: victim.txt still on main after land" \
    git -C "$REPO" cat-file -e main:src/victim.txt
  assert_eq "m2: remote tip moved to lane tip" "$(git -C "$REPO" rev-parse lane-mt)" "$(_remote_tip)"
  local row; row="$(tail -n 1 "$LEDGER" 2>/dev/null)"
  assert_contains "m2: ledger row landed" "$(_field "$row" outcome)" "landed"
}

# ── m3: write set declared as a FILE (comments + blank lines ignored) ───────
case_m3() {
  _mk_case m3
  _mk_lane_pair
  printf '# the lane write set\nsrc/lane.txt\n\n' > "${REPO}/ws.txt"
  local err rc
  _rc_land lane-mt-del LEADV2_LAND_WRITE_SET="${REPO}/ws.txt"
  rc=$?
  err="$(_run_land lane-mt-del LEADV2_LAND_WRITE_SET="${REPO}/ws.txt")"
  assert_eq "m3: rc=1 via file-form write set" 1 "$rc"
  assert_contains "m3: refusal names the file" "$err" "src/victim.txt"
}

# ── m4: DERIVED write set (unset) — the lane's own deletion is its decision ─
case_m4() {
  _mk_case m4
  _mk_lane_pair
  local rc
  _rc_land lane-mt-del
  rc=$?
  assert_eq "m4: rc=0 with derived write set (lane's own deletion)" 0 "$rc"
  assert "m4: victim.txt gone from main (the lane's own decision landed)" \
    test "$(git -C "$REPO" cat-file -e main:src/victim.txt 2>/dev/null && echo yes || echo no)" = no
}

# ── m5: content revert (M) outside the declared set is refused too ──────────
case_m5() {
  _mk_case m5
  git -C "$REPO" checkout -q -b lane-m5 main
  echo "lane work" > "${REPO}/src/lane5.txt"
  echo "reverted content" > "${REPO}/src/keep.txt"
  git -C "$REPO" add -A
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m "lane work + silent revert"
  git -C "$REPO" checkout -q main
  local err rc
  _rc_land lane-m5 LEADV2_LAND_WRITE_SET="src/lane5.txt"
  rc=$?
  err="$(_run_land lane-m5 LEADV2_LAND_WRITE_SET="src/lane5.txt")"
  assert_eq "m5: rc=1 on outside-write-set revert" 1 "$rc"
  assert_contains "m5: refusal names the reverted file" "$err" "changes main file outside the lane write set: src/keep.txt"
  assert "m5: keep.txt untouched on main" grep -q "keep me on main" "${REPO}/src/keep.txt"
}

# ── m6: directory-prefix write-set entries cover everything beneath them ────
case_m6() {
  _mk_case m6
  git -C "$REPO" checkout -q -b lane-m6 main
  echo "lane work" > "${REPO}/src/lane6.txt"
  git -C "$REPO" rm -q src/other.txt
  git -C "$REPO" add -A
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m "declared deletion under src/"
  git -C "$REPO" checkout -q main
  local rc
  _rc_land lane-m6 LEADV2_LAND_WRITE_SET="src"
  rc=$?
  assert_eq "m6: rc=0 with prefix entry src" 0 "$rc"
}

case_m1; case_m2; case_m3; case_m4; case_m5; case_m6

printf '# land-merged-tree pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ ${FAIL} -eq 0 ]]
