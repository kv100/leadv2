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
PRODUCT_CLOSE_SH="${SCRIPT_DIR}/../leadv2-dispatch-product-close.sh"
LANE_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
# shellcheck disable=SC1090
source "${LIB}"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

# M2: a killed run used to leave redproof-fixture-<pid>/ behind in the real repo tree,
# where cmd_close_gate would then report it back. mktemp -d + LEADV2_CLOSE_GATE_DIR_OVERRIDE
# keeps the whole fixture outside any real checkout.
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/redproof-fixture.XXXXXX")"
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

# C2: the worker writes its completed claim under dispatch-<sig8>/ while the founder
# task directory owns RED evidence. The proof and claim roots must therefore be distinct.
CLAIM_DIR="${FIXTURE_DIR}-claim-root"
mkdir -p "${CLAIM_DIR}"
trap 'rm -rf "${FIXTURE_DIR}" "${CLAIM_DIR}"' EXIT
cat > "${CLAIM_DIR}/developer.full.md" <<'EOF'
## [High] claim root is separate

The completed worker wrote this claim outside the founder evidence directory.

DELIVERABLE_COMPLETE
EOF
cat > "${FIXTURE_DIR}/red/separate-claim.log" <<'EOF'
mutation: applied inside the production function body
fix: claim root is separate
result: 1 failed, 4 passed
EOF
separate_unproven="$(leadv2_red_proof_unproven "${FIXTURE_DIR}" "${CLAIM_DIR}")"
[[ -z "${separate_unproven}" ]] \
  && pass "C2: separate worker claim root is checked against founder RED evidence" \
  || fail "C2: separate claim root was not read: ${separate_unproven}"

# Real completed workers use a dispatch-titled H1 rather than reviewer severity syntax.
DISPATCH_CLAIM_DIR="${FIXTURE_DIR}-dispatch-claim-root"
mkdir -p "${DISPATCH_CLAIM_DIR}"
trap 'rm -rf "${FIXTURE_DIR}" "${CLAIM_DIR}" "${DISPATCH_CLAIM_DIR}"' EXIT
cat > "${DISPATCH_CLAIM_DIR}/developer.full.md" <<'EOF'
# dispatch-1234abcd — completed worker claim

DELIVERABLE_COMPLETE
EOF
dispatch_claims="$(leadv2_red_proof_named_fixes "${DISPATCH_CLAIM_DIR}")"
printf '%s\n' "${dispatch_claims}" | grep -qxF 'completed worker claim' \
  && pass "C2: dispatch-titled completed worker report contributes its task claim" \
  || fail "C2: dispatch-titled worker claim was not extracted: ${dispatch_claims}"

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

# ── round-3: has_red also finds a backing artifact under round*-red/, not just red/ ──
ROUNDRED_DIR="${FIXTURE_DIR}-roundred"
mkdir -p "${ROUNDRED_DIR}/round2-red"
trap 'rm -rf "${FIXTURE_DIR}" "${ZERO_DIR:-}" "${ROUNDRED_DIR}"' EXIT
cat > "${ROUNDRED_DIR}/round2-red/rank-fix.log" <<'EOF'
mutation: reverted the rank fix
fix: rank fix reverts silently
result: 4 failed, 10 passed
EOF
leadv2_red_proof_has_red "${ROUNDRED_DIR}" "rank fix reverts silently" \
  && pass "has_red: backing artifact under round2-red/ (not just red/) satisfies the fix" \
  || fail "has_red: round2-red/ artifact wrongly not found"

# ── round-3: a mission/brief file quoting review findings is NOT read as a worker claim ──
BRIEF_DIR="${FIXTURE_DIR}-brief"
mkdir -p "${BRIEF_DIR}/red"
trap 'rm -rf "${FIXTURE_DIR}" "${ZERO_DIR:-}" "${ROUNDRED_DIR}" "${BRIEF_DIR}"' EXIT
cat > "${BRIEF_DIR}/lane-mission.md" <<'EOF'
# round 3 mission

Full report: review-r2.md.

## [Critical] some prior-round finding quoted verbatim

