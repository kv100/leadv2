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

set -uo pipefail
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

# ---- Case 1: dead PID, no evidence -> reclaim succeeds ----------------------
case_reclaims_dead_confirmed_row() {
  local d out sig8
  d="$(mktemp -d)"; setup_repo "${d}"

  # A PID guaranteed not to be running: fork a subshell, capture its PID, let it exit.
  ( exit 0 ) & local dead_pid=$!
  wait "${dead_pid}" 2>/dev/null

  local mission="V3-DISPATCHER retry-dead case 1 mission text"
  # Reserve a real ledger row by dispatching once with spawn disabled (SPAWN=0 leaves the
  # row "pending"); dispatch-code itself prints the sig8 in its journal lines.
  out="$(CLAUDE_PROJECT_ROOT="${d}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache-c1" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_REQUIRE_LANE_WRITES=0 LEADV2_ROUTER_V2=0 LEADV2_LANE_SHAPE=off LEADV2_EXCLUDED_ARMS=glm,codex,opus \
    LEADV2_DISPATCH_SPAWN=0 \
    bash "${DC}" "${mission}" --kind product 2>&1)"
  sig8="$(printf '%s\n' "${out}" | sed -n 's/.*task_sig=\([a-f0-9]\{8\}\).*/\1/p' | head -1)"
  [[ -n "${sig8}" ]] || sig8="$(printf '%s\n' "${out}" | grep -oE 'task=[a-f0-9]{8}' | head -1 | cut -d= -f2)"

  if [[ -z "${sig8}" ]]; then
    bad "case1 setup: could not extract sig8 from dispatch output (${out})"
    rm -rf "${d}"; return
  fi

  local ledger_file="${d}/cache-c1/dispatch-ledger/leadv2.jsonl"
  if [[ ! -f "${ledger_file}" ]]; then
    bad "case1 setup: no ledger file written at ${ledger_file}"
    rm -rf "${d}"; return
  fi
  # Force the row to a confirmed state with a known-dead sonnet PID handle, bypassing the
  # real spawn machinery (SPAWN=0 above never confirms) -- this isolates retry-dead's own
  # reclaim logic from spawn-path flakiness.
  python3 - "${ledger_file}" "${dead_pid}" <<'PY'
import json, sys
path, pid = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()
out = []
for ln in lines:
    row = json.loads(ln)
    if row.get("state") == "pending":
        row["state"] = "confirmed"
        row["arm"] = "sonnet"
        row["handle"] = pid
    out.append(json.dumps(row))
open(path, "w").write("\n".join(out) + "\n")
PY

  # A second dispatch of the SAME mission must be refused as duplicate first (sanity).
  local dup_out
  dup_out="$(CLAUDE_PROJECT_ROOT="${d}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache-c1" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_REQUIRE_LANE_WRITES=0 LEADV2_ROUTER_V2=0 LEADV2_LANE_SHAPE=off LEADV2_EXCLUDED_ARMS=glm,codex,opus \
    LEADV2_DISPATCH_SPAWN=0 \
    bash "${DC}" "${mission}" --kind product 2>&1)"
  if printf '%s' "${dup_out}" | grep -q 'duplicate_task_signature'; then
    ok "sanity: redispatch of the same mission is refused as duplicate before retry-dead runs"
  else
    bad "sanity check failed: expected duplicate_task_signature refusal before retry-dead (got: ${dup_out})"
  fi

  local rd_out rd_rc
  rd_out="$(CLAUDE_PROJECT_ROOT="${d}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache-c1" \
    bash "${DC}" retry-dead "${sig8}" 2>&1)"; rd_rc=$?
  if [[ ${rd_rc} -eq 0 ]] && printf '%s' "${rd_out}" | grep -q 'dispatch_retry_over_dead_attempt'; then
    ok "retry-dead clears a confirmed row whose PID is dead and has no evidence"
  else
    bad "expected retry-dead to succeed with dispatch_retry_over_dead_attempt (rc=${rd_rc}, out: ${rd_out})"
  fi

  local retry_out
  retry_out="$(CLAUDE_PROJECT_ROOT="${d}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache-c1" \
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
  local d out sig8
  d="$(mktemp -d)"; setup_repo "${d}"

  ( sleep 30 ) & local alive_pid=$!

  local mission="V3-DISPATCHER retry-dead case 2 mission text"
  out="$(CLAUDE_PROJECT_ROOT="${d}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache-c2" \
    LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
    LEADV2_REQUIRE_LANE_WRITES=0 LEADV2_ROUTER_V2=0 LEADV2_LANE_SHAPE=off LEADV2_EXCLUDED_ARMS=glm,codex,opus \
    LEADV2_DISPATCH_SPAWN=0 \
    bash "${DC}" "${mission}" --kind product 2>&1)"
  sig8="$(printf '%s\n' "${out}" | grep -oE 'task=[a-f0-9]{8}' | head -1 | cut -d= -f2)"

  local ledger_file="${d}/cache-c2/dispatch-ledger/leadv2.jsonl"
  if [[ -z "${sig8}" || ! -f "${ledger_file}" ]]; then
    bad "case2 setup: could not extract sig8 or ledger file missing (${out})"
    kill "${alive_pid}" 2>/dev/null; rm -rf "${d}"; return
  fi
  python3 - "${ledger_file}" "${alive_pid}" <<'PY'
import json, sys
path, pid = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()
out = []
for ln in lines:
    row = json.loads(ln)
    if row.get("state") == "pending":
        row["state"] = "confirmed"
        row["arm"] = "sonnet"
        row["handle"] = pid
    out.append(json.dumps(row))
open(path, "w").write("\n".join(out) + "\n")
PY

  local rd_out rd_rc
  rd_out="$(CLAUDE_PROJECT_ROOT="${d}" LEADV2_DISPATCH_CACHE_DIR="${d}/cache-c2" \
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
