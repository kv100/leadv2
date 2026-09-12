#!/usr/bin/env bash
# tests/test-status-collector-facts.sh — CODE-INTEL-IS-INSTALLED-AND-UNUSED-01
#
# .claude/leadv2-overrides/status-collector-facts.sh is the repo_facts hook
# that puts the code-intel attach rate (leadv2-code-intel-rate.sh) in front
# of the status surfaces (leadv2-status-collector.sh -> repo_facts ->
# leadv2-status-surface.sh render_repo_facts), so the
# rate can never again silently regress to 0/5 attached without anyone
# seeing it. This suite proves collect_repo_facts():
#   - always emits exactly one valid JSON object (the collector's own
#     contract -- an invalid section is dropped, not fatal, but this hook
#     must hold up its end);
#   - reports "0 decisions" honestly on an empty tree, never a fabricated
#     rate;
#   - surfaces a real rate + per-arm breakdown when data exists.
#
# Run: bash plugins/leadv2/scripts/tests/test-status-collector-facts.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_SCRIPTS}/../../.." && pwd)"
HOOK="${REPO_ROOT}/.claude/leadv2-overrides/status-collector-facts.sh"

PASS=0
FAIL=0
ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

CLEANUP_PATHS=()
_cleanup() { for p in "${CLEANUP_PATHS[@]:-}"; do [[ -n "$p" ]] && rm -rf "$p"; done; }
trap _cleanup EXIT

[[ -f "${HOOK}" ]] || { echo "[TEST] FATAL: ${HOOK} missing"; exit 1; }

if bash -n "${HOOK}" 2>/tmp/ci-scf-syntax.err; then
  pass "bash -n ${HOOK}"
else
  fail "bash -n ${HOOK}: $(cat /tmp/ci-scf-syntax.err)"
fi

run_hook() {
  # subshell: source + call, mirroring leadv2-status-collector.sh's
  # _sc_repo_facts_section (cd "$PROJECT_ROOT"; source hook; collect_repo_facts).
  # PROJECT_ROOT is set as a plain assignment BEFORE sourcing (not a
  # `VAR=val source file` prefix) -- whether a prefix assignment on a
  # source/`.` command persists into later commands in the same shell is a
  # POSIX-special-builtin nuance that measurably differs between bash builds
  # (passed on this machine's bash, failed under `set -u` on bash 5.2 in a
  # Linux container) -- matching production's own pattern sidesteps it.
  (
    cd "${REPO_ROOT}"
    PROJECT_ROOT="${REPO_ROOT}"
    source "${HOOK}"
    collect_repo_facts
  )
}

# ---------------------------------------------------------------------------
# Case 1: real repo tree (whatever journals exist here) -> valid single JSON
# object, always -- this is the collector's own hard requirement
# (_sc_run_section validates with json.load and drops the section otherwise).
# ---------------------------------------------------------------------------
OUT1="$(run_hook)"
RC1=$?
if [[ ${RC1} -eq 0 ]]; then
  pass "case1: collect_repo_facts exits 0"
else
  fail "case1: collect_repo_facts exited ${RC1}"
fi

if printf '%s' "${OUT1}" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d, dict)' 2>/tmp/ci-scf-json.err; then
  pass "case1: output is exactly one valid JSON object"
else
  fail "case1: output is not valid JSON: ${OUT1} ($(cat /tmp/ci-scf-json.err))"
fi

if printf '%s' "${OUT1}" | grep -q '"code_intel_attach_rate"' && printf '%s' "${OUT1}" | grep -q '"code_intel_by_arm"'; then
  pass "case1: both expected keys present"
else
  fail "case1: missing code_intel_attach_rate/code_intel_by_arm key(s): ${OUT1}"
fi

# ---------------------------------------------------------------------------
# Case 2: empty journal tree -> honest zero, not a fabricated rate.
# ---------------------------------------------------------------------------
EMPTY="$(mktemp -d "${TMPDIR:-/tmp}/ci-scf-empty.XXXXXX")"
CLEANUP_PATHS+=("${EMPTY}")
mkdir -p "${EMPTY}/docs/leadv2/tasks"

