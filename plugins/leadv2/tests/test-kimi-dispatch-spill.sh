#!/usr/bin/env bash
# End-to-end dispatcher coverage for KIMI-CHANNEL-REHAB-01 C1/C2.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${HERE}/.." && pwd)"
DISPATCH="${PLUGIN_ROOT}/scripts/leadv2-dispatch-code.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

PROJECT_ROOT="${TMP_ROOT}/project"
STUB_STATE="${TMP_ROOT}/stub-state"
mkdir -p "${PROJECT_ROOT}/.claude/ref" "${PROJECT_ROOT}/docs/handoff" \
  "${TMP_ROOT}/home" "${TMP_ROOT}/tmp" "${STUB_STATE}"
cp "${PLUGIN_ROOT}/config/leadv2-routing.yaml" "${PROJECT_ROOT}/.claude/ref/leadv2-routing.yaml"

GLM_STUB="${TMP_ROOT}/glm.sh"
KIMI_STUB="${TMP_ROOT}/kimi.sh"
CODEX_STUB="${TMP_ROOT}/codex.sh"
SONNET_STUB="${TMP_ROOT}/sonnet.sh"
WORKTREE_STUB="${TMP_ROOT}/lane-worktree.sh"

cat > "${GLM_STUB}" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "bg" ]]; then
  echo 'LEADV2_DISPATCH_REFUSED: offline_glm' >&2
  exit 1
fi
exit 1
EOF

cat > "${KIMI_STUB}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${KIMI_STUB_STATE:?}"
run_id="${KIMI_STUB_RUN_ID:-stub-kimi-no-work}"
verdict_delay_s="${KIMI_STUB_VERDICT_DELAY_S:-0.2}"
terminal_ledger="${KIMI_STUB_TERMINAL_LEDGER:-}"
run_dir="${state}/${run_id}"
case "${1:-}" in
  bg)
    mkdir -p "${run_dir}"
    printf '%s\n' \
      "run_id: ${run_id}" \
      'status: running' \
      'exit_code:' \
      'channel_outcome:' > "${run_dir}/meta.yaml"
    (
      sleep "${verdict_delay_s}"
      tmp="${run_dir}/meta.yaml.tmp"
      printf '%s\n' \
        "run_id: ${run_id}" \
        'status: failed' \
        'exit_code: 78' \
        'channel_outcome: no_work' > "${tmp}"
      mv "${tmp}" "${run_dir}/meta.yaml"
      if [[ -n "${terminal_ledger}" ]]; then
        mkdir -p "$(dirname "${terminal_ledger}")"
        printf '{"run_id":"%s","terminal":"no_work","cause":"channel_no_work","channel_outcome":"no_work"}\n' \
          "${run_id}" >> "${terminal_ledger}"
      fi
    ) >/dev/null 2>&1 &
    printf '%s\n' "${run_id}"
    ;;
  status)
    cat "${state}/${2}/meta.yaml"
    ;;
  *) exit 2 ;;
esac
EOF

cat > "${CODEX_STUB}" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  task) echo 'Dispatch started in the background as task-kimispill-abc123.' ;;
  status) exit 0 ;;
  *) exit 2 ;;
esac
EOF

cat > "${SONNET_STUB}" <<'EOF'
#!/usr/bin/env bash
echo 'sonnet must not be reached after codex accepts' >&2
exit 42
EOF

cat > "${WORKTREE_STUB}" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  ensure) printf '%s\n' "${CLAUDE_PROJECT_ROOT:?}" ;;
  cleanup) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${GLM_STUB}" "${KIMI_STUB}" "${CODEX_STUB}" "${SONNET_STUB}" "${WORKTREE_STUB}"

MISSION='Fix one typo in one file through dispatcher spill.'
set +e
OUTPUT="$(
  HOME="${TMP_ROOT}/home" \
  TMPDIR="${TMP_ROOT}/tmp" \
  PROJECT_ROOT="${PROJECT_ROOT}" CLAUDE_PROJECT_ROOT="${PROJECT_ROOT}" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache" \
  LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
  LEADV2_ROUTER_V2=0 \
  LEADV2_DISPATCH_GLM_BIN="${GLM_STUB}" \
  LEADV2_DISPATCH_KIMI_BIN="${KIMI_STUB}" \
  LEADV2_DISPATCH_CODEX_BIN="${CODEX_STUB}" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${SONNET_STUB}" \
  LEADV2_DISPATCH_LANE_WORKTREE_BIN="${WORKTREE_STUB}" \
  LEADV2_KIMI_VERDICT_WAIT_S=3 \
  LEADV2_KIMI_VERDICT_POLL_S=0.05 \
  KIMI_STUB_STATE="${STUB_STATE}" \
  bash "${DISPATCH}" --kind plugin "${MISSION}" 2>&1
)"
RC=$?
set -e

FAIL=0
check() {
  local description="$1" pattern="$2"
  if grep -qE "${pattern}" <<< "${OUTPUT}"; then
    printf 'PASS: %s\n' "${description}"
  else
    printf 'FAIL: %s\n' "${description}"
    FAIL=$((FAIL + 1))
  fi
}

if [[ ${RC} -eq 0 ]]; then
  printf 'PASS: dispatcher exits successfully after spill\n'
