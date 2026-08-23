#!/usr/bin/env bash
# tests/test-dispatch-silent-arm.sh — ARM-PRODUCES-NOTHING-AND-CHAIN-NEVER-ADVANCES-01
# (Fix 1): coverage for leadv2-dispatch-product-close.sh's pc_silent_arm_probe.
#
# Drives the REAL leadv2-dispatch-product-close.sh (never a reimplementation of the
# probe's predicate). Both e2e/review kill-switches are exercised deliberately: cases 1
# and 4 leave E2E_ON=1 REVIEW_ON=1 to prove the probe short-circuits BEFORE the e2e
# block ever runs (no e2e_gate journal line); cases 2/3 use 0/0 to keep the regression-
# lock and existing-path assertions free of a real e2e entrypoint dependency.
#
# Portable: no GNU-only date/sed/timeout. Sandboxed via LEADV2_DISPATCH_TERMINAL_
# LEDGER_FILE / CLAUDE_PROJECT_ROOT / LEADV2_DISPATCH_CACHE_DIR / LEADV2_LANE_WORK_ROOT
# -- never touches the real repo's ledger, journal, or active.yaml.
# Run: bash scripts/tests/test-dispatch-silent-arm.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail

# GATE-FALSE-SILENT-01 round 2 (§0.3): scrub ambient LEADV2_* env vars before the
# first fixture runs -- see test-silent-arm-commits-ahead.sh for the full rationale.
# This suite's Case 2 in particular is contaminated by a leaked
# LEADV2_DISPATCH_LANE_WRITES from an enclosing dispatch worker: the scope gate then
# refuses the fixture's undeclared newfile.txt as if it belonged to a different
# lane's write-set, which has nothing to do with what this case tests.
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

tmp="$(lv2_mktemp_dir "pc-silent-arm-test")"; trap 'rm -rf "$tmp"' EXIT
ROOT="$tmp/root"
CACHE="$tmp/cache"
LANE="$tmp/lane"
mkdir -p "$ROOT" "$CACHE" "$LANE"

# A clean git worktree for _pc_lane_dirty to see as clean.
git -C "$LANE" init -q
git -C "$LANE" config user.email test@test.local
git -C "$LANE" config user.name test
printf 'seed\n' > "$LANE/seed.txt"
git -C "$LANE" add seed.txt
git -C "$LANE" commit -q -m seed

# ── Case 1 (GATE-FALSE-SILENT-01): no stream file + clean worktree, arm
#    registered -> an absent stream is NEVER evidence of silence (too early to tell,
#    or a codex arm that structurally never writes one). Must NOT be classified
#    arm_produced_nothing and must NOT emit an arm_advance decision -- falls through
#    to the existing empty_diff path instead, which still exits 5/no_work on this
#    fixture (LANE has no changes), so the exit-code/no_work assertions are unchanged;
#    only the cause and the arm_advance emission flip. ─────────────────────────────
SIG1="c1c1c1c1"
LEDGER1="$tmp/ledger-1.jsonl"
HANDOFF1="$ROOT/docs/handoff/dispatch-${SIG1}"
mkdir -p "$HANDOFF1"
printf 'arm=glm handle=PID=0 epoch=0\n' > "$HANDOFF1/arm-registered"

out1="$(
  CLAUDE_PROJECT_ROOT="$ROOT" \
  LEADV2_DISPATCH_CACHE_DIR="$CACHE" \
  LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGER1" \
  LEADV2_LANE_WORK_ROOT="$LANE" \
  LEADV2_ARM_ADVANCE=0 \
    bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIG1" glm "" 1 1 "" 2>&1
)"
rc1=$?

if [[ "$rc1" -eq 5 ]]; then
  pass "Case 1: exits 5 (falls through to the existing empty_diff terminal)"
else
  fail "Case 1: expected exit 5, got rc=${rc1} -- out=${out1}"
fi

