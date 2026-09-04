#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: freepool-coder leadv2-worker-epilogue.sh
# FREEPOOL-MUST-ACTUALLY-GET-WORK-01: exercise the real freepool supervisor
# with a local stream-json worker that writes a declared file then consumes its
# turn budget. A capped round must checkpoint that work into a commit before
# outcome classification. The negative control disables only the dedicated
# checkpoint seam and proves the exact commit assertion goes RED.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODER="${SCRIPT_DIR}/../freepool-coder.sh"
EPILOGUE="${SCRIPT_DIR}/../lib/leadv2-worker-epilogue.sh"
OUTCOME="${SCRIPT_DIR}/../leadv2-lane-outcome.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/freepool-turncap-checkpoint.XXXXXX")"
cleanup() { [[ "${FREEPOOL_TEST_KEEP:-0}" == "1" ]] || rm -rf "${TMP}"; }
trap cleanup EXIT

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

if bash -n "${CODER}" && bash -n "${EPILOGUE}" && bash -n "${OUTCOME}"; then
  pass 'bash syntax: freepool checkpoint path'
else
  fail 'bash syntax: freepool checkpoint path'
fi

FAKE_CLAUDE="${TMP}/fake-claude.sh"
cat > "${FAKE_CLAUDE}" <<'EOF'
#!/usr/bin/env bash
printf 'turn-capped work\n' >> tests/turncap-work.txt
printf '%s\n' '{"type":"assistant","message":{"id":"turn-1","content":[{"type":"text","text":"work written"}]}}'
while :; do sleep 1; done
EOF
chmod +x "${FAKE_CLAUDE}"
printf 'FREEPOOL_AUTH_TOKEN=test\n' > "${TMP}/freepool.env"
chmod 600 "${TMP}/freepool.env"

run_case() { # <checkpoint 1|0> -> run_dir
  local checkpoint="$1" repo runs raw run_id run_dir waited=0
  repo="${TMP}/repo-${checkpoint}"
  runs="${TMP}/runs-${checkpoint}"
  mkdir -p "${repo}/tests" "${runs}"
  git -C "${repo}" init -q -b main
  git -C "${repo}" config user.email test@example.com
  git -C "${repo}" config user.name test
  printf 'baseline\n' > "${repo}/tests/turncap-work.txt"
  git -C "${repo}" add tests/turncap-work.txt && git -C "${repo}" commit -qm baseline
  raw="$(cd "${repo}" && FREEPOOL_SECRETS_FILE="${TMP}/freepool.env" FREEPOOL_RUNS_DIR="${runs}" \
    FREEPOOL_CLAUDE_BIN="${FAKE_CLAUDE}" FREEPOOL_SKIP_GATE=1 FREEPOOL_SKIP_MODEL_SELECT=1 \
    FREEPOOL_TEST_NO_REDACT=1 FREEPOOL_TIMEOUT=20 FREEPOOL_STALL_S=20 FREEPOOL_TURN_LIMIT=1 \
    FREEPOOL_NO_PROGRESS_S=20 FREEPOOL_TURNCAP_CHECKPOINT="${checkpoint}" \
    bash "${CODER}" bg $'LANE_WRITES: tests/\nTurn-cap checkpoint probe.')"
  run_id="$(printf '%s\n' "${raw}" | grep -E '^[0-9]{6}-[0-9]{6}-' | tail -1)"
  [[ -n "${run_id}" ]] || return 1
  run_dir="${runs}/${run_id}"
  while [[ ${waited} -lt 20 && ! -f "${run_dir}/.finalized" ]]; do
    sleep 1
    waited=$((waited + 1))
  done
  [[ -f "${run_dir}/.finalized" ]] || return 1
  printf '%s\n' "${run_dir}"
}

green_run="$(run_case 1)"; green_rc=$?
green_repo="${TMP}/repo-1"
if [[ ${green_rc} -eq 0 ]] && [[ -f "${green_run}/.bound_reason" ]] \
   && grep -qx 'turn_count' "${green_run}/.bound_reason" \
   && grep -q 'TURN_CAP_CHECKPOINT bound=turn_count enabled=1' "${green_run}/progress.log" \
   && grep -q '^auto_committed: 1$' "${green_run}/meta.yaml" \
   && git -C "${green_repo}" log -1 --format=%s | grep -q 'turn-cap checkpoint' \
   && [[ -z "$(git -C "${green_repo}" status --porcelain)" ]]; then
  pass 'green: turn-capped freepool round leaves an in-scope checkpoint commit'
else
  fail 'green: turn-capped freepool round leaves an in-scope checkpoint commit' "rc=${green_rc} run=${green_run:-none}"
fi

# Negative control B: disable the checkpoint. The same capped run is now
# deliberately left dirty, so the commit assertion above is RED.
red_run="$(run_case 0)"; red_rc=$?
red_repo="${TMP}/repo-0"
if [[ ${red_rc} -eq 0 ]] && grep -q 'TURN_CAP_CHECKPOINT bound=turn_count enabled=0' "${red_run}/progress.log" \
   && [[ -n "$(git -C "${red_repo}" status --porcelain)" ]] \
   && ! git -C "${red_repo}" log -1 --format=%s | grep -q 'turn-cap checkpoint'; then
  pass 'RED: negative control B checkpoint-disabled turn-capped round has no commit and remains dirty'
else
  fail 'negative control B: disabling checkpoint did not make commit assertion red' "rc=${red_rc} run=${red_run:-none}"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
