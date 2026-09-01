#!/usr/bin/env bash
# test-phase-record.sh — record/assert/show round-trip for leadv2-phase-record.sh
# PHASES-ARE-THE-ONLY-PATH-01 §11 test suite 1.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_RECORD="${SCRIPT_DIR}/../leadv2-phase-record.sh"

# Use a temp project root
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# PHASE-GATE-IS-INVERTED-01: a session-exported PROJECT_ROOT diverging from
# this suite's LEADV2_PROJECT_ROOT would now refuse every record write; this
# suite's store root comes from LEADV2_PROJECT_ROOT alone, so drop the other
# name.
unset PROJECT_ROOT
export LEADV2_PROJECT_ROOT="$TMP_ROOT"
export LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/.cache"
export LEADV2_JOURNAL_BIN=/dev/null  # silent — no real journal

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; }

SIG8="abc12345"
PHASES_D="${TMP_ROOT}/docs/handoff/dispatch-${SIG8}/phases.d"

# ── Test 1: record basic round-trip ──────────────────────────────────────────
printf 'test: record basic round-trip\n'
mkdir -p "${TMP_ROOT}/src"
echo "content" > "${TMP_ROOT}/src/file.py"
bash "$PHASE_RECORD" record "$SIG8" build --status done \
  --artifact src/file.py --owner test:test 2>/dev/null
if [[ -f "${PHASES_D}/build.yaml" ]]; then
  ok
else
  fail "build.yaml not created"
fi

# Verify flat schema fields
if grep -q '^phase: build' "${PHASES_D}/build.yaml" \
   && grep -q '^status: done' "${PHASES_D}/build.yaml" \
   && grep -q '^artifact: src/file.py' "${PHASES_D}/build.yaml" \
   && grep -q '^artifact_sha256:' "${PHASES_D}/build.yaml"; then
  ok
else
  fail "build.yaml missing expected fields"
fi

# ── Test 2: mkdir -p on a lane with no docs/handoff/<id>/ ────────────────────
printf 'test: mkdir -p on missing dir\n'
SIG8_B="deadbeef"
bash "$PHASE_RECORD" record "$SIG8_B" classify --status done --owner test:test 2>/dev/null
if [[ -f "${TMP_ROOT}/docs/handoff/dispatch-${SIG8_B}/phases.d/classify.yaml" ]]; then
  ok
else
  fail "classify.yaml not created in fresh dir"
fi

# ── Test 3: atomic-rename leaves no .tmp behind ──────────────────────────────
printf 'test: no tmp files left behind\n'
TMP_FILES="$(find "${PHASES_D}" -name '.build.*' 2>/dev/null | head -5)"
if [[ -z "$TMP_FILES" ]]; then
  ok
else
  fail "temp files left behind: $TMP_FILES"
fi

# ── Test 4: concurrent record of two different phases ────────────────────────
printf 'test: concurrent record of two phases\n'
SIG8_C="cafe1234"
bash "$PHASE_RECORD" record "$SIG8_C" build --status running --handle h1 --owner test 2>/dev/null &
PID1=$!
bash "$PHASE_RECORD" record "$SIG8_C" plan --status done --artifact src/file.py --owner test 2>/dev/null &
PID2=$!
wait $PID1
wait $PID2
PDIR="${TMP_ROOT}/docs/handoff/dispatch-${SIG8_C}/phases.d"
if [[ -f "${PDIR}/build.yaml" && -f "${PDIR}/plan.yaml" ]]; then
  ok
else
  fail "concurrent record produced incomplete files"
fi

# ── Test 5: n/a requires --reason ────────────────────────────────────────────
printf 'test: n/a requires reason\n'
bash "$PHASE_RECORD" record "$SIG8" test --status n/a 2>/dev/null
rc=$?
if [[ $rc -eq 4 ]]; then
  ok
else
  fail "n/a without reason should exit 4 (got $rc)"
fi

bash "$PHASE_RECORD" record "$SIG8" test --status n/a --reason docs_only 2>/dev/null
rc=$?
if [[ $rc -eq 0 ]]; then
  ok
else
  fail "n/a with reason should succeed (got $rc)"
fi

# ── Test 6: waived requires --reason ─────────────────────────────────────────
printf 'test: waived requires reason\n'
bash "$PHASE_RECORD" record "$SIG8" diverge --status waived 2>/dev/null
rc=$?
if [[ $rc -eq 4 ]]; then
  ok
else
  fail "waived without reason should exit 4 (got $rc)"
fi

# ── Test 7: running requires --handle ────────────────────────────────────────
printf 'test: running requires handle\n'
bash "$PHASE_RECORD" record "$SIG8" build --status running 2>/dev/null
rc=$?
if [[ $rc -eq 4 ]]; then
  ok
else
  fail "running without handle should exit 4 (got $rc)"
fi

# ── Test 8: show prints a table ──────────────────────────────────────────────
printf 'test: show output\n'
SHOW_OUT="$(bash "$PHASE_RECORD" show "$SIG8" 2>/dev/null)"
if printf '%s' "$SHOW_OUT" | grep -q 'build'; then
  ok
else
  fail "show should list build phase"
fi

# ── Test 9: plan-for prints mandatory set ────────────────────────────────────
printf 'test: plan-for Standard\n'
PLAN_OUT="$(bash "$PHASE_RECORD" plan-for --class Standard 2>/dev/null)"
if printf '%s' "$PLAN_OUT" | grep -q 'MANDATORY.*review'; then
  ok
else
  fail "plan-for Standard should include review as mandatory"
fi
if printf '%s' "$PLAN_OUT" | grep -q 'MANDATORY.*close'; then
  ok
else
  fail "plan-for Standard should include close as mandatory"
fi

printf '\n[PORE-RECORD] pass=%d fail=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
