#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: claude-subsession.sh leadv2-dispatch-code.sh leadv2-dispatch-product-close.sh
# WORKER-OUTLIVES-ITS-TERMINAL-STATE-01 regression harness.
# Proves the continuation handle is normalized, the close gate waits for the
# Sonnet finalizer, and a bounded timeout reaps both producer processes before
# writing a terminal decision.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH="${TEST_DIR}/../leadv2-dispatch-code.sh"
CLOSE="${TEST_DIR}/../leadv2-dispatch-product-close.sh"
SUBSESSION="${TEST_DIR}/../claude-subsession.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/worker-terminal-state.XXXXXX")"
PIDS=()
trap 'for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; for p in "${PIDS[@]:-}"; do wait "$p" 2>/dev/null || true; done; rm -rf "${TMP_ROOT}"' EXIT INT TERM

PASS=0
FAIL=0
# The production close gate is configured with a 2s poll ceiling in this
# fixture. Its model and finalizer TERM grace loops are each bounded at 5s;
# 3s covers process scheduling and filesystem visibility. Therefore a
# terminal decision must leave every recorded producer gone within 15s.
TERMINAL_GONE_BOUND_S=15
ok() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

if grep -Fq '> "$RUN_DIR/finalizer_pid"' "${SUBSESSION}"; then
  ok "Sonnet launcher records the finalizer PID"
else
  bad "Sonnet launcher does not record the finalizer PID"
fi

# The continuation path must apply the same normalization already used by the
# ordinary dispatch path. This is both a source-level registration guard and a
# direct check of the Sonnet raw-handle contract.
if grep -Fq 'candidate_handle="$(_dispatch_normalize_handle "${candidate}" "${candidate_handle}")"' "${DISPATCH}"; then
  ok "continuation path normalizes raw handles"
else
  bad "continuation path omits raw-handle normalization"
fi
normalize_fn="$(sed -n '/^_dispatch_normalize_handle()/,/^}/p' "${DISPATCH}")"
eval "${normalize_fn}"
if [[ "$(_dispatch_normalize_handle sonnet 'PID=12345 LABEL=developer SESSION_ID=s STREAM=x')" == "12345" ]]; then
  ok "Sonnet raw handle reduces to PID"
else
  bad "Sonnet raw handle did not reduce to PID"
fi

make_repo() {
  local root="$1"
  mkdir -p "${root}"
  git -C "${root}" init -q -b main
  git -C "${root}" config user.email worker-terminal-state@test.local
  git -C "${root}" config user.name worker-terminal-state
  printf 'seed\n' > "${root}/seed.txt"
  git -C "${root}" add seed.txt
  git -C "${root}" commit -qm seed
}

make_journal() {
  local file="$1"
  printf '%s\n' '#!/usr/bin/env bash' \
    'case "$1" in' \
    '  append) printf "%s\n" "$4" >> "$WTS_JOURNAL" ;;' \
    '  tail) cat "$WTS_JOURNAL" 2>/dev/null || true ;;' \
    'esac' > "${file}"
  chmod +x "${file}"
}

run_close() {
  local root="$1" cache="$2" journal="$3" task="$4" max_wait="$5"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}" \
    LEADV2_DISPATCH_CACHE_DIR="${cache}" LEADV2_PC_RUNS_ROOT="${cache}" \
    LEADV2_CLAUDE_RUNS_DIR="${cache}/claude-runs" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="seed.txt" LEADV2_JOURNAL_BIN="${journal}" \
    LEADV2_DISPATCH_TERMINAL_LEDGER=0 LEADV2_PC_WORKER_POLL_S=1 \
    LEADV2_PC_WORKER_MAX_WAIT_S="${max_wait}" LEADV2_PC_WORKER_LOG_EVERY_S=1 \
    LEADV2_PC_LEASE_REFRESH_EVERY_S=3600 LEADV2_LEASE_BIN=/bin/true \
    LEADV2_STATE_PATH_BIN=/bin/false \
    LEADV2_LANE_START_SHA="$(git -C "${root}" rev-parse HEAD)" \
    WTS_JOURNAL="${journal}.log" \
    bash "${CLOSE}" "${root}" "${task}" sonnet "$6" 0 0
}