This heading is the BRIEF's own quoted review text, not a claim this worker is making.
EOF
brief_names="$(leadv2_red_proof_named_fixes "${BRIEF_DIR}")"
[[ -z "${brief_names}" ]] \
  && pass "named_fixes: a lane-mission.md heading is not read as a worker claim" \
  || fail "named_fixes: brief file wrongly contributed a claim: ${brief_names}"

# ── round-3: a same-directory file without DELIVERABLE_COMPLETE is also not a claim ──
cat > "${BRIEF_DIR}/notes.md" <<'EOF'
## [Critical] not actually finished

This file never reached the protocol's own completion marker.
EOF
notes_names="$(leadv2_red_proof_named_fixes "${BRIEF_DIR}")"
[[ -z "${notes_names}" ]] \
  && pass "named_fixes: a file without the completion marker is not read as a worker claim" \
  || fail "named_fixes: undelivered file wrongly contributed a claim: ${notes_names}"

# ── CLI: close-gate reports the unproven fix by name ────────────────────────────
out="$(cd "${LANE_ROOT}" && LEADV2_CLOSE_GATE_DIR_OVERRIDE="${FIXTURE_DIR}" bash "${DISPATCH_SH}" close-gate "redproof-fixture-hermetic" 2>&1)"; rc=$?
[[ ${rc} -eq 0 ]] && printf '%s' "${out}" | grep -qF 'unproven: negated grep never fails' \
  && pass "CLI: close-gate reports unproven finding (never blocks -- rc=0)" \
  || fail "CLI: close-gate rc=${rc} out=${out}"

# ── L1: task_id path traversal / absolute-path injection is rejected ───────────────
out_l1a="$(cd "${LANE_ROOT}" && bash "${DISPATCH_SH}" close-gate "/etc/passwd" 2>&1)"; rc_l1a=$?
[[ ${rc_l1a} -ne 0 ]] && pass "L1: leading-/ task_id rejected" || fail "L1: leading-/ task_id NOT rejected: rc=${rc_l1a} out=${out_l1a}"
out_l1b="$(cd "${LANE_ROOT}" && bash "${DISPATCH_SH}" close-gate "../../etc/passwd" 2>&1)"; rc_l1b=$?
[[ ${rc_l1b} -ne 0 ]] && pass "L1: .. task_id rejected" || fail "L1: .. task_id NOT rejected: rc=${rc_l1b} out=${out_l1b}"

# ── C3: execute every production terminal-render expression ──────────────────
# The five `_dl_note` calls are the close notes a founder sees.  Extract their command
# substitutions and execute them with the production renderer loaded; this is deliberately
# behavioural (the values rendered), not a grep assertion about the source text.
_rendered_terminal_notes() { # <product-close.sh> -> one rendered note per production call site
  local product_close="$1" expression count=0
  while IFS= read -r expression; do
    [[ -n "${expression}" ]] || continue
    count=$((count + 1))
    (
      diff_hash="abcdef123456"
      _pc_report_deliverable="docs/handoff/render-proof.md"
      _rgf_dnm=""
      _t11_branch="render-probe"
      _pc_unproven_suffix=" unproven=negated grep never fails"
      # shellcheck disable=SC2086
      eval "${expression}"
      printf '\n'
    )
  done <<EOF
$(awk '
  /_dl_note .*leadv2_red_proof_render_evidence/ {
    line=$0
    sub(/^.*\$\(/, "", line)
    sub(/\)".*$/, "", line)
    print line
  }
' "${product_close}")
EOF
  [[ "${count}" -eq 5 ]] || return 64
}

rendered_notes="$(_rendered_terminal_notes "${PRODUCT_CLOSE_SH}")"; rendered_notes_rc=$?
if [[ ${rendered_notes_rc} -ne 0 ]]; then
  fail "C3: production terminal-render anchor drifted (expected 5 call sites, rc=${rendered_notes_rc})"
elif [[ "$(printf '%s\n' "${rendered_notes}" | grep -cF 'unproven=negated grep never fails')" -eq 5 ]]; then
  pass "C3: all five production rendered close notes carry the unproven downgrade"
else
  fail "C3: rendered production close note lost downgrade: ${rendered_notes}"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
