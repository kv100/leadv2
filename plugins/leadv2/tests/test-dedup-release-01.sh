#!/usr/bin/env bash
# tests/test-dedup-release-01.sh — regression test for DEDUP-RELEASE-01.
#
# Defect: codex-task.sh's `status <id> --json` cross-workspace fallback (hit
# whenever a caller queries from a DIFFERENT cwd than the job's own
# workspaceRoot -- e.g. leadv2-lane-liveness.sh querying with
# --cwd "$PROJECT_ROOT" for a job that ran from a worktree,
# .claude/worktrees/<sig8>) always rendered the plain-text
# "<id> <status> <phase> workspaceRoot=... log=..." line, even when --json
# was passed. leadv2-lane-liveness.sh's provider_jobs() feeds that string
# through json.loads(); a non-JSON line throws, so it silently returned {}
# regardless of the job's real status. leadv2-dispatch-code.sh's
# _dispatch_worker_liveness() then resolved verdict="unknown" for EVERY
# worktree-dispatched codex job, and _dispatch_outcome_blocks()'s safe
# default ("unknown" -> blocks, never free a live-or-unprovable task) meant
# a confirmed dedup-ledger row for a dead codex worker could NEVER be
# reclaimed, no matter how dead the worker actually was -- root cause of
# the 2026-08-21 hand-clear incident (4 lanes, `dispatch_refused
# reason=duplicate_task_signature`, only recoverable by hand-clearing the
# ledger).
#
# Note: leadv2-dispatch-code.sh's outcome-ledger machinery
# (_dispatch_worker_liveness / _dispatch_outcome_blocks /
# _dispatch_sig_blocked, guarded by OUTCOME_LEDGER default=1) ALREADY
# implements the fail-closed dedup-release contract correctly (arm's own
# registry, never a timeout guess; unknown/alive never freed; one
# `dispatch_reclaimed`-shaped decision line per release). The break was
# entirely upstream, in codex-task.sh's status fallback silently returning
# non-JSON for a --json caller. This test proves the fix through the REAL
# end-to-end chain rather than adding a second, redundant reclaim
# mechanism to leadv2-dispatch-code.sh.
#
# Fix: the cross-workspace fallback now emits a `{"job": {...}}` object
# (the same "job" key provider_jobs() already understands) when the caller
# passed --json, leaving the plain-text line unchanged for every caller
# that does not.
#
# This test exercises the REAL production chain end to end against a
# planted job-state fixture (in the REAL state root -- codex-task.sh hard
# requires a real installed codex-companion.mjs to even start, so faking
# $HOME is not viable; the fixture lane id is a random, collision-proof
# throwaway and is removed in the EXIT trap) that reproduces the exact
# worker_process_died shape from the incident:
#   codex-task.sh status --json  ->  leadv2-lane-liveness.sh --job --json
#   ->  _dispatch_worker_liveness (sourced from leadv2-dispatch-code.sh)
#   ->  _dispatch_outcome_blocks
# and separately asserts the FAIL-CLOSED direction: a job whose state file
# says "running" must still block (never released) through the exact same
# chain, and an unresolvable handle must ALSO still block.
#
# Usage: bash tests/test-dedup-release-01.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"
CODEX_TASK_SH="${SCRIPTS_DIR}/codex-task.sh"
LIVENESS_SH="${SCRIPTS_DIR}/leadv2-lane-liveness.sh"
DISPATCH_SH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

TMPD="$(mktemp -d)"
LANE_ID="dedup-release-01-test-$$-${RANDOM}${RANDOM}"
STATE_ROOT="$HOME/.claude/plugins/data/codex-openai-codex/state"
LANE_DIR="${STATE_ROOT}/${LANE_ID}/jobs"
cleanup() {
  rm -rf "$TMPD" 2>/dev/null || true
  rm -rf "${STATE_ROOT}/${LANE_ID}" 2>/dev/null || true
}
trap cleanup EXIT
mkdir -p "$LANE_DIR"

PROJECT_ROOT="${TMPD}/repo"
mkdir -p "$PROJECT_ROOT"
# _dispatch_evidence_exists shells out to `git log` against PROJECT_ROOT and
# fails closed (treats a git error as "evidence unknown" -> blocks) when the
# path is not a git repo at all -- true in production (PROJECT_ROOT is always
# a real checkout) but not by default in a mktemp fixture, so this test must
# init one to exercise the REAL rc0/rc1 boundary instead of the git-error one.
(cd "$PROJECT_ROOT" && git init -q && git config user.email t@t.com && git config user.name t && git commit -q --allow-empty -m init)

