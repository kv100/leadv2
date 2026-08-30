#!/usr/bin/env bash
# test-mission-writeset.sh — DISPATCH-CLOSE-GATE-01 Mechanism 1 unit coverage for
# lib/leadv2-mission-writeset.sh (required-path extraction, LANE_WRITES coverage) and the
# leadv2-dispatch-code.sh `mission-writeset-check` CLI entry point.
#
# Negative controls (mutation-proven): the citation-exclusion in
# leadv2_writeset_extract_required, the coverage loop in leadv2_writeset_missing, and all
# three live `_mission_writeset_guard` call sites in leadv2-dispatch-code.sh are each
# mutated (lib on a temp copy; the dispatcher via a symlink-populated scratch dir, single-
# source rule preserved) and the suite asserts the relevant test goes red.
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
PROJECT_ROOT_FOR_TEST="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

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
Leave the RED logs in `docs/handoff/Z/other/`.
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

# control CITE: citation-exclusion mutated out of leadv2_writeset_extract_required -> caught
MUT_LIB="${TMP}/leadv2-mission-writeset.mut1.sh"
python3 - "${LIB}" "${MUT_LIB}" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
old = "    if citation_re.search(prefix):\n        return\n"
if old not in text:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(text.replace(old, "", 1))
PYEOF
if [[ $? -ne 0 ]]; then
  fail "control CITE: mutation source pattern not found (lib drifted, update mutation)"
else
  (
    # shellcheck disable=SC1090
    source "${MUT_LIB}"
    r="$(leadv2_writeset_extract_required <<< "${MISSION_CITE_ONLY}")"
    [[ -z "${r}" ]] && exit 0 || exit 1
  )
  mut_rc=$?
  [[ ${mut_rc} -ne 0 ]] && pass "control CITE: mutated lib leaks citation path into required -> caught (would be red)" \
    || fail "control CITE: mutation NOT caught -- citation exclusion is not actually tested"
fi

# control COVERAGE: coverage loop in leadv2_writeset_missing defeated -> caught
MUT_LIB2="${TMP}/leadv2-mission-writeset.mut2.sh"
python3 - "${LIB}" "${MUT_LIB2}" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
old = '    for decl in ${decls[@]+"${decls[@]}"}; do'
new = '    hit=1\n    for decl in ${decls[@]+"${decls[@]}"}; do'
if old not in text:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYEOF
if [[ $? -ne 0 ]]; then
  fail "control COVERAGE: mutation source pattern not found (lib drifted, update mutation)"
else
  (
    # shellcheck disable=SC1090
    source "${MUT_LIB2}"
    m="$(leadv2_writeset_missing "plugins/leadv2/scripts/foo.sh" <<< "${MISSION_REFUSE}")"
    [[ -n "${m}" ]] && exit 0 || exit 1
  )
  mut_rc2=$?
  [[ ${mut_rc2} -ne 0 ]] && pass "control COVERAGE: mutated lib always reports covered -> caught (would be red)" \
    || fail "control COVERAGE: mutation NOT caught -- missing-path detection is not actually tested"
fi

# C1: consumer repositories install this entrypoint as a single-file symlink. The
# symlink directory intentionally has no lib/ sibling; canonical fallback must load both
# new libraries before the real CLI can start.
CONSUMER_SCRIPTS="${TMP}/consumer/.claude/scripts"
mkdir -p "${CONSUMER_SCRIPTS}"
ln -s "${DISPATCH_SH}" "${CONSUMER_SCRIPTS}/leadv2-dispatch-code.sh"
consumer_out="$(cd "${TMP}/consumer" && LEADV2_CANONICAL_ROOT="${PROJECT_ROOT_FOR_TEST}" bash ".claude/scripts/leadv2-dispatch-code.sh" mission-writeset-check "${MFILE_CITE}" "plugins/leadv2/scripts/foo.sh" 2>&1)"; consumer_rc=$?
[[ ${consumer_rc} -eq 0 ]] \
  && pass "C1: per-file consumer symlink starts with canonical mission/red-proof libraries" \
  || fail "C1: consumer symlink startup failed rc=${consumer_rc} out=${consumer_out}"

# C4: extraction precision remains below the enable-by-default bar, so the production
# rollout is intentionally opt-in. This reads the dispatcher's live effective default.
default_out="$(LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="${PROJECT_ROOT_FOR_TEST}" bash -c 'source "$1"; printf "%s" "$REQUIRE_MISSION_WRITESET"' _ "${DISPATCH_SH}" 2>&1)"; default_rc=$?
[[ ${default_rc} -eq 0 && "${default_out}" == "0" ]] \
  && pass "C4: mission writeset enforcement defaults to opt-in (0)" \
  || fail "C4: expected default 0 rc=${default_rc} out=${default_out}"

