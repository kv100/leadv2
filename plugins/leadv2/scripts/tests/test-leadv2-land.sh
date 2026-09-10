#!/usr/bin/env bash
# test-leadv2-land.sh — LAND-PATH-IS-BROKEN-01
#
# Hermetic fixtures for leadv2-land.sh, brief §7.6 items (a)-(g) plus two
# honesty cases the brief's §5 flow names: queue-acquire rc not swallowed
# (h) and push-failure leaving main moved locally with pushed=false (i).
#
# Every fixture is a from-scratch `git init` + a bare origin + a scratch
# control plane (LEADV2_STATE_BASE), under mktemp -d — never
# `git worktree add` in the shared tree (founder lesson 2026-08-22), never
# the live control plane. The real script set (leadv2-land.sh + its four
# script-dir dependencies) is copied into the scratch repo so land resolves
# ROOT = scratch.
#
# Anti-tautology (brief §7.3): each case asserts its OWN setup state
# (branch counts, dirtiness) before invoking land, and asserts FILESYSTEM /
# refs post-state — a return code alone proves nothing.
#
# Bash 3.2 compatible: no associative arrays, no ${x^^}, no readarray.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0
DIRS=()

_ok()   { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
_fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }
# assert <description> <command...> — passes when the command succeeds
assert() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then _ok "${desc}"; else _fail "${desc}"; fi
}
# assert_eq <description> <expected> <actual>
assert_eq() {
  if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1 (expected [$2], got [$3])"; fi
}
# assert_contains <description> <haystack> <needle>
assert_contains() {
  case "$2" in
    *"$3"*) _ok "$1" ;;
    *) _fail "$1 (missing [$3] in [$(printf '%.120s' "$2")])" ;;
  esac
}

_suite_cleanup() {
  local d
  for d in ${DIRS[@]+"${DIRS[@]}"}; do rm -rf "$d" 2>/dev/null || true; done
}
trap _suite_cleanup EXIT

_mk_case() { # <name> — sets CASE, REPO, ORIGIN, STATE, LEDGER, LAND
  local name="$1"
  CASE="$name"
  local base
  base="$(mktemp -d "${TMPDIR:-/tmp}/land-${name}.XXXXXX")"
  DIRS=(${DIRS[@]+"${DIRS[@]}"} "$base")
  REPO="${base}/repo"
  ORIGIN="${base}/origin.git"
  STATE="${base}/state"
  git init -q "$REPO"
  git -C "$REPO" checkout -q -b main
  mkdir -p "$REPO/plugins/leadv2/scripts"
  local f
  for f in leadv2-land.sh leadv2-branch-merged.sh leadv2-merge-queue.sh \
           leadv2-merge-safety-gate.sh leadv2-state-path.sh \
           leadv2-portable-lock.sh; do
    cp "${SRC_DIR}/${f}" "${REPO}/plugins/leadv2/scripts/${f}"
  done
  LAND="${REPO}/plugins/leadv2/scripts/leadv2-land.sh"
  echo "base $CASE" > "${REPO}/README"
  git -C "$REPO" add README
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m base
  git init -q --bare "$ORIGIN"
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q -u origin main
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
  git -C "$REPO" remote set-head origin main
  SLUG="$(basename "$REPO")"
  LEDGER="${STATE}/${SLUG}/land-ledger/${SLUG}.jsonl"
}

_commit() { # <repo> <file> <content> <message>
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$4"
}

_run_land() { # <lane> [extra env as VAR=VAL ...] -- runs land in REPO, rc to caller
  local lane="$1"; shift
  ( cd "$REPO" && env "$@" LEADV2_STATE_BASE="$STATE" LEADV2_MERGE_TIMEOUT_SEC=30 \
      bash "$LAND" "$lane" >/dev/null 2>&1 )
}

_land_stderr() { # <lane> [VAR=VAL...] -> stderr of land (for refusal-text asserts)
  local lane="$1"; shift
  ( cd "$REPO" && env "$@" LEADV2_STATE_BASE="$STATE" LEADV2_MERGE_TIMEOUT_SEC=30 \
      bash "$LAND" "$lane" 2>&1 >/dev/null )
}

