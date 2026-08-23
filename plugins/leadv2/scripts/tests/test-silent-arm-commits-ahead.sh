#!/usr/bin/env bash
# tests/test-silent-arm-commits-ahead.sh — GATE-FALSE-SILENT-01
#
# Coverage for the two defects fixed in pc_silent_arm_probe
# (leadv2-dispatch-product-close.sh):
#   Defect 1 — a lane that COMMITTED work (clean worktree, commits ahead of the
#              recorded start sha) must never be classified arm_produced_nothing.
#   Defect 2 — an absent/fresh stream, or a live worker process, must never be
#              treated as evidence of silence.
#
# Drives the REAL leadv2-dispatch-product-close.sh end to end, same harness idiom
# as test-dispatch-silent-arm.sh. Sandboxed via CLAUDE_PROJECT_ROOT /
# LEADV2_DISPATCH_CACHE_DIR / LEADV2_DISPATCH_TERMINAL_LEDGER_FILE /
# LEADV2_LANE_WORK_ROOT — never touches the real repo's ledger, journal, or
# active.yaml.
# Run: bash scripts/tests/test-silent-arm-commits-ahead.sh
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

tmp="$(lv2_mktemp_dir "pc-silent-commits-test")"; trap 'rm -rf "$tmp"' EXIT
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

# ── Case A: seed commit recorded as start-sha, a SECOND commit landed, worktree
#    clean, stream present with 0 assistant events and a STALE mtime, arm
#    registered -> must NOT be classified arm_produced_nothing (Defect 1: commits
#    ahead of base are production even though the worktree is clean). ────────────
SIGA="caaaaaaa"
LEDGERA="$tmp/ledger-a.jsonl"
HANDOFFA="$ROOT/docs/handoff/dispatch-${SIGA}"
mkdir -p "$HANDOFFA"
printf 'arm=glm handle=PID=0 epoch=0\n' > "$HANDOFFA/arm-registered"
printf '{"type":"system"}\n' > "$HANDOFFA/developer.stream.jsonl"
touch -t 202001010000 "$HANDOFFA/developer.stream.jsonl" 2>/dev/null || \
  touch -d '2020-01-01' "$HANDOFFA/developer.stream.jsonl" 2>/dev/null || true
printf '%s\n' "$SEED_SHA" > "${CACHE}/dispatch-${SIGA}.start-sha"
printf 'second\n' > "$LANE/second.txt"
git -C "$LANE" add second.txt
git -C "$LANE" commit -q -m second

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

if grep -q 'reason: arm_produced_nothing' "$HANDOFFA/review-gate.md" 2>/dev/null; then
  fail "Case A: a lane with a commit ahead of base was classified arm_produced_nothing -- out=${outA}"
else
  pass "Case A: a committed lane (clean worktree) is NOT classified arm_produced_nothing"
fi

if printf '%s\n' "$outA" | grep -q 'arm_advance'; then
  fail "Case A: arm_advance decision emitted for a lane that produced a commit -- out=${outA}"
else
  pass "Case A: no arm_advance decision for a committed lane"
fi

# Reset lane to the seed commit for the remaining cases.
git -C "$LANE" reset -q --hard "$SEED_SHA"

# ── Case B: stream absent, clean worktree, registered -> NOT silent (Defect 2:
#    absent stream is never evidence of silence). ────────────────────────────────
SIGB="cbbbbbbb"
LEDGERB="$tmp/ledger-b.jsonl"
HANDOFFB="$ROOT/docs/handoff/dispatch-${SIGB}"
mkdir -p "$HANDOFFB"
printf 'arm=glm handle=PID=0 epoch=0\n' > "$HANDOFFB/arm-registered"

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

if grep -q 'reason: arm_produced_nothing' "$HANDOFFB/review-gate.md" 2>/dev/null; then
  fail "Case B: absent stream classified arm_produced_nothing -- out=${outB}"
else
  pass "Case B: absent stream is NOT classified arm_produced_nothing"
fi

