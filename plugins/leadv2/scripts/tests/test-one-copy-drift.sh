#!/usr/bin/env bash
# tests/test-one-copy-drift.sh — APPLY-ONE-COPY-01 DoD test for
# leadv2-one-copy-convert.sh --check's category logic.
#
# Runs entirely against a disposable scratch fixture (own shared/canonical
# roots + own exception list), NEVER the real ~/.claude shared trees —
# TEST-DESTROYS-PRODUCTION-SCRIPT-01 containment pattern, same as
# test-statusline-never-writes-executables.sh and test-red-first-gate.sh.
# Only --check is exercised (cmd_apply's precondition_ok requires a real git
# history this fixture doesn't have, and isn't what this test is about).
#
# Run: bash scripts/tests/test-one-copy-drift.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONVERT="${SCRIPT_DIR}/leadv2-one-copy-convert.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

if bash -n "${CONVERT}" 2>/dev/null; then pass "bash -n leadv2-one-copy-convert.sh"; else fail "bash -n leadv2-one-copy-convert.sh"; fi

# mk_fixture -> prints "tmp_root" with:
#   $tmp/shared/leadv2-shared/scripts   (shared root, leaf name matches root_key_for)
#   $tmp/shared/agents-shared           (shared root, leaf name matches root_key_for)
#   $tmp/canonical/scripts              (canonical counterpart for "scripts")
#   $tmp/canonical/agents               (canonical counterpart for "agents")
mk_fixture() {
  local tmp; tmp="$(lv2_mktemp_dir one-copy-fixture)"
  mkdir -p "${tmp}/shared/leadv2-shared/scripts" "${tmp}/shared/agents-shared" \
           "${tmp}/canonical/scripts" "${tmp}/canonical/agents"
  printf '%s' "$tmp"
}

run_check() { # <tmp> -> sets RC, OUT
  local tmp="$1"
  OUT="$(
    LEADV2_ONE_COPY_SCRIPTS_SHARED_ROOT="${tmp}/shared/leadv2-shared/scripts" \
    LEADV2_ONE_COPY_SCRIPTS_CANONICAL_ROOT="${tmp}/canonical/scripts" \
    LEADV2_ONE_COPY_AGENTS_SHARED_ROOT="${tmp}/shared/agents-shared" \
    LEADV2_ONE_COPY_AGENTS_CANONICAL_ROOT="${tmp}/canonical/agents" \
    LEADV2_ONE_COPY_EXCEPTIONS_FILE="${tmp}/exceptions.txt" \
    bash "${CONVERT}" --check 2>&1
  )"
  RC=$?
}

# ── T1: identical real copy -> REGRESSION, exit 1 ────────────────────────
tmp="$(mk_fixture)"
printf 'echo hi\n' > "${tmp}/canonical/scripts/foo.sh"
cp "${tmp}/canonical/scripts/foo.sh" "${tmp}/shared/leadv2-shared/scripts/foo.sh"
run_check "$tmp"
if [[ "$RC" -eq 1 ]] && grep -q 'REGRESSION:.*foo\.sh' <<<"$OUT"; then
  pass "T1 identical real copy -> REGRESSION, exit 1"
else
  fail "T1 identical real copy -> REGRESSION, exit 1 (rc=${RC})"
fi
rm -rf "$tmp"

# ── T2: symlink to canonical -> LINKED, exit 0 ───────────────────────────
tmp="$(mk_fixture)"
printf 'echo hi\n' > "${tmp}/canonical/scripts/foo.sh"
ln -sfn "${tmp}/canonical/scripts/foo.sh" "${tmp}/shared/leadv2-shared/scripts/foo.sh"
run_check "$tmp"
if [[ "$RC" -eq 0 ]] && grep -qE 'tally:.*linked=1 regression=0 badlink=0' <<<"$OUT"; then
  pass "T2 symlink to canonical -> LINKED, exit 0"
else
  fail "T2 symlink to canonical -> LINKED, exit 0 (rc=${RC}) OUT=${OUT}"
fi
rm -rf "$tmp"