_last_row() { tail -n 1 "$LEDGER" 2>/dev/null || printf '' ; }
_field() { # <json> <field>
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())[sys.argv[1]])' "$2" 2>/dev/null
}
_hygiene_has() { # <json> <path> — hygiene array contains path
  printf '%s' "$1" | python3 -c 'import json,sys; sys.exit(0 if sys.argv[1] in json.loads(sys.stdin.read())["hygiene"] else 1)' "$2" 2>/dev/null
}
_remote_tip() { git -C "$REPO" ls-remote origin refs/heads/main 2>/dev/null | awk '{print $1}'; }

# ── (a) a lane exactly at main's tip lands ff and pushes ─────────────────────
case_a() {
  _mk_case a
  git -C "$REPO" checkout -q -b lane-a
  _commit "$REPO" src/a.txt "a-work" "lane a work"
  local tip; tip="$(git -C "$REPO" rev-parse lane-a)"
  git -C "$REPO" checkout -q main
  # setup self-check
  assert "a: lane-a is 0 behind" test "$(git -C "$REPO" rev-list --count lane-a..main)" = 0
  assert "a: lane-a is 1 ahead" test "$(git -C "$REPO" rev-list --count main..lane-a)" = 1
  assert "a: main checkout clean" test -z "$(git -C "$REPO" status --porcelain | grep -v '^??')"
  _run_land lane-a
  local rc=$?
  assert_eq "a: rc=0" 0 "$rc"
  assert_eq "a: local main == lane tip" "$tip" "$(git -C "$REPO" rev-parse main)"
  assert_eq "a: remote tip == lane tip" "$tip" "$(_remote_tip)"
  local row; row="$(_last_row)"
  assert_contains "a: row landed" "$(_field "$row" outcome)" "landed"
  assert_contains "a: row reason ok" "$(_field "$row" reason)" "ok"
  assert_contains "a: row pushed" "$(_field "$row" pushed)" "True"
  assert_eq "a: row main_after == tip" "$tip" "$(_field "$row" main_after)"
  assert_eq "a: row behind=0" 0 "$(_field "$row" behind)"
  assert_eq "a: row ahead=1" 1 "$(_field "$row" ahead)"
  assert_eq "a: row mode=ff" ff "$(_field "$row" mode)"
  assert_eq "a: row files=1" 1 "$(_field "$row" files)"
  assert_eq "a: no worktree leaked" 1 "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')"
}

# ── (b) a lane 1 behind is refused, salvage named, main unmoved ──────────────
case_b() {
  _mk_case b
  git -C "$REPO" checkout -q -b lane-b
  _commit "$REPO" src/b.txt "b-work" "lane b work"
  git -C "$REPO" checkout -q main
  _commit "$REPO" src/main-after-fork.txt "later" "main advanced past the fork"
  git -C "$REPO" push -q origin main
  local main_before; main_before="$(git -C "$REPO" rev-parse main)"
  # setup self-check
  assert "b: lane-b is 1 behind" test "$(git -C "$REPO" rev-list --count lane-b..main)" = 1
  local err; err="$(_land_stderr lane-b)"
  local rc=$?
  assert_eq "b: rc=1" 1 "$rc"
  assert_contains "b: refusal names lane-salvage" "$err" "leadv2-lane-salvage.sh"
  assert_contains "b: refusal names reason" "$err" "behind_main"
  local row; row="$(_last_row)"
  assert_contains "b: row refused" "$(_field "$row" outcome)" "refused"
  assert_contains "b: row reason behind_main" "$(_field "$row" reason)" "behind_main"
  assert_eq "b: row behind=1" 1 "$(_field "$row" behind)"
  assert_eq "b: main unmoved" "$main_before" "$(git -C "$REPO" rev-parse main)"
  assert_eq "b: remote unmoved" "$main_before" "$(_remote_tip)"
}