if grep -q 'reason: arm_produced_nothing' "$HANDOFF1/review-gate.md" 2>/dev/null; then
  fail "Case 1: absent stream wrongly classified as arm_produced_nothing -- out=${out1}"
else
  pass "Case 1: absent stream is NOT classified as arm_produced_nothing"
fi

row1="$(grep "\"task_sig\":\"${SIG1}\"" "$LEDGER1" 2>/dev/null)"
if printf '%s\n' "$row1" | grep -q '"terminal":"no_work"' && printf '%s\n' "$row1" | grep -q '"cause":"empty_diff"'; then
  pass "Case 1: ledger row is no_work/empty_diff (existing path, not the silent-arm path)"
else
  fail "Case 1: ledger row wrong -- $row1"
fi

if printf '%s\n' "$out1" | grep -q 'arm_advance'; then
  fail "Case 1: arm_advance decision emitted for an absent (unproven) stream -- out=${out1}"
else
  pass "Case 1: no arm_advance decision for an absent stream"
fi

# ── Case 2: real stream (>=1 assistant event) + real diff -> byte-identical to
#    today's existing (non-silent) verdict path -- regression lock. ────────────────
SIG2="c2c2c2c2"
LEDGER2="$tmp/ledger-2.jsonl"
HANDOFF2="$ROOT/docs/handoff/dispatch-${SIG2}"
mkdir -p "$HANDOFF2"
printf '{"type":"assistant","text":"working"}\n' > "$HANDOFF2/developer.stream.jsonl"
printf 'new content\n' > "$LANE/newfile.txt"

out2="$(
  CLAUDE_PROJECT_ROOT="$ROOT" \
  LEADV2_DISPATCH_CACHE_DIR="$CACHE" \
  LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGER2" \
  LEADV2_LANE_WORK_ROOT="$LANE" \
  LEADV2_ARM_ADVANCE=0 \
  LEADV2_DISPATCH_LANE_WRITES="" \
    bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIG2" glm "" 0 0 "" 2>&1
)"
rc2=$?

if grep -q 'reason: arm_produced_nothing' "$HANDOFF2/review-gate.md" 2>/dev/null; then
  fail "Case 2: review-gate.md wrongly shows arm_produced_nothing for a real diff with assistant events"
else
  pass "Case 2: review-gate.md not arm_produced_nothing (assistant events present)"
fi

row2="$(grep "\"task_sig\":\"${SIG2}\"" "$LEDGER2" 2>/dev/null)"
if printf '%s\n' "$row2" | grep -q '"terminal":"landed"'; then
  pass "Case 2: ledger row lands as before (regression lock, both gates off)"
else
  fail "Case 2: expected landed, got -- $row2 (rc=${rc2}, out=${out2})"
fi

rm -f "$LANE/newfile.txt"

# ── Case 3: stream present, zero assistant events, FRESH mtime -> growth guard
#    keeps this NOT silent -- falls through to the existing empty_diff path. ───────
SIG3="c3c3c3c3"
LEDGER3="$tmp/ledger-3.jsonl"
HANDOFF3="$ROOT/docs/handoff/dispatch-${SIG3}"
mkdir -p "$HANDOFF3"
printf '{"type":"system"}\n' > "$HANDOFF3/developer.stream.jsonl"

out3="$(
  CLAUDE_PROJECT_ROOT="$ROOT" \
  LEADV2_DISPATCH_CACHE_DIR="$CACHE" \
  LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGER3" \
  LEADV2_LANE_WORK_ROOT="$LANE" \
  LEADV2_ARM_ADVANCE=0 \
    bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIG3" glm "" 0 0 "" 2>&1
)"
rc3=$?

if grep -q 'reason: arm_produced_nothing' "$HANDOFF3/review-gate.md" 2>/dev/null; then
  fail "Case 3: fresh stream mistakenly classified as silent -- out=${out3}"
else
  pass "Case 3: fresh (within growth window) stream falls through as NOT silent"