# ── Case C: stream present, 0 assistant events, FRESH mtime, clean, registered
#    -> NOT silent (growth guard, unchanged behaviour reconfirmed here). ─────────
SIGC="ccccccc1"
LEDGERC="$tmp/ledger-c.jsonl"
HANDOFFC="$ROOT/docs/handoff/dispatch-${SIGC}"
mkdir -p "$HANDOFFC"
printf 'arm=glm handle=PID=0 epoch=0\n' > "$HANDOFFC/arm-registered"
printf '{"type":"system"}\n' > "$HANDOFFC/developer.stream.jsonl"

outC="$(
  CLAUDE_PROJECT_ROOT="$ROOT" \
  LEADV2_DISPATCH_CACHE_DIR="$CACHE" \
  LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGERC" \
  LEADV2_LANE_WORK_ROOT="$LANE" \
  LEADV2_ARM_ADVANCE=0 \
    bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIGC" glm "" 0 0 "" 2>&1
)"
rcC=$?

if grep -q 'reason: arm_produced_nothing' "$HANDOFFC/review-gate.md" 2>/dev/null; then
  fail "Case C: fresh stream classified arm_produced_nothing -- out=${outC}"
else
  pass "Case C: fresh stream is NOT classified arm_produced_nothing"
fi

# ── Case D (positive control): registered, stream present with 0 events and a
#    STALE mtime, NO commit ahead of the recorded start sha, clean worktree, no
#    live pid -> STILL arm_produced_nothing, no_work/arm_produced_nothing ledger
#    row, and with LEADV2_ARM_ADVANCE=1 + a candidate chain, exactly ONE
#    arm_advance line and the .arm-advanced marker present. ─────────────────────
SIGD="cddddddd"
LEDGERD="$tmp/ledger-d.jsonl"
HANDOFFD="$ROOT/docs/handoff/dispatch-${SIGD}"
mkdir -p "$HANDOFFD"
printf 'arm=glm handle=PID=0 epoch=0\n' > "$HANDOFFD/arm-registered"
printf '{"type":"system"}\n' > "$HANDOFFD/developer.stream.jsonl"
touch -t 202001010000 "$HANDOFFD/developer.stream.jsonl" 2>/dev/null || \
  touch -d '2020-01-01' "$HANDOFFD/developer.stream.jsonl" 2>/dev/null || true
printf '%s\n' "$SEED_SHA" > "${CACHE}/dispatch-${SIGD}.start-sha"

outD="$(
  CLAUDE_PROJECT_ROOT="$ROOT" \
  LEADV2_DISPATCH_CACHE_DIR="$CACHE" \
  LEADV2_DISPATCH_LEDGER_BIN="$REAL_LEDGER_SH" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$LEDGERD" \
  LEADV2_LANE_WORK_ROOT="$LANE" \
  LEADV2_ARM_ADVANCE=1 \
  LEADV2_DISPATCH_CANDIDATE_ARMS="glm,codex" \
    bash "$PRODUCT_CLOSE_SH" "$ROOT" "$SIGD" glm "" 0 0 "" 2>&1
)"
rcD=$?

if grep -q 'reason: arm_produced_nothing' "$HANDOFFD/review-gate.md" 2>/dev/null; then
  pass "Case D: genuinely silent arm still classified arm_produced_nothing"
else
  fail "Case D: positive control regressed -- out=${outD} -- $(cat "$HANDOFFD/review-gate.md" 2>/dev/null)"
fi

rowD="$(grep "\"task_sig\":\"${SIGD}\"" "$LEDGERD" 2>/dev/null)"
if printf '%s\n' "$rowD" | grep -q '"terminal":"no_work"' && printf '%s\n' "$rowD" | grep -q '"cause":"arm_produced_nothing"'; then
  pass "Case D: ledger row is no_work/arm_produced_nothing"
else
  fail "Case D: ledger row wrong -- $rowD"
fi

advance_lines_D="$(printf '%s\n' "$outD" | grep -c 'arm_advance' || true)"
if [[ "$advance_lines_D" -eq 1 ]]; then
  pass "Case D: exactly one arm_advance decision line"
else
  fail "Case D: expected exactly 1 arm_advance line, got ${advance_lines_D} -- out=${outD}"
fi

if [[ -f "$HANDOFFD/.arm-advanced-glm" ]]; then
  pass "Case D: .arm-advanced-glm marker present"
else
  fail "Case D: .arm-advanced-glm marker missing"
fi

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
