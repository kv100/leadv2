#!/usr/bin/env bash
# test-lane-finish.sh — W-LEAD-LAST-MILE-01 §3
# run-all-triggers: leadv2-lane-finish leadv2-land leadv2-mutation-control
#
# The ONE finish command: suite -> lead mutation on the REAL file ->
# restore + cleanliness -> land (hygiene, merged-tree, merge, push).
# Acceptance §3: when the mutation does NOT redden (negative control not
# proven) the command REFUSES to merge — non-zero rc, line naming the step.
# Also: a red lane suite refuses at step=suite; a green chain dry-runs; a
# green chain really lands with --no-ff and the Landed-lane:/Landed-branch:
# trailers.
#
# Fixture shape: a scratch repo (repo-main, on main, bare origin) plus a
# `git worktree add` lane checkout — the production shape (finish runs from
# the LANE checkout; leadv2-land.sh resolves the PRIMARY checkout from its
# own script dir's git common dir). All under mktemp -d.
#
# Bash 3.2 compatible.
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

_mk_case() { # <name> — sets CASE, REPO, LANE_WT, ORIGIN, STATE, LEDGER, FINISH
  local name="$1" base f
  CASE="$name"
  base="$(mktemp -d "${TMPDIR:-/tmp}/lane-fin-${name}.XXXXXX")"
  DIRS=(${DIRS[@]+"${DIRS[@]}"} "$base")
  REPO="${base}/repo-main"
  ORIGIN="${base}/origin.git"
  STATE="${base}/state"
  git init -q "$REPO"
  git -C "$REPO" checkout -q -b main
  mkdir -p "${REPO}/plugins/leadv2/scripts"
  for f in leadv2-land.sh leadv2-lane-finish.sh leadv2-mutation-control.sh \
           leadv2-branch-merged.sh leadv2-merge-queue.sh \
           leadv2-merge-safety-gate.sh leadv2-state-path.sh \
           leadv2-portable-lock.sh; do
    cp "${SRC_DIR}/${f}" "${REPO}/plugins/leadv2/scripts/${f}"
  done
  echo "base $CASE" > "${REPO}/README"
  echo "keep on main" > "${REPO}/src-keep.txt"
  git -C "$REPO" add -A
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m base
  git init -q --bare "$ORIGIN"
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q -u origin main
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
  git -C "$REPO" remote set-head origin main
  LANE="lane-fin-${name}"
  git -C "$REPO" checkout -q -b "${LANE}" main
  mkdir -p "${REPO}/suites" "${REPO}/src"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'grep -q "^MC-LIVE-ANCHOR 1" "$(dirname "$0")/../src/thing.sh" || { echo "anchor check FAILED"; exit 1; }\n'
    printf 'echo ok\n'
  } > "${REPO}/suites/mc-fast.sh"
  {
    printf 'MC-LIVE-ANCHOR 1\n'
    printf '# inert comment the suite never reads\n'
  } > "${REPO}/src/thing.sh"
  echo "lane work" > "${REPO}/src/lane-work.txt"
  git -C "$REPO" add -A
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m "lane work"
  git -C "$REPO" checkout -q main
  LANE_WT="${base}/repo-lane"
  git -C "$REPO" worktree add -q "${LANE_WT}" "${LANE}" >/dev/null 2>&1
  FINISH="${LANE_WT}/plugins/leadv2/scripts/leadv2-lane-finish.sh"
  SLUG="$(basename "$REPO")"
  LEDGER="${STATE}/${SLUG}/land-ledger/${SLUG}.jsonl"
  assert "${CASE}: setup — lane worktree clean" test -z "$(git -C "${LANE_WT}" status --porcelain)"
}

_run_finish() { # <args...> — combined output; rc in RC (run from LANE worktree)
  ( cd "${LANE_WT}" && LEADV2_STATE_BASE="${STATE}" LEADV2_MERGE_TIMEOUT_SEC=30 \
      bash "${FINISH}" "$@" 2>&1 )
}

_remote_tip() { git -C "$REPO" ls-remote origin refs/heads/main 2>/dev/null | awk '{print $1}'; }
_field() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())[sys.argv[1]])' "$2" 2>/dev/null; }

WS="src/thing.sh,src/lane-work.txt,suites/mc-fast.sh"
REDDEN='s/^MC-LIVE-ANCHOR 1$/MC-LIVE-ANCHOR 0/'
INERT='s/^# inert comment the suite never reads$/# inert comment CHANGED/'

