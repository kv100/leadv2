#!/usr/bin/env bash
# test-lane-report-address.sh — INVISIBLE-DELIVERABLES-CENSUS-01 suite.
#
# Every case builds its own fixture tree with mkdir/cp under a mktemp root and
# points PROJECT_ROOT at it; nothing reads the live docs/handoff/ and nothing
# uses git archive (mutation-control isolation, census §7c).
#
# Cases C1-C11 map 1:1 to census §7a. The load-bearing ones:
#   C5 — a miss with unattributable dirs present is `unknown`, never `none`
#   C7 — the mirror: a neighbouring dir whose review.diff quotes the founder
#        id is never credited (exact-attribution invariant)
#   C11 — a location that yields nothing still prints its labelled line
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SCRIPT="$SCRIPT_DIR/../lib/mktemp-guard.sh"
if [ ! -f "$GUARD_SCRIPT" ]; then
    GUARD_SCRIPT="$SCRIPT_DIR/../../../plugins/leadv2/scripts/lib/mktemp-guard.sh"
fi
if [ -f "$GUARD_SCRIPT" ]; then
    source "$GUARD_SCRIPT"
else
    echo "Error: mktemp-guard.sh not found" >&2
    exit 1
fi
mktemp_guard
set -uo pipefail

REPORT_BIN="${SCRIPT_DIR}/../leadv2-lane-report.sh"
TID="TEST-LANE-ONE-01"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

# mk_receipth <dir> <task_id value>
mk_receipt() { printf 'task_id: %s\n' "$2" > "$1/admission-receipt.yaml"; }
# mk_missionh <dir> <line1>
mk_mission() { printf '%s\n\nprose body mentioning %s incidentally\n' "$2" "$TID" > "$1/lane-mission.md"; }
mk_deliv()   { printf 'report %s\n' "$1" > "$2"; }

# Base fixture: a report in a dispatch-named dir + an unattributable dir +
# a mirror dir (review.diff quoting the founder id) + a self-ref receipt dir.
mk_base_fixture() {
  local root="$1"
  mkdir -p "$root/docs/handoff/dispatch-aaaa1111" \
           "$root/docs/handoff/dispatch-bbbb2222" \
           "$root/docs/handoff/dispatch-cccc3333" \
           "$root/docs/handoff/dispatch-dddd4444" \
           "$root/docs/leadv2"
  printf 'sessions: {}\n' > "$root/docs/leadv2/active.yaml"

  # the real one: receipt + mission H1 both point at $TID
  mk_receipt "$root/docs/handoff/dispatch-aaaa1111" "$TID"
  mk_mission "$root/docs/handoff/dispatch-aaaa1111" "# $TID fix the address problem"
  mk_deliv x "$root/docs/handoff/dispatch-aaaa1111/developer.full.md"
  mk_deliv x "$root/docs/handoff/dispatch-aaaa1111/developer.summary.md"

  # unattributable: deliverable, no admissible pointer
  mk_deliv x "$root/docs/handoff/dispatch-bbbb2222/other.full.md"

  # self-referential receipt (49 real ones exist)
  mk_receipt "$root/docs/handoff/dispatch-cccc3333" "dispatch-cccc3333"

  # the mirror: another lane's report + banned-source files quoting $TID
  mk_receipt "$root/docs/handoff/dispatch-dddd4444" "OTHER-LANE-09"
  mk_deliv x "$root/docs/handoff/dispatch-dddd4444/review.full.md"
  printf -- "--- a\n-%s touched here\n" "$TID" \
    > "$root/docs/handoff/dispatch-dddd4444/review.diff"
  printf '%s\n' "docs/handoff/$TID/lands-here" \
    > "$root/docs/handoff/dispatch-dddd4444/main-dirt.base"
}

run_report() { # run_report <root> <args...> -> sets OUT, RC
  OUT=$(PROJECT_ROOT="$1" "$REPORT_BIN" "${@:2}" 2>&1); RC=$?
}

if [[ ! -x "$REPORT_BIN" && ! -f "$REPORT_BIN" ]]; then
  printf 'FATAL: report bin not found at %s\n' "$REPORT_BIN" >&2
  exit 1
fi

section "C1 founder id -> dispatch-named report (receipt present)"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lraddr.XXXXXX")
mk_base_fixture "$ROOT"
run_report "$ROOT" "$TID"
if [[ $RC -eq 0 && "$OUT" == *"dispatch-aaaa1111/developer.full.md"* \
  && "$OUT" == *"result: found 2"* ]]; then ok "resolved via receipt, exit 0"; else bad "C1 rc=$RC out=$OUT"; fi
rm -rf "$ROOT"

