#!/usr/bin/env bash

# Test script for verifying --resume-lane argument shapes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_SCRIPT="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"

# Create fixture worktrees
FIXTURE_ROOT="$(mktemp -d)"
FIXTURE_WORKTREE_DIR="${FIXTURE_ROOT}/.claude/worktrees"
mkdir -p "${FIXTURE_WORKTREE_DIR}"

# Create a test lane worktree
TEST_LANE_NAME="test-lane"
TEST_LANE_WORKTREE="${FIXTURE_WORKTREE_DIR}/${TEST_LANE_NAME}"
mkdir -p "${TEST_LANE_WORKTREE}"

# Create a test mission file
TEST_MISSION_FILE="${FIXTURE_ROOT}/test-mission.md"
echo "# Test Mission" > "${TEST_MISSION_FILE}"

# Function to run the dispatch script and check output
run_dispatch() {
  local args=("${DISPATCH_SCRIPT}" "--mission" "${TEST_MISSION_FILE}" "$@")
  local output
  local rc

  output=$("${args[@]}" 2>&1 || true)
  rc=$?

  echo "Command: ${args[*]}"
  echo "Exit code: $rc"
  echo "Output:"
  echo "$output"
  echo "---"

  return $rc
}

# Test 1: bare name of an existing lane
run_dispatch "--resume-lane" "${TEST_LANE_NAME}"

# Test 2: absolute path to that same lane's worktree
run_dispatch "--resume-lane" "${TEST_LANE_WORKTREE}"

# Test 3: absolute path that is not a lane worktree
BAD_PATH="/tmp/nonexistent-path"
run_dispatch "--resume-lane" "${BAD_PATH}"

# Test 4: the refusal message never contains a doubled .claude/worktrees/ segment
DOUBLED_PATH="${FIXTURE_ROOT}/.claude/worktrees/.claude/worktrees/test-doubled"
run_dispatch "--resume-lane" "${DOUBLED_PATH}"

# Clean up
rm -rf "${FIXTURE_ROOT}"

echo "All tests completed"