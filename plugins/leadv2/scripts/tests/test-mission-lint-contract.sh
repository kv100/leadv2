#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: leadv2-mission-lint
# test-mission-lint-contract.sh — MISSION-LINT-MUST-REFUSE-AN-INCOMPLETE-BRIEF-01.
#
# The approach-heading fixture pair differs only by the heading itself. The
# negative control removes check_decision_complete's body from a scratch copy;
# the no-approach assertion must then go red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LINTER="${SCRIPTS_DIR}/leadv2-mission-lint.sh"

PASS=0
FAIL=0
ERRORS=()
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mission-lint-contract.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

log()  { printf '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); log "FAIL: $1"; }

run_lint() { # <linter> <fixture> <output-file>; prints its exit status
  local linter="$1" fixture="$2" output="$3" rc=0
  bash "$linter" "$fixture" >"$output" 2>&1 || rc=$?
  printf '%s' "$rc"
}

WITHOUT_APPROACH="${TMP}/without-approach.md"
WITH_APPROACH="${TMP}/with-approach.md"
MUTATION_NO_BEHAVIOUR="${TMP}/mutation-no-behaviour.md"

cat >"${WITHOUT_APPROACH}" <<'EOF'
# Brief

Change the linter.
EOF
{
  printf '## Approach\n\n'
  cat "${WITHOUT_APPROACH}"
} >"${WITH_APPROACH}"
cat >"${MUTATION_NO_BEHAVIOUR}" <<'EOF'
# Brief

## Approach

Run a mutation-control negative check.
EOF

if bash -n "${LINTER}"; then
  pass "bash -n: mission linter parses"
else
  fail "bash -n: mission linter does not parse"
fi

OUT_MISSING="${TMP}/missing.out"
rc_missing="$(run_lint "${LINTER}" "${WITHOUT_APPROACH}" "${OUT_MISSING}")"
if [[ "${rc_missing}" == "9" ]] && grep -q 'MISSION_NOT_DECISION_COMPLETE' "${OUT_MISSING}"; then
  pass "no approach heading -> MISSION_NOT_DECISION_COMPLETE, exit 9"
else
  fail "no approach heading -> expected rc=9 and named reason; rc=${rc_missing}; out=$(cat "${OUT_MISSING}")"
fi

OUT_PRESENT="${TMP}/present.out"
rc_present="$(run_lint "${LINTER}" "${WITH_APPROACH}" "${OUT_PRESENT}")"
if [[ "${rc_present}" == "0" ]]; then
  pass "adding only an Approach heading -> exit 0"
else
  fail "adding only an Approach heading -> expected rc=0; rc=${rc_present}; out=$(cat "${OUT_PRESENT}")"
fi

OUT_WARNING="${TMP}/warning.out"
rc_warning="$(run_lint "${LINTER}" "${MUTATION_NO_BEHAVIOUR}" "${OUT_WARNING}")"
if [[ "${rc_warning}" == "0" ]] && grep -q 'MISSION_MUTATION_WITHOUT_BEHAVIOUR' "${OUT_WARNING}"; then
  pass "mutation without behaviour -> warning and exit 0"
else
  fail "mutation without behaviour -> expected warning + rc=0; rc=${rc_warning}; out=$(cat "${OUT_WARNING}")"
fi

# Negative control: remove check A inside its function body. The test's real
# no-approach fixture must now fail because the mutant incorrectly exits 0.
MUT_DIR="${TMP}/mutated-scripts"
mkdir -p "${MUT_DIR}"
for entry in "${SCRIPTS_DIR}"/*; do
  base="$(basename "${entry}")"
  [[ "${base}" == "leadv2-mission-lint.sh" ]] && continue
  ln -s "${entry}" "${MUT_DIR}/${base}"
done
MUT_LINTER="${MUT_DIR}/leadv2-mission-lint.sh"
python3 - "${LINTER}" "${MUT_LINTER}" <<'PY'
import re
import sys

src, dst = sys.argv[1:]
text = open(src, encoding="utf-8").read()
pattern = r"check_decision_complete\(\) \{.*?^\}\n"
mutated, count = re.subn(pattern, "check_decision_complete() { return 0; }\n", text, count=1, flags=re.M | re.S)
if count != 1:
    raise SystemExit("decision-complete function mutation anchor not found")
open(dst, "w", encoding="utf-8").write(mutated)
PY
mutate_rc=$?
if [[ "${mutate_rc}" -ne 0 ]]; then
  fail "negative control setup: decision-complete function mutation anchor not found"
else
  OUT_MUTANT="${TMP}/mutant.out"
  rc_mutant="$(run_lint "${MUT_LINTER}" "${WITHOUT_APPROACH}" "${OUT_MUTANT}")"
  if [[ "${rc_mutant}" == "0" ]]; then
    pass "negative control: removing check A inside its function makes no-approach case red"
  else
    fail "negative control: mutant should let no-approach brief pass; rc=${rc_mutant}; out=$(cat "${OUT_MUTANT}")"
  fi
fi

log "----"
log "PASS=${PASS} FAIL=${FAIL}"
if [[ "${FAIL}" -gt 0 ]]; then
  printf '[TEST] %s\n' "${ERRORS[@]}"
  exit 1
fi
