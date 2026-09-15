#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH="${TESTS_DIR}/../leadv2-dispatch-code.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/prepass-outcome.XXXXXX")" || exit 2
trap 'rm -rf "${WORK}"' EXIT
PASS=0 FAIL=0
ok() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
classify() { # <dispatcher> <rc> <status> <provider-class>
  LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="${WORK}" CLAUDE_PROJECT_ROOT="${WORK}" \
    bash -c 'source "$1"; _architect_prepass_outcome_reason "$2" "$3" "$4"' _ "$@"
}

[[ "$(classify "${DISPATCH}" 124 unknown failed_rc_124)" == 'prepass_timeout' ]] \
  && ok 'rc=124 is named prepass_timeout' || bad 'rc=124 was not prepass_timeout'
[[ "$(classify "${DISPATCH}" 1 allowed failed_rc_1)" == 'prepass_failed_after_allowed' ]] \
  && ok 'rc=1 after allowed is named distinctly' || bad 'allowed rc=1 was not distinct'
[[ "$(classify "${DISPATCH}" 1 quota_refused rate_limited)" == 'rate_limited' ]] \
  && ok 'explicit provider quota refusal remains rate_limited' || bad 'quota refusal was not rate_limited'

cp "${DISPATCH}" "${WORK}/dispatch-mut.sh"
python3 - "${WORK}/dispatch-mut.sh" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
pat = r'(?ms)^_architect_prepass_outcome_reason\(\) \{.*?^\}\n\n_architect_prepass_admission_status'
s2, n = re.subn(pat, '_architect_prepass_outcome_reason() { printf "%s" "rate_limited"; }\n\n_architect_prepass_admission_status', s, count=1)
if n != 1: raise SystemExit('mutation anchor _architect_prepass_outcome_reason not found exactly once')
open(p, 'w', encoding='utf-8').write(s2)
PY
if [[ $? -ne 0 ]]; then
  bad 'control mutation anchor failed loudly'
else
  mutant="$(classify "${WORK}/dispatch-mut.sh" 124 unknown failed_rc_124)"
  [[ "${mutant}" == 'rate_limited' ]] && ok 'NC collapsed outcomes mutant goes RED' \
    || bad "NC mutant was not caught: ${mutant}"
fi

printf '[prepass-outcome-is-named] PASS=%d FAIL=%d\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
