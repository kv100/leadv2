#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/prepass-artifact.XXXXXX")" || exit 2
trap 'rm -rf "${WORK}"' EXIT
PASS=0 FAIL=0
ok() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

REPO="${WORK}/repo"; mkdir -p "${REPO}"
git -C "${REPO}" init -q -b main && git -C "${REPO}" config user.email test@example.invalid \
  && git -C "${REPO}" config user.name test && printf 'seed\n' > "${REPO}/seed" \
  && git -C "${REPO}" add seed && git -C "${REPO}" commit -qm seed || exit 2

write_design() { local f="$1"; for n in $(seq 1 8); do printf 'design line %s\n' "${n}"; done > "${f}"; }
verify() { # <dispatcher> <path> -> output, process rc
  LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="${REPO}" CLAUDE_PROJECT_ROOT="${REPO}" \
    bash -c 'cd "$2"; source "$1"; _prepass_verify_design_artifact "$2" "$3"; rc=$?; printf " reason=%s" "$PREPASS_DESIGN_ARTIFACT_REASON"; exit "$rc"' \
    _ "$1" "${REPO}" "$2"
}

PRESENT="${REPO}/present.md"; write_design "${PRESENT}"
out="$(verify "${SCRIPTS_DIR}/leadv2-dispatch-code.sh" "${PRESENT}")"; rc=$?
[[ ${rc} -eq 0 && "${out}" == *'reason=design_artifact_verified'* ]] \
  && ok 'present non-trivial artifact is verified' || bad "present rc=${rc} out=${out}"

out="$(verify "${SCRIPTS_DIR}/leadv2-dispatch-code.sh" "${REPO}/no-ref.md")"; rc=$?
[[ ${rc} -ne 0 && "${out}" == *'reason=design_artifact_missing'* ]] \
  && ok 'path in no ref is refused as design_artifact_missing' || bad "missing rc=${rc} out=${out}"

STUB="${REPO}/stub.md"; printf 'title only\n' > "${STUB}"
out="$(verify "${SCRIPTS_DIR}/leadv2-dispatch-code.sh" "${STUB}")"; rc=$?
[[ ${rc} -ne 0 && "${out}" == *'reason=design_artifact_stub'* ]] \
  && ok 'empty/stub artifact is refused as design_artifact_stub' || bad "stub rc=${rc} out=${out}"

# Mutation control: locate the named production function, not a fragile line
# number; an unmatched function name is a hard test failure.  The mutant makes
# its body unconditionally succeed, so the missing-artifact assertion must RED.
cp -R "${SCRIPTS_DIR}" "${WORK}/mut-scripts"
MUT="${WORK}/mut-scripts/leadv2-dispatch-code.sh"
python3 - "${MUT}" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
pat = r'(?ms)^_prepass_verify_design_artifact\(\) \{.*?^\}\n\n# DISPATCH-HONESTY-01'
replacement = '_prepass_verify_design_artifact() { PREPASS_DESIGN_ARTIFACT_REASON="design_artifact_verified"; PREPASS_DESIGN_ARTIFACT_PATH="$2"; return 0; }\n\n# DISPATCH-HONESTY-01'
s2, n = re.subn(pat, replacement, s, count=1)
if n != 1: raise SystemExit('mutation anchor _prepass_verify_design_artifact not found exactly once')
open(p, 'w', encoding='utf-8').write(s2)
PY
if [[ $? -ne 0 ]]; then
  bad 'control mutation anchor failed loudly'
else
  out="$(verify "${MUT}" "${REPO}/no-ref.md")"; rc=$?
  [[ ${rc} -eq 0 ]] && ok 'NC artifact verifier unconditional-success mutant goes RED' \
    || bad "NC mutant was not caught rc=${rc} out=${out}"
fi

printf '[prepass-verifies-the-design-artifact] PASS=%d FAIL=%d\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
