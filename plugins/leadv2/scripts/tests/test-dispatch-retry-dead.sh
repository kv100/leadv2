#!/usr/bin/env bash
# V3-DISPATCHER-ACCEPTANCE-01 Fault 3 — retry-dead sanctioned path.
#
# Live incident: a worker died mid-flight; every redispatch of the SAME
# mission text was refused as duplicate_task_signature until the ledger row
# was hand-deleted by exact sig -- 4x in one night. `retry-dead <sig8>` is the
# on-demand version of the automatic outcome-ledger reclaim: it clears a row
# ONLY when the recorded worker is provably dead (liveness=dead) AND no
# terminal artifact exists for the task -- never a blind force-clear.
#
# Case 1 (red before the flag existed / green after): a confirmed row whose
# sonnet PID handle is not running, no docs/handoff evidence -> retry-dead
# clears it, journals dispatch_retry_over_dead_attempt, and a subsequent
# dispatch of the identical mission is no longer refused as a duplicate.
# Case 2 (must refuse, not force): a confirmed row whose PID IS alive ->
# retry-dead refuses (exit 2), leaves the row in place, next dispatch is
# still refused as duplicate.
#
# FIX-ROUND (critic blocker 3, dispatch-b4042501-review): SPAWN=0 never
# leaves a ledger row at all -- dispatch_abort rolls the reservation back
# and dispatch-code journals `dispatch_rolled_back reason=no_spawn_dry_run`
# before exiting 0 (leadv2-dispatch-code.sh ~4836). Both cases below now
# dispatch with LEADV2_DISPATCH_SPAWN=1 and a stubbed
# LEADV2_DISPATCH_SUBSESSION_BIN (a fake launcher that prints
# `PID=<real backgrounded pid>` as its handle line) so spawn_worker's
# kill-0 liveness check at spawn time genuinely passes and dispatch_confirm
# writes a real `state:"confirmed"` row -- exactly the row shape retry-dead
# is built to reclaim. LEADV2_ARM_EARLY_VERDICT_S=0 disables the 20s
# post-spawn poll window (sonnet has no status adapter, so it would
# otherwise idle out every run).
#
# FIX-ROUND-3 (item 3, dispatch-b4042501-review codex.r2): the guard added in
# blocker 2 now DEFAULTS ON, and every `bash "${DC}" ...` call below set
# CLAUDE_PROJECT_ROOT to the fixture repo ${d} WITHOUT ever `cd`-ing there
# first -- exactly the non-hermetic shape the guard's own header warns about
# (this suite's own checkout is cwd, ${d} is a different real repo in env, so
# the guard silently rerooted PROJECT_ROOT onto the checkout instead of the
# fixture). Every dispatch/retry-dead invocation is now wrapped in
# `( cd "${d}" && ... )` so cwd's git toplevel equals the fixture, matching
# every other guard-aware suite. Case 1 also now asserts the
# `dispatch_retry_over_dead_attempt` journal line actually lands in the task
# journal file (not just stdout) -- retry-dead sets JOURNAL_TASK itself
# (leadv2-dispatch-code.sh cmd_retry_dead), so this proves that delivery
# path, not just the printf mirror.

set -uo pipefail
# Dev-shell hygiene: this suite may itself run inside a leadv2 lane worktree,
# whose own session env carries LEADV2_LANE_WORK_ROOT / PROJECT_ROOT for THIS
# lane -- unset before dispatching so the fixture repo's CLAUDE_PROJECT_ROOT
# is the only root signal each dispatch call sees (same pattern as
# test-lane-placement-pin.sh).
unset PROJECT_ROOT 2>/dev/null || true
unset LEADV2_LANE_WORK_ROOT 2>/dev/null || true
unset LEADV2_PROJECT_ROOT 2>/dev/null || true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DC="${SCRIPT_DIR}/leadv2-dispatch-code.sh"
PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

setup_repo() {
  local d="$1"
  mkdir -p "${d}/.claude/ref"
  ( cd "${d}" && git init -q && git config user.email t@e.com && git config user.name t && : > seed && git add seed && git commit -qm seed )
  printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' > "${d}/.claude/ref/leadv2-routing.yaml"
}

