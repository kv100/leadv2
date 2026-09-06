#!/usr/bin/env bash
# tests/test-silent-arm-index-and-cross-repo.sh — PRODUCED-NOTHING-IS-REPO-SCOPED-
# AND-INDEX-BLIND-01
#
# pc_silent_arm_probe (leadv2-dispatch-product-close.sh) had two blind spots that
# together produced a false arm_produced_nothing/no_work terminal on lane 49be1f0b
# (2026-09-06, ряд 0b89d0b792e0), a lane that had in fact fully landed its work:
#
#   Defect 1 (index-blind): lv2_lane_dirty excludes docs/handoff/* by design (it
#     answers "is there SCOPE dirt", and routine lane-state writes are not scope
#     dirt) -- but pc_silent_arm_probe reused that same exclude-filtered check to
#     answer a DIFFERENT question, "did the arm do anything at all". A report
#     staged (or fully written) under docs/handoff and never committed is real
#     evidence of activity that the filtered check could never see. 159 lines of
#     report sat exactly there, in the lane's own worktree index, on 49be1f0b.
#
#   Defect 2 (repo-scoped): the commits-ahead check is scoped to the lane's own
#     worktree repository only. A lane whose mission touches the shared leadv2
#     plugin tree commits its CODE in a SEPARATE git checkout (~/Projects/leadv2)
#     the probe never looked at. 49be1f0b landed a full commit (16efd6fa,
#     +482/-17) there while the probe saw zero commits ahead in its own repo.
#
# Both fixes are independent escape hatches inside pc_silent_arm_probe, verified
# separately below, against the SAME otherwise-silent baseline shape Case D of
# test-silent-arm-commits-ahead.sh already uses as its positive control (kept
# green here too, as the regression guard: a genuinely silent arm must still be
# classified arm_produced_nothing).
#
# Drives the REAL leadv2-dispatch-product-close.sh end to end, same harness idiom
# as test-silent-arm-commits-ahead.sh. Sandboxed via CLAUDE_PROJECT_ROOT /
# LEADV2_DISPATCH_CACHE_DIR / LEADV2_DISPATCH_TERMINAL_LEDGER_FILE /
# LEADV2_LANE_WORK_ROOT / LEADV2_CANONICAL_ROOT — never touches the real repo's
# ledger, journal, active.yaml, or the real ~/Projects/leadv2 checkout.
# Run: bash scripts/tests/test-silent-arm-index-and-cross-repo.sh
# Exit 0 = all pass; non-zero = failures found.
# run-all-triggers: leadv2-dispatch-product-close

set -uo pipefail

# Scrub ambient LEADV2_* env vars first — same reasoning as
# test-silent-arm-commits-ahead.sh: this suite must be green regardless of which
# harness invoked it, not just under a caller that happens to leave no lane vars
# exported.
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

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

bash -n "$PRODUCT_CLOSE_SH" || { fail "bash -n failed on leadv2-dispatch-product-close.sh"; exit 1; }

tmp="$(lv2_mktemp_dir "pc-silent-idx-xrepo-test")"
MUT_PC=""
trap 'rm -rf "$tmp"; [[ -n "$MUT_PC" ]] && rm -f "$MUT_PC"' EXIT
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

# Common baseline for every case below: arm registered, stream present with 0
# assistant events and a STALE mtime, no live pid, no commit ahead of the
# recorded start sha -- by itself this is EXACTLY the silent shape (matches Case
# D of test-silent-arm-commits-ahead.sh).
seed_case() { # <sig> -> writes $HANDOFF path to stdout
  local sig="$1" handoff
  handoff="$ROOT/docs/handoff/dispatch-${sig}"
  mkdir -p "$handoff"
  printf 'arm=glm handle=PID=0 epoch=0\n' > "$handoff/arm-registered"
  printf '{"type":"system"}\n' > "$handoff/developer.stream.jsonl"
  touch -t 202001010000 "$handoff/developer.stream.jsonl" 2>/dev/null || \
    touch -d '2020-01-01' "$handoff/developer.stream.jsonl" 2>/dev/null || true
  printf '%s\n' "$SEED_SHA" > "${CACHE}/dispatch-${sig}.start-sha"
  printf '%s' "$handoff"
}

run_gate() { # <sig> <ledger> <founder_task_id> [extra env already exported by caller]
  local sig="$1" ledger="$2" ftid="$3"
  CLAUDE_PROJECT_ROOT="$ROOT" \
  LEADV2_DISPATCH_CACHE_DIR="$CACHE" \
  LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$ledger" \
  LEADV2_LANE_WORK_ROOT="$LANE" \
  LEADV2_ARM_ADVANCE=0 \
    bash "$PRODUCT_CLOSE_SH" "$ROOT" "$sig" glm "" 0 0 "$ftid" 2>&1
}

