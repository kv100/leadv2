#!/usr/bin/env bash
# test-red-proof-gate.sh — DISPATCH-CLOSE-GATE-01 Mechanism 2 unit coverage for
# lib/leadv2-red-proof.sh (named-fix extraction, RED-artifact backing) and the
# leadv2-dispatch-code.sh `close-gate` CLI entry point.
#
# Negative control (mutation-proven, see bottom): the nonzero-failure-count requirement in
# leadv2_red_proof_has_red is mutated on a temp copy of the lib so it accepts a "0 failed"
# artifact, and the suite asserts the relevant test goes red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../lib/leadv2-red-proof.sh"
DISPATCH_SH="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
LANE_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
# shellcheck disable=SC1090
source "${LIB}"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

FIXTURE_DIR="${LANE_ROOT}/docs/handoff/DISPATCH-CLOSE-GATE-01/redproof-fixture-$$"
mkdir -p "${FIXTURE_DIR}/red"
trap 'rm -rf "${FIXTURE_DIR}"' EXIT

cat > "${FIXTURE_DIR}/developer.full.md" <<'EOF'
# Developer report

## [Critical] rank fix reverts silently

The rank fix can be fully reverted with the suite still passing. Fixed by X.

## [High] negated grep never fails

test-dirty-lane-never-lands.sh:89 asserts with `! grep -Fq`, so it never trips under set -e.

DELIVERABLE_COMPLETE
EOF

# backing RED artifact for the Critical fix only
cat > "${FIXTURE_DIR}/red/critical-rank-fix.log" <<'EOF'
mutation: reverted the rank fix
fix: rank fix reverts silently
result: 3 failed, 12 passed
EOF

# ── extraction: both named fixes found ──────────────────────────────────────────
names="$(leadv2_red_proof_named_fixes "${FIXTURE_DIR}")"
printf '%s\n' "${names}" | grep -qF 'rank fix reverts silently' \
  && pass "named_fixes: Critical heading extracted" || fail "named_fixes: missing Critical: ${names}"
printf '%s\n' "${names}" | grep -qF 'negated grep never fails' \
  && pass "named_fixes: High heading extracted" || fail "named_fixes: missing High: ${names}"

# ── has_red: backed fix returns 0 ──────────────────────────────────────────────
leadv2_red_proof_has_red "${FIXTURE_DIR}" "rank fix reverts silently" \
  && pass "has_red: backed Critical fix satisfied" || fail "has_red: backed fix wrongly unproven"

# ── has_red: unbacked fix returns 1 ─────────────────────────────────────────────
if leadv2_red_proof_has_red "${FIXTURE_DIR}" "negated grep never fails"; then
  fail "has_red: unbacked High fix wrongly satisfied"
else
  pass "has_red: unbacked High fix correctly unproven"
fi

# ── unproven: exactly one name, the unbacked one ────────────────────────────────
unproven="$(leadv2_red_proof_unproven "${FIXTURE_DIR}")"
unproven_count="$(printf '%s\n' "${unproven}" | grep -c '^unproven: ' || true)"
[[ "${unproven_count}" -eq 1 ]] && pass "unproven: exactly one unproven line" || fail "unproven: expected 1 got ${unproven_count}: ${unproven}"
printf '%s\n' "${unproven}" | grep -qF 'unproven: negated grep never fails' \
  && pass "unproven: names the correct fix" || fail "unproven: wrong content: ${unproven}"
printf '%s\n' "${unproven}" | grep -qF 'unproven: rank fix reverts silently' \
  && fail "unproven: wrongly flagged the backed fix" || pass "unproven: backed fix not flagged"

# ── "0 failed" artifact does not satisfy its fix ────────────────────────────────
ZERO_DIR="${FIXTURE_DIR}-zero"
mkdir -p "${ZERO_DIR}/red"
trap 'rm -rf "${FIXTURE_DIR}" "${ZERO_DIR}"' EXIT
cat > "${ZERO_DIR}/developer.full.md" <<'EOF'
## [Critical] empty control

Claims a fix but the run shows 0 failed.

DELIVERABLE_COMPLETE
EOF
cat > "${ZERO_DIR}/red/empty-control.log" <<'EOF'
mutation: applied to the function body
fix: empty control
result: 0 failed, 9 passed
EOF
if leadv2_red_proof_has_red "${ZERO_DIR}" "empty control"; then
  fail "has_red: a '0 failed' artifact wrongly satisfied its fix"
else
  pass "has_red: a '0 failed' artifact correctly does not satisfy its fix"
fi

# ── CLI: close-gate reports the unproven fix by name ────────────────────────────
task_rel="DISPATCH-CLOSE-GATE-01/redproof-fixture-$$"
out="$(cd "${LANE_ROOT}" && bash "${DISPATCH_SH}" close-gate "${task_rel}" 2>&1)"; rc=$?
[[ ${rc} -eq 0 ]] && printf '%s' "${out}" | grep -qF 'unproven: negated grep never fails' \
  && pass "CLI: close-gate reports unproven finding (never blocks -- rc=0)" \
  || fail "CLI: close-gate rc=${rc} out=${out}"

# ── C1 negative control: nonzero-failure requirement mutated out -> '0 failed' passes ──
TMP="$(mktemp -d "${TMPDIR:-/tmp}/red-proof-test.XXXXXX")"
trap 'rm -rf "${FIXTURE_DIR}" "${ZERO_DIR}" "${TMP}"' EXIT
MUT_LIB="${TMP}/leadv2-red-proof.mut1.sh"
python3 - "${LIB}" "${MUT_LIB}" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
old = 'grep -qiE \'\\b[1-9][0-9]*[[:space:]]+(test[s]?[[:space:]]+)?(failed|failing)\\b\' "${f}" 2>/dev/null && return 0'
new = 'grep -qiE \'[0-9]+[[:space:]]+(test[s]?[[:space:]]+)?(failed|failing)\\b\' "${f}" 2>/dev/null && return 0'
if old not in text:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYEOF
if [[ $? -ne 0 ]]; then
  fail "control C1: mutation source pattern not found (lib drifted, update mutation)"
else
  (
    # shellcheck disable=SC1090
    source "${MUT_LIB}"
    leadv2_red_proof_has_red "${ZERO_DIR}" "empty control"
  )
  mut_rc=$?
  [[ ${mut_rc} -eq 0 ]] && pass "control C1: mutated lib accepts '0 failed' as backing -> caught (would be red)" \
    || fail "control C1: mutation NOT caught -- nonzero-failure requirement is not actually tested"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
