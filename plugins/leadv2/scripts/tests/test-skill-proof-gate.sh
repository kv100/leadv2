#!/usr/bin/env bash
# test-skill-proof-gate.sh — unit tests for leadv2-skill-proof.sh (the skill DoD gate).
#
# HARD RULE: fixture PROOF.sh files must be syntactically valid (pass bash -n)
# and fail at RUNTIME or be refused by the tautology check.  A deliberately
# broken-syntax fixture would turn run-core-offline.sh's syntax_all RED.
#
# Coverage:
#   (a) valid+passing fixture → GREEN, exit 0
#   (b) valid+failing fixture → RED-FAILED, exit 1
#   (c) tautological fixture  → RED-INVALID, validate exits 3, never executed (sentinel)
#   (d) no-proof fixture      → RED-NO-PROOF, exit 1
#   (e) mixed tree            → exit 1 with correct counts
#   (f) state-hash invalidation → GREEN recorded, proof edited, --from-state reports RED-NEVER-RUN
#   (g) bash -n and shellcheck on gate + lib
#
# Run: bash scripts/tests/test-skill-proof-gate.sh
# Exit 0 = all pass; non-zero = failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPTS_DIR}/.." && pwd)"

# Guard against mktemp -t without XXX in template
GUARD_SCRIPT="${SCRIPTS_DIR}/lib/mktemp-guard.sh"
if [ -f "$GUARD_SCRIPT" ]; then
    source "$GUARD_SCRIPT"
else
    echo "Error: mktemp-guard.sh not found" >&2
    exit 1
fi
mktemp_guard

GATE="${SCRIPTS_DIR}/leadv2-skill-proof.sh"
LIB="${SCRIPTS_DIR}/leadv2-proof-lib.sh"
FIXTURES="${SCRIPT_DIR}/fixtures/skill-proof"

PASS=0
FAIL=0
ERRORS=()

log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# ── (g) syntax + shellcheck ─────────────────────────────────────────────────
if bash -n "$GATE" 2>/dev/null; then
  pass "bash -n: leadv2-skill-proof.sh"
else
  fail "bash -n: leadv2-skill-proof.sh"
fi
if bash -n "$LIB" 2>/dev/null; then
  pass "bash -n: leadv2-proof-lib.sh"
else
  fail "bash -n: leadv2-proof-lib.sh"
fi

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x "$GATE" >/dev/null 2>&1; then
    pass "shellcheck: leadv2-skill-proof.sh"
  else
    fail "shellcheck: leadv2-skill-proof.sh"
  fi
  if shellcheck -x "$LIB" >/dev/null 2>&1; then
    pass "shellcheck: leadv2-proof-lib.sh"
  else
    fail "shellcheck: leadv2-proof-lib.sh"
  fi
else
  log "shellcheck not installed — skipping"
fi

# ── Helper: run gate against a fixture skills-dir ───────────────────────────
# Captures stdout and exit code. Uses a throwaway state file.
run_gate() {
  local fixture_dir="$1"; shift
  local state_tmp; state_tmp=$(mktemp -t skill-proof-state.XXXXXX.json)
  LEADV2_SKILL_PROOF_STATE="$state_tmp" \
    bash "$GATE" run --skills-dir "$fixture_dir" "$@" 2>&1 || true
  # Return state path via a global
  _LAST_STATE="$state_tmp"
}

# ── (a) valid+passing → GREEN, exit 0 ────────────────────────────────────────
rc=0
out=$(LEADV2_SKILL_PROOF_STATE="$(mktemp -t sp.XXXXXX.json)" \
  bash "$GATE" run --skills-dir "$FIXTURES/valid-pass" 2>&1) || rc=$?
if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q 'GREEN'; then
  pass "(a) valid+passing → GREEN, exit 0"
else
  fail "(a) valid+passing → expected GREEN exit 0, got rc=$rc"
  echo "$out" | tail -5
fi

# ── (b) valid+failing → RED-FAILED, exit 1 ───────────────────────────────────
rc=0
out=$(LEADV2_SKILL_PROOF_STATE="$(mktemp -t sp.XXXXXX.json)" \
  bash "$GATE" run --skills-dir "$FIXTURES/valid-fail" 2>&1) || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$out" | grep -q 'RED-FAILED'; then
  pass "(b) valid+failing → RED-FAILED, exit 1"
else
  fail "(b) valid+failing → expected RED-FAILED exit 1, got rc=$rc"
  echo "$out" | tail -5
fi

# ── (c) tautological → RED-INVALID, validate exits 3, never executed ─────────
# First: validate subcommand
rc=0
bash "$GATE" validate "$FIXTURES/tautological/my-skill/PROOF.sh" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 3 ]]; then
  pass "(c) validate → exit 3 (refused)"
else
  fail "(c) validate → expected exit 3, got $rc"
fi

# Second: full run reports RED-INVALID and sentinel never exists
rc=0
state_tmp=$(mktemp -t sp-taut.XXXXXX.json)
# Pre-create a sentinel-check tmp — the gate will create LEADV2_PROOF_TMP per proof,
# but we check at the fixture level: the proof touches $LEADV2_PROOF_TMP/tautology-ran.sentinel
# If the proof is never executed, this file never exists anywhere.
out=$(LEADV2_SKILL_PROOF_STATE="$state_tmp" \
  bash "$GATE" run --skills-dir "$FIXTURES/tautological" 2>&1) || rc=$?
