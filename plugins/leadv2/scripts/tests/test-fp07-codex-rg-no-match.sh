#!/usr/bin/env bash
# FP-07 test: Codex reviewer arm chokes on rg exit 1 (no matches)
# This test verifies that the fix for FP-07 works correctly

set -uo pipefail

# Test setup
TEST_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create minimal test environment
TASK="fp07-test-task"
ROOT="${TEST_DIR}"
HANDOFF="${TEST_DIR}/handoff"
DIFF_FILE="${TEST_DIR}/diff.txt"
AUTHOR="sonnet"

mkdir -p "${HANDOFF}"
mkdir -p "${ROOT}/docs/handoff/dispatch-${TASK}-review"

# Create a diff that will cause rg to find no matches
echo "diff --git a/test.txt b/test.txt
new file mode 100644
index 0000000..e69de29
+// This is a test file with no actual issues
+int main() { return 0; }
" > "${DIFF_FILE}"

# Refuse to write a mock onto a TRACKED file. On 2026-09-11 this suite wrote its mock to
# "${SCRIPT_DIR}/../codex-task.sh" -- the real 2417-line production script -- and its trap
# only removed the temp dir, so the mock STAYED. The plugin working tree is what the symlink
# farm resolves to in all four repos, so one run left every repo with a code-review gate that
# answered a fabricated "REVIEW_VERDICT: PASS / critical=0" to everything. HEAD was never
# touched, so no CI run could have seen it. LEADV2_FP07_MOCK_TARGET exists ONLY so the
# negative control can aim this at a tracked path and prove the refusal below fires.
MOCK_TARGET="${LEADV2_FP07_MOCK_TARGET:-${TEST_DIR}/codex-task.sh}"
if git -C "$(dirname "${MOCK_TARGET}")" ls-files --error-unmatch \
     "$(basename "${MOCK_TARGET}")" >/dev/null 2>&1; then
  echo "[TEST] REFUSED: mock target is a TRACKED file: ${MOCK_TARGET}" >&2
  echo "[TEST] a suite writes its mock into its own sandbox, never onto a source file" >&2
  exit 2
fi

# Mock the codex-task.sh to simulate the rg exit 1 scenario
cat > "${MOCK_TARGET}" <<'EOF'
#!/usr/bin/env bash
# Mock codex-task.sh that simulates rg exit 1 (no matches) scenario

# Simulate Codex finding no issues (rg exits 1, but this is not an error)
# Codex would normally still produce some output, but we simulate the case
# where it produces minimal output that could trigger body_lost detection

if [[ "$1" == "adversarial-review" ]]; then
    # Simulate Codex producing a minimal valid review (but with potential body loss risk)
    echo "REVIEW_VERDICT: PASS"
    echo "REVIEW_FINDINGS: critical=0 high=0 medium=0 low=0"
    exit 0
else
    echo "Unknown subcommand: $1" >&2
    exit 1
fi
EOF
chmod +x "${MOCK_TARGET}"

# Test execution
echo "Running FP-07 test: Codex reviewer should not choke on rg exit 1"

# Temporarily point to our mock
export LEADV2_DISPATCH_CODEX_BIN="${MOCK_TARGET}"

# Run the review engine
"${SCRIPT_DIR}/../leadv2-review-run.sh" \
    --task "${TASK}" \
    --root "${ROOT}" \
    --handoff "${HANDOFF}" \
    --diff "${DIFF_FILE}" \
    --author "${AUTHOR}"

RESULT=$?

# Check results
if [[ $RESULT -eq 0 ]]; then
    echo "PASS: FP-07 test passed - Codex reviewer handled rg exit 1 correctly"

    # Verify the review gate shows pass, not blocked
    if [[ -f "${HANDOFF}/review-gate.md" ]]; then
        if grep -q "status: pass" "${HANDOFF}/review-gate.md"; then
            echo "PASS: Review gate shows correct PASS status"
        else
            echo "FAIL: Review gate does not show PASS status"
            cat "${HANDOFF}/review-gate.md"
            exit 1
        fi
    else
        echo "FAIL: Review gate file not created"
        exit 1
    fi
elif [[ $RESULT -eq 6 ]]; then
    echo "FAIL: FP-07 test failed - review_body_lost detected (exit 6)"
    if [[ -f "${HANDOFF}/review-gate.md" ]]; then
        echo "Review gate contents:"
        cat "${HANDOFF}/review-gate.md"
    fi
    exit 1
else
    echo "FAIL: FP-07 test failed with unexpected exit code: $RESULT"
    if [[ -f "${HANDOFF}/review-gate.md" ]]; then
        echo "Review gate contents:"
        cat "${HANDOFF}/review-gate.md"
    fi
    exit 1
fi

echo "FP-07 test completed successfully"
EOF
chmod +x /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/27434c7a/plugins/leadv2/scripts/tests/test-fp07-codex-rg-no-match.sh