OUT2="$(cd "${REPO_ROOT}" && PROJECT_ROOT="${REPO_ROOT}" LEADV2_CODE_INTEL_RATE_ROOT="${EMPTY}" \
  bash -c 'source "'"${HOOK}"'" && collect_repo_facts')"
if printf '%s' "${OUT2}" | grep -q "0 decisions recorded"; then
  pass "case2: empty tree reports 0 decisions honestly"
else
  fail "case2: expected '0 decisions recorded' in output, got: ${OUT2}"
fi
if printf '%s' "${OUT2}" | grep -q '"code_intel_by_arm": "no data"'; then
  pass "case2: by_arm reports 'no data' when nothing recorded"
else
  fail "case2: expected by_arm 'no data', got: ${OUT2}"
fi

# ---------------------------------------------------------------------------
# Case 3: populated scratch tree -> real percentage + per-arm breakdown
# surfaces through the hook, not just through the underlying CLI.
# ---------------------------------------------------------------------------
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/ci-scf-scratch.XXXXXX")"
CLEANUP_PATHS+=("${SCRATCH}")
mkdir -p "${SCRATCH}/docs/leadv2/tasks/dispatch-aaa"
cat > "${SCRATCH}/docs/leadv2/tasks/dispatch-aaa/journal.md" <<'EOF'
- 2026-09-03T04:48:18Z [decision] code_intel_preamble arm=codex task=aaa mode=none reason=arm_unwired
- 2026-09-03T04:48:20Z [decision] code_intel_preamble arm=sonnet task=aaa mode=skipped reason=fail_open
- 2026-09-03T04:48:22Z [decision] code_intel_preamble arm=glm-flash task=aaa mode=attached
EOF

OUT3="$(cd "${REPO_ROOT}" && PROJECT_ROOT="${REPO_ROOT}" LEADV2_CODE_INTEL_RATE_ROOT="${SCRATCH}" \
  bash -c 'source "'"${HOOK}"'" && collect_repo_facts')"
if printf '%s' "${OUT3}" | grep -q "1/2 = 50%"; then
  pass "case3: populated tree surfaces the real attach-rate percentage"
else
  fail "case3: expected '1/2 = 50%' in output, got: ${OUT3}"
fi
if printf '%s' "${OUT3}" | grep -q "glm-flash:attached=1" && printf '%s' "${OUT3}" | grep -q "sonnet:fail_open=1"; then
  pass "case3: per-arm breakdown present in by_arm"
else
  fail "case3: expected per-arm breakdown in output, got: ${OUT3}"
fi

# ---------------------------------------------------------------------------
# Case 4: rate script missing/non-executable -> hook degrades to
# "unavailable"/"no data", never crashes (collector isolation contract).
# ---------------------------------------------------------------------------
FAKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ci-scf-fakeroot.XXXXXX")"
CLEANUP_PATHS+=("${FAKE_ROOT}")
mkdir -p "${FAKE_ROOT}/plugins/leadv2/scripts"
OUT4="$(PROJECT_ROOT="${FAKE_ROOT}" bash -c 'source "'"${HOOK}"'" && collect_repo_facts')"
RC4=$?
if [[ ${RC4} -eq 0 ]]; then
  pass "case4: missing rate script does not crash the hook"
else
  fail "case4: hook exited ${RC4} when rate script is missing"
fi
if printf '%s' "${OUT4}" | grep -q '"code_intel_attach_rate": "unavailable"'; then
  pass "case4: missing rate script reports 'unavailable', not a fabricated rate"
else
  fail "case4: expected 'unavailable', got: ${OUT4}"
fi

echo
echo "=== SUMMARY: ${PASS} passed, ${FAIL} failed ==="
if [[ ${FAIL} -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