else
  printf 'FAIL: dispatcher rc=%s\n' "${RC}"
  FAIL=$((FAIL + 1))
fi
check 'narrow empty-write/no-prepass mission admits kimi' \
  'candidate_chain .*arms=glm,kimi,codex,sonnet'
check 'detached kimi launch is observed' \
  'worker_spawned by=router model=kimi'
check 'terminal no-work verdict is consumed by dispatcher' \
  'arm_refused by=router model=kimi .*reason=channel_no_work'
check 'candidate ladder continues to codex' \
  'worker_spawned by=router model=codex'
check 'final resolved arm is codex' \
  'route_resolved by=router .*model=codex'

LEDGER="$(find "${TMP_ROOT}/cache/dispatch-ledger" -name '*.jsonl' -print -quit 2>/dev/null || true)"
if [[ -n "${LEDGER}" ]] && grep -q '"arm":"codex"' "${LEDGER}" \
  && ! grep -q '"arm":"kimi"' "${LEDGER}"; then
  printf 'PASS: no-work kimi reservation is removed before codex confirmation\n'
else
  printf 'FAIL: dispatch ledger did not retain only the accepted codex arm\n'
  FAIL=$((FAIL + 1))
fi

# The caller's verdict window is intentionally shorter than the detached
# supervisor's completion. The confirmed Kimi dispatch must return success
# immediately after that window; the supervisor records channel_no_work later.
LATE_LEDGER="${TMP_ROOT}/late-terminal-ledger.jsonl"
LATE_RUN_ID='stub-kimi-late-no-work'
set +e
LATE_OUTPUT="$(
  HOME="${TMP_ROOT}/home" \
  TMPDIR="${TMP_ROOT}/tmp" \
  PROJECT_ROOT="${PROJECT_ROOT}" CLAUDE_PROJECT_ROOT="${PROJECT_ROOT}" \
  LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache-late" \
  LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
  LEADV2_ROUTER_V2=0 \
  LEADV2_DISPATCH_GLM_BIN="${GLM_STUB}" \
  LEADV2_DISPATCH_KIMI_BIN="${KIMI_STUB}" \
  LEADV2_DISPATCH_CODEX_BIN="${CODEX_STUB}" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${SONNET_STUB}" \
  LEADV2_DISPATCH_LANE_WORKTREE_BIN="${WORKTREE_STUB}" \
  LEADV2_KIMI_VERDICT_WAIT_S=1 \
  LEADV2_KIMI_VERDICT_POLL_S=0.05 \
  KIMI_STUB_STATE="${STUB_STATE}" \
  KIMI_STUB_RUN_ID="${LATE_RUN_ID}" \
  KIMI_STUB_VERDICT_DELAY_S=3 \
  KIMI_STUB_TERMINAL_LEDGER="${LATE_LEDGER}" \
  bash "${DISPATCH}" --kind plugin 'Fix one late typo without blocking the caller.' 2>&1
)"
LATE_RC=$?
set -e

if [[ ${LATE_RC} -eq 0 ]]; then
  printf 'PASS: dispatcher returns 0 before the late Kimi verdict\n'
else
  printf 'FAIL: late-verdict dispatcher rc=%s\n' "${LATE_RC}"
  FAIL=$((FAIL + 1))
fi
if grep -qE 'kimi_verdict_wait .*outcome=no_verdict_yet .*timeout_s=1' <<< "${LATE_OUTPUT}"; then
  printf 'PASS: expired verdict window is journaled as no_verdict_yet\n'
else
  printf 'FAIL: no_verdict_yet expiry journal missing\n'
  FAIL=$((FAIL + 1))
fi
if [[ ! -s "${LATE_LEDGER}" ]]; then
  printf 'PASS: terminal ledger is still empty when dispatcher returns\n'
else
  printf 'FAIL: late Kimi verdict landed before dispatcher returned\n'
  FAIL=$((FAIL + 1))
fi

for ((i = 0; i < 50; i++)); do
  if [[ -s "${LATE_LEDGER}" ]] \
    && grep -q '"terminal":"no_work"' "${LATE_LEDGER}" \
    && grep -q '"cause":"channel_no_work"' "${LATE_LEDGER}"; then
    break
  fi
  sleep 0.1
done
LATE_META="${STUB_STATE}/${LATE_RUN_ID}/meta.yaml"
if [[ -s "${LATE_LEDGER}" ]] \
  && grep -q '"terminal":"no_work"' "${LATE_LEDGER}" \
  && grep -q '"cause":"channel_no_work"' "${LATE_LEDGER}" \
  && grep -q '^channel_outcome: no_work$' "${LATE_META}"; then
  printf 'PASS: detached supervisor later records the channel_no_work terminal row\n'
else
  printf 'FAIL: late channel_no_work terminal row did not arrive\n'
  FAIL=$((FAIL + 1))
fi

if [[ ${FAIL} -ne 0 ]]; then
  printf '%s\n' '--- dispatcher output ---' "${OUTPUT}" \
    '--- late-verdict dispatcher output ---' "${LATE_OUTPUT}"
fi
printf 'FAIL=%d\n' "${FAIL}"
(( FAIL == 0 ))
