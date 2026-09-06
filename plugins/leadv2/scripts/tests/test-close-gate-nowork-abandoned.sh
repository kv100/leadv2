#!/usr/bin/env bash
# tests/test-close-gate-nowork-abandoned.sh — CLOSE-GATE-CALLS-A-FINISHED-LANE-no_work-01
#
# _pc_diff_base (leadv2-dispatch-product-close.sh) prefers a recorded
# LEADV2_LANE_START_SHA/cache start-sha over origin/main. A RE-DISPATCHED lane
# has that start-sha rewritten to the CURRENT tip before the worker runs again
# -- so when the tip already contains the previous round's real, committed
# work and the worker does nothing new this round, merge-base(start_sha, HEAD)
# degenerates to HEAD itself and the diff against it is empty BY CONSTRUCTION,
# even though the branch carries real commits origin/main has never seen. The
# origin/main fallback inside _pc_diff_base never fires here because the
# start-sha candidate resolved fine -- it just resolved to the wrong fact.
#
# Case A is the false-positive shape (2026-09-04,
# DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01): must NOT be stamped
# terminal=no_work cause=empty_diff.
# Case B is the paired control (2026-09-06, same lane re-dispatched after the
# work genuinely landed in main): must STILL be stamped
# terminal=no_work cause=empty_diff -- the fix must not strand a truly
# finished lane forever.
#
# Drives the REAL leadv2-dispatch-product-close.sh end to end, same harness
# idiom as test-silent-arm-commits-ahead.sh. Sandboxed via CLAUDE_PROJECT_ROOT
# / LEADV2_DISPATCH_CACHE_DIR / LEADV2_DISPATCH_TERMINAL_LEDGER_FILE /
# LEADV2_LANE_WORK_ROOT -- never touches the real repo's ledger, journal, or
# active.yaml.
# Run: bash scripts/tests/test-close-gate-nowork-abandoned.sh
# Exit 0 = all pass; non-zero = failures found.
# run-all-triggers: leadv2-dispatch-product-close leadv2-dispatch-ledger

set -uo pipefail

# Scrub ambient LEADV2_* env vars first (GATE-FALSE-SILENT-01 §0.3 precedent):
# this suite is driven directly and must not inherit a live lane's exported
# LEADV2_LANE_START_SHA / LEADV2_DISPATCH_LANE_WRITES.
while IFS= read -r _v; do
  [[ -n "$_v" ]] || continue
  case "$_v" in
    LEADV2_*) unset "$_v" ;;
  esac
done < <(compgen -e 2>/dev/null || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

PRODUCT_CLOSE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"
REAL_LEDGER_SH="${SCRIPTS_ROOT}/leadv2-dispatch-ledger.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

if bash -n "$PRODUCT_CLOSE_SH"; then
  pass "bash -n clean (leadv2-dispatch-product-close.sh)"
else
  fail "bash -n failed on leadv2-dispatch-product-close.sh"
fi

tmp="$(lv2_mktemp_dir "pc-nowork-abandoned-test")"; trap 'rm -rf "$tmp"' EXIT
ROOT="$tmp/root"
CACHE="$tmp/cache"
LANE="$tmp/lane"
mkdir -p "$ROOT" "$CACHE" "$LANE"

git -C "$LANE" init -q
git -C "$LANE" config user.email test@test.local
git -C "$LANE" config user.name test
printf 'seed\n' > "$LANE/seed.txt"
git -C "$LANE" add seed.txt
git -C "$LANE" commit -q -m seed
SEED_SHA="$(git -C "$LANE" rev-parse HEAD)"
# origin/main never moves in this fixture: it is the true upstream both cases
# are judged against.
git -C "$LANE" update-ref refs/remotes/origin/main "$SEED_SHA"

# Three real, committed work commits -- the round-1 lane's actual deliverable.
printf 'w1\n' > "$LANE/w1.txt"; git -C "$LANE" add w1.txt; git -C "$LANE" commit -q -m work1
printf 'w2\n' > "$LANE/w2.txt"; git -C "$LANE" add w2.txt; git -C "$LANE" commit -q -m work2
printf 'w3\n' > "$LANE/w3.txt"; git -C "$LANE" add w3.txt; git -C "$LANE" commit -q -m work3
WORK_TIP="$(git -C "$LANE" rev-parse HEAD)"

# ── Case A (the false-positive shape, 2026-09-04): re-dispatch records a
#    FRESH start-sha at the CURRENT tip (already containing the 3 work
#    commits); the worker does nothing new this round (clean worktree, no
#    live pid, stale/empty stream) -- must NOT be stamped
#    terminal=no_work cause=empty_diff, because origin/main still sees 3
#    commits of real work this lane never landed. ───────────────────────────
SIGA="daaaaaaa"
LEDGERA="$tmp/ledger-a.jsonl"
HANDOFFA="$ROOT/docs/handoff/dispatch-${SIGA}"
mkdir -p "$HANDOFFA"
# No arm-registered/stream file -- a manual close-gate run (_pc_diff_base's
# own comment: "manual close-gate runs may have no cache file"), so
# pc_silent_arm_probe never fires and the case exercises pc_scope_diff's
# empty_diff classification directly, not the separate arm_produced_nothing
# heuristic.
printf '%s\n' "$WORK_TIP" > "${CACHE}/dispatch-${SIGA}.start-sha"

outA="$(
  CLAUDE_PROJECT_ROOT="$ROOT" \
  LEADV2_DISPATCH_CACHE_DIR="$CACHE" \
  LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGERA" \
  LEADV2_LANE_WORK_ROOT="$LANE" \
  LEADV2_ARM_ADVANCE=0 \
    bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIGA" glm "" 0 0 "" 2>&1
)"
rcA=$?

