#!/usr/bin/env bash
# test-mission-writeset.sh — DISPATCH-CLOSE-GATE-01 Mechanism 1 unit coverage for
# lib/leadv2-mission-writeset.sh (required-path extraction, LANE_WRITES coverage) and the
# leadv2-dispatch-code.sh `mission-writeset-check` CLI entry point.
#
# Negative controls (mutation-proven, see bottom): the citation-exclusion in
# leadv2_writeset_extract_required, and the coverage loop in leadv2_writeset_missing, are
# each mutated on a temp copy of the lib and the suite asserts the relevant test goes red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/../lib/leadv2-mission-writeset.sh"
DISPATCH_SH="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
# shellcheck disable=SC1090
source "${LIB}"

PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/mission-writeset-test.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

# ── fixtures ──────────────────────────────────────────────────────────────────
MISSION_REFUSE="$(cat <<'EOF'
# TASK

Some intro text.

## Done means

Leave the RED logs in `docs/handoff/X/round4-red/` and the render proof at
`docs/handoff/X/render-proof.md`.
EOF
)"

MISSION_CITE_ONLY="$(cat <<'EOF'
# TASK

## Context

See the prior report at `docs/handoff/Y/report.md` for background.

## Done means

Per the render proof described in `docs/handoff/Y/report.md`, ship the fix.
EOF
)"

MISSION_INSTR="$(cat <<'EOF'
# TASK

Write the RED artifact to `docs/handoff/Z/red/run1.log` before closing.
Also leave the logs in docs/handoff/Z/other/
EOF
)"

# ── extraction: Done-means backticked paths are required ───────────────────────
req="$(leadv2_writeset_extract_required <<< "${MISSION_REFUSE}")"
printf '%s\n' "${req}" | grep -qF 'docs/handoff/X/round4-red/' \
  && pass "extract: Done-means backtick path captured" || fail "extract: round4-red missing from: ${req}"
printf '%s\n' "${req}" | grep -qF 'docs/handoff/X/render-proof.md' \
  && pass "extract: second Done-means backtick path captured" || fail "extract: render-proof missing"

# ── extraction: a cited-only path is NOT required ───────────────────────────────
req_cite="$(leadv2_writeset_extract_required <<< "${MISSION_CITE_ONLY}")"
[[ -z "${req_cite}" ]] \
  && pass "extract: citation-only path excluded (see/described in)" || fail "extract: cite leaked into required: ${req_cite}"

# ── extraction: write/leave-the-logs instructions anywhere in the mission ──────
req_instr="$(leadv2_writeset_extract_required <<< "${MISSION_INSTR}")"
printf '%s\n' "${req_instr}" | grep -qF 'docs/handoff/Z/red/run1.log' \
  && pass "extract: 'write ... to' instruction captured" || fail "extract: write-to missing: ${req_instr}"
printf '%s\n' "${req_instr}" | grep -qF 'docs/handoff/Z/other/' \
  && pass "extract: 'leave the logs in' instruction captured" || fail "extract: leave-logs missing: ${req_instr}"

# ── missing: uncovered LANE_WRITES refuses, naming the exact path ──────────────
missing="$(leadv2_writeset_missing "plugins/leadv2/scripts/foo.sh" <<< "${MISSION_REFUSE}")"
printf '%s\n' "${missing}" | grep -qF 'docs/handoff/X/round4-red/' \
  && pass "missing: uncovered path named" || fail "missing: round4-red not reported: ${missing}"

# ── missing: cited-only mission dispatches normally (nothing missing) ──────────
missing_cite="$(leadv2_writeset_missing "plugins/leadv2/scripts/foo.sh" <<< "${MISSION_CITE_ONLY}")"
[[ -z "${missing_cite}" ]] \
  && pass "missing: citation-only mission has nothing missing" || fail "missing: cite-only wrongly refused: ${missing_cite}"

# ── missing: directory-prefix coverage ──────────────────────────────────────────
missing_covered="$(leadv2_writeset_missing "docs/handoff/X/" <<< "${MISSION_REFUSE}")"
[[ -z "${missing_covered}" ]] \
  && pass "missing: directory-prefix LANE_WRITES covers nested Done-means paths" \
  || fail "missing: dir-prefix coverage failed: ${missing_covered}"