# ── (c) unrelated dirty state files are preserved, land proceeds ─────────────
case_c() {
  _mk_case c
  _commit "$REPO" docs/leadv2/live-state.json '{"v":1}' "live state tracked"
  _commit "$REPO" docs/LEAD_V2_STATE.md "state base" "state doc tracked"
  _commit "$REPO" docs/handoff/dispatch-nw0012/x.json '{"x":1}' "nw handoff tracked"
  git -C "$REPO" checkout -q -b lane-c
  _commit "$REPO" src/c.txt "c-work" "lane c work"
  git -C "$REPO" checkout -q main
  # dirty the three state paths in the main checkout
  printf '{"v":99}' > "$REPO/docs/leadv2/live-state.json"
  printf 'dirty state\n' > "$REPO/docs/LEAD_V2_STATE.md"
  printf '{"x":9}' > "$REPO/docs/handoff/dispatch-nw0012/x.json"
  local tip; tip="$(git -C "$REPO" rev-parse lane-c)"
  # setup self-check
  assert "c: three state paths dirty" test "$(git -C "$REPO" status --porcelain | grep -cv '^??')" = 3
  _run_land lane-c
  local rc=$?
  assert_eq "c: rc=0 despite state dirt" 0 "$rc"
  assert "c: live-state.json preserved" grep -qx '{"v":99}' "$REPO/docs/leadv2/live-state.json"
  assert "c: LEAD_V2_STATE.md preserved" grep -qx 'dirty state' "$REPO/docs/LEAD_V2_STATE.md"
  assert "c: dispatch-nw0012 preserved" grep -qx '{"x":9}' "$REPO/docs/handoff/dispatch-nw0012/x.json"
  assert_eq "c: main == lane tip" "$tip" "$(git -C "$REPO" rev-parse main)"
  local row; row="$(_last_row)"
  assert_contains "c: row landed" "$(_field "$row" outcome)" "landed"
  assert_eq "c: row does not rewrite unrelated state" "[]" "$(_field "$row" hygiene)"
}

# ── (d) tracked-in-lane / ignored-on-main file dropped before the ff ─────────
case_d() {
  _mk_case d
  printf 'generated/\n' > "$REPO/.gitignore"
  git -C "$REPO" add .gitignore
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m "ignore generated"
  git -C "$REPO" checkout -q -b lane-d
  # lane workers force-add past the ignore (the measured shape) — plain
  # `git add` would silently refuse the ignored path and the setup assert
  # below would catch a fixture that never tested anything
  mkdir -p "$REPO/generated"
  printf '{"g":1}\n' > "$REPO/generated/out.json"
  git -C "$REPO" add -f generated/out.json
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m "lane adds ignored file"
  _commit "$REPO" docs/LEAD_V2_STATE.md "leaked state" "lane adds state doc (not tracked on main here)"
  _commit "$REPO" src/d.txt "d-work" "lane d real work"
  git -C "$REPO" checkout -q main
  local tip; tip="$(git -C "$REPO" rev-parse lane-d)"
  # setup self-check
  assert "d: generated/out.json tracked in lane" git -C "$REPO" cat-file -e "lane-d:generated/out.json"
  assert "d: state doc tracked in lane" git -C "$REPO" cat-file -e "lane-d:docs/LEAD_V2_STATE.md"
  assert "d: neither tracked on main" test -z "$(git -C "$REPO" ls-tree main --name-only -- generated/out.json docs/LEAD_V2_STATE.md)"
  _run_land lane-d
  local rc=$?
  assert_eq "d: rc=0" 0 "$rc"
  assert "d: main does not track generated/out.json" bash -c "! git -C '$REPO' cat-file -e main:generated/out.json 2>/dev/null"
  assert "d: main does not track LEAD_V2_STATE.md" bash -c "! git -C '$REPO' cat-file -e main:docs/LEAD_V2_STATE.md 2>/dev/null"
  assert "d: src/d.txt did land" git -C "$REPO" cat-file -e main:src/d.txt
  # the ignored proof itself, per brief §7.5: add --dry-run, never check-ignore.
  # The file must exist on disk for the probe to hit the ignore rule.
  mkdir -p "$REPO/generated"
  printf '{"g":1}\n' > "$REPO/generated/out.json"
  local probe; probe="$(cd "$REPO" && git add --dry-run generated/out.json 2>&1)"
  assert_contains "d: add --dry-run proves still-ignored" "$probe" "ignored by one of your .gitignore files"
  assert_eq "d: remote == local main" "$(git -C "$REPO" rev-parse main)" "$(_remote_tip)"
  local row; row="$(_last_row)"
  assert_contains "d: row landed" "$(_field "$row" outcome)" "landed"
}