# ── Case 1 (Defect 1 — index-blind): baseline silent shape, PLUS a report staged
#    (git add, never committed) under docs/handoff/<sig> in the LANE worktree —
#    the exact shape 49be1f0b hit. lv2_lane_dirty alone would filter this path
#    out; the unfiltered porcelain check must still catch it. ────────────────────
SIG1="cidx0001"
HANDOFF1="$(seed_case "$SIG1")"
mkdir -p "$LANE/docs/handoff/${SIG1}"
printf 'report line\n%.0s' $(seq 1 20) > "$LANE/docs/handoff/${SIG1}/report.md"
git -C "$LANE" add "docs/handoff/${SIG1}/report.md"

out1="$(run_gate "$SIG1" "$tmp/ledger-1.jsonl" "")"
git -C "$LANE" reset -q HEAD -- "docs/handoff/${SIG1}/report.md" 2>/dev/null || true
rm -rf "${LANE:?}/docs/handoff/${SIG1}"

if grep -q 'reason: arm_produced_nothing' "$HANDOFF1/review-gate.md" 2>/dev/null; then
  fail "Case 1: report staged (index-only) under docs/handoff was still classified arm_produced_nothing -- out=${out1}"
else
  pass "Case 1: report staged in the lane's index (docs/handoff, never committed) is NOT classified arm_produced_nothing"
fi

# ── Case 2 (Defect 2 — repo-scoped): baseline silent shape, LANE stays fully
#    clean/no-commits-ahead, but a SEPARATE "canonical leadv2" repo carries a
#    commit whose message names this lane's own FOUNDER_TASK_ID — the exact
#    shape of 49be1f0b's 16efd6fa landing in leadv2 while persona-engine's lane
#    worktree showed nothing. ──────────────────────────────────────────────────
SIG2="cxrepo02"
FTID2="PRODUCED-NOTHING-IS-REPO-SCOPED-AND-INDEX-BLIND-01-TESTFTID"
HANDOFF2="$(seed_case "$SIG2")"
CANON="$tmp/canonical-leadv2"
mkdir -p "$CANON"
git -C "$CANON" init -q
git -C "$CANON" config user.email test@test.local
git -C "$CANON" config user.name test
printf 'x\n' > "$CANON/f.txt"
git -C "$CANON" add f.txt
git -C "$CANON" commit -q -m "fix(leadv2): ${FTID2} — landed in the sibling repo"

out2="$(LEADV2_CANONICAL_ROOT="$CANON" run_gate "$SIG2" "$tmp/ledger-2.jsonl" "$FTID2")"

if grep -q 'reason: arm_produced_nothing' "$HANDOFF2/review-gate.md" 2>/dev/null; then
  fail "Case 2: a matching commit in the sibling leadv2 repo was still classified arm_produced_nothing -- out=${out2}"
else
  pass "Case 2: a commit naming FOUNDER_TASK_ID in the sibling leadv2 repo is NOT classified arm_produced_nothing"
fi

# ── Case 3 (regression guard / positive control): identical baseline to Case 2
#    but the sibling repo's commit does NOT name this lane's FOUNDER_TASK_ID —
#    must still fire arm_produced_nothing. Proves Case 2 is not just "any commit
#    anywhere always suppresses the verdict". ───────────────────────────────────
SIG3="cxrepo03"
FTID3="PRODUCED-NOTHING-IS-REPO-SCOPED-AND-INDEX-BLIND-01-UNRELATED-FTID"
HANDOFF3="$(seed_case "$SIG3")"

out3="$(LEADV2_CANONICAL_ROOT="$CANON" run_gate "$SIG3" "$tmp/ledger-3.jsonl" "$FTID3")"

if grep -q 'reason: arm_produced_nothing' "$HANDOFF3/review-gate.md" 2>/dev/null; then
  pass "Case 3: an unrelated commit in the sibling repo does not suppress a genuinely silent verdict"
else
  fail "Case 3: positive control regressed -- unrelated FOUNDER_TASK_ID still suppressed arm_produced_nothing -- out=${out3}"
fi

# ── Case 4 (regression guard): fully silent baseline, no staged index content,
#    no canonical repo override at all — must still fire arm_produced_nothing,
#    exactly like Case D of test-silent-arm-commits-ahead.sh. ───────────────────
SIG4="csilent4"
HANDOFF4="$(seed_case "$SIG4")"

out4="$(run_gate "$SIG4" "$tmp/ledger-4.jsonl" "")"

if grep -q 'reason: arm_produced_nothing' "$HANDOFF4/review-gate.md" 2>/dev/null; then
  pass "Case 4: a genuinely silent arm (no index content, no cross-repo evidence) is still classified arm_produced_nothing"