# ── missing: glob coverage ───────────────────────────────────────────────────────
missing_glob="$(leadv2_writeset_missing "docs/handoff/X/*" <<< "${MISSION_REFUSE}")"
[[ -z "${missing_glob}" ]] \
  && pass "missing: glob LANE_WRITES covers Done-means paths" || fail "missing: glob coverage failed: ${missing_glob}"

# ── suggest line ──────────────────────────────────────────────────────────────
suggested="$(printf '%s\n' "${missing}" | leadv2_writeset_suggest_line "plugins/leadv2/scripts/foo.sh")"
printf '%s' "${suggested}" | grep -qF 'LANE_WRITES: plugins/leadv2/scripts/foo.sh,docs/handoff/X/round4-red/' \
  && pass "suggest_line: appends missing paths to existing LANE_WRITES" || fail "suggest_line: got '${suggested}'"

# ── CLI: mission-writeset-check exit codes (the mission's stated Control) ──────
MFILE="${TMP}/mission-refuse.md"; printf '%s\n' "${MISSION_REFUSE}" > "${MFILE}"
out="$(bash "${DISPATCH_SH}" mission-writeset-check "${MFILE}" "plugins/leadv2/scripts/foo.sh" 2>&1)"; rc=$?
[[ ${rc} -ne 0 ]] && printf '%s' "${out}" | grep -qF 'docs/handoff/X/round4-red/' \
  && pass "CLI: refuses with exit non-zero and names the missing path" \
  || fail "CLI: refuse case rc=${rc} out=${out}"

MFILE_CITE="${TMP}/mission-cite.md"; printf '%s\n' "${MISSION_CITE_ONLY}" > "${MFILE_CITE}"
out2="$(bash "${DISPATCH_SH}" mission-writeset-check "${MFILE_CITE}" "plugins/leadv2/scripts/foo.sh" 2>&1)"; rc2=$?
[[ ${rc2} -eq 0 ]] \
  && pass "CLI: a citation-only mission dispatches normally (exit 0)" || fail "CLI: cite-only case rc=${rc2} out=${out2}"

# ── C1 negative control: citation exclusion mutated out -> extraction test goes red ─
MUT_LIB="${TMP}/leadv2-mission-writeset.mut1.sh"
python3 - "${LIB}" "${MUT_LIB}" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
old = "            if citation_re.search(prefix):\n                continue\n"
if old not in text:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(text.replace(old, "", 1))
PYEOF
if [[ $? -ne 0 ]]; then
  fail "control C1: mutation source pattern not found (lib drifted, update mutation)"
else
  (
    # shellcheck disable=SC1090
    source "${MUT_LIB}"
    r="$(leadv2_writeset_extract_required <<< "${MISSION_CITE_ONLY}")"
    [[ -z "${r}" ]] && exit 0 || exit 1
  )
  mut_rc=$?
  [[ ${mut_rc} -ne 0 ]] && pass "control C1: mutated lib leaks citation path into required -> caught (would be red)" \
    || fail "control C1: mutation NOT caught -- citation exclusion is not actually tested"
fi

# ── C2 negative control: coverage loop defeated -> missing-path detection goes red ──
MUT_LIB2="${TMP}/leadv2-mission-writeset.mut2.sh"
python3 - "${LIB}" "${MUT_LIB2}" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
old = '    hit=0\n    for decl in "${decls[@]}"; do'
new = '    hit=0; hit=1\n    for decl in "${decls[@]}"; do'
if old not in text:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYEOF
if [[ $? -ne 0 ]]; then
  fail "control C2: mutation source pattern not found (lib drifted, update mutation)"
else
  (
    # shellcheck disable=SC1090
    source "${MUT_LIB2}"
    m="$(leadv2_writeset_missing "plugins/leadv2/scripts/foo.sh" <<< "${MISSION_REFUSE}")"
    [[ -n "${m}" ]] && exit 0 || exit 1
  )
  mut_rc2=$?
  [[ ${mut_rc2} -ne 0 ]] && pass "control C2: mutated lib always reports covered -> caught (would be red)" \
    || fail "control C2: mutation NOT caught -- missing-path detection is not actually tested"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