# ── (e) a non-state dirty file outside the merged tree does not refuse ───────
case_e() {
  _mk_case e
  git -C "$REPO" checkout -q -b lane-e
  _commit "$REPO" src/e.txt "e-work" "lane e work"
  git -C "$REPO" checkout -q main
  printf 'locally modified README\n' > "$REPO/README"
  local main_before; main_before="$(git -C "$REPO" rev-parse main)"
  # setup self-check
  assert "e: README dirty" test -n "$(git -C "$REPO" status --porcelain -- README)"
  local err; err="$(_land_stderr lane-e)"
  local rc=$?
  assert_eq "e: rc=0" 0 "$rc"
  assert "e: README modification preserved" grep -q "locally modified README" "$REPO/README"
  assert "e: main moved to lane tip" git -C "$REPO" merge-base --is-ancestor lane-e main
  local row; row="$(_last_row)"
  assert_contains "e: row landed" "$(_field "$row" outcome)" "landed"
}

# ── (f) safety-gate rc=1 refuses and writes merge-blocker.flag ───────────────
case_f() {
  _mk_case f
  git -C "$REPO" checkout -q -b lane-f
  _commit "$REPO" src/f.txt "f-work" "lane f work"
  git -C "$REPO" checkout -q main
  # main adds a file AFTER the fork that the lane never touches: the exact
  # shape leadv2-merge-safety-gate.sh exists to refuse (rc=1)
  _commit "$REPO" shared/main-file.txt "shared" "main adds file lane-f never saw"
  local main_before; main_before="$(git -C "$REPO" rev-parse main)"
  # setup self-check
  assert "f: shared file on main tip" git -C "$REPO" cat-file -e main:shared/main-file.txt
  assert "f: shared file absent from lane tip" bash -c "! git -C '$REPO' cat-file -e lane-f:shared/main-file.txt 2>/dev/null"
  assert "f: gate alone refuses" bash -c "! bash '$REPO/plugins/leadv2/scripts/leadv2-merge-safety-gate.sh' '$REPO' lane-f main"
  _run_land lane-f LEADV2_LAND_MAX_BEHIND=5
  local rc=$?
  assert_eq "f: rc=1" 1 "$rc"
  assert "f: merge-blocker.flag written" test -f "$REPO/docs/handoff/lane-f/merge-blocker.flag"
  assert_contains "f: flag merge_blocked true" "$(cat "$REPO/docs/handoff/lane-f/merge-blocker.flag" 2>/dev/null)" "merge_blocked: true"
  assert_contains "f: flag reason" "$(cat "$REPO/docs/handoff/lane-f/merge-blocker.flag" 2>/dev/null)" "reason: safety_gate_refused"
  local row; row="$(_last_row)"
  assert_contains "f: row reason safety_gate_refused" "$(_field "$row" reason)" "safety_gate_refused"
  assert_eq "f: main unmoved" "$main_before" "$(git -C "$REPO" rev-parse main)"
}

# ── (g) kill -9 mid-run still leaves outcome=failed reason=trap ──────────────
case_g() {
  _mk_case g
  git -C "$REPO" checkout -q -b lane-g
  _commit "$REPO" src/g.txt "g-work" "lane g work"
  git -C "$REPO" checkout -q main
  local main_before; main_before="$(git -C "$REPO" rev-parse main)"
  local mq="${REPO}/plugins/leadv2/scripts/leadv2-merge-queue.sh"
  # a different task id holds the queue; land blocks in acquire (timeout 60s)
  PROJECT_ROOT="$REPO" LEADV2_STATE_BASE="$STATE" bash "$mq" acquire g-holder >/dev/null 2>&1 &
  local holder=$!
  sleep 1
  assert "g: holder acquired" grep -q g-holder "${STATE}/$(basename "$REPO")/merge-queue.jsonl"
  ( cd "$REPO" && env LEADV2_STATE_BASE="$STATE" LEADV2_MERGE_TIMEOUT_SEC=60 \
      bash "$LAND" lane-g >/dev/null 2>&1 ) &
  local landpid=$!
  sleep 2
  kill -9 "$landpid" 2>/dev/null
  wait "$landpid" 2>/dev/null
  local row; row="$(_last_row)"
  assert_contains "g: row exists after kill -9" "$(_field "$row" outcome)" "failed"
  assert_contains "g: row reason trap" "$(_field "$row" reason)" "trap"
  assert_eq "g: row names lane" lane-g "$(_field "$row" lane)"
  assert_eq "g: main unmoved" "$main_before" "$(git -C "$REPO" rev-parse main)"
  # teardown: free the queue for later cases in THIS scratch state dir
  PROJECT_ROOT="$REPO" LEADV2_STATE_BASE="$STATE" bash "$mq" release g-holder >/dev/null 2>&1 || true
  PROJECT_ROOT="$REPO" LEADV2_STATE_BASE="$STATE" bash "$mq" release land-lane-g >/dev/null 2>&1 || true
}