fi
if grep -q 'reason: no_work' "$HANDOFF3/review-gate.md" 2>/dev/null; then
  pass "Case 3: existing empty-diff path still produces reason: no_work"
else
  fail "Case 3: expected reason: no_work on the existing path -- $(cat "$HANDOFF3/review-gate.md" 2>/dev/null)"
fi

# ── Case 4: stream present, zero assistant events, STALE mtime, clean worktree
#    -> silent. ──────────────────────────────────────────────────────────────────
SIG4="c4c4c4c4"
LEDGER4="$tmp/ledger-4.jsonl"
HANDOFF4="$ROOT/docs/handoff/dispatch-${SIG4}"
mkdir -p "$HANDOFF4"
printf 'arm=glm handle=PID=0 epoch=0\n' > "$HANDOFF4/arm-registered"
printf '{"type":"system"}\n' > "$HANDOFF4/developer.stream.jsonl"
touch -t 202001010000 "$HANDOFF4/developer.stream.jsonl" 2>/dev/null || \
  touch -d '2020-01-01' "$HANDOFF4/developer.stream.jsonl" 2>/dev/null || true
# GATE-FALSE-SILENT-01 round 2: _pc_lane_commits_ahead now reports "unknown" (NOT
# silent) rather than "0" when no base is resolvable. This case means to test the
# genuine-silence path -- a lane with a resolvable base and 0 commits ahead of it --
# so it must declare a start-sha cache pointing at LANE's current HEAD; otherwise it
# tests "unresolvable base", which is a different (and now differently-handled) state.
printf '%s\n' "$(git -C "$LANE" rev-parse HEAD)" > "${CACHE}/dispatch-${SIG4}.start-sha"

out4="$(
  CLAUDE_PROJECT_ROOT="$ROOT" \
  LEADV2_DISPATCH_CACHE_DIR="$CACHE" \
  LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGER4" \
  LEADV2_LANE_WORK_ROOT="$LANE" \
  LEADV2_ARM_ADVANCE=0 \
    bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIG4" glm "" 1 1 "" 2>&1
)"
rc4=$?

if grep -q 'reason: arm_produced_nothing' "$HANDOFF4/review-gate.md" 2>/dev/null; then
  pass "Case 4: stale stream + clean worktree classified as silent"
else
  fail "Case 4: stale stream should classify as silent -- out=${out4} -- $(cat "$HANDOFF4/review-gate.md" 2>/dev/null)"
fi

# ── Case 5 (ARM-PRODUCES-NOTHING-02 negative twin): identical setup to Case 1 (no
#    stream, clean worktree, E2E_ON=1 REVIEW_ON=1) but NO arm-registered file. The
#    probe must NOT fire — the lane belongs to the existing empty_diff path, not the
#    silent-arm path. No arm_advance decision line must be emitted. ─────────────────
SIG5="c5c5c5c5"
LEDGER5="$tmp/ledger-5.jsonl"
HANDOFF5="$ROOT/docs/handoff/dispatch-${SIG5}"

out5="$(
  CLAUDE_PROJECT_ROOT="$ROOT" \
  LEADV2_DISPATCH_CACHE_DIR="$CACHE" \
  LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGER5" \
  LEADV2_LANE_WORK_ROOT="$LANE" \
  LEADV2_ARM_ADVANCE=0 \
    bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIG5" glm "" 1 1 "" 2>&1
)"
rc5=$?

if grep -q 'reason: arm_produced_nothing' "$HANDOFF5/review-gate.md" 2>/dev/null; then
  fail "Case 5: arm_produced_nothing emitted without arm-registered file -- out=${out5}"
else
  pass "Case 5: no arm_produced_nothing when arm not registered (empty_diff path owns it)"
fi

if printf '%s\n' "$out5" | grep -q 'arm_advance'; then
  fail "Case 5: arm_advance decision emitted without arm-registered file -- out=${out5}"
else
  pass "Case 5: no arm_advance decision without arm registration"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