section "C2 dispatch-<sig8> in -> byte-identical path"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lraddr.XXXXXX")
mk_base_fixture "$ROOT"
run_report "$ROOT" "$TID";          P1=$(printf '%s\n' "$OUT" | grep -o 'docs/handoff/dispatch-aaaa1111/developer.full.md' | head -1)
run_report "$ROOT" "dispatch-aaaa1111"; P2=$(printf '%s\n' "$OUT" | grep -o 'docs/handoff/dispatch-aaaa1111/developer.full.md' | head -1)
if [[ $RC -eq 0 && -n "$P1" && "$P1" == "$P2" ]]; then ok "same report from dispatch- name"; else bad "C2 rc=$RC p1=$P1 p2=$P2"; fi
rm -rf "$ROOT"

section "C3 bare sig8 in -> same report again"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lraddr.XXXXXX")
mk_base_fixture "$ROOT"
run_report "$ROOT" "aaaa1111"; P3=$(printf '%s\n' "$OUT" | grep -o 'docs/handoff/dispatch-aaaa1111/developer.full.md' | head -1)
if [[ $RC -eq 0 && -n "$P3" && "$P3" == "$P1" || $RC -eq 0 && -n "$P3" ]]; then ok "same report from bare sig8"; else bad "C3 rc=$RC out=$OUT"; fi
if [[ $RC -ne 0 ]]; then bad "C3 rc nonzero"; fi
rm -rf "$ROOT"

section "C4 no report anywhere, every dir carries a pointer -> none + searched paths"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lraddr.XXXXXX")
mkdir -p "$ROOT/docs/handoff/dispatch-eeee1111" "$ROOT/docs/handoff/dispatch-ffff2222" "$ROOT/docs/leadv2"
printf 'sessions: {}\n' > "$ROOT/docs/leadv2/active.yaml"
mk_receipt "$ROOT/docs/handoff/dispatch-eeee1111" "SOME-LANE-A-01"
mk_receipt "$ROOT/docs/handoff/dispatch-ffff2222" "SOME-LANE-B-01"
run_report "$ROOT" "MISSING-LANE-01"
c4=0
[[ $RC -eq 1 ]] && ok "exit 1" || { bad "C4 rc=$RC"; c4=1; }
[[ "$OUT" == *"result: none"* && "$OUT" != *"result: unknown"* ]] && ok "says none" || { bad "C4 not none: $OUT"; c4=1; }
[[ "$OUT" == *"docs/leadv2/active.yaml"* && "$OUT" == *"receipts"* && "$OUT" == *"missions"* && "$OUT" == *"docs/handoff/MISSING-LANE-01/"* ]] \
  && ok "searched paths listed" || { bad "C4 searched paths missing: $OUT"; c4=1; }
[[ "$OUT" == *"0 unattributable dirs remain"* ]] && ok "states 0 unattributable" || { bad "C4 no unattributable line"; c4=1; }
rm -rf "$ROOT"

section "C5 no pointer matched but unattributable dirs exist -> unknown"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lraddr.XXXXXX")
mk_base_fixture "$ROOT"
run_report "$ROOT" "MISSING-LANE-02"
c5=0
[[ $RC -eq 2 ]] && ok "exit 2" || { bad "C5 rc=$RC"; c5=1; }
[[ "$OUT" == *"result: unknown"* ]] && ok "says unknown" || { bad "C5 not unknown: $OUT"; c5=1; }
[[ "$OUT" != *"result: none"* ]] && ok "NOT none" || { bad "C5 collapsed to none: $OUT"; c5=1; }
[[ "$OUT" =~ unattributable ]] && ok "names unattributable" || { bad "C5 no unattributable count"; c5=1; }
rm -rf "$ROOT"

section "C6 report dir unreadable (chmod 000) -> unknown, not none"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lraddr.XXXXXX")
mk_base_fixture "$ROOT"
if [[ "$(id -u)" -eq 0 ]]; then
  printf '  SKIP C6: running as root, chmod 000 does not bite root\n'
else
  mkdir -p "$ROOT/docs/handoff/dispatch-eeee5555"
  mk_receipt "$ROOT/docs/handoff/dispatch-eeee5555" "$TID"
  mk_deliv x "$ROOT/docs/handoff/dispatch-eeee5555/developer.full.md"
  chmod 000 "$ROOT/docs/handoff/dispatch-eeee5555"
  run_report "$ROOT" "$TID"
  if [[ $RC -eq 2 && "$OUT" == *"unknown"* && "$OUT" != *"result: none"* ]]; then ok "unknown under unreadable dir"; else bad "C6 rc=$RC out=$OUT"; fi
  chmod 755 "$ROOT/docs/handoff/dispatch-eeee5555"
fi
rm -rf "$ROOT"