# ── (h) queue acquire rc is not swallowed ────────────────────────────────────
case_h() {
  _mk_case h
  git -C "$REPO" checkout -q -b lane-h
  _commit "$REPO" src/h.txt "h-work" "lane h work"
  git -C "$REPO" checkout -q main
  local mq="${REPO}/plugins/leadv2/scripts/leadv2-merge-queue.sh"
  PROJECT_ROOT="$REPO" LEADV2_STATE_BASE="$STATE" bash "$mq" acquire h-holder >/dev/null 2>&1 &
  local holder=$!
  sleep 1
  _run_land lane-h LEADV2_MERGE_TIMEOUT_SEC=2
  local rc=$?
  assert_eq "h: rc=1 on queue timeout" 1 "$rc"
  local row; row="$(_last_row)"
  assert_contains "h: row refused" "$(_field "$row" outcome)" "refused"
  assert_contains "h: row reason queue_acquire_failed" "$(_field "$row" reason)" "queue_acquire_failed"
  PROJECT_ROOT="$REPO" LEADV2_STATE_BASE="$STATE" bash "$mq" release h-holder >/dev/null 2>&1 || true
}

# ── (i) push failure: main moved locally, pushed=false, reason recorded ──────
case_i() {
  _mk_case i
  git -C "$REPO" checkout -q -b lane-i
  _commit "$REPO" src/i.txt "i-work" "lane i work"
  local tip; tip="$(git -C "$REPO" rev-parse lane-i)"
  git -C "$REPO" checkout -q main
  # break the origin AFTER setup so the ff succeeds but the push cannot
  git -C "$REPO" remote set-url origin "${REPO}-nope.git"
  _run_land lane-i
  local rc=$?
  assert_eq "i: rc=1 on push failure" 1 "$rc"
  assert_eq "i: local main moved to tip" "$tip" "$(git -C "$REPO" rev-parse main)"
  local row; row="$(_last_row)"
  assert_contains "i: row failed" "$(_field "$row" outcome)" "failed"
  assert_contains "i: row reason push_failed" "$(_field "$row" reason)" "push_failed"
  assert_eq "i: row pushed=false" False "$(_field "$row" pushed)"
  assert_eq "i: row main_after == tip (honest)" "$tip" "$(_field "$row" main_after)"
  assert_eq "i: row mode=ff" ff "$(_field "$row" mode)"
}

# ── (j) an already-landed lane is NOT a land: main_after == main_before ─────
case_j() {
  _mk_case j
  git -C "$REPO" checkout -q -b lane-j main
  local tip; tip="$(git -C "$REPO" rev-parse lane-j)"
  git -C "$REPO" checkout -q main
  # setup self-check: 0 behind, 0 ahead — the ff/push are no-ops, so §4's
  # condition 2 (main_after != main_before) is the only thing distinguishing
  # a real land from a no-op
  assert "j: lane-j is 0 behind" test "$(git -C "$REPO" rev-list --count lane-j..main)" = 0
  assert "j: lane-j is 0 ahead" test "$(git -C "$REPO" rev-list --count main..lane-j)" = 0
  _run_land lane-j
  local rc=$?
  assert_eq "j: rc=1 on no-op land" 1 "$rc"
  local row; row="$(_last_row)"
  assert_contains "j: row failed" "$(_field "$row" outcome)" "failed"
  assert_contains "j: row reason verify_failed" "$(_field "$row" reason)" "verify_failed"
}

case_a; case_b; case_c; case_d; case_e; case_f; case_g; case_h; case_i; case_j

printf '# land-suite pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ ${FAIL} -eq 0 ]]