# ── T3: divergent real copy, not on exception list -> DIVERGED, exit 0 ───
tmp="$(mk_fixture)"
printf 'echo canonical\n' > "${tmp}/canonical/scripts/foo.sh"
printf 'echo shared-diverged\n' > "${tmp}/shared/leadv2-shared/scripts/foo.sh"
run_check "$tmp"
if [[ "$RC" -eq 0 ]] && grep -q 'DIVERGED:.*foo\.sh' <<<"$OUT"; then
  pass "T3 divergent real copy, not exempted -> DIVERGED, exit 0"
else
  fail "T3 divergent real copy, not exempted -> DIVERGED, exit 0 (rc=${RC})"
fi
rm -rf "$tmp"

# ── T4: divergent real copy, on exception list -> EXPECTED-OVERRIDE, exit 0
tmp="$(mk_fixture)"
printf 'echo canonical\n' > "${tmp}/canonical/scripts/foo.sh"
printf 'echo shared-override\n' > "${tmp}/shared/leadv2-shared/scripts/foo.sh"
printf 'scripts/foo.sh\n' > "${tmp}/exceptions.txt"
run_check "$tmp"
if [[ "$RC" -eq 0 ]] && grep -q 'EXPECTED-OVERRIDE:.*foo\.sh' <<<"$OUT" && ! grep -q 'DIVERGED:' <<<"$OUT"; then
  pass "T4 divergent + declared exception -> EXPECTED-OVERRIDE, exit 0"
else
  fail "T4 divergent + declared exception -> EXPECTED-OVERRIDE, exit 0 (rc=${RC})"
fi
rm -rf "$tmp"

# ── T4b: declared exception, but now IDENTICAL -> STALE-EXCEPTION, still non-gating
tmp="$(mk_fixture)"
printf 'echo same\n' > "${tmp}/canonical/scripts/foo.sh"
cp "${tmp}/canonical/scripts/foo.sh" "${tmp}/shared/leadv2-shared/scripts/foo.sh"
printf 'scripts/foo.sh\n' > "${tmp}/exceptions.txt"
run_check "$tmp"
if [[ "$RC" -eq 0 ]] && grep -q 'STALE-EXCEPTION:' <<<"$OUT"; then
  pass "T4b stale exception (now identical) -> STALE-EXCEPTION, non-gating"
else
  fail "T4b stale exception (now identical) -> STALE-EXCEPTION, non-gating (rc=${RC})"
fi
rm -rf "$tmp"

# ── T5: symlink pointing elsewhere / dangling -> BADLINK, exit 1 ────────
tmp="$(mk_fixture)"
printf 'echo hi\n' > "${tmp}/canonical/scripts/foo.sh"
ln -sfn "${tmp}/canonical/scripts/nonexistent-target.sh" "${tmp}/shared/leadv2-shared/scripts/foo.sh"
run_check "$tmp"
if [[ "$RC" -eq 1 ]] && grep -q 'BADLINK:.*foo\.sh' <<<"$OUT"; then
  pass "T5 dangling/misrouted symlink -> BADLINK, exit 1"
else
  fail "T5 dangling/misrouted symlink -> BADLINK, exit 1 (rc=${RC})"
fi
rm -rf "$tmp"

# ── T6: missing exception file -> WARN, still exit 0 on an otherwise-clean tree
tmp="$(mk_fixture)"
printf 'echo hi\n' > "${tmp}/canonical/scripts/foo.sh"
ln -sfn "${tmp}/canonical/scripts/foo.sh" "${tmp}/shared/leadv2-shared/scripts/foo.sh"
# deliberately do NOT create ${tmp}/exceptions.txt
run_check "$tmp"
if [[ "$RC" -eq 0 ]] && grep -q 'WARN: exception list not found' <<<"$OUT"; then
  pass "T6 missing exception file -> WARN, exit 0 on clean tree"
else
  fail "T6 missing exception file -> WARN, exit 0 on clean tree (rc=${RC})"
fi
rm -rf "$tmp"

log "── ${PASS} passed, ${FAIL} failed ──"
[[ "$FAIL" -eq 0 ]]