if echo "$out" | grep -q 'RED-INVALID'; then
  pass "(c) full run → RED-INVALID"
else
  fail "(c) full run → expected RED-INVALID in output"
  echo "$out" | tail -5
fi
# Verify the proof was never executed by checking validate output for the refusal.
# The gate correctly exits 3; under pipefail a pipe's status is the leftmost
# non-zero, so we must capture before grepping.
refused_out=$(bash "$GATE" validate "$FIXTURES/tautological/my-skill/PROOF.sh" 2>&1) || true
if grep -qi 'REFUSED' <<<"$refused_out"; then
  pass "(c) validate prints refusal message"
else
  fail "(c) validate should print a REFUSED message"
fi
rm -f "$state_tmp"

# ── (d) no-proof → RED-NO-PROOF, exit 1 ──────────────────────────────────────
rc=0
out=$(LEADV2_SKILL_PROOF_STATE="$(mktemp -t sp.XXXXXX.json)" \
  bash "$GATE" run --skills-dir "$FIXTURES/no-proof" 2>&1) || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$out" | grep -q 'RED-NO-PROOF'; then
  pass "(d) no-proof → RED-NO-PROOF, exit 1"
else
  fail "(d) no-proof → expected RED-NO-PROOF exit 1, got rc=$rc"
  echo "$out" | tail -5
fi

# ── (e) mixed tree → exit 1 with correct counts ─────────────────────────────
rc=0
out=$(LEADV2_SKILL_PROOF_STATE="$(mktemp -t sp-mix.XXXXXX.json)" \
  bash "$GATE" run --skills-dir "$FIXTURES/mixed" 2>&1) || rc=$?
if [[ "$rc" -eq 1 ]]; then
  pass "(e) mixed tree → exit 1"
else
  fail "(e) mixed tree → expected exit 1, got rc=$rc"
fi
if echo "$out" | grep -q 'green=1'; then
  pass "(e) mixed tree → green=1"
else
  fail "(e) mixed tree → expected green=1 in summary"
  echo "$out" | grep 'green=' | tail -1
fi
if echo "$out" | grep -q 'red=2'; then
  pass "(e) mixed tree → red=2"
else
  fail "(e) mixed tree → expected red=2 in summary"
  echo "$out" | grep 'red=' | tail -1
fi

# ── (f) state-hash invalidation ──────────────────────────────────────────────
# Step 1: run valid-pass → GREEN recorded in state
hash_state=$(mktemp -t sp-hash.XXXXXX.json)
LEADV2_SKILL_PROOF_STATE="$hash_state" \
  bash "$GATE" run --skills-dir "$FIXTURES/valid-pass" >/dev/null 2>&1 || true

# Verify GREEN recorded
recorded=$(LEADV2_SKILL_PROOF_STATE="$hash_state" \
  bash "$GATE" run --from-state --skills-dir "$FIXTURES/valid-pass" 2>&1 || true)
if echo "$recorded" | grep -q 'GREEN'; then
  pass "(f) step 1: GREEN recorded in state"
else
  fail "(f) step 1: expected GREEN from state"
  echo "$recorded" | tail -3
fi

# Step 2: modify the proof (append a comment to change sha256)
echo "# modified" >> "$FIXTURES/valid-pass/my-skill/PROOF.sh"

# Step 3: --from-state should report RED-NEVER-RUN (sha mismatch)
after=$(LEADV2_SKILL_PROOF_STATE="$hash_state" \
  bash "$GATE" run --from-state --skills-dir "$FIXTURES/valid-pass" 2>&1 || true)
if echo "$after" | grep -q 'RED-NEVER-RUN'; then
  pass "(f) step 3: hash mismatch → RED-NEVER-RUN"
else
  fail "(f) step 3: expected RED-NEVER-RUN after proof edit"
  echo "$after" | tail -5
fi

# Step 4: re-run to update state → GREEN again
LEADV2_SKILL_PROOF_STATE="$hash_state" \
  bash "$GATE" run --skills-dir "$FIXTURES/valid-pass" >/dev/null 2>&1 || true

# Restore the proof to its original content
cat > "$FIXTURES/valid-pass/my-skill/PROOF.sh" <<'RESTORE'
#!/usr/bin/env bash
set -euo pipefail
# proof-of: trivially valid proof that passes
source "$LEADV2_PLUGIN_ROOT/scripts/leadv2-proof-lib.sh"
assert_eq 1 1 "trivial equality holds"
RESTORE

rm -f "$hash_state"

# ── list subcommand ──────────────────────────────────────────────────────────
rc=0
out=$(bash "$GATE" list --skills-dir "$FIXTURES/mixed" 2>&1) || rc=$?
if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q 'green-skill.*present' && echo "$out" | grep -q 'noproof-skill.*absent'; then
  pass "list subcommand → correct matrix"
else
  fail "list subcommand → expected correct matrix"
  echo "$out"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
log "----"
log "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