wait_for_file() {
  local file="$1" limit="$2" i=0
  while [[ ! -f "${file}" && ${i} -lt ${limit} ]]; do sleep 0.1; i=$((i + 1)); done
  [[ -f "${file}" ]]
}

run_dir_for() { printf '%s/claude-runs/%s' "$1" "$2"; }

# Case 1: model exits, but the finalizer remains alive. No review_gate decision
# may appear until .finalized is present.
case_finalizer_wait() {
  local d="${TMP_ROOT}/wait" root cache journal run_id run_dir worker finalizer close_pid
  root="${d}/repo"; cache="${d}/cache"; journal="${d}/journal.sh"
  run_id="sonnet-wait-run"; run_dir="${cache}/claude-runs/${run_id}"
  mkdir -p "${cache}/claude-runs"; make_repo "${root}"; make_journal "${journal}"; : > "${journal}.log"
  sleep 30 & worker=$!; PIDS+=("${worker}")
  sleep 30 & finalizer=$!; PIDS+=("${finalizer}")
  mkdir -p "${run_dir}"; printf '%s\n' "${run_id}" > "${root}/docs-session-pointer"
  mkdir -p "${root}/docs/handoff/dispatch-waitstate"
  printf '%s\n' "${run_id}" > "${root}/docs/handoff/dispatch-waitstate/.claude-session-runner.run-id"
  printf '%s\n' "${worker}" > "${run_dir}/pid"
  printf '%s\n' "${finalizer}" > "${run_dir}/finalizer_pid"
  WTS_JOURNAL="${journal}.log" run_close "${root}" "${cache}" "${journal}" waitstate 8 "${worker}" >"${journal}.close.log" 2>&1 &
  close_pid=$!
  PIDS+=("${close_pid}")
  kill -TERM "${worker}" 2>/dev/null || true
  sleep 2
  if grep -q 'review_gate' "${journal}.log" 2>/dev/null; then
    bad "close gate stayed terminal after model exit"
    sed -n '1,120p' "${journal}.close.log" 2>/dev/null || true
  else
    ok "close gate waits while finalizer is alive"
  fi
  touch "${run_dir}/.finalized"
  kill -TERM "${finalizer}" 2>/dev/null || true; wait "${finalizer}" 2>/dev/null || true
  local i=0
  while kill -0 "${close_pid}" 2>/dev/null && [[ ${i} -lt 50 ]]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "${close_pid}" 2>/dev/null; then
    bad "close gate did not finish after finalizer completion"
  else
    ok "close gate finishes after .finalized"
  fi
}