if grep -q 'cause=empty_diff' <<<"$outA" || grep -q '^reason: no_work$' "$HANDOFFA/review-gate.md" 2>/dev/null; then
  fail "Case A: 3 commits ahead of origin/main were stamped no_work/empty_diff -- out=${outA}"
else
  pass "Case A: 3 commits ahead of origin/main are NOT stamped no_work/empty_diff"
fi

rowA="$(grep "\"task_sig\":\"${SIGA}\"" "$LEDGERA" 2>/dev/null | grep '"cause":"empty_diff"' || true)"
if [[ -z "$rowA" ]]; then
  pass "Case A: no empty_diff ledger row for the lane with real work ahead of main"
else
  fail "Case A: ledger recorded empty_diff despite real work ahead of main -- $rowA"
fi

# ── Case B (the paired control, 2026-09-06): SAME lane re-dispatched after the
#    3 commits genuinely landed in main (origin/main fast-forwarded to
#    WORK_TIP), lane worktree still at WORK_TIP, clean, nothing new -- must
#    STILL be stamped terminal=no_work cause=empty_diff. A fix that stops
#    emitting empty_diff unconditionally would strand this lane forever. ────
git -C "$LANE" update-ref refs/remotes/origin/main "$WORK_TIP"

SIGB="dbbbbbbb"
LEDGERB="$tmp/ledger-b.jsonl"
HANDOFFB="$ROOT/docs/handoff/dispatch-${SIGB}"
mkdir -p "$HANDOFFB"
printf '%s\n' "$WORK_TIP" > "${CACHE}/dispatch-${SIGB}.start-sha"

outB="$(
  CLAUDE_PROJECT_ROOT="$ROOT" \
  LEADV2_DISPATCH_CACHE_DIR="$CACHE" \
  LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGERB" \
  LEADV2_LANE_WORK_ROOT="$LANE" \
  LEADV2_ARM_ADVANCE=0 \
    bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIGB" glm "" 0 0 "" 2>&1
)"
rcB=$?

if grep -q 'cause=empty_diff' <<<"$outB"; then
  pass "Case B: a lane whose work genuinely landed in main is still stamped empty_diff"
else
  fail "Case B: legitimate landed-lane no longer stamped empty_diff -- fix stranded it -- out=${outB}"
fi

rowB="$(grep "\"task_sig\":\"${SIGB}\"" "$LEDGERB" 2>/dev/null | grep '"cause":"empty_diff"' || true)"
if [[ -n "$rowB" ]]; then
  pass "Case B: ledger row is no_work/empty_diff for the landed lane"
else
  fail "Case B: ledger row missing empty_diff for the landed lane"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