else
  fail "Case 4: positive control regressed -- out=${out4}"
fi

# --- MUTATION CONTROL — revert both new escape hatches STRICTLY INSIDE
# pc_silent_arm_probe's body (never a top-level/line-number insert), confirm the
# mutated copy actually differs, then rerun Case 1 and Case 2 against it: both
# must go RED (back to arm_produced_nothing), proving this suite actually
# exercises the fix and is not a tautology.
# Written INSIDE the real scripts dir (not an isolated tmp dir) so the mutated
# copy's own SCRIPT_DIR-relative sourcing of lib/leadv2-lane-guard.sh etc.
# resolves normally, instead of falling back to LEADV2_CANONICAL_ROOT -- which
# Case 2's setup below points at a bare fixture repo with no lib/ subtree at all.
MUT_PC="${SCRIPTS_ROOT}/.mut-silent-arm-idx-xrepo-$$.sh"
python3 - "$PRODUCT_CLOSE_SH" "$MUT_PC" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
text = text.replace(
    'if [[ -n "$(git -C "${_lane_root}" status --porcelain --untracked-files=all 2>/dev/null)" ]]; then\n'
    '    return 1\n'
    '  fi\n',
    '',
    1,
)
text = text.replace(
    '  local _canonical_leadv2="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}"\n'
    '  if [[ -n "${FOUNDER_TASK_ID:-}" && -d "${_canonical_leadv2}/.git" ]] \\\n'
    '     && [[ "$(_lv2_phys "${_canonical_leadv2}" 2>/dev/null)" != "$(_lv2_phys "${_lane_root}" 2>/dev/null)" ]] \\\n'
    '     && git -C "${_canonical_leadv2}" log --all --fixed-strings \\\n'
    '          --grep="${FOUNDER_TASK_ID}" --format=%H -1 2>/dev/null | grep -q .; then\n'
    '    return 1\n'
    '  fi\n',
    '',
    1,
)
open(dst, 'w').write(text)
PY
chmod +x "$MUT_PC" 2>/dev/null || true

if diff -q "$PRODUCT_CLOSE_SH" "$MUT_PC" >/dev/null 2>&1; then
  fail "mutation control: mutated file byte-identical to production -- the mutation never applied, this control proves nothing"
else
  HANDOFF1M="$(seed_case "cidxmut1")"
  mkdir -p "$LANE/docs/handoff/cidxmut1"
  printf 'report line\n%.0s' $(seq 1 20) > "$LANE/docs/handoff/cidxmut1/report.md"
  git -C "$LANE" add "docs/handoff/cidxmut1/report.md"
  out1m="$(
    CLAUDE_PROJECT_ROOT="$ROOT" LEADV2_DISPATCH_CACHE_DIR="$CACHE" \
    LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$tmp/ledger-1m.jsonl" \
    LEADV2_LANE_WORK_ROOT="$LANE" LEADV2_ARM_ADVANCE=0 \
      bash "$MUT_PC" "$ROOT" "cidxmut1" glm "" 0 0 "" 2>&1
  )"
  git -C "$LANE" reset -q HEAD -- "docs/handoff/cidxmut1/report.md" 2>/dev/null || true
  rm -rf "${LANE:?}/docs/handoff/cidxmut1"

  HANDOFF2M="$(seed_case "cxrepomut2")"
  out2m="$(
    CLAUDE_PROJECT_ROOT="$ROOT" LEADV2_DISPATCH_CACHE_DIR="$CACHE" \
    LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$tmp/ledger-2m.jsonl" \
    LEADV2_LANE_WORK_ROOT="$LANE" LEADV2_ARM_ADVANCE=0 LEADV2_CANONICAL_ROOT="$CANON" \
      bash "$MUT_PC" "$ROOT" "cxrepomut2" glm "" 0 0 "$FTID2" 2>&1
  )"

  if grep -q 'reason: arm_produced_nothing' "$HANDOFF1M/review-gate.md" 2>/dev/null \
     && grep -q 'reason: arm_produced_nothing' "$HANDOFF2M/review-gate.md" 2>/dev/null; then
    pass "MUTATION CONTROL: reverting both escape hatches makes Case 1 and Case 2 go red (arm_produced_nothing again)"
  else
    fail "mutation control: mutated binary did not reproduce arm_produced_nothing for either case -- out1m=${out1m} out2m=${out2m}"
  fi
fi
rm -f "$MUT_PC"

if [[ "$FAIL" -eq 0 ]]; then
  echo "ALL PASS: test-silent-arm-index-and-cross-repo.sh ($PASS passed)"
  exit 0
else
  echo "SOME FAILED: test-silent-arm-index-and-cross-repo.sh ($FAIL failed, $PASS passed)"
  exit 1
fi