# ── C1 wiring control: architect_prepass itself, not just the lib/CLI, must refuse ──────
# DISPATCH-CLOSE-GATE-01 review round 1, C1: deleting all three `_mission_writeset_guard`
# call sites in architect_prepass left this suite green (pass=14 fail=0) because every
# assertion above only exercises the lib functions and the standalone CLI subcommand,
# neither of which is on the live dispatch path. This drives architect_prepass itself
# (LEADV2_DISPATCH_SOURCE_ONLY=1 lets the dispatcher be sourced instead of run as a CLI)
# with a mission that names a path outside LANE_WRITES, on the kill-switch branch
# (ARCHITECT_GATE=0) which is the cheapest real call site to exercise end-to-end.
_run_prepass_refusal() { # <dispatch_script_path> -> stdout=combined output; exit=architect_prepass rc
  local dsh="$1"
  LEADV2_DISPATCH_SOURCE_ONLY=1 LEADV2_REQUIRE_MISSION_WRITESET=1 PROJECT_ROOT="${PROJECT_ROOT_FOR_TEST}" \
  CLAUDE_PROJECT_ROOT="${PROJECT_ROOT_FOR_TEST}" \
  bash -c '
    set -uo pipefail
    # shellcheck disable=SC1090
    source "$1"
    export ARCHITECT_GATE=0
    architect_prepass "$2" "wiretest8" "plugins/leadv2/scripts/foo.sh"
    exit $?
  ' _ "${dsh}" "${MISSION_REFUSE}" 2>&1
  return $?
}
wire_out="$(_run_prepass_refusal "${DISPATCH_SH}")"; wire_rc=$?
[[ ${wire_rc} -ne 0 ]] && printf '%s' "${wire_out}" | grep -qF 'mission_writeset_refused' \
  && pass "wiring: architect_prepass itself refuses a non-covering mission" \
  || fail "wiring: architect_prepass rc=${wire_rc} out=${wire_out}"

