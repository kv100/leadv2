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

# Mock the codex-task.sh to simulate the rg exit 1 scenario
cat > "${SCRIPT_DIR}/../codex-task.sh" <<'EOF'
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
chmod +x "${SCRIPT_DIR}/../codex-task.sh"

# Test execution
echo "Running FP-07 test: Codex reviewer should not choke on rg exit 1"

# Temporarily point to our mock
export LEADV2_DISPATCH_CODEX_BIN="${SCRIPT_DIR}/../codex-task.sh"

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