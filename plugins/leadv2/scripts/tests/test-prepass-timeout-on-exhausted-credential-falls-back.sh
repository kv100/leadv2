#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code.sh leadv2-quota-read.py
# DISPATCH-HONESTY-01 §1: assert the real architect_prepass and a lower-level
# fake launcher.  The timeout mutation is made inside architect_prepass's body.
set -u

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-honesty-prepass.XXXXXX")"
trap 'rm -rf "${ROOT}"' EXIT
DISPATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-dispatch-code.sh"
PRIMARY="${ROOT}/architect-timeout.sh"
CODEX="${ROOT}/codex-fallback.sh"
QUOTA="${ROOT}/quota-reader.py"
MUTATED="${ROOT}/dispatch-mutated.sh"
mkdir -p "${ROOT}/docs/handoff" "${ROOT}/profiles/work"

git -C "${ROOT}" init -q
git -C "${ROOT}" config user.email test@example.invalid
git -C "${ROOT}" config user.name dispatch-honesty-test
printf 'fixture\n' > "${ROOT}/fixture.txt"
git -C "${ROOT}" add fixture.txt
git -C "${ROOT}" commit -qm fixture
printf '{}\n' > "${ROOT}/profiles/work/.credentials.json"
printf 'work\t%s\tfile:%s\n' "${ROOT}/profiles/work" "${ROOT}/profiles/work/.credentials.json" > "${ROOT}/profiles.tsv"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'task=' \
  'while [[ $# -gt 0 ]]; do' \
  '  [[ "$1" == "--task-id" ]] && task="$2" && shift 2 && continue' \
  '  shift' \
  'done' \
  'sig="${task#dispatch-}"; sig="${sig%-architect}"' \
  'mkdir -p "${PROJECT_ROOT}/docs/handoff/dispatch-${sig}-architect"' \
  'printf "%s [claude-profile] selected=work score=0 source=live candidates=1 cred_kind=file identity=team/test@example.invalid\\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${PROJECT_ROOT}/docs/handoff/dispatch-${sig}-architect/claude-profile.log"' \
  'sleep 5' > "${PRIMARY}"
chmod +x "${PRIMARY}"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\\n" "Fallback design" "LANE_WRITES: src/a.py,src/b.py"' > "${CODEX}"
chmod +x "${CODEX}"

printf '%s\n' \
  'import json' \
  'print(json.dumps({"provider":"anthropic","accounts":[{"active":True,"account_label":"work","binding_window":"five_hour","five_hour":{"usable_now":0.0}}]}))' > "${QUOTA}"

run_case() {
  local script="$1" sig="$2"
  rm -rf "${ROOT}/docs/handoff/dispatch-${sig}-architect"
  set +e
  RUN_OUT="$(cd "${ROOT}" && \
    PROJECT_ROOT="${ROOT}" WORK_ROOT="${ROOT}" \
    LEADV2_DISPATCH_SOURCE_ONLY=1 LEADV2_DISPATCH_ARCHITECT_BIN="${PRIMARY}" \
    LEADV2_DISPATCH_CODEX_BIN="${CODEX}" LEADV2_QUOTA_READ="${QUOTA}" \
    LEADV2_CLAUDE_PROFILES_FILE="${ROOT}/profiles.tsv" \
    LEADV2_DISPATCH_ARCHITECT_MODEL=sonnet LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=1 \
    LEADV2_DISPATCH_ARCHITECT_ATTEMPTS=1 LEADV2_DISPATCH_ARCHITECT_FALLBACK=1 \
    LEADV2_PREPASS_CACHE=0 LEADV2_REQUIRE_LANE_WRITES=0 \
    LEADV2_JOURNAL_BIN=/bin/true LEADV2_EVENT_BIN=/bin/true \
    bash -c 'source "$1"; ARCHITECT_LANE_SUFFIX=architect; _LADDER_IDS=(codex); _LADDER_PROVIDERS=(codex); _LADDER_UNTRUSTED=(0); _LADDER_WHEN=(all); JOURNAL_TASK="dispatch-'"${sig}"'"; architect_prepass "mission with two declared files" "'"${sig}"'" "src/a.py,src/b.py"' _ "${script}" 2>&1)"
  RUN_RC=$?
  set -u
}

run_case "${DISPATCH}" deadbeef
if [[ ${RUN_RC} -eq 0 ]] \
  && printf '%s' "${RUN_OUT}" | grep -q 'architect_prepass .*status=failed reason=quota_exceeded rc=124' \
  && printf '%s' "${RUN_OUT}" | grep -q 'architect_prepass_fallback .*outcome=used reason=quota_exceeded'; then
  printf '[ok] exhausted selected credential reclassifies rc=124 as quota_exceeded and opens the existing fallback\n'
else
  printf '[FAIL] positive exhausted-credential case rc=%s\n%s\n' "${RUN_RC}" "${RUN_OUT}"
  exit 1
fi

# Negative control: this replacement is deliberately inside architect_prepass's
# rc=124 classification body. It restores the unconditional timeout lie and
# must make the same real-function case red (no fallback event).
sed 's/_pp_cls="quota_exceeded"/_pp_cls="timeout"/' "${DISPATCH}" > "${MUTATED}"
run_case "${MUTATED}" badc0de1
if [[ ${RUN_RC} -ne 0 ]] \
  && printf '%s' "${RUN_OUT}" | grep -q 'architect_prepass .*status=failed reason=timeout rc=124' \
  && ! printf '%s' "${RUN_OUT}" | grep -q 'architect_prepass_fallback .*outcome=used'; then
  printf '[red-control §1 raw]\n%s\n' "${RUN_OUT}"
  printf '[ok] negative control: unconditional timeout classification blocks fallback\n'
else
  printf '[FAIL] negative control unexpectedly passed rc=%s\n%s\n' "${RUN_RC}" "${RUN_OUT}"
  exit 1
fi

printf '=== all checks passed ===\n'