DEAD_JOB="task-deadworker-$$-000001"
cat > "${LANE_DIR}/${DEAD_JOB}.json" <<EOF
{"id": "${DEAD_JOB}", "status": "failed", "phase": "failed",
 "workspaceRoot": "${PROJECT_ROOT}/.claude/worktrees/deadbeef",
 "logFile": "${LANE_DIR}/${DEAD_JOB}.log", "errorMessage": "worker_process_died"}
EOF
touch "${LANE_DIR}/${DEAD_JOB}.log"

ALIVE_JOB="task-aliveworker-$$-000002"
cat > "${LANE_DIR}/${ALIVE_JOB}.json" <<EOF
{"id": "${ALIVE_JOB}", "status": "running", "phase": "running",
 "workspaceRoot": "${PROJECT_ROOT}/.claude/worktrees/alivebeef",
 "logFile": "${LANE_DIR}/${ALIVE_JOB}.log"}
EOF
touch "${LANE_DIR}/${ALIVE_JOB}.log"

# ── Step 1: codex-task.sh status --json cross-workspace fallback ───────────
# Query from $PROJECT_ROOT (NOT the job's own workspaceRoot under
# .claude/worktrees/), forcing the companion's cwd-scoped lookup to miss and
# fall into the cross-workspace scan -- exactly the incident's shape.
dead_status_json="$(bash "$CODEX_TASK_SH" status "$DEAD_JOB" --json --cwd "$PROJECT_ROOT" 2>/dev/null)"
if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d.get('job',{}).get('status')=='failed'" "$dead_status_json" 2>/dev/null; then
  pass "codex-task.sh status --json (cross-workspace fallback) emits valid JSON with status=failed for the dead job"
else
  fail "codex-task.sh status --json did not emit parseable {\"job\":{\"status\":\"failed\"}} -- got: ${dead_status_json}"
fi

alive_status_json="$(bash "$CODEX_TASK_SH" status "$ALIVE_JOB" --json --cwd "$PROJECT_ROOT" 2>/dev/null)"
if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d.get('job',{}).get('status')=='running'" "$alive_status_json" 2>/dev/null; then
  pass "codex-task.sh status --json (cross-workspace fallback) emits valid JSON with status=running for the alive job"
else
  fail "codex-task.sh status --json did not emit parseable {\"job\":{\"status\":\"running\"}} for the alive job -- got: ${alive_status_json}"
fi

# Plain-text (non-json) callers must see byte-identical output to before the fix.
dead_status_plain="$(bash "$CODEX_TASK_SH" status "$DEAD_JOB" --cwd "$PROJECT_ROOT" 2>/dev/null)"
expected_plain="${DEAD_JOB} failed failed workspaceRoot=${PROJECT_ROOT}/.claude/worktrees/deadbeef log=${LANE_DIR}/${DEAD_JOB}.log"
if [[ "$dead_status_plain" == "$expected_plain" ]]; then
  pass "codex-task.sh status (no --json) is byte-identical to the pre-fix plain-text line"
else
  fail "plain-text status output changed shape -- expected [${expected_plain}] got [${dead_status_plain}]"
fi

# ── Step 2: leadv2-lane-liveness.sh --job --json (full chain, real script) ─
dead_liveness_json="$(CODEX_TASK_SH="$CODEX_TASK_SH" \
  bash "$LIVENESS_SH" --project-root "$PROJECT_ROOT" --job "$DEAD_JOB" --json 2>/dev/null)"
dead_verdict="$(printf '%s' "$dead_liveness_json" | python3 -c "import json,sys; d=json.load(sys.stdin); j=d.get('jobs') or []; print(j[0].get('verdict','unknown') if j else 'unknown')" 2>/dev/null)"
if [[ "$dead_verdict" == "failed" ]]; then
  pass "leadv2-lane-liveness.sh --job --json resolves verdict=failed for the dead worktree job"
else
  fail "leadv2-lane-liveness.sh --job --json resolved verdict=${dead_verdict} (expected failed) -- raw: ${dead_liveness_json}"
fi

alive_liveness_json="$(CODEX_TASK_SH="$CODEX_TASK_SH" \
  bash "$LIVENESS_SH" --project-root "$PROJECT_ROOT" --job "$ALIVE_JOB" --json 2>/dev/null)"
