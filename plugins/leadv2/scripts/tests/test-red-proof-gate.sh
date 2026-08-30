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

# ── L1: task_id path traversal / absolute-path injection is rejected ───────────────
out_l1a="$(cd "${LANE_ROOT}" && bash "${DISPATCH_SH}" close-gate "/etc/passwd" 2>&1)"; rc_l1a=$?
[[ ${rc_l1a} -ne 0 ]] && pass "L1: leading-/ task_id rejected" || fail "L1: leading-/ task_id NOT rejected: rc=${rc_l1a} out=${out_l1a}"
out_l1b="$(cd "${LANE_ROOT}" && bash "${DISPATCH_SH}" close-gate "../../etc/passwd" 2>&1)"; rc_l1b=$?
[[ ${rc_l1b} -ne 0 ]] && pass "L1: .. task_id rejected" || fail "L1: .. task_id NOT rejected: rc=${rc_l1b} out=${out_l1b}"

# ── C5 wiring: leadv2-dispatch-product-close.sh's PASS-branch block, extracted and RUN ──
# DISPATCH-CLOSE-GATE-01 review round 1, C5: this mechanism had zero callers on the live
# close path. leadv2-dispatch-product-close.sh is the only live close gate and is a
# multi-thousand-line procedural script that assumes a live review-gate/handoff/reviewer-
# arm environment far beyond a unit test's reach end-to-end (documented precedent:
# test-close-chain.sh's own scope note, same file). This instead slices out the exact
# production block between its two anchor comments and RUNS it against a fixture HANDOFF
# dir with a stubbed emit() -- the real lines execute, not a reimplementation.
_extract_c5_block() { # <src_file> -> stdout: the block, or empty + rc2 if anchors missing
  awk '
    /# C5-BLOCK-BEGIN/ { grab=1 }
    grab { print }
    grab && /# C5-BLOCK-END/ { exit }
  ' "$1"
}
c5_block="$(_extract_c5_block "${PRODUCT_CLOSE_SH}")"
if [[ -z "${c5_block}" ]] || ! printf '%s' "${c5_block}" | grep -qF 'leadv2_red_proof_unproven "${_pc_redproof_dir}"'; then
  fail "C5 wiring: block anchors not found in leadv2-dispatch-product-close.sh (drifted, update extractor)"
else
  c5_out="$(
    # shellcheck disable=SC1090
    source "${LIB}"
    emit() { :; }
    ROOT="${LANE_ROOT}"
    HANDOFF="${FIXTURE_DIR}"
    FOUNDER_TASK_ID=""
    LANE_NAME=""
    TASK="wiretest"
    eval "${c5_block}"
    printf 'SUFFIX:%s\n' "${_pc_unproven_suffix}"
    printf 'NOTE:%s\n' "$(_pc_evidence_with_unproven "diff=abc123")"
  )"
  printf '%s' "${c5_out}" | grep -qF 'unproven: negated grep never fails' \
    && printf '%s' "${c5_out}" | grep -qF 'SUFFIX: unproven=negated grep never fails' \
    && pass "C5 wiring: product-close's real PASS-branch block prints + suffixes the unproven finding" \
    || fail "C5 wiring: block ran but did not surface the unproven finding: ${c5_out}"

  # ── behavioural control on the RENDERED close note (round-3 finding): the five real
  # `_dl_note` call sites all route through `_pc_evidence_with_unproven` now instead of
  # each spelling out `...${_pc_unproven_suffix}` -- this asserts what the founder would
  # actually SEE in a terminal note, not just that the internal suffix variable got set.
  printf '%s' "${c5_out}" | grep -qF 'NOTE:diff=abc123 unproven=negated grep never fails' \
    && pass "C5 wiring: rendered close note (via _pc_evidence_with_unproven) carries the unproven suffix" \
    || fail "C5 wiring: rendered close note missing the suffix: ${c5_out}"

  # negative control: delete the one call site from a scratch copy -> block goes inert
  MUT_PC="${TMP}/leadv2-dispatch-product-close.mut1.sh"
  python3 - "${PRODUCT_CLOSE_SH}" "${MUT_PC}" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
old = '_pc_unproven="$(leadv2_red_proof_unproven "${_pc_redproof_dir}")"\n'
if text.count(old) != 1:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(text.replace(old, '_pc_unproven=""\n', 1))
PYEOF
  mut_pc_rc=$?
  if [[ ${mut_pc_rc} -ne 0 ]]; then
    fail "control C5-wiring: mutation source pattern not found (product-close drifted, update mutation)"
  else
    mut_c5_block="$(_extract_c5_block "${MUT_PC}")"
    mut_c5_out="$(
      # shellcheck disable=SC1090
      source "${LIB}"
      emit() { :; }
      ROOT="${LANE_ROOT}"
      HANDOFF="${FIXTURE_DIR}"
      FOUNDER_TASK_ID=""
      LANE_NAME=""
      TASK="wiretest"
      eval "${mut_c5_block}"
      printf 'SUFFIX:%s\n' "${_pc_unproven_suffix}"
    )"
    printf '%s' "${mut_c5_out}" | grep -qF 'SUFFIX:' && ! printf '%s' "${mut_c5_out}" | grep -qF 'unproven=' \
      && pass "control C5-wiring: call site removed -> block no longer surfaces the finding (caught, would be red)" \
      || fail "control C5-wiring: mutation NOT caught: ${mut_c5_out}"
    rm -f "${MUT_PC}"
  fi

  # ── C5-note negative control: strip the suffix append INSIDE _pc_evidence_with_unproven
  # itself (the exact mutation the review demanded: "removing all five interpolations" is
  # now equivalent to removing this one append) -> the rendered note goes red ──
  MUT_NOTE="${TMP}/leadv2-dispatch-product-close.mut2.sh"
  python3 - "${PRODUCT_CLOSE_SH}" "${MUT_NOTE}" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
old = "_pc_evidence_with_unproven() {\n  printf '%s%s' \"$1\" \"${_pc_unproven_suffix}\"\n}\n"
if text.count(old) != 1:
    sys.exit(2)
new = "_pc_evidence_with_unproven() {\n  printf '%s' \"$1\"\n}\n"
open(dst, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYEOF
  mut_note_rc=$?
  if [[ ${mut_note_rc} -ne 0 ]]; then
    fail "control C5-note: mutation source pattern not found (helper drifted, update mutation)"
  else
    mut_note_block="$(_extract_c5_block "${MUT_NOTE}")"
    mut_note_out="$(
      # shellcheck disable=SC1090
      source "${LIB}"
      emit() { :; }
      ROOT="${LANE_ROOT}"
      HANDOFF="${FIXTURE_DIR}"
      FOUNDER_TASK_ID=""
      LANE_NAME=""
      TASK="wiretest"
      eval "${mut_note_block}"
      printf 'NOTE:%s\n' "$(_pc_evidence_with_unproven "diff=abc123")"
    )"
    printf '%s' "${mut_note_out}" | grep -qxF 'NOTE:diff=abc123' \
      && pass "control C5-note: suffix append removed from the render helper -> note loses it (caught, would be red)" \
      || fail "control C5-note: mutation NOT caught -- rendered note still carries the suffix: ${mut_note_out}"
    rm -f "${MUT_NOTE}"
  fi
fi

printf 'SUMMARY: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