# A fake sonnet launcher: ignores its args, prints a PID= handle line for a
# REAL backgrounded process ($LV2_TEST_ALIVE_PID, set by the caller before
# invoking dispatch), and exits 0 -- mirrors claude-subsession.sh's no-wait
# handle contract (`PID=<pid> LABEL=... SESSION_ID=...`) without spawning a
# real claude session.
write_fake_subsession_bin() {
  local f="$1"
  cat > "${f}" <<'EOS'
#!/usr/bin/env bash
printf 'PID=%s LABEL=test SESSION_ID=test\n' "${LV2_TEST_ALIVE_PID:?LV2_TEST_ALIVE_PID unset}"
exit 0
EOS
  chmod +x "${f}"
}

# ---- Case 1: dead PID, no evidence -> reclaim succeeds ----------------------
case_reclaims_dead_confirmed_row() {
  local d out sig8 stub
  d="$(mktemp -d)"; setup_repo "${d}"
  stub="${d}/fake-subsession.sh"; write_fake_subsession_bin "${stub}"

  # A real, alive-at-spawn-time process so spawn_worker's kill-0 liveness check
  # passes and the row is genuinely confirmed -- killed right after, before
  # retry-dead runs, so it is provably dead by the time retry-dead probes it.
  ( sleep 30 ) & local case1_pid=$!

  local mission="V3-DISPATCHER retry-dead case 1 mission text"
  out="$(cd "${d}" && CLAUDE_PROJECT_ROOT="${d}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache-c1" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_REQUIRE_LANE_WRITES=0 LEADV2_ROUTER_V2=0 LEADV2_LANE_SHAPE=off LEADV2_EXCLUDED_ARMS=glm,codex,opus \
    LEADV2_DISPATCH_SPAWN=1 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_DISPATCH_SUBSESSION_BIN="${stub}" LV2_TEST_ALIVE_PID="${case1_pid}" \
    bash "${DC}" "${mission}" --kind product 2>&1)"
  sig8="$(printf '%s\n' "${out}" | sed -n 's/.*task_sig=\([a-f0-9]\{8\}\).*/\1/p' | head -1)"
  [[ -n "${sig8}" ]] || sig8="$(printf '%s\n' "${out}" | grep -oE 'task=[a-f0-9]{8}' | head -1 | cut -d= -f2)"

  if [[ -z "${sig8}" ]]; then
    bad "case1 setup: could not extract sig8 from dispatch output (${out})"
    kill "${case1_pid}" 2>/dev/null; rm -rf "${d}"; return
  fi

  local ledger_file; ledger_file="$(ls "${d}/cache-c1/dispatch-ledger/"*.jsonl 2>/dev/null | head -1)"
  if [[ ! -f "${ledger_file}" ]] || ! grep -qF '"state":"confirmed"' "${ledger_file}"; then
    bad "case1 setup: no confirmed ledger row at ${ledger_file} (out: ${out})"
    kill "${case1_pid}" 2>/dev/null; rm -rf "${d}"; return
  fi
  ok "case1 setup: a real confirmed row was written by dispatch itself (no hand-crafted state)"

  # Now kill the handle so it is provably dead at reclaim time.
  kill "${case1_pid}" 2>/dev/null
  wait "${case1_pid}" 2>/dev/null

  # NOTE: no "must be refused as duplicate first" sanity probe here. A plain
  # redispatch of a dead+no-evidence row is ALSO auto-reclaimed by dispatch's
  # own dispatch_outcome_blocks()/unattributed_empty path (leadv2-dispatch-
  # code.sh ~2021) -- probing it here would just exercise that unrelated
  # mechanism (and silently clear the row) before retry-dead ever runs.
  # retry-dead's distinguishing value is clearing the row WITHOUT attempting
  # a new dispatch/spawn; that is what's proven below.
  local rd_out rd_rc
  rd_out="$(cd "${d}" && CLAUDE_PROJECT_ROOT="${d}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache-c1" \
    bash "${DC}" retry-dead "${sig8}" 2>&1)"; rd_rc=$?
  if [[ ${rd_rc} -eq 0 ]] && printf '%s' "${rd_out}" | grep -q 'dispatch_retry_over_dead_attempt'; then
    ok "retry-dead clears a confirmed row whose PID is dead and has no evidence"
  else
    bad "expected retry-dead to succeed with dispatch_retry_over_dead_attempt (rc=${rd_rc}, out: ${rd_out})"
  fi

  # item 3: prove the journal LINE, not just stdout, actually landed -- retry-dead
  # sets JOURNAL_TASK="dispatch-${sig8}" itself, so the file lives at the default
  # leadv2_dir (docs/leadv2, no override configured by this fixture).
  local journal_file="${d}/docs/leadv2/tasks/dispatch-${sig8}/journal.md"
  if [[ -f "${journal_file}" ]] && grep -q 'dispatch_retry_over_dead_attempt' "${journal_file}"; then
    ok "retry-dead's dispatch_retry_over_dead_attempt line lands in the task journal file"
  else
    bad "expected dispatch_retry_over_dead_attempt in ${journal_file} (present: $([[ -f "${journal_file}" ]] && echo yes || echo no))"
  fi

  local retry_out
  retry_out="$(cd "${d}" && CLAUDE_PROJECT_ROOT="${d}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache-c1" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_REQUIRE_LANE_WRITES=0 LEADV2_ROUTER_V2=0 LEADV2_LANE_SHAPE=off LEADV2_EXCLUDED_ARMS=glm,codex,opus \
    LEADV2_DISPATCH_SPAWN=0 \
    bash "${DC}" "${mission}" --kind product 2>&1)"
  if printf '%s' "${retry_out}" | grep -q 'duplicate_task_signature'; then
    bad "expected redispatch to succeed after retry-dead cleared the row (still refused: ${retry_out})"
  else
    ok "redispatch of the identical mission is no longer refused after retry-dead"
  fi

  rm -rf "${d}"
}