alive_verdict="$(printf '%s' "$alive_liveness_json" | python3 -c "import json,sys; d=json.load(sys.stdin); j=d.get('jobs') or []; print(j[0].get('verdict','unknown') if j else 'unknown')" 2>/dev/null)"
if [[ "$alive_verdict" == "running" ]]; then
  pass "leadv2-lane-liveness.sh --job --json resolves verdict=running for the alive worktree job"
else
  fail "leadv2-lane-liveness.sh --job --json resolved verdict=${alive_verdict} (expected running) -- raw: ${alive_liveness_json}"
fi

# ── Step 3: _dispatch_worker_liveness + _dispatch_outcome_blocks (real
# functions, sourced from leadv2-dispatch-code.sh) — the actual dedup gate.
DISPATCH_FUNCS_FILE="${TMPD}/dispatch-funcs.sh"
{
  sed -n '/^_dispatch_row_fields() {/,/^}$/p' "$DISPATCH_SH"
  sed -n '/^_dispatch_normalize_handle() {/,/^}$/p' "$DISPATCH_SH"
  sed -n '/^_dispatch_worker_liveness() {/,/^}$/p' "$DISPATCH_SH"
  sed -n '/^_dispatch_handoff_evidence_exists() {/,/^}$/p' "$DISPATCH_SH"
  sed -n '/^_dispatch_evidence_exists() {/,/^}$/p' "$DISPATCH_SH"
  sed -n '/^_dispatch_checkpoint_marker() {/,/^}$/p' "$DISPATCH_SH"
  sed -n '/^_dispatch_completion_sentinel() {/,/^}$/p' "$DISPATCH_SH"
  sed -n '/^_dispatch_maxturns_cutoff() {/,/^}$/p' "$DISPATCH_SH"
  sed -n '/^_dispatch_checkpointed_cutoff() {/,/^}$/p' "$DISPATCH_SH"
  sed -n '/^_dispatch_outcome_blocks() {/,/^}$/p' "$DISPATCH_SH"
} > "$DISPATCH_FUNCS_FILE"
if [[ ! -s "$DISPATCH_FUNCS_FILE" ]]; then
  fail "could not extract the outcome-ledger functions from leadv2-dispatch-code.sh -- have they been renamed/removed?"
else
  pass "extracted _dispatch_worker_liveness + _dispatch_outcome_blocks (and helpers) from leadv2-dispatch-code.sh ($(wc -l < "$DISPATCH_FUNCS_FILE") lines)"
fi

run_outcome_check() {  # <label> <job_id> <expect_blocks 0|1>
  local label="$1"
  local job_id="$2"
  local expect_blocks="$3"
  local out rc
  out="$(bash -c "
    set -u
    CODEX_BIN='$CODEX_TASK_SH'
    LEADV2_DISPATCH_LANE_LIVENESS_BIN='$LIVENESS_SH'
    PROJECT_ROOT='$PROJECT_ROOT'
    EVIDENCE_ATTRIBUTION=0
    CHECKPOINT_CUTOFF=0
    EVIDENCE_EXCLUDE_RE='\.lock\$|(^|/)docs/leadv2/\.bus-offsets/|(^|/)docs/leadv2/active\.yaml\$'
    emit() { :; }
    source '$DISPATCH_FUNCS_FILE'
    _dispatch_outcome_blocks codex '$job_id' 0 deadbeef
  " 2>&1)"
  rc=$?
  if [[ "$expect_blocks" == "1" ]]; then
    if [[ $rc -eq 0 ]]; then
      pass "${label}: outcome check BLOCKS (dedup row kept) -- ${out:-<no output>}"
    else
      fail "${label}: expected BLOCKS (rc0) but got rc=${rc} -- ${out:-<no output>}"
    fi
  else
    if [[ $rc -eq 1 ]]; then
      pass "${label}: outcome check FREES the row (dead worker, no evidence) -- ${out:-<no output>}"
    else
      fail "${label}: expected FREE (rc1) but got rc=${rc} -- ${out:-<no output>}"
    fi
  fi
}

run_outcome_check "dead worktree job (no evidence dir)" "$DEAD_JOB" 0
run_outcome_check "alive worktree job (fail-closed direction)" "$ALIVE_JOB" 1
run_outcome_check "unknown/unresolvable handle (fail-closed direction)" "task-does-not-exist-000000" 1

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[[ "$FAIL" -eq 0 ]]