section "C7 mirror: banned sources never credit the neighbouring dir"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lraddr.XXXXXX")
mk_base_fixture "$ROOT"
run_report "$ROOT" "OTHER-LANE-09"
[[ "$OUT" != *"dispatch-aaaa1111"* ]] && ok "querying the neighbour does not credit aaaa1111" || bad "C7 cross-credit: $OUT"
run_report "$ROOT" "$TID"
[[ "$OUT" != *"dddd4444"* ]] && ok "dddd4444 (review.diff/main-dirt.base quoting $TID) never listed" \
  || bad "C7 mirror listed: $OUT"
[[ -f "$ROOT/docs/handoff/dispatch-dddd4444/review.diff" ]] || bad "C7 fixture missing review.diff"
rm -rf "$ROOT"

section "C8 self-referential receipt is not a founder pointer"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lraddr.XXXXXX")
mk_base_fixture "$ROOT"
run_report "$ROOT" "$TID"
if [[ "$OUT" != *"dispatch-cccc3333"* ]]; then ok "dispatch-cccc3333 not credited via self-ref task_id"; else bad "C8 self-ref credited: $OUT"; fi
rm -rf "$ROOT"

section "C9 worktree-only report (depth 5)"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lraddr.XXXXXX")
# dedicated fixture: no main-tree match, no unattributable dirs — the ONLY
# report for $TID lives inside a lane worktree at depth 5 (census 2c)
mkdir -p "$ROOT/docs/handoff/dispatch-pointed0" "$ROOT/docs/leadv2"
printf 'sessions: {}\n' > "$ROOT/docs/leadv2/active.yaml"
mk_receipt "$ROOT/docs/handoff/dispatch-pointed0" "POINTED-LANE-01"
mkdir -p "$ROOT/.claude/worktrees/WTX/docs/handoff/dispatch-eeee6666"
mk_receipt "$ROOT/.claude/worktrees/WTX/docs/handoff/dispatch-eeee6666" "$TID"
mk_deliv x "$ROOT/.claude/worktrees/WTX/docs/handoff/dispatch-eeee6666/developer.full.md"
run_report "$ROOT" "$TID"
if [[ "$RC" -ne 0 && "$OUT" == *"NOT SEARCHED (pass --worktrees)"* && "$OUT" != *"eeee6666"* ]]; then ok "without --worktrees: not found, states not searched"; else bad "C9a rc=$RC out=$OUT"; fi
run_report "$ROOT" "$TID" --worktrees
if [[ $RC -eq 0 && "$OUT" == *"wt/WTX"* && "$OUT" == *"eeee6666/developer.full.md"* ]]; then ok "with --worktrees: found, labelled"; else bad "C9b rc=$RC out=$OUT"; fi
rm -rf "$ROOT"

section "C10 one founder id, two dispatch dirs -> both returned"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lraddr.XXXXXX")
mkdir -p "$ROOT/docs/handoff/dispatch-1a2b3c4d" "$ROOT/docs/handoff/dispatch-5e6f7a8b" "$ROOT/docs/leadv2"
printf 'sessions: {}\n' > "$ROOT/docs/leadv2/active.yaml"
mk_receipt "$ROOT/docs/handoff/dispatch-1a2b3c4d" "$TID"
mk_receipt "$ROOT/docs/handoff/dispatch-5e6f7a8b" "$TID"
mk_deliv x "$ROOT/docs/handoff/dispatch-1a2b3c4d/round1.full.md"
mk_deliv x "$ROOT/docs/handoff/dispatch-5e6f7a8b/round2.full.md"
run_report "$ROOT" "$TID"
if [[ $RC -eq 0 && "$OUT" == *"result: found 2"* \
     && "$OUT" == *"dispatch-1a2b3c4d/round1.full.md"* \
     && "$OUT" == *"dispatch-5e6f7a8b/round2.full.md"* ]]; then ok "both dirs returned"; else bad "C10 rc=$RC out=$OUT"; fi
rm -rf "$ROOT"

section "C11 every consulted location prints a labelled line"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lraddr.XXXXXX")
mkdir -p "$ROOT/docs/handoff/dispatch-9999aaaa" "$ROOT/docs/leadv2"
printf 'sessions: {}\n' > "$ROOT/docs/leadv2/active.yaml"
mk_receipt "$ROOT/docs/handoff/dispatch-9999aaaa" "POINTED-LANE-01"
run_report "$ROOT" "MISSING-LANE-03"
nlines=$(printf '%s\n' "$OUT" | grep -cE '^  (registry|receipts|missions|eponymous|worktrees)  ')
if [[ "$nlines" -eq 5 ]]; then ok "five labelled search lines (registry/receipts/missions/eponymous/worktrees)"; else bad "C11 nlines=$nlines out=$OUT"; fi
rm -rf "$ROOT"

printf '\nPASS=%s FAIL=%s\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
