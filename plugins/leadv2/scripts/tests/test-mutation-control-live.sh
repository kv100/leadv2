#!/usr/bin/env bash
# test-mutation-control-live.sh — W-LEAD-LAST-MILE-01 §2
# run-all-triggers: leadv2-mutation-control
#
# The LEAD mode of leadv2-mutation-control.sh (--live): the SAME mutation
# applied to the REAL file in the lane checkout, suite proven red there,
# file restored, `git status --porcelain` identical to the pre-run state
# (empty when the checkout was clean) — and all of that still true when the
# run is KILLED mid-suite (TERM): the restore must not depend on the happy
# path. A mutation of a scratch copy proves nothing for the lead; that is
# the defect this mode closes.
#
# Hermetic: one from-scratch git repo per case, under mktemp -d, with the
# real leadv2-mutation-control.sh copied in. Bash 3.2 compatible.
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

MC="${SRC_DIR}/leadv2-mutation-control.sh"

_mk_case() { # <name> — sets CASE, REPO, THING, ORIG; a clean lane checkout
  local name="$1" base
  CASE="$name"
  base="$(mktemp -d "${TMPDIR:-/tmp}/mutctl-live-${name}.XXXXXX")"
  DIRS=(${DIRS[@]+"${DIRS[@]}"} "$base")
  REPO="${base}/repo"
  git init -q "$REPO"
  git -C "$REPO" checkout -q -b main
  echo "main base" > "${REPO}/README"
  git -C "$REPO" add README
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m base
  git -C "$REPO" checkout -q -b lane
  mkdir -p "${REPO}/suites" "${REPO}/src"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'grep -q "^MC-LIVE-ANCHOR 1" "$(dirname "$0")/../src/thing.sh" || { echo "anchor check FAILED"; exit 1; }\n'
    printf 'echo ok\n'
  } > "${REPO}/suites/mc-fast.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'grep -q "^MC-LIVE-ANCHOR 1" "$(dirname "$0")/../src/thing.sh" || { echo "anchor check FAILED after slow probe"; sleep 30; exit 1; }\n'
    printf 'echo ok\n'
  } > "${REPO}/suites/mc-slow.sh"
  {
    printf 'MC-LIVE-ANCHOR 1\n'
    printf '# inert comment the suite never reads\n'
    printf 'echo body\n'
  } > "${REPO}/src/thing.sh"
  echo "lane work" > "${REPO}/src/lane-work.txt"
  git -C "$REPO" add -A
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m "lane work + thing + suites"
  THING="${REPO}/src/thing.sh"
  ORIG="$(cat "${THING}")"
  assert "${CASE}: setup — checkout clean" test -z "$(git -C "$REPO" status --porcelain)"
}

_run_mc() { # <extra-args...> — combined output; rc in RC
  ( cd "$REPO" && bash "$MC" "$@" 2>&1 )
}

# ── l1: happy path — real-file mutation, red proof, byte restore ────────────
# The artifact goes OUTSIDE the repo here on purpose: MC writes it AFTER its
# porcelain proof (a deliberate write, not residue), and this case asserts
# the acceptance wording verbatim — `git status --porcelain` = 0 after.
case_l1() {
  _mk_case l1
  local out; out="$(_run_mc --live suites/mc-fast.sh src/thing.sh 's/^MC-LIVE-ANCHOR 1$/MC-LIVE-ANCHOR 0/' "${REPO}/../l1-tasks")"
  RC=$?
  assert_eq "l1: rc=0" 0 "$RC"
  assert_contains "l1: ok line says mode=live" "$out" "MUTATION-CONTROL ok mode=live"
  assert_contains "l1: ok line proves porcelain_clean" "$out" "porcelain_clean=yes"
  assert_eq "l1: file restored byte-identical" "$ORIG" "$(cat "$THING")"
  assert "l1: git status --porcelain is empty (was clean before)" test -z "$(git -C "$REPO" status --porcelain)"
  local art; art="$(ls "${REPO}/../l1-tasks/mutation-control/"*.txt 2>/dev/null | head -1)"
  assert "l1: artifact written" test -n "$art"
  assert "l1: artifact carries mode=live" grep -q '^mode=live$' "$art"
  assert "l1: artifact carries porcelain_clean=yes" grep -q '^porcelain_clean=yes$' "$art"
  assert "l1: artifact carries restored=yes" grep -q '^restored=yes$' "$art"
}

# ── l2: kill mid-run (TERM during the mutated suite) — restore still holds ──
case_l2() {
  _mk_case l2
  ( cd "$REPO" && exec bash "$MC" --live suites/mc-slow.sh src/thing.sh 's/^MC-LIVE-ANCHOR 1$/MC-LIVE-ANCHOR 0/' docs/handoff/l2 ) \
    > "${REPO}/../l2-out.txt" 2>&1 &
  local pid=$!
  # deterministic kill point: poll until the real file IS mutated (the worst
  # window), then TERM immediately
  local i=0 saw_mutated=0
  while [[ $i -lt 200 ]]; do
    if ! cmp -s "${THING}" <<<"$ORIG" 2>/dev/null; then
      if [[ "$(cat "${THING}")" != "$ORIG" ]]; then saw_mutated=1; break; fi
    fi
    i=$((i + 1))
    sleep 0.1
  done
  assert_eq "l2: kill landed while the real file was mutated" 1 "$saw_mutated"
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  local krc=$?
  assert_eq "l2: killed run exits 143" 143 "$krc"
  assert_eq "l2: file restored byte-identical after kill" "$ORIG" "$(cat "$THING")"
  assert "l2: git status --porcelain empty after kill" test -z "$(git -C "$REPO" status --porcelain)"
}

# ── l3: mutant_survived (inert mutation) — non-zero rc AND restored file ────
case_l3() {
  _mk_case l3
  local out; out="$(_run_mc --live suites/mc-fast.sh src/thing.sh 's/^# inert comment the suite never reads$/# inert comment CHANGED/' docs/handoff/l3)"
  RC=$?
  assert_eq "l3: rc=1 on mutant_survived" 1 "$RC"
  assert_contains "l3: verdict line" "$out" "mutant_survived mode=live"
  assert_eq "l3: file restored byte-identical" "$ORIG" "$(cat "$THING")"
  assert "l3: git status --porcelain empty" test -z "$(git -C "$REPO" status --porcelain)"
}

# ── l4: noop mutation never touches the real file (control_not_applied) ─────
case_l4() {
  _mk_case l4
  local out; out="$(_run_mc --live suites/mc-fast.sh src/thing.sh 's/^NO-SUCH-ANCHOR$/x/' docs/handoff/l4)"
  RC=$?
  assert_eq "l4: rc=2 on control_not_applied" 2 "$RC"
  assert_contains "l4: reason=noop_edit (sed matched nothing)" "$out" "reason=noop_edit"
  assert_eq "l4: file untouched" "$ORIG" "$(cat "$THING")"
  assert "l4: git status --porcelain empty" test -z "$(git -C "$REPO" status --porcelain)"
}

case_l1; case_l2; case_l3; case_l4

printf '# mutation-control-live pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ ${FAIL} -eq 0 ]]
