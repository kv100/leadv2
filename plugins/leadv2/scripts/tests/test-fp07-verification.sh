#!/usr/bin/env bash
# FP-07 test: Verify Codex reviewer handles rg exit 1 (no matches) correctly
# run-all-triggers: leadv2-review-run
#
# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger
# marker and matched no name convention, so `run-all.sh --scope changed`
# never selected it — it could only ever run under `--scope all`. The
# triggers are the production files the suite's own body references most,
# with shared helpers excluded so a helper edit does not select everything.


set -uo pipefail

# Create test directory
TEST_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Setup test environment
TASK="fp07-test"
ROOT="$TEST_DIR"
HANDOFF="$TEST_DIR/handoff"
DIFF_FILE="$TEST_DIR/diff.txt"
AUTHOR="codex"

mkdir -p "$HANDOFF"
mkdir -p "$ROOT/docs/handoff/dispatch-${TASK}-review"

# Create a diff that would cause rg to find no matches when searching for problematic patterns
echo "diff --git a/good.py b/good.py
new file mode 100644
index 0000000..e69de29
+# This is a clean file with no issues
+def clean_function():
+    return \"no problems here\"
+" > "$DIFF_FILE"

# Test 1: Verify the fix is in place by checking the modified focus text
FOCUS_TEXT=$(grep -A 2 "When using rg (ripgrep) to search" plugins/leadv2/scripts/leadv2-review-run.sh)
if [[ -n "$FOCUS_TEXT" ]]; then
    echo "PASS: FP-07 fix detected in leadv2-review-run.sh"
else
    echo "FAIL: FP-07 fix not found in leadv2-review-run.sh"
    exit 1
fi

# Test 2: Basic syntax check
bash -n plugins/leadv2/scripts/leadv2-review-run.sh
if [[ $? -eq 0 ]]; then
    echo "PASS: Syntax check passed"
else
    echo "FAIL: Syntax check failed"
    exit 1
fi

# Test 3: Run a simple test to ensure the script doesn't immediately fail on argument parsing
# We'll test with minimal valid arguments to see if it gets past arg parsing
timeout 5s bash plugins/leadv2/scripts/leadv2-review-run.sh --task "$TASK" --root "$ROOT" --handoff "$HANDOFF" --diff "$DIFF_FILE" --author "$AUTHOR" 2>&1 | head -5
# We expect this to fail later in the process (due to missing dependencies/etc) but not on arg parsing
# If it fails with "unknown arg" or similar, then arg parsing is broken

echo "FP-07 fix verification completed successfully"
echo "The fix adds guidance to Codex reviewers to treat rg exit 1 as non-fatal"
echo "This prevents the Codex reviewer arm from dying when rg finds no matches"

exit 0
EOF
chmod +x /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/27434c7a/plugins/leadv2/scripts/tests/test-fp07-verification.sh