# control WIRING: remove all 3 live call sites -> the wiring test above goes red ──
# Mutant must still resolve sibling libs the same way the real dispatcher does (SCRIPT_DIR
# derived from its own BASH_SOURCE) without ever placing a real file inside the production
# scripts dir (single-source rule) -- so a scratch dir is populated with symlinks to every
# real sibling entry, and only the mutated dispatcher file itself is a real file, under TMP.
MUT_REAL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MUT_DIR="${TMP}/mission-writeset-mut"
mkdir -p "${MUT_DIR}"
for _mut_entry in "${MUT_REAL_DIR}"/*; do
  _mut_base="$(basename "${_mut_entry}")"
  [[ "${_mut_base}" == "leadv2-dispatch-code.sh" ]] && continue
  ln -s "${_mut_entry}" "${MUT_DIR}/${_mut_base}"
done
MUT_DISPATCH="${MUT_DIR}/leadv2-dispatch-code.sh"
python3 - "${DISPATCH_SH}" "${MUT_DISPATCH}" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
site1 = '    _mission_writeset_guard "${sig8}" "${writes}" "${raw}" || return 1\n'
n1 = text.count(site1)
if n1 != 2:
    sys.exit(2)
text = text.replace(site1, "", 2)
site2 = 'if ! _lane_writes_guard "${sig8}" "${writes}" 1 || ! _mission_writeset_guard "${sig8}" "${writes}" "${raw}" || ! _acceptance_guard "${sig8}" "${f}"; then'
if site2 not in text:
    sys.exit(3)
text = text.replace(
    site2,
    'if ! _lane_writes_guard "${sig8}" "${writes}" 1 || ! _acceptance_guard "${sig8}" "${f}"; then',
    1,
)
open(dst, "w", encoding="utf-8").write(text)
PYEOF
mut_prep_rc=$?
if [[ ${mut_prep_rc} -ne 0 ]]; then
  fail "control WIRING: mutation source pattern not found (dispatcher drifted, update mutation, rc=${mut_prep_rc})"
else
  mut_wire_out="$(_run_prepass_refusal "${MUT_DISPATCH}")"; mut_wire_rc=$?
  [[ ${mut_wire_rc} -eq 0 ]] \
    && pass "control WIRING: removing all 3 call sites -> architect_prepass no longer refuses (caught, would be red)" \
    || fail "control WIRING: mutation NOT caught -- wiring test still refuses without the call sites: ${mut_wire_out}"
fi

# ── real on-disk specimens (C2/C3): the fixtures ARE the test, not a hand-fitted string ──
SPECIMEN_DIR="${SCRIPT_DIR}/../../../../docs/handoff/DISPATCH-CLOSE-GATE-01/specimens"
R4="${SPECIMEN_DIR}/fix-round-4.md"
R5="${SPECIMEN_DIR}/fix-round-5.md"

if [[ -f "${R4}" ]]; then
  out_r4="$(bash "${DISPATCH_SH}" mission-writeset-check "${R4}" 2>&1)"; rc_r4=$?
  [[ ${rc_r4} -eq 0 ]] \
    && pass "specimen: fix-round-4.md (real corrected mission) dispatches normally" \
    || fail "specimen: fix-round-4.md wrongly refused rc=${rc_r4} out=${out_r4}"
else
  fail "specimen: docs/handoff/DISPATCH-CLOSE-GATE-01/specimens/fix-round-4.md not found"
fi

if [[ -f "${R5}" ]]; then
  # Reconstructed pre-correction write set: the real round-5 LANE_WRITES minus
  # `lib/leadv2-lane-guard.sh`, which the "Write set note (corrected)" paragraph in the
  # SAME on-disk file says was omitted from the first dispatch. The mission body is
  # untouched -- only the declared csv is rolled back, exactly what the first dispatch saw.
  PRECORRECTION_CSV="plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-ledger.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh,plugins/leadv2/scripts/tests/test-close-chain.sh,plugins/leadv2/scripts/tests/test-t13-slice1.sh,plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh,plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh,plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh,tests/run-all.sh,.gitignore"
  out_r5="$(bash "${DISPATCH_SH}" mission-writeset-check "${R5}" "${PRECORRECTION_CSV}" 2>&1)"; rc_r5=$?
  [[ ${rc_r5} -ne 0 ]] && printf '%s' "${out_r5}" | grep -qF 'lib/leadv2-lane-guard.sh' \
    && pass "specimen: pre-correction fix-round-5.md refused, names lib/leadv2-lane-guard.sh" \
    || fail "specimen: pre-correction fix-round-5.md rc=${rc_r5} out=${out_r5}"
else
  fail "specimen: docs/handoff/DISPATCH-CLOSE-GATE-01/specimens/fix-round-5.md not found"
fi

# ── usage heredoc: no unescaped backticks leaking a spurious "command not found" ──
# DISPATCH-CLOSE-GATE-01 round 6: the unquoted `cat >&2 <<EOF` in usage() ran the literal
# text `when:` as a command substitution (backticks are NOT literal inside an unquoted
# heredoc), printing "when:: command not found" on stderr for every invocation that shows
# usage -- including from consumer repos that only ever see this file. This control asserts
# the specific failure signature is gone. --help intentionally exits 1 (usage error, `S8`
# convention) and its whole body goes to stderr by design, so the control checks for the
# error signature (mutation-proven: reverting the escaping locally reproduces it), not for
# empty stderr.
usage_out="$(bash "${DISPATCH_SH}" --help 2>&1 1>/dev/null)"
if printf '%s' "${usage_out}" | grep -qF 'command not found'; then
  fail "usage: --help stderr contains a spurious command-not-found: ${usage_out}"
else
  pass "usage: --help stderr has no unescaped-backtick command-not-found artifact"
fi
# control: reproduce the bug locally against a copy with the escaping reverted
MUT_DISPATCH_USAGE="${TMP}/leadv2-dispatch-code.usage-mut.sh"
python3 - "${DISPATCH_SH}" "${MUT_DISPATCH_USAGE}" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
old = "\\`when:\\` gate (e.g. freepool's\n                \\`when: [standard, bulk]\\`)"
new = "`when:` gate (e.g. freepool's\n                `when: [standard, bulk]`)"
if old not in text:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(text.replace(old, new, 1))
PYEOF
if [[ $? -ne 0 ]]; then
  fail "control USAGE: mutation source pattern not found (usage heredoc drifted, update mutation)"
else
  mut_usage_out="$(bash "${MUT_DISPATCH_USAGE}" --help 2>&1 1>/dev/null)"
  printf '%s' "${mut_usage_out}" | grep -qF 'command not found' \
    && pass "control USAGE: reverting the backtick escaping reproduces the error -> caught (would be red)" \
    || fail "control USAGE: mutation NOT caught -- unescaped backticks no longer reproduce the failure"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
