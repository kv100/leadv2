#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/prepass-codex.XXXXXX")" || exit 2
trap 'rm -rf "${WORK}"' EXIT
PASS=0 FAIL=0
ok() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

REPO="${WORK}/repo"; mkdir -p "${REPO}"
git -C "${REPO}" init -q -b main && git -C "${REPO}" config user.email test@example.invalid \
  && git -C "${REPO}" config user.name test && printf 'seed\n' > "${REPO}/seed" \
  && git -C "${REPO}" add seed && git -C "${REPO}" commit -qm seed || exit 2
CODEX="${WORK}/codex.sh"
printf '#!/usr/bin/env bash\nfor n in $(seq 1 8); do printf "design %%s\\n" "$n"; done\n' > "${CODEX}"
chmod +x "${CODEX}"
printf 'mission\n' > "${WORK}/mission.md"

run_fallback() { # <dispatcher> -> output, rc
  LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="${REPO}" CLAUDE_PROJECT_ROOT="${REPO}" \
    LEADV2_DISPATCH_CODEX_BIN="${CODEX}" ARCHITECT_PREPASS_TIMEOUT_SEC=5 \
    bash -c '
      cd "$2"
      source "$1"
      _LADDER_IDS=(claude codex); _LADDER_PROVIDERS=(anthropic openai)
      _provider_available() { return 0; }
      failed="$(_architect_prepass_provider claude)"
      _architect_fallback_design "$3" proof123 rate_limited "$4" "$failed"
    ' _ "$1" "${REPO}" "${WORK}/mission.md" "${WORK}/out.md"
}

out="$(run_fallback "${SCRIPTS_DIR}/leadv2-dispatch-code.sh")"; rc=$?
[[ ${rc} -eq 0 && -s "${WORK}/out.md" ]] && ok 'Claude failure admits Codex fallback candidate' \
  || bad "fallback rc=${rc} out=${out}"

cp -R "${SCRIPTS_DIR}" "${WORK}/mut-scripts"
MUT="${WORK}/mut-scripts/leadv2-dispatch-code.sh"
python3 - "${MUT}" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
pat = r'(?ms)^_architect_prepass_provider\(\) \{.*?^\}\n\n_architect_fallback_provider_allowed'
s2, n = re.subn(pat, '_architect_prepass_provider() { printf "%s" "openai"; }\n\n_architect_fallback_provider_allowed', s, count=1)
if n != 1: raise SystemExit('mutation anchor _architect_prepass_provider not found exactly once')
open(p, 'w', encoding='utf-8').write(s2)
PY
rm -f "${WORK}/out.md"
if [[ $? -ne 0 ]]; then
  bad 'control mutation anchor failed loudly'
else
  out="$(run_fallback "${MUT}")"; rc=$?
  [[ ${rc} -ne 0 && ! -s "${WORK}/out.md" ]] && ok 'NC restored Codex same-provider exclusion goes RED' \
    || bad "NC mutant was not caught rc=${rc} out=${out}"
fi

printf '[prepass-fallback-admits-codex] PASS=%d FAIL=%d\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
