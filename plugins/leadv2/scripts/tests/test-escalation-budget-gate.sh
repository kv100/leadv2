#!/usr/bin/env bash
# tests/test-escalation-budget-gate.sh — NESTED-AGENTS-AND-FORKS-01 (item 3)
#
# The brief's premise as written ("escalation-budget.yaml appears 4 times in
# 30 days, never denied anything -- prove real or delete") reads as
# vaporware. It is not: hooks/leadv2-routing-guard.sh implements a complete,
# wired escalation-budget deny path (registered on the Agent matcher in
# hooks.json), atomically incrementing `used` under flock and denying with
# named reasons once `used >= max_escalations`. What was actually missing was
# only a test exercising that path -- nobody had ever driven the deny branch,
# which is why the census found "never denied anything." This suite drives
# the REAL hook script against a scratch fixture (a plain git repo + a hand-
# written escalation-budget.yaml), asserting: first nested spawn beyond the
# base allowlist is ALLOWED and increments `used`; the second, once
# used>=max_escalations, is DENIED with escalation_budget_exhausted; and a
# negative control that neuters the ONE comparison inside the budget-check
# function body (`if used >= max_esc:`) flips the second call back to ALLOW,
# proving this suite actually exercises that line.
# run-all-triggers: leadv2-routing-guard

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SH="${SCRIPT_DIR}/../../hooks/leadv2-routing-guard.sh"
FAIL=0

bash -n "${HOOK_SH}" || { echo "ERROR: bash -n failed for ${HOOK_SH}"; exit 1; }

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

REPO="${TMP_ROOT}/repo"
mkdir -p "${REPO}"
git -C "${REPO}" init -q
git -C "${REPO}" config user.email t@t
git -C "${REPO}" config user.name t
echo x > "${REPO}/f.txt"
git -C "${REPO}" add .
git -C "${REPO}" commit -qm init

TASK_ID="ESC-BUDGET-TEST-01"
BUDGET_DIR="${REPO}/docs/handoff/${TASK_ID}"
mkdir -p "${BUDGET_DIR}"
cat > "${BUDGET_DIR}/escalation-budget.yaml" <<'YAML'
max_escalations: 1
used: 0
allowed_types: [critic]
allowed_models: [opus]
YAML

# A request outside the base allowlist (explore|general-purpose with
# haiku|sonnet): caller="developer" (a caller type, unaffected by the
# write-role-denied gate, which only inspects the REQUESTED subagent_type),
# requesting subagent_type="critic" model="opus" -- not in the base
# allowlist, not a write-capable role either, so it falls straight through to
# the escalation-budget check.
INPUT='{"agent_type":"developer","tool_input":{"subagent_type":"critic","model":"opus"},"cwd":"'"${REPO}"'"}'

run_hook() { printf '%s' "${INPUT}" | LEADV2_TASK_ID="${TASK_ID}" bash "${HOOK_SH}"; }

# --- test 1: first nested spawn within budget -- ALLOW ---
out1="$(run_hook 2>&1)"; rc1=$?
if [[ ${rc1} -eq 0 ]]; then
  pass "first nested spawn within budget is allowed (rc=0)"
else
  fail "first spawn" "rc=${rc1} out='${out1}' want rc=0"
fi

used_after_1="$(grep -oE 'used:\s*[0-9]+' "${BUDGET_DIR}/escalation-budget.yaml" | grep -oE '[0-9]+')"
if [[ "${used_after_1}" == "1" ]]; then
  pass "budget file's used counter incremented to 1 after the allowed spawn"
else
  fail "budget increment" "used='${used_after_1}' want 1"
fi

# --- test 2: second nested spawn, budget now exhausted -- DENY ---
out2="$(run_hook 2>&1)"; rc2=$?
if [[ ${rc2} -eq 2 && "${out2}" == *"escalation budget exhausted"* ]]; then
  pass "second nested spawn is denied once used>=max_escalations (rc=2, escalation_budget_exhausted)"
else
  fail "second spawn" "rc=${rc2} out='${out2}' want rc=2 mentioning 'escalation budget exhausted'"
fi

# --- test 3: MUTATION CONTROL -- neuter the ONE comparison inside the
# budget-check function body (never a top-level/line-number insert): the
# `if used >= max_esc:` guard becomes `if False:`, so the check that must
# deny the exhausted case instead always falls through to ALLOW. Confirms
# this suite actually exercises that comparison, not just "hook runs".
MUT_SH="${TMP_ROOT}/mutated-routing-guard.sh"
sed -E 's/if used >= max_esc:/if False:  # NEGATIVE CONTROL: check neutered/' "${HOOK_SH}" > "${MUT_SH}"
if diff -q "${HOOK_SH}" "${MUT_SH}" >/dev/null 2>&1; then
  fail "mutation control" "sed produced a byte-identical file -- the mutation never applied, this control proves nothing"
else
  # Reset the fixture to a freshly-exhausted budget so the mutation's effect
  # (bypassing the deny) is the only variable between this and test 2.
  cat > "${BUDGET_DIR}/escalation-budget.yaml" <<'YAML'
max_escalations: 1
used: 1
allowed_types: [critic]
allowed_models: [opus]
YAML
  mut_out="$(printf '%s' "${INPUT}" | LEADV2_TASK_ID="${TASK_ID}" bash "${MUT_SH}" 2>&1)"; mut_rc=$?
  if [[ ${mut_rc} -eq 0 ]]; then
    pass "MUTATION CONTROL: neutering 'if used >= max_esc:' inside the function body flips the exhausted case to ALLOW (suite would go red)"
  else
    fail "mutation control" "mutated hook still returned rc=${mut_rc} out='${mut_out}' -- mutation did not neutralize the check as intended"
  fi
fi

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS: test-escalation-budget-gate.sh"
  exit 0
else
  echo "SOME FAILED: test-escalation-budget-gate.sh"
  exit 1
fi