# Case 1b: a shared handoff pointer may have moved to a newer role. The close
# gate must resolve the Sonnet run by the exact worker PID recorded in the run
# directory, or it can declare a terminal state while the old finalizer still
# owns the worktree.
case_pointer_moved_exact_pid() {
  local d="${TMP_ROOT}/pointer-moved" root cache journal target_run distractor_run
  local target_dir distractor_dir worker finalizer close_pid i
  root="${d}/repo"; cache="${d}/cache"; journal="${d}/journal.sh"
  target_run="sonnet-pointer-target"; distractor_run="sonnet-pointer-newer"
  target_dir="${cache}/claude-runs/${target_run}"
  distractor_dir="${cache}/claude-runs/${distractor_run}"
  mkdir -p "${cache}/claude-runs"; make_repo "${root}"; make_journal "${journal}"; : > "${journal}.log"
  sleep 30 & worker=$!; PIDS+=("${worker}")
  sleep 30 & finalizer=$!; PIDS+=("${finalizer}")
  mkdir -p "${target_dir}" "${distractor_dir}" "${root}/docs/handoff/dispatch-pointerstate"
  printf '%s\n' "${distractor_run}" > "${root}/docs/handoff/dispatch-pointerstate/.claude-session-runner.run-id"
  printf '%s\n' "${worker}" > "${target_dir}/pid"
  printf '%s\n' "${finalizer}" > "${target_dir}/finalizer_pid"
  printf '%s\n' "999999" > "${distractor_dir}/pid"
  WTS_JOURNAL="${journal}.log" run_close "${root}" "${cache}" "${journal}" pointerstate 8 "${worker}" >"${journal}.close.log" 2>&1 &
  close_pid=$!; PIDS+=("${close_pid}")
  kill -TERM "${worker}" 2>/dev/null || true
  sleep 2
  if grep -q 'review_gate' "${journal}.log" 2>/dev/null; then
    bad "pointer-moved close gate ignored exact PID run directory"
  else
    ok "pointer-moved close gate waits on exact PID run directory"
  fi
  touch "${target_dir}/.finalized"
  kill -TERM "${finalizer}" 2>/dev/null || true; wait "${finalizer}" 2>/dev/null || true
  i=0
  while kill -0 "${close_pid}" 2>/dev/null && [[ ${i} -lt 50 ]]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "${close_pid}" 2>/dev/null; then
    bad "pointer-moved close gate did not finish after finalizer completion"
  else
    ok "pointer-moved close gate finishes after exact run finalization"
  fi
}

# Case 2: the hard ceiling must reap both the model and finalizer before the
# timeout terminal decision is emitted.
case_timeout_reaps_both() {
  local d="${TMP_ROOT}/timeout" root cache journal run_id run_dir worker finalizer close_pid rc started elapsed
  root="${d}/repo"; cache="${d}/cache"; journal="${d}/journal.sh"
  run_id="sonnet-timeout-run"; run_dir="${cache}/claude-runs/${run_id}"
  mkdir -p "${cache}/claude-runs"; make_repo "${root}"; make_journal "${journal}"; : > "${journal}.log"
  sleep 30 & worker=$!; PIDS+=("${worker}")
  sleep 30 & finalizer=$!; PIDS+=("${finalizer}")
  mkdir -p "${run_dir}" "${root}/docs/handoff/dispatch-timeoutstate"
  printf '%s\n' "${run_id}" > "${root}/docs/handoff/dispatch-timeoutstate/.claude-session-runner.run-id"
  printf '%s\n' "${worker}" > "${run_dir}/pid"
  printf '%s\n' "${finalizer}" > "${run_dir}/finalizer_pid"
  started="$(date +%s)"
  WTS_JOURNAL="${journal}.log" run_close "${root}" "${cache}" "${journal}" timeoutstate 2 "${worker}" >/dev/null 2>&1
  rc=$?
  elapsed=$(( $(date +%s) - started ))
  if [[ ${rc} -eq 5 ]]; then ok "timeout close exits blocked"; else bad "timeout close rc=${rc}, want 5"; fi
  if ! kill -0 "${worker}" 2>/dev/null && ! kill -0 "${finalizer}" 2>/dev/null; then
    ok "timeout terminal has no live model or finalizer"
  else
    bad "timeout terminal left a producer alive"
  fi
  if grep -q 'worker_timeout terminal=dead' "${journal}.log" 2>/dev/null; then
    ok "timeout terminal emitted after reaping"
  else
    bad "timeout terminal evidence missing"
  fi
  if [[ ${elapsed} -le ${TERMINAL_GONE_BOUND_S} ]]; then
    ok "recorded terminal leaves worker and finalizer gone within ${TERMINAL_GONE_BOUND_S}s (${elapsed}s)"
  else
    bad "recorded terminal exceeded ${TERMINAL_GONE_BOUND_S}s bound (${elapsed}s)"
  fi
}

case_finalizer_wait
case_pointer_moved_exact_pid
case_timeout_reaps_both
printf 'test-worker-outlives-terminal-state: %d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ ${FAIL} -eq 0 ]]