# ── f1 (acceptance §3): mutation did NOT redden -> refuse to merge ──────────
case_f1() {
  _mk_case f1
  local main_before; main_before="$(git -C "$REPO" rev-parse main)"
  local out; out="$(_run_finish "${LANE}" suites/mc-fast.sh src/thing.sh "${INERT}" \
    --task-dir docs/handoff/fin-f1 --write-set "${WS}")"
  RC=$?
  assert_eq "f1: rc=1 when the negative control was not proven" 1 "$RC"
  assert_contains "f1: refusal names the step" "$out" "REFUSED step=mutation"
  assert_eq "f1: main did not move" "$main_before" "$(git -C "$REPO" rev-parse main)"
  assert_eq "f1: remote did not move" "$main_before" "$(_remote_tip)"
  assert "f1: no land-ledger row (land never ran)" test ! -f "$LEDGER"
}

# ── f2: green chain, dry-run — every step ok, nothing lands ─────────────────
case_f2() {
  _mk_case f2
  local main_before; main_before="$(git -C "$REPO" rev-parse main)"
  local out; out="$(_run_finish "${LANE}" suites/mc-fast.sh src/thing.sh "${REDDEN}" \
    --task-dir docs/handoff/fin-f2 --write-set "${WS}" --dry-run)"
  RC=$?
  assert_eq "f2: rc=0 on the green chain (dry-run)" 0 "$RC"
  assert_contains "f2: STEP suite ok" "$out" "STEP suite ok"
  assert_contains "f2: STEP mutation ok" "$out" "STEP mutation ok"
  assert_contains "f2: STEP cleanliness ok" "$out" "STEP cleanliness ok"
  assert_contains "f2: STEP land ok" "$out" "STEP land ok"
  assert_contains "f2: CHAIN GREEN" "$out" "CHAIN GREEN"
  assert_eq "f2: main did not move (dry-run)" "$main_before" "$(git -C "$REPO" rev-parse main)"
  assert "f2: lane worktree porcelain clean after the chain" \
    test -z "$(git -C "${LANE_WT}" status --porcelain -uall | grep -vE '^\?\? docs(/handoff/fin-f2.*)?$')"
}

# ── f3: green chain, real land with --no-ff + Landed-* trailers ─────────────
case_f3() {
  _mk_case f3
  local main_before; main_before="$(git -C "$REPO" rev-parse main)"
  local out; out="$(_run_finish "${LANE}" suites/mc-fast.sh src/thing.sh "${REDDEN}" \
    --task-dir docs/handoff/fin-f3 --write-set "${WS}" --no-ff)"
  RC=$?
  assert_eq "f3: rc=0 on the green chain (real land)" 0 "$RC"
  assert "f3: main moved" test "$(git -C "$REPO" rev-parse main)" != "$main_before"
  assert "f3: landed as a MERGE commit (two parents)" \
    test "$(git -C "$REPO" rev-list --parents -n 1 main | wc -w | tr -d ' ')" = 3
  assert_eq "f3: trailer Landed-lane" "${LANE}" \
    "$(git -C "$REPO" log -1 --format='%(trailers:key=Landed-lane,valueonly)')"
  assert_eq "f3: trailer Landed-branch" "${LANE}" \
    "$(git -C "$REPO" log -1 --format='%(trailers:key=Landed-branch,valueonly)')"
  assert_eq "f3: remote tip == local main" "$(git -C "$REPO" rev-parse main)" "$(_remote_tip)"
  assert "f3: lane tip is an ancestor of main" \
    git -C "$REPO" merge-base --is-ancestor "${LANE}" main
  local row; row="$(tail -n 1 "$LEDGER" 2>/dev/null)"
  assert_contains "f3: ledger row landed" "$(_field "$row" outcome)" "landed"
  assert_contains "f3: ledger row mode no_ff" "$(_field "$row" mode)" "no_ff"
}

# ── f4: red lane suite refuses at step=suite, before any mutation ───────────
case_f4() {
  _mk_case f4
  git -C "${LANE_WT}" checkout -q -b "${LANE}-red"
  printf '#!/usr/bin/env bash\necho deliberately red\nexit 1\n' > "${LANE_WT}/suites/mc-fast.sh"
  git -C "${LANE_WT}" add suites/mc-fast.sh
  git -C "${LANE_WT}" -c user.name=t -c user.email=t@t commit -q -m "suite goes red"
  local main_before; main_before="$(git -C "$REPO" rev-parse main)"
  local out; out="$(_run_finish "${LANE}-red" suites/mc-fast.sh src/thing.sh "${REDDEN}" \
    --task-dir docs/handoff/fin-f4 --write-set "${WS}")"
  RC=$?
  assert_eq "f4: rc=1 on a red lane suite" 1 "$RC"
  assert_contains "f4: refusal names the step" "$out" "REFUSED step=suite"
  assert_eq "f4: main did not move" "$main_before" "$(git -C "$REPO" rev-parse main)"
  assert "f4: no land-ledger row" test ! -f "$LEDGER"
}

case_f1; case_f2; case_f3; case_f4

printf '# lane-finish pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ ${FAIL} -eq 0 ]]
