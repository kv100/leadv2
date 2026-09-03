#!/usr/bin/env bash
# tests/test-leadv2-code-intel-rate.sh — CODE-INTEL-IS-INSTALLED-AND-UNUSED-01
#
# leadv2-code-intel-rate.sh scans docs/leadv2/tasks/*/journal.md for the
# code_intel_preamble decision line and tallies by arm/mode. This suite
# proves the tally is correct against a scratch journal tree (never the
# real repo's 800+ journals — LEADV2_CODE_INTEL_RATE_ROOT points the script
# at a throwaway tasks/ dir) and that an empty tree reports zero rather than
# fabricating a rate.
#
# Run: bash plugins/leadv2/scripts/tests/test-leadv2-code-intel-rate.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET="${PLUGIN_SCRIPTS}/leadv2-code-intel-rate.sh"

PASS=0
FAIL=0
ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

CLEANUP_PATHS=()
_cleanup() { for p in "${CLEANUP_PATHS[@]:-}"; do [[ -n "$p" ]] && rm -rf "$p"; done; }
trap _cleanup EXIT

[[ -f "${TARGET}" ]] || { echo "[TEST] FATAL: ${TARGET} missing"; exit 1; }

if bash -n "${TARGET}" 2>/tmp/ci-rate-syntax.err; then
  pass "bash -n ${TARGET}"
else
  fail "bash -n ${TARGET}: $(cat /tmp/ci-rate-syntax.err)"
fi

# ---------------------------------------------------------------------------
# Case 1: scratch tree with known lines -> exact counts.
# ---------------------------------------------------------------------------
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/ci-rate-scratch.XXXXXX")"
CLEANUP_PATHS+=("${SCRATCH}")

mkdir -p "${SCRATCH}/docs/leadv2/tasks/dispatch-aaa11111" \
         "${SCRATCH}/docs/leadv2/tasks/dispatch-bbb22222" \
         "${SCRATCH}/docs/leadv2/tasks/dispatch-ccc33333"

cat > "${SCRATCH}/docs/leadv2/tasks/dispatch-aaa11111/journal.md" <<'EOF'
- 2026-09-03T04:48:18Z [decision] code_intel_preamble arm=codex task=aaa11111 mode=none reason=arm_unwired
- 2026-09-03T04:48:20Z [decision] code_intel_preamble arm=sonnet task=aaa11111 mode=skipped reason=fail_open
EOF

cat > "${SCRATCH}/docs/leadv2/tasks/dispatch-bbb22222/journal.md" <<'EOF'
- 2026-09-03T03:09:02Z [decision] code_intel_preamble arm=glm-flash task=bbb22222 mode=attached
- 2026-09-03T03:27:54Z [decision] code_intel_preamble arm=glm-flash task=bbb22222 mode=attached
EOF

# a journal with no code_intel_preamble lines at all -- must be silently
# ignored, not counted as a zero-mode row.
cat > "${SCRATCH}/docs/leadv2/tasks/dispatch-ccc33333/journal.md" <<'EOF'
- 2026-09-03T01:00:00Z [decision] some_unrelated_line arm=glm task=ccc33333
EOF

OUT="$(LEADV2_CODE_INTEL_RATE_ROOT="${SCRATCH}" bash "${TARGET}")"

if echo "${OUT}" | grep -qE "^glm-flash +attached +2$"; then
  pass "case1: glm-flash attached count = 2"
else
  fail "case1: expected 'glm-flash attached 2' row, got: ${OUT}"
fi

if echo "${OUT}" | grep -qE "^sonnet +fail_open +1$"; then
  pass "case1: sonnet fail_open count = 1"
else
  fail "case1: expected 'sonnet fail_open 1' row, got: ${OUT}"
fi

if echo "${OUT}" | grep -qE "^codex +arm_unwired +1$"; then
  pass "case1: codex arm_unwired count = 1"
else
  fail "case1: expected 'codex arm_unwired 1' row, got: ${OUT}"
fi

# attach rate excludes codex (arm_unwired is not MCP-capable): attached=2,
# fail_open=1 -> 2/3 = 67%.
if echo "${OUT}" | grep -qE "attach rate among MCP-capable arms.*2/3 = 67%"; then
  pass "case1: attach rate = 2/3 = 67% (codex excluded from denominator)"
else
  fail "case1: expected '2/3 = 67%' attach-rate line, got: ${OUT}"
fi

if echo "${OUT}" | grep -q "some_unrelated_line"; then
  fail "case1: unrelated journal line leaked into the tally"
else
  pass "case1: unrelated journal line correctly ignored"
fi

# ---------------------------------------------------------------------------
# Case 2: empty tree -> explicit zero, never a fabricated rate.
# ---------------------------------------------------------------------------
EMPTY="$(mktemp -d "${TMPDIR:-/tmp}/ci-rate-empty.XXXXXX")"
CLEANUP_PATHS+=("${EMPTY}")
mkdir -p "${EMPTY}/docs/leadv2/tasks"

OUT2="$(LEADV2_CODE_INTEL_RATE_ROOT="${EMPTY}" bash "${TARGET}")"
if echo "${OUT2}" | grep -q "0 decisions recorded"; then
  pass "case2: empty tree reports 0 decisions, no fabricated rate"
else
  fail "case2: expected '0 decisions recorded', got: ${OUT2}"
fi

# ---------------------------------------------------------------------------
# Case 3: --since filters out lines before the cutoff date.
# ---------------------------------------------------------------------------
SINCE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ci-rate-since.XXXXXX")"
CLEANUP_PATHS+=("${SINCE_ROOT}")
mkdir -p "${SINCE_ROOT}/docs/leadv2/tasks/dispatch-old" "${SINCE_ROOT}/docs/leadv2/tasks/dispatch-new"
cat > "${SINCE_ROOT}/docs/leadv2/tasks/dispatch-old/journal.md" <<'EOF'
- 2026-08-01T00:00:00Z [decision] code_intel_preamble arm=glm-flash task=old mode=attached
EOF
cat > "${SINCE_ROOT}/docs/leadv2/tasks/dispatch-new/journal.md" <<'EOF'
- 2026-09-03T00:00:00Z [decision] code_intel_preamble arm=glm-flash task=new mode=attached
EOF
OUT3="$(LEADV2_CODE_INTEL_RATE_ROOT="${SINCE_ROOT}" bash "${TARGET}" --since 2026-09-01)"
if echo "${OUT3}" | grep -qE "^glm-flash +attached +1$"; then
  pass "case3: --since 2026-09-01 excludes the 2026-08-01 line"
else
  fail "case3: expected exactly 1 glm-flash attached row after --since filter, got: ${OUT3}"
fi

echo
echo "=== SUMMARY: ${PASS} passed, ${FAIL} failed ==="
if [[ ${FAIL} -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
