#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code
# Negative controls for the two dispatcher-guard suites. Mutants live only in
# a private temp copy; refuse loudly if that target is ever tracked.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${HERE}/.." && pwd)"
ROOT="$(cd "${SCRIPTS}/../../.." && pwd)"
R1="${HERE}/test-resume-lane-refuses-invisible-mission.sh"
R2="${HERE}/test-placement-refusal-exits-before-gates.sh"
PASS=0 FAIL=0
ok() { printf '[NC] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[NC] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
D="$(mktemp -d /tmp/leadv2-dispatcher-guards-nc-XXXXXX)"; trap 'rm -rf "${D}"' EXIT

run_mutant() { # <name> <python replacement program> <suite> <named case>
  local name="$1" py="$2" suite="$3" named="$4" copy out rc=0
  copy="${D}/${name}-scripts"
  out="${D}/${name}.out"
  cp -R "${SCRIPTS}" "${copy}"
  local mutant="${copy}/leadv2-dispatch-code.sh"
  if git -C "${ROOT}" ls-files --error-unmatch "${mutant#${ROOT}/}" >/dev/null 2>&1; then
    bad "${name}: refusing to write a mock onto tracked file ${mutant}"
    return
  fi
  python3 - "${mutant}" "${py}" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); old = p.read_text(); needle, repl = sys.argv[2].split('|||', 1)
if needle not in old:
    raise SystemExit('MUTATION_PATTERN_NOT_FOUND: ' + needle)
p.write_text(old.replace(needle, repl, 1))
PY
  if ! LEADV2_DISPATCH_CODE_FILE="${mutant}" bash "${suite}" >"${out}" 2>&1; then rc=1; fi
  if [[ ${rc} -eq 1 ]] && grep -Fq "${named}" "${out}"; then
    ok "${name}: RED on named ${named}"
    sed -n "/${named}/p" "${out}"
  else
    bad "${name}: expected named RED ${named}; rc=${rc}; out=$(tail -8 "${out}")"
  fi
}

run_mutant mission_visibility $'if git -C "${candidate}" ls-tree --name-only HEAD -- "${p}" 2>/dev/null | grep -Fx -- "${p}" >/dev/null 2>&1; then|||if true; then' \
  "${R1}" 'case 2 invisible main mission refuses with lane-specific remedy'
run_mutant placement_fallthrough $'return 5\n  fi\n  # Dead branch|||return 0\n  fi\n  # Dead branch' \
  "${R2}" 'case 5 placement refusal returns rc=5 to caller'

printf 'nc-dispatcher-guards: %d passed, %d failed\n' "${PASS}" "${FAIL}"
exit "${FAIL}"
