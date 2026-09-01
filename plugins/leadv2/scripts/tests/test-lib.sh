#!/usr/bin/env bash

# Test library for promise guard test suites

set -euo pipefail

# Function to run a test case
run_test() {
    local test_name="$1"
    shift
    local test_script="$@"

    echo "[TEST] Running: $test_name"

    # Create a temporary script file
    local temp_script="/tmp/test_$test_name.sh"
    echo "$test_script" > "$temp_script"
    chmod +x "$temp_script"

    # Run the test script
    if "$temp_script"; then
        echo "[TEST] PASSED: $test_name"
    else
        echo "[TEST] FAILED: $test_name"
        exit 1
    fi

    # Clean up
    rm -f "$temp_script"
}

# Function to run all test cases
run_all_tests() {
    echo "[TEST] Running all tests"
    local passed=0
    local failed=0

    for test_func in $(declare -F | awk '{print $3}' | grep '^test_'); do
        if "$test_func"; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi
    done

    echo "[TEST] Results: $passed passed, $failed failed"
    if [ "$failed" -gt 0 ]; then
        exit 1
    fi
}