#!/usr/bin/env bash
# N1-EMPTY-LANE-IS-NOT-A-PASS / PREMATURE-NO-WORK-TERMINAL-01 harness.
# Besides the original empty/partial/surface cases, proves product-close waits
# for provider + process completion, scopes the diff only after worker exit, and
# uses dead/timeout rather than no_work when a live worker exceeds the ceiling.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PC="${SCRIPT_DIR}/leadv2-dispatch-product-close.sh"
SURFACE="${SCRIPT_DIR}/leadv2-status-surface.sh"
PASS=0; FAIL=0
ok()   { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }
assert_eq() { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

make_stubs() { # <dir>
  local d="$1"
  cat > "${d}/resolver.py" <<'PY'
print("reviewer=codex"); print("pool=codex"); print("refusal=")
PY
  cat > "${d}/codex.sh" <<'SH'
#!/usr/bin/env bash
mkdir -p "$2"; printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n' > "$1"
SH
  chmod +x "${d}/codex.sh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/journal.log"\n' "${d}" > "${d}/journal.sh"
  chmod +x "${d}/journal.sh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/ledger.log"\n' "${d}" > "${d}/ledger.sh"
  chmod +x "${d}/ledger.sh"
}

new_repo() {
  local root="$1"
  mkdir -p "${root}/agent"
  ( cd "${root}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > agent/seed.py && git add agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
}

CASE_PIDS=()
CASE_REG_DIR=""
FAKE_JOB_REGISTRY_ROOT=""
FAKE_PID=""
FAKE_RUNS=""

track_pid() { CASE_PIDS+=("$1"); }

cleanup_case() { # <sandbox>
  local d="$1" pid
  for pid in "${CASE_PIDS[@]:-}"; do
    [[ -n "${pid}" ]] && kill "${pid}" 2>/dev/null || true
  done
  for pid in "${CASE_PIDS[@]:-}"; do
    [[ -n "${pid}" ]] && wait "${pid}" 2>/dev/null || true
  done
  [[ -n "${CASE_REG_DIR}" ]] && rm -rf "${CASE_REG_DIR}"
  rm -rf "${d}"
  CASE_PIDS=()
  CASE_REG_DIR=""
  FAKE_JOB_REGISTRY_ROOT=""
  FAKE_PID=""
  FAKE_RUNS=""
}

fake_glm_run() { # <sandbox> <repo> <handle> <delay_s> <work_mode:0=empty,1=dirty,2=committed>
  local d="$1" root="$2" handle="$3" delay_s="$4" work_mode="$5"
  FAKE_RUNS="${d}/glm-runs"
  FAKE_JOB_REGISTRY_ROOT="${d}/job-registry"
  local run_dir="${FAKE_RUNS}/${handle}"
  CASE_REG_DIR="${FAKE_JOB_REGISTRY_ROOT}/pc-no-work-$$-${RANDOM}"
  mkdir -p "${run_dir}" "${CASE_REG_DIR}"
  : > "${CASE_REG_DIR}/${handle}"
  (
    trap 'exit 0' TERM INT
    worker_deadline=$(( SECONDS + delay_s ))
    while [[ "${SECONDS}" -lt "${worker_deadline}" ]]; do sleep 0.1; done
    if [[ "${work_mode}" != 0 ]]; then
      printf 'worker diff\n' >> "${root}/agent/seed.py"
    fi
    if [[ "${work_mode}" == 2 ]]; then
      git -C "${root}" add agent/seed.py
      git -C "${root}" commit -qm 'stub worker commit'
    fi
    sed 's/^status: running$/status: complete/' "${run_dir}/meta.yaml" > "${run_dir}/meta.yaml.tmp"
    mv "${run_dir}/meta.yaml.tmp" "${run_dir}/meta.yaml"
    rm -f "${CASE_REG_DIR}/${handle}"
  ) &
  FAKE_PID=$!
  track_pid "${FAKE_PID}"
  printf 'run_id: %s\npid: %s\nstatus: running\n' "${handle}" "${FAKE_PID}" > "${run_dir}/meta.yaml"
}

# ---- Case 1: empty diff -> no_work / empty_diff, no e2e flag, exit 5 ---------
case_empty_no_work() {
  local d root
  d="$(mktemp -d)"; root="${d}/repo"; mkdir -p "${root}"
  new_repo "${root}"; make_stubs "${d}"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${root}" nw1sig001 sonnet "" 1 1 "founder-nw1" >/dev/null 2>&1
  local rc=$?
  local handoff="${root}/docs/handoff/dispatch-nw1sig001"
  assert_eq "${rc}" "5" "empty-diff exits 5"
  if [[ -f "${handoff}/review-gate.md" ]] && grep -q '^reason: no_work$' "${handoff}/review-gate.md"; then
    ok "review-gate.md reason=no_work"
  else bad "review-gate.md reason=no_work (got: $(cat "${handoff}/review-gate.md" 2>/dev/null))"
  fi
  if [[ ! -f "${handoff}/e2e-gate-passed.flag" ]]; then ok "e2e-gate-passed.flag absent"; else bad "e2e-gate-passed.flag present"; fi
  if grep -q 'terminal=no_work cause=empty_diff' "${d}/journal.log" 2>/dev/null; then
    ok "ledger decision line terminal=no_work cause=empty_diff"
  else bad "ledger decision line missing (got: $(grep review_gate "${d}/journal.log" 2>/dev/null | tail -1))"
  fi
  rm -rf "${d}"
}

# ---- Case 1b (T8C-FOREIGN-REPO-LANDING-01): empty local diff + a declared
# lane-target-repo marker whose foreign repo carries a commit tagged with the task
# sig -> terminal=landed cause=landed_foreign, exit 0, never no_work. -----------
case_foreign_repo_landing() {
  local d root foreign
  d="$(mktemp -d)"; root="${d}/repo"; mkdir -p "${root}"
  new_repo "${root}"; make_stubs "${d}"
  foreign="${d}/foreign-repo"
  mkdir -p "${foreign}"
  ( cd "${foreign}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > seed.py && git add seed.py && git commit -qm seed \
    && printf 'fix\n' >> seed.py && git commit -qam "fix(leadv2): frl2sig001 -- landed in canonical" \
  ) >/dev/null 2>&1
  mkdir -p "${root}/docs/handoff/dispatch-frl2sig001"
  printf '%s\n' "${foreign}" > "${root}/docs/handoff/dispatch-frl2sig001/lane-target-repo"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${root}" frl2sig001 sonnet "" 1 1 "founder-frl2" >/dev/null 2>&1
  local rc=$?
  local handoff="${root}/docs/handoff/dispatch-frl2sig001"
  assert_eq "${rc}" "0" "foreign-landed lane exits 0"
  if [[ -f "${handoff}/review-gate.md" ]] && grep -q '^reason: landed_foreign$' "${handoff}/review-gate.md" \
     && grep -q '^status: passed$' "${handoff}/review-gate.md"; then
    ok "review-gate.md reason=landed_foreign status=passed"
  else bad "review-gate.md reason=landed_foreign (got: $(cat "${handoff}/review-gate.md" 2>/dev/null))"
  fi
  if grep -q 'terminal=landed cause=landed_foreign' "${d}/journal.log" 2>/dev/null; then
    ok "ledger decision line terminal=landed cause=landed_foreign"
  else bad "ledger decision line missing (got: $(grep review_gate "${d}/journal.log" 2>/dev/null | tail -1))"
  fi
  rm -rf "${d}"
}

# ---- Case 1c (T8C negative control): same empty local diff, NO lane-target-repo
# marker at all -> must stay on the pre-existing no_work/empty_diff path unchanged. --
case_foreign_repo_absent_stays_no_work() {
  local d root
  d="$(mktemp -d)"; root="${d}/repo"; mkdir -p "${root}"
  new_repo "${root}"; make_stubs "${d}"
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${root}" fra2sig001 sonnet "" 1 1 "founder-fra2" >/dev/null 2>&1
  local rc=$?
  local handoff="${root}/docs/handoff/dispatch-fra2sig001"
  assert_eq "${rc}" "5" "no-marker empty-diff lane still exits 5"
  if [[ -f "${handoff}/review-gate.md" ]] && grep -q '^reason: no_work$' "${handoff}/review-gate.md" \
     && ! grep -q 'landed_foreign' "${handoff}/review-gate.md"; then
    ok "review-gate.md reason=no_work (no foreign-repo marker present)"
  else bad "review-gate.md unexpectedly mentions landed_foreign (got: $(cat "${handoff}/review-gate.md" 2>/dev/null))"
  fi
  rm -rf "${d}"
}

# ---- Case 2: partial_diff (mixed group) stays refused -----------------------
case_partial_stays_refused() {
  local d plugin target
  d="$(mktemp -d)"; plugin="${d}/plugin-repo"; target="${d}/target-repo"
  mkdir -p "${plugin}/scripts" "${target}/.claude/scripts" "${target}/agent"
  ( cd "${plugin}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'orig\n' > scripts/foo.sh && git add scripts/foo.sh && git commit -qm seed ) >/dev/null 2>&1
  printf 'orig\npatched\n' > "${plugin}/scripts/foo.sh"
  ( cd "${target}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > agent/seed.py && ln -s "${plugin}/scripts/foo.sh" .claude/scripts/foo.sh \
    && git add agent/seed.py .claude/scripts/foo.sh && git commit -qm seed ) >/dev/null 2>&1
  make_stubs "${d}"
  CLAUDE_PROJECT_ROOT="${target}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
    LEADV2_LANE_WORK_ROOT="${target}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py,.claude/scripts/foo.sh" \
    LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${PC}" "${target}" nw2sig002 sonnet "" 0 1 "founder-nw2" >/dev/null 2>&1
  local gate="${target}/docs/handoff/dispatch-nw2sig002/review-gate.md"
  if [[ -f "${gate}" ]] && grep -q '^reason: partial_diff$' "${gate}"; then
    ok "partial_diff stays refused (reason=partial_diff, not no_work)"
  else bad "partial_diff should stay refused (got: $(cat "${gate}" 2>/dev/null))"
  fi
  rm -rf "${d}"
}

# ---- Case 3 (R1): a no_work terminal row renders RED, never done(...) --------
case_surface_no_work_not_done() {
  local SB NOW LEDGER DIR
  SB="$(mktemp -d)"; DIR="${SB}/state"; LEDGER="${SB}/ledger"; mkdir -p "${DIR}" "${LEDGER}"
  NOW=$(( $(date +%s) ))
  # 30min old: lands on stale(...) for lack of any live signal, but inside the
  # DEAD_TTL window so it is NOT age-dropped before render. task_sig is the 8-char
  # sig the surface keys on; the row lives at ${LEDGER_DIR}/${REPO}.jsonl.
  local old=$(( NOW - 1800 ))
  printf '{"task_sig":"nw3sig00","founder_task_id":"founder-nw3","terminal":"no_work","cause":"empty_diff","created_epoch":%s,"task_id":"founder-nw3"}\n' "${old}" \
    > "${LEDGER}/testrepo.jsonl"
  : > "${DIR}/active.yaml"
  local out
  out="$(LEADV2_STATUS_STATE_DIR="${DIR}" \
         LEADV2_STATUS_LEDGER_DIR="${LEDGER}" \
         LEADV2_STATUS_RUNS_ROOT="${SB}/cache" \
         LEADV2_STATUS_REPO="testrepo" \
         LEADV2_STATUS_REPO_ROOT="${SB}" \
         LEADV2_STATUS_NOW="${NOW}" \
         LEADV2_STATUS_TASKS_YAML="${SB}/tasks.yaml" \
         bash "${SURFACE}" 2>/dev/null || true)"
  if printf '%s' "${out}" | grep -q 'no-work(empty-diff)'; then
    ok "surface renders no-work(empty-diff)"
  else bad "surface should render no-work(empty-diff) (got: $(printf '%s' "${out}" | grep -i nw3 || echo '<row absent>'))"
  fi
  if printf '%s' "${out}" | grep -qE 'done\(no_work|done\(terminal\)'; then
    bad "R1: no_work row laundered into done(...)"
  else ok "R1: no_work row NOT laundered into done(...)"
  fi
  rm -rf "${SB}"
}

# ---- Case 4: watcher wakes while worker lives -> no terminal/artifacts ------
case_alive_worker_has_no_terminal() {
  local d root handle close_pid handoff
  d="$(mktemp -d)"; root="${d}/repo"; handle="slow-alive-$$"
  mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"
  fake_glm_run "${d}" "${root}" "${handle}" 30 0
  GLM_RUNS_DIR="${FAKE_RUNS}" LEADV2_PC_RUNS_ROOT="${d}" \
    LEADV2_JOB_REGISTRY_ROOT="${FAKE_JOB_REGISTRY_ROOT}" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=40 LEADV2_PC_WORKER_LOG_EVERY_S=1 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    bash "${PC}" "${root}" nw4sig004 glm "${handle}" 0 0 "founder-nw4" >"${d}/close.log" 2>&1 &
  close_pid=$!; track_pid "${close_pid}"
  for _ in $(seq 1 50); do
    grep -q 'status=waiting_worker' "${d}/journal.log" 2>/dev/null && break
    sleep 0.1
  done
  handoff="${root}/docs/handoff/dispatch-nw4sig004"
  if [[ ! -f "${handoff}/review-gate.md" ]]; then ok "alive worker has no review-gate.md"; else bad "alive worker wrote review-gate.md"; fi
  if [[ ! -f "${handoff}/review.diff" ]]; then ok "alive worker has no early review.diff"; else bad "alive worker wrote review.diff before exit"; fi
  if grep -q 'write-terminal' "${d}/ledger.log" 2>/dev/null; then bad "alive worker emitted a terminal row"; else ok "alive worker emits no terminal row"; fi
  if grep -q 'product_close task=nw4sig004 status=waiting_worker author=glm handle=' "${d}/journal.log" 2>/dev/null; then
    ok "alive worker journals waiting_worker"
  else bad "alive worker waiting journal missing"
  fi
  cleanup_case "${d}"
}

# ---- Case 5: worker writes, exits -> exit-time diff is non-empty ------------
case_diff_measured_after_exit() {
  local d root handle close_pid rc handoff
  d="$(mktemp -d)"; root="${d}/repo"; handle="slow-diff-$$"
  mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"
  fake_glm_run "${d}" "${root}" "${handle}" 2 1
  GLM_RUNS_DIR="${FAKE_RUNS}" LEADV2_PC_RUNS_ROOT="${d}" \
    LEADV2_JOB_REGISTRY_ROOT="${FAKE_JOB_REGISTRY_ROOT}" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=15 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    bash "${PC}" "${root}" nw5sig005 glm "${handle}" 0 0 "founder-nw5" >"${d}/close.log" 2>&1 &
  close_pid=$!; track_pid "${close_pid}"
  wait "${close_pid}"; rc=$?
  handoff="${root}/docs/handoff/dispatch-nw5sig005"
  assert_eq "${rc}" "0" "diff-writing worker exits through non-empty path"
  if [[ -s "${handoff}/review.diff" ]]; then ok "exit-time review.diff is non-empty"; else bad "exit-time review.diff is empty"; fi
  if grep -q 'terminal=no_work' "${d}/journal.log" 2>/dev/null; then bad "diff-writing worker misclassified no_work"; else ok "diff-writing worker is not no_work"; fi
  if grep -q 'write-terminal nw5sig005 .* landed review_gate_disabled' "${d}/ledger.log" 2>/dev/null; then ok "diff-writing worker terminal reflects non-empty path"; else bad "diff-writing worker terminal row is not landed"; fi
  cleanup_case "${d}"
}

# ---- Case 6: finished, genuinely empty worker -> empty_diff allowed ---------
case_finished_empty_allowed() {
  local d root handle close_pid rc handoff
  d="$(mktemp -d)"; root="${d}/repo"; handle="slow-empty-$$"
  mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"
  fake_glm_run "${d}" "${root}" "${handle}" 1 0
  GLM_RUNS_DIR="${FAKE_RUNS}" LEADV2_PC_RUNS_ROOT="${d}" \
    LEADV2_JOB_REGISTRY_ROOT="${FAKE_JOB_REGISTRY_ROOT}" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=15 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    bash "${PC}" "${root}" nw6sig006 glm "${handle}" 0 0 "founder-nw6" >"${d}/close.log" 2>&1 &
  close_pid=$!; track_pid "${close_pid}"
  wait "${close_pid}"; rc=$?
  handoff="${root}/docs/handoff/dispatch-nw6sig006"
  assert_eq "${rc}" "5" "finished empty worker exits 5"
  if [[ -f "${handoff}/review-gate.md" ]] && grep -q '^reason: no_work$' "${handoff}/review-gate.md"; then
    ok "finished empty worker may emit empty_diff/no_work"
  else bad "finished empty worker missing no_work gate"
  fi
  if grep -q 'terminal=no_work cause=empty_diff' "${d}/journal.log" 2>/dev/null; then ok "finished empty worker journals empty_diff"; else bad "finished empty worker terminal missing"; fi
  if grep -q 'write-terminal nw6sig006 .* no_work empty_diff' "${d}/ledger.log" 2>/dev/null; then ok "finished empty worker writes no_work terminal row"; else bad "finished empty worker ledger row missing"; fi
  cleanup_case "${d}"
}

# ---- Case 7: live past ceiling -> dead/timeout, never no_work ---------------
case_live_worker_timeout() {
  local d root handle close_pid rc gate
  d="$(mktemp -d)"; root="${d}/repo"; handle="slow-timeout-$$"
  mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"
  fake_glm_run "${d}" "${root}" "${handle}" 30 0
  GLM_RUNS_DIR="${FAKE_RUNS}" LEADV2_PC_RUNS_ROOT="${d}" \
    LEADV2_JOB_REGISTRY_ROOT="${FAKE_JOB_REGISTRY_ROOT}" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=2 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    bash "${PC}" "${root}" nw7sig007 glm "${handle}" 0 0 "founder-nw7" >"${d}/close.log" 2>&1 &
  close_pid=$!; track_pid "${close_pid}"
  wait "${close_pid}"; rc=$?
  gate="${root}/docs/handoff/dispatch-nw7sig007/review-gate.md"
  assert_eq "${rc}" "5" "live worker timeout exits 5"
  if [[ -f "${gate}" ]] && grep -q '^reason: worker_timeout$' "${gate}"; then ok "timeout gate says worker_timeout"; else bad "timeout gate reason missing"; fi
  if grep -q 'terminal=dead cause=timeout' "${d}/journal.log" 2>/dev/null; then ok "timeout journals dead/timeout"; else bad "timeout dead terminal missing"; fi
  if grep -q 'write-terminal nw7sig007 .* dead timeout' "${d}/ledger.log" 2>/dev/null; then ok "timeout writes dead/timeout terminal row"; else bad "timeout ledger row missing"; fi
  if grep -q 'terminal=no_work' "${d}/journal.log" 2>/dev/null; then bad "timeout emitted no_work"; else ok "timeout never emits no_work"; fi
  cleanup_case "${d}"
}

# ---- Case 8: codex provider probe seam is polled until terminal ------------
case_codex_probe_waits() {
  local d root close_pid rc calls started elapsed
  d="$(mktemp -d)"; root="${d}/repo"; mkdir -p "${root}"
  new_repo "${root}"; make_stubs "${d}"; printf '0' > "${d}/probe-count"
  FAKE_JOB_REGISTRY_ROOT="${d}/job-registry"
  CASE_REG_DIR="${FAKE_JOB_REGISTRY_ROOT}/codex-case"
  mkdir -p "${CASE_REG_DIR}"
  : > "${CASE_REG_DIR}/task-test-waits"
  ( sleep 3; rm -f "${CASE_REG_DIR}/task-test-waits" ) &
  track_pid "$!"
  cat > "${d}/liveness.sh" <<'SH'
#!/usr/bin/env bash
n=$(cat "${LEADV2_TEST_LIVENESS_COUNT}")
n=$((n + 1))
printf '%s' "${n}" > "${LEADV2_TEST_LIVENESS_COUNT}"
if [[ "${n}" -lt 2 ]]; then
  printf '{"provider":"codex","jobs":[{"verdict":"running"}]}\n'
else
  printf '{"provider":"codex","jobs":[{"verdict":"done"}]}\n'
fi
SH
  chmod +x "${d}/liveness.sh"
  started="$(date +%s)"
  LEADV2_TEST_LIVENESS_COUNT="${d}/probe-count" LEADV2_LANE_LIVENESS_BIN="${d}/liveness.sh" \
    LEADV2_JOB_REGISTRY_ROOT="${FAKE_JOB_REGISTRY_ROOT}" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=10 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    bash "${PC}" "${root}" nw8sig008 codex task-test-waits 0 0 "founder-nw8" >"${d}/close.log" 2>&1 &
  close_pid=$!; track_pid "${close_pid}"
  wait "${close_pid}"; rc=$?
  elapsed=$(( $(date +%s) - started )); calls="$(cat "${d}/probe-count")"
  assert_eq "${rc}" "5" "codex finished-empty path remains no_work"
  if [[ "${calls}" -ge 3 ]]; then ok "codex wrapped jobs verdict is polled through done"; else bad "codex liveness probe called only ${calls} times"; fi
  if [[ "${elapsed}" -ge 3 ]]; then ok "codex close honors registry-root seam until handle clears"; else bad "codex close ignored seamed registry (${elapsed}s)"; fi
  cleanup_case "${d}"
}

# ---- Case 9: Sonnet numeric PID exits naturally before diff classification --
case_sonnet_natural_completion() {
  local d root worker_pid close_pid rc started elapsed handoff
  d="$(mktemp -d)"; root="${d}/repo"; mkdir -p "${root}"
  new_repo "${root}"; make_stubs "${d}"
  (
    sleep 2
    printf 'sonnet worker diff\n' >> "${root}/agent/seed.py"
  ) &
  worker_pid=$!; track_pid "${worker_pid}"
  started="$(date +%s)"
  LEADV2_JOB_REGISTRY_ROOT="${d}/job-registry" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=10 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    bash "${PC}" "${root}" nw9sig009 sonnet "${worker_pid}" 0 0 "founder-nw9" >"${d}/close.log" 2>&1 &
  close_pid=$!; track_pid "${close_pid}"
  wait "${close_pid}"; rc=$?
  elapsed=$(( $(date +%s) - started ))
  handoff="${root}/docs/handoff/dispatch-nw9sig009"
  assert_eq "${rc}" "0" "Sonnet natural completion reaches non-empty close path"
  if [[ "${elapsed}" -ge 2 ]]; then ok "Sonnet close waits for numeric PID exit"; else bad "Sonnet close returned before PID exit (${elapsed}s)"; fi
  if [[ -s "${handoff}/review.diff" ]] && grep -q 'sonnet worker diff' "${handoff}/review.diff"; then
    ok "Sonnet exit-time diff is classified after natural completion"
  else bad "Sonnet natural-completion diff missing"
  fi
  cleanup_case "${d}"
}

# ---- Case 10: GLM/Kimi revival finalizes the original stale registry handle -
case_revived_status_is_terminal_for_handle() {
  local status idx d root handle runs reg rc started elapsed gate
  idx=0
  for status in revived revive_blocked_by_gate; do
    idx=$((idx + 1))
    d="$(mktemp -d)"; root="${d}/repo"; handle="revived-${idx}-$$"
    mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"
    runs="${d}/glm-runs"; reg="${d}/job-registry/revive-case"
    mkdir -p "${runs}/${handle}" "${reg}"
    printf 'run_id: %s\nstatus: %s\nrevived_to: replacement-run\n' "${handle}" "${status}" > "${runs}/${handle}/meta.yaml"
    : > "${reg}/${handle}"
    started="$(date +%s)"
    GLM_RUNS_DIR="${runs}" LEADV2_JOB_REGISTRY_ROOT="${d}/job-registry" \
      LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=2 \
      LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
      LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
      bash "${PC}" "${root}" "nwrv000${idx}" glm "${handle}" 0 0 "founder-revive-${idx}" >"${d}/close.log" 2>&1
    rc=$?; elapsed=$(( $(date +%s) - started ))
    gate="${root}/docs/handoff/dispatch-nwrv000${idx}/review-gate.md"
    assert_eq "${rc}" "5" "${status} reaches ordinary empty-diff terminal"
    # elapsed is wall-clock (date +%s resolution).  The script's own startup
    # (source lib, mkdir handoff, write pidfile, parse args) can push the
    # total to exactly max_wait_s (2 s) even though pc_worker_alive returned
    # promptly — the intent is "did NOT hit the worker_timeout ceiling", which
    # is proven by the no_work gate + absence of dead/timeout, not by elapsed.
    if [[ "${elapsed}" -le 2 ]] && grep -q '^reason: no_work$' "${gate}" 2>/dev/null; then
      ok "${status} ignores stale original registry handle"
    else bad "${status} waited to timeout instead of finalizing original handle"
    fi
    if grep -q ' dead timeout' "${d}/ledger.log" 2>/dev/null; then bad "${status} wrote permanent dead/timeout"; else ok "${status} never writes dead/timeout"; fi
    cleanup_case "${d}"
  done
}

# ---- Case 11: a live close watcher extends the founder claim lease ---------
case_live_watcher_refreshes_lease() {
  local d root handle close_pid lease_state
  d="$(mktemp -d)"; root="${d}/repo"; handle="lease-alive-$$"
  mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"
  mkdir -p "${root}/docs"
  cat > "${root}/docs/tasks.yaml" <<'YAML'
- id: founder-lease
  lane: recovery
  status: in_progress
  claim:
    by: lease-session
    lease_expires: '2000-01-01T00:00:00Z'
YAML
  fake_glm_run "${d}" "${root}" "${handle}" 30 0
  GLM_RUNS_DIR="${FAKE_RUNS}" LEADV2_JOB_REGISTRY_ROOT="${FAKE_JOB_REGISTRY_ROOT}" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=10 LEADV2_PC_LEASE_REFRESH_EVERY_S=1 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    bash "${PC}" "${root}" nwls0011 glm "${handle}" 0 0 "founder-lease" >"${d}/close.log" 2>&1 &
  close_pid=$!; track_pid "${close_pid}"
  for _ in $(seq 1 50); do
    grep -q 'status=waiting_worker' "${d}/journal.log" 2>/dev/null && break
    sleep 0.1
  done
  lease_state="$(python3 - "${root}/docs/tasks.yaml" <<'PY'
import sys, yaml
item = (yaml.safe_load(open(sys.argv[1])) or [{}])[0]
claim = item.get("claim") or {}
print(f"{item.get('status')}|{claim.get('by')}|{claim.get('lease_expires')}")
PY
)"
  if [[ "${lease_state}" == in_progress\|lease-session\|* && "${lease_state}" != *2000-01-01* ]]; then
    ok "live close watcher extends lease without changing claim ownership"
  else bad "live close watcher did not refresh lease (got ${lease_state})"
  fi
  cleanup_case "${d}"
}

# ---- Case 12: worker commits, exits, and origin/main exposes committed work -
case_committed_worker_diff() {
  local d root handle close_pid rc handoff start_sha
  d="$(mktemp -d)"; root="${d}/repo"; handle="committed-work-$$"
  mkdir -p "${root}"; new_repo "${root}"; make_stubs "${d}"
  start_sha="$(git -C "${root}" rev-parse HEAD)"
  git -C "${root}" update-ref refs/remotes/origin/main "${start_sha}"
  fake_glm_run "${d}" "${root}" "${handle}" 1 2
  GLM_RUNS_DIR="${FAKE_RUNS}" LEADV2_JOB_REGISTRY_ROOT="${FAKE_JOB_REGISTRY_ROOT}" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=15 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    bash "${PC}" "${root}" nwcm0012 glm "${handle}" 0 0 "founder-commit" >"${d}/close.log" 2>&1 &
  close_pid=$!; track_pid "${close_pid}"
  wait "${close_pid}"; rc=$?
  handoff="${root}/docs/handoff/dispatch-nwcm0012"
  assert_eq "${rc}" "0" "committed worker reaches non-empty close path"
  if git -C "${root}" diff --quiet HEAD -- agent/seed.py && [[ -s "${handoff}/review.diff" ]] && grep -q 'worker diff' "${handoff}/review.diff"; then
    ok "committed-ahead diff is non-empty despite clean worker path"
  else bad "committed-ahead worker diff was classified empty"
  fi
  if grep -q 'write-terminal nwcm0012 .* landed review_gate_disabled' "${d}/ledger.log" 2>/dev/null; then
    ok "committed worker terminal reflects committed diff"
  else bad "committed worker terminal is not landed"
  fi
  cleanup_case "${d}"
}

# ---- Case 13: Codex probe time is part of the hard wait budget -------------
case_codex_probe_respects_budget() {
  local d root rc started elapsed
  d="$(mktemp -d)"; root="${d}/repo"; mkdir -p "${root}"
  new_repo "${root}"; make_stubs "${d}"
  cat > "${d}/slow-liveness.sh" <<'SH'
#!/usr/bin/env bash
sleep 10
printf '{"provider":"codex","jobs":[{"verdict":"done"}]}\n'
SH
  chmod +x "${d}/slow-liveness.sh"
  started="$(date +%s)"
  LEADV2_LANE_LIVENESS_BIN="${d}/slow-liveness.sh" LEADV2_JOB_REGISTRY_ROOT="${d}/job-registry" \
    LEADV2_PC_WORKER_POLL_S=1 LEADV2_PC_WORKER_MAX_WAIT_S=2 \
    LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" LEADV2_JOURNAL_BIN="${d}/journal.sh" LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" \
    bash "${PC}" "${root}" nwcb0013 codex task-slow-probe 0 0 "founder-budget" >"${d}/close.log" 2>&1
  rc=$?; elapsed=$(( $(date +%s) - started ))
  assert_eq "${rc}" "5" "slow Codex probe reaches bounded timeout path"
  if [[ "${elapsed}" -ge 2 && "${elapsed}" -lt 6 ]]; then ok "Codex probe latency stays inside wait budget"; else bad "Codex probe exceeded budget (${elapsed}s)"; fi
  if grep -q 'Traceback' "${d}/close.log" 2>/dev/null; then bad "Codex probe leaked a Python traceback"; else ok "Codex probe failures stay quiet"; fi
  cleanup_case "${d}"
}

case_empty_no_work
case_foreign_repo_landing
case_foreign_repo_absent_stays_no_work
case_partial_stays_refused
case_surface_no_work_not_done
case_alive_worker_has_no_terminal
case_diff_measured_after_exit
case_finished_empty_allowed
case_live_worker_timeout
case_codex_probe_waits
case_sonnet_natural_completion
case_revived_status_is_terminal_for_handle
case_live_watcher_refreshes_lease
case_committed_worker_diff
case_codex_probe_respects_budget

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
