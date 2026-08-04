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

# ── Case 1: no stream file + clean worktree -> arm_produced_nothing, no_work,
#    and the e2e block must never run (E2E_ON=1). ─────────────────────────────────
SIG1="c1c1c1c1"
LEDGER1="$tmp/ledger-1.jsonl"
HANDOFF1="$ROOT/docs/handoff/dispatch-${SIG1}"

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
  pass "Case 1: exits 5 (matches other blocked branches)"
else
  fail "Case 1: expected exit 5, got rc=${rc1} -- out=${out1}"
fi

if grep -q 'reason: arm_produced_nothing' "$HANDOFF1/review-gate.md" 2>/dev/null; then
  pass "Case 1: review-gate.md carries reason: arm_produced_nothing"
else
  fail "Case 1: review-gate.md missing/wrong -- $(cat "$HANDOFF1/review-gate.md" 2>/dev/null)"
fi

row1="$(grep "\"task_sig\":\"${SIG1}\"" "$LEDGER1" 2>/dev/null)"
if printf '%s\n' "$row1" | grep -q '"terminal":"no_work"' && printf '%s\n' "$row1" | grep -q '"cause":"arm_produced_nothing"'; then
  pass "Case 1: ledger row is no_work/arm_produced_nothing"
else
  fail "Case 1: ledger row wrong -- $row1"
fi

journal1="$ROOT/docs/leadv2/tasks/dispatch-${SIG1}/journal.md"
if [[ -f "$journal1" ]] && grep -q 'e2e_gate' "$journal1"; then
  fail "Case 1: e2e_gate line found in journal -- the probe must run BEFORE the e2e block"
else
  pass "Case 1: no e2e_gate line in journal (probe short-circuited before e2e)"
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
printf '{"type":"system"}\n' > "$HANDOFF4/developer.stream.jsonl"
touch -t 202001010000 "$HANDOFF4/developer.stream.jsonl" 2>/dev/null || \
  touch -d '2020-01-01' "$HANDOFF4/developer.stream.jsonl" 2>/dev/null || true

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

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
