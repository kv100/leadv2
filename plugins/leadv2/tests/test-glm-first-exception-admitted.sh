#!/usr/bin/env bash
# tests/test-glm-first-exception-admitted.sh — proves the glm_quota_gate_80
# exception token (ROUTING-BURNS-THE-SCARCEST-BUCKET-01 §1e/§3.1) is actually
# admitted by the GLM-FIRST-01 enforcement hook, and that the SAME payload
# without the token is denied.
#
# The hook itself (leadv2-glm-first-agent-gate.sh) is a per-repo file — it is
# NOT plugin-owned (it lives at <repo>/.claude/hooks/, registered in that
# repo's settings.json PreToolUse:Agent matcher), so this test resolves it
# via, in order: $LEADV2_GLM_FIRST_HOOK override (hermetic CI use),
# $CLAUDE_PROJECT_DIR/.claude/hooks/... (the exact path Claude Code's hook
# runner uses), then a walk up from CWD looking for .claude/hooks/... . If
# none resolve, the test SKIPS (exit 0) rather than falsely failing a plugin
# CI run that has no calling project checked out.
#
# Usage: bash tests/test-glm-first-exception-admitted.sh
set -euo pipefail

resolve_hook() {
  if [[ -n "${LEADV2_GLM_FIRST_HOOK:-}" && -f "${LEADV2_GLM_FIRST_HOOK}" ]]; then
    printf '%s' "${LEADV2_GLM_FIRST_HOOK}"
    return 0
  fi
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -f "${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-glm-first-agent-gate.sh" ]]; then
    printf '%s' "${CLAUDE_PROJECT_DIR}/.claude/hooks/leadv2-glm-first-agent-gate.sh"
    return 0
  fi
  local _dir="${PWD}"
  while [[ "${_dir}" != "/" ]]; do
    if [[ -f "${_dir}/.claude/hooks/leadv2-glm-first-agent-gate.sh" ]]; then
      printf '%s' "${_dir}/.claude/hooks/leadv2-glm-first-agent-gate.sh"
      return 0
    fi
    _dir="$(dirname "${_dir}")"
  done
  return 1
}

HOOK="$(resolve_hook || true)"
if [[ -z "${HOOK}" ]]; then
  printf 'SKIP test-glm-first-exception-admitted: no leadv2-glm-first-agent-gate.sh found in any calling project (set LEADV2_GLM_FIRST_HOOK to run hermetically)\n'
  exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/glm-first-exc.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT
JOURNAL="${tmp}/exceptions.jsonl"
FENCE="${tmp}/denies.jsonl"

run_hook() {
  local prompt="$1"
  python3 -c '
import json, sys
print(json.dumps({
    "tool_name": "Agent",
    "session_id": "test-session-glm-first-exc",
    "tool_input": {
        "subagent_type": "developer",
        "model": "sonnet",
        "prompt": sys.argv[1],
    },
}))
' "${prompt}" | LEADV2_GLM_EXCEPTION_JOURNAL="${JOURNAL}" LEADV2_DISPATCH_FENCE_LOG="${FENCE}" bash "${HOOK}"
}

# ---- 1. WITH the approved token: must NOT deny (no permissionDecision:deny in stdout) ----
WITH_TOKEN_MISSION="GLM_FIRST_EXCEPTION=glm_quota_gate_80
(router-issued: GLM quota gate refused this lane at >=80%; arm chosen from live headroom.)

Implement the thing."
out_with="$(run_hook "${WITH_TOKEN_MISSION}")"

if grep -q '"permissionDecision":"deny"' <<<"${out_with}"; then
  printf 'FAIL: spawn carrying glm_quota_gate_80 was DENIED — hook output: %s\n' "${out_with}" >&2
  exit 1
fi

if [[ ! -s "${JOURNAL}" ]]; then
  printf 'FAIL: exception journal was not written for an admitted glm_quota_gate_80 spawn\n' >&2
  exit 1
fi
if ! grep -q '"event":"glm_first_exception_used"' "${JOURNAL}"; then
  printf 'FAIL: exception journal missing glm_first_exception_used row: %s\n' "$(cat "${JOURNAL}")" >&2
  exit 1
fi
if ! grep -q '"exception":"glm_quota_gate_80"' "${JOURNAL}"; then
  printf 'FAIL: exception journal row does not name exception=glm_quota_gate_80: %s\n' "$(cat "${JOURNAL}")" >&2
  exit 1
fi
if [[ -s "${FENCE}" ]]; then
  printf 'FAIL: an admitted spawn wrote a code_dispatch_denied row to the fence log: %s\n' "$(cat "${FENCE}")" >&2
  exit 1
fi

# ---- 2. WITHOUT the token: same subagent_type/model MUST be denied ----
out_without="$(run_hook "Implement the thing.")"
if ! grep -q '"permissionDecision":"deny"' <<<"${out_without}"; then
  printf 'FAIL: spawn WITHOUT any exception token was NOT denied — hook output: %s\n' "${out_without}" >&2
  exit 1
fi
if [[ ! -s "${FENCE}" ]]; then
  printf 'FAIL: denied spawn did not write a code_dispatch_denied fence row\n' >&2
  exit 1
fi
if ! grep -q '"event":"code_dispatch_denied"' "${FENCE}"; then
  printf 'FAIL: fence log missing code_dispatch_denied row: %s\n' "$(cat "${FENCE}")" >&2
  exit 1
fi

printf 'PASS test-glm-first-exception-admitted (hook=%s)\n' "${HOOK}"