# ---- Case 2: alive PID -> refuse, do not force -------------------------------
case_refuses_alive_row() {
  local d out sig8 stub
  d="$(mktemp -d)"; setup_repo "${d}"
  stub="${d}/fake-subsession.sh"; write_fake_subsession_bin "${stub}"

  ( sleep 30 ) & local alive_pid=$!

  local mission="V3-DISPATCHER retry-dead case 2 mission text"
  out="$(cd "${d}" && CLAUDE_PROJECT_ROOT="${d}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache-c2" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_REQUIRE_LANE_WRITES=0 LEADV2_ROUTER_V2=0 LEADV2_LANE_SHAPE=off LEADV2_EXCLUDED_ARMS=glm,codex,opus \
    LEADV2_DISPATCH_SPAWN=1 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_DISPATCH_SUBSESSION_BIN="${stub}" LV2_TEST_ALIVE_PID="${alive_pid}" \
    bash "${DC}" "${mission}" --kind product 2>&1)"
  sig8="$(printf '%s\n' "${out}" | grep -oE 'task=[a-f0-9]{8}' | head -1 | cut -d= -f2)"

  local ledger_file; ledger_file="$(ls "${d}/cache-c2/dispatch-ledger/"*.jsonl 2>/dev/null | head -1)"
  if [[ -z "${sig8}" || ! -f "${ledger_file}" ]] || ! grep -qF '"state":"confirmed"' "${ledger_file}"; then
    bad "case2 setup: could not extract sig8 or no confirmed ledger row (${out})"
    kill "${alive_pid}" 2>/dev/null; rm -rf "${d}"; return
  fi
  ok "case2 setup: a real confirmed row was written by dispatch itself (no hand-crafted state)"

  local rd_out rd_rc
  rd_out="$(cd "${d}" && CLAUDE_PROJECT_ROOT="${d}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache-c2" \
    bash "${DC}" retry-dead "${sig8}" 2>&1)"; rd_rc=$?
  if [[ ${rd_rc} -eq 2 ]] && printf '%s' "${rd_out}" | grep -q 'not_dead'; then
    ok "retry-dead refuses a row whose PID is still alive (rc=2, reason=not_dead)"
  else
    bad "expected refusal (rc=2, reason=not_dead) for an alive PID (rc=${rd_rc}, out: ${rd_out})"
  fi

  kill "${alive_pid}" 2>/dev/null
  wait "${alive_pid}" 2>/dev/null
  rm -rf "${d}"
}

case_reclaims_dead_confirmed_row
case_refuses_alive_row

printf '[test-dispatch-retry-dead] pass=%s fail=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
