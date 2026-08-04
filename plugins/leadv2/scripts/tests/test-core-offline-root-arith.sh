#!/usr/bin/env bash
# test-core-offline-root-arith.sh — GATE-ROOT-ARITH-01
# Verifies that run-core-offline.sh derives REPO_ROOT from git (not ../.. hops)
# and that PLUGIN_ROOT always resolves to the canonical plugin tree physically.

set -euo pipefail

# --- locate the runner under test (physical, not logical) ---------------------
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
TEST_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
RUNNER="$TEST_DIR/run-core-offline.sh"
CANONICAL_PLUGIN_ROOT="$(cd -P "$TEST_DIR/../.." && pwd)"

# Helper: extract a KEY=value field from a probe line.
probe_field() {
  local key="$1" line="$2"
  printf '%s' "$line" | sed -nE "s/.* ${key}=([^ ]*).*/\1/p"
}

pass=0
fail=0
cleanup_items=()

cleanup() {
  for item in "${cleanup_items[@]:-}"; do
    rm -rf "$item" 2>/dev/null || true
  done
}
trap cleanup EXIT

# --- case (a): 3-deep symlink from a fixture repo -----------------------------
echo "[ROOT-ARITH] case (a): symlink entry from fixture repo"
fixture_a="$(mktemp -d)"
cleanup_items+=("$fixture_a")
git -C "$fixture_a" init -q
git -C "$fixture_a" config user.email test@test.test
git -C "$fixture_a" config user.name Test
mkdir -p "$fixture_a/.claude/scripts/tests"
ln -s "$RUNNER" "$fixture_a/.claude/scripts/tests/run-core-offline.sh"
# Need at least one commit so rev-parse has a toplevel.
touch "$fixture_a/.gitkeep"
git -C "$fixture_a" add -A
git -C "$fixture_a" commit -qm init

expected_repo_a="$(git -C "$fixture_a" rev-parse --show-toplevel)"

line_a="$(env -u GIT_DIR -u GIT_WORK_TREE LEADV2_CORE_OFFLINE_PROBE=1 \
  bash "$fixture_a/.claude/scripts/tests/run-core-offline.sh" 2>&1)"
repo_a="$(probe_field REPO_ROOT "$line_a")"
plugin_a="$(probe_field PLUGIN_ROOT "$line_a")"

if [ "$repo_a" = "$expected_repo_a" ]; then
  echo "[ROOT-ARITH]   (a) REPO_ROOT = fixture repo ✓"
else
  echo "[ROOT-ARITH]   (a) FAIL: REPO_ROOT='$repo_a' expected='$expected_repo_a'"
  fail=$((fail + 1))
  : skip_rest_a
fi
if [ "$plugin_a" = "$CANONICAL_PLUGIN_ROOT" ]; then
  echo "[ROOT-ARITH]   (a) PLUGIN_ROOT = canonical ✓"
else
  echo "[ROOT-ARITH]   (a) FAIL: PLUGIN_ROOT='$plugin_a' expected='$CANONICAL_PLUGIN_ROOT'"
  fail=$((fail + 1))
fi
if [ "$repo_a" != "/Users/kostiantyn.vlasenko/Projects" ]; then
  echo "[ROOT-ARITH]   (a) REPO_ROOT is not the shared parent ✓"
else
  echo "[ROOT-ARITH]   (a) FAIL: REPO_ROOT is the shared parent!"
  fail=$((fail + 1))
fi
[ "$fail" -eq 0 ] && pass=$((pass + 1))

# --- case (b): canonical invocation from this checkout -----------------------
echo "[ROOT-ARITH] case (b): canonical invocation"
expected_repo_b="$(git -C "$CANONICAL_PLUGIN_ROOT" rev-parse --show-toplevel)"

line_b="$(env -u GIT_DIR -u GIT_WORK_TREE LEADV2_CORE_OFFLINE_PROBE=1 \
  bash "$RUNNER" 2>&1)"
repo_b="$(probe_field REPO_ROOT "$line_b")"
testdir_b="$(probe_field TEST_DIR "$line_b")"

if [ "$repo_b" = "$expected_repo_b" ]; then
  echo "[ROOT-ARITH]   (b) REPO_ROOT = invoking checkout ✓"
else
  echo "[ROOT-ARITH]   (b) FAIL: REPO_ROOT='$repo_b' expected='$expected_repo_b'"
  fail=$((fail + 1))
fi
if [ "$testdir_b" = "$TEST_DIR" ]; then
  echo "[ROOT-ARITH]   (b) TEST_DIR = canonical scripts/tests ✓"
else
  echo "[ROOT-ARITH]   (b) FAIL: TEST_DIR='$testdir_b' expected='$TEST_DIR'"
  fail=$((fail + 1))
fi
[ "$fail" -eq 0 ] && pass=$((pass + 1))

# --- case (b'): worktree entry (proves .git-as-file passes guard) -------------
echo "[ROOT-ARITH] case (b'): worktree entry"
# Use a minimal standalone repo so worktree creation is instant (the leadv2
# repo is too large for a fast `git worktree add` inside a test).
wt_main="$(mktemp -d)"
cleanup_items+=("$wt_main")
git -C "$wt_main" init -q
git -C "$wt_main" config user.email test@test.test
git -C "$wt_main" config user.name Test
mkdir -p "$wt_main/plugins/leadv2/scripts/tests"
ln -s "$RUNNER" "$wt_main/plugins/leadv2/scripts/tests/run-core-offline.sh"
touch "$wt_main/.gitkeep"
git -C "$wt_main" add -A
git -C "$wt_main" commit -qm init

wt_lane="$wt_main/lane-wt"
git -C "$wt_main" worktree add -q "$wt_lane" HEAD
cleanup_items+=("$wt_lane")

line_bp="$(env -u GIT_DIR -u GIT_WORK_TREE LEADV2_CORE_OFFLINE_PROBE=1 \
  bash "$wt_lane/plugins/leadv2/scripts/tests/run-core-offline.sh" 2>&1)"
repo_bp="$(probe_field REPO_ROOT "$line_bp")"

expected_repo_bp="$(git -C "$wt_lane" rev-parse --show-toplevel)"
if [ "$repo_bp" = "$expected_repo_bp" ]; then
  echo "[ROOT-ARITH]   (b') REPO_ROOT = worktree lane toplevel ✓"
else
  echo "[ROOT-ARITH]   (b') FAIL: REPO_ROOT='$repo_bp' expected='$expected_repo_bp'"
  fail=$((fail + 1))
fi
[ "$fail" -eq 0 ] && pass=$((pass + 1))

# --- case (c): non-git location → fatal, exit 2, zero suites -----------------
echo "[ROOT-ARITH] case (c): non-git location"
fixture_c="$(mktemp -d)"
cleanup_items+=("$fixture_c")

# Copy the runner into the non-git temp dir (so BASH_SOURCE resolves there).
cp "$RUNNER" "$fixture_c/run-core-offline.sh"

# Assert the temp dir has no git ancestor.
if git -C "$fixture_c" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "[ROOT-ARITH]   (c) SKIP: temp dir is inside a git repo — test environment issue"
  fail=$((fail + 1))
else
  set +e
  stdout_c="$(env -u GIT_DIR -u GIT_WORK_TREE \
    bash "$fixture_c/run-core-offline.sh" 2>&1)"
  rc_c=$?
  set -e

  if echo "$stdout_c" | grep -q 'repo_root_unresolvable'; then
    echo "[ROOT-ARITH]   (c) stderr contains repo_root_unresolvable ✓"
  else
    echo "[ROOT-ARITH]   (c) FAIL: no repo_root_unresolvable in output"
    fail=$((fail + 1))
  fi
  if [ "$rc_c" -eq 2 ]; then
    echo "[ROOT-ARITH]   (c) exit code = 2 ✓"
  else
    echo "[ROOT-ARITH]   (c) FAIL: exit code=$rc_c expected=2"
    fail=$((fail + 1))
  fi
  # Zero suite-name lines should appear (exclude FATAL/probe diagnostic lines).
  suite_lines="$(printf '%s' "$stdout_c" | grep '\[CORE-OFFLINE\] ' | grep -cv 'FATAL' || true)"
  if [ "$suite_lines" -eq 0 ]; then
    echo "[ROOT-ARITH]   (c) zero suite lines printed ✓"
  else
    echo "[ROOT-ARITH]   (c) FAIL: $suite_lines [CORE-OFFLINE] lines appeared"
    fail=$((fail + 1))
  fi
fi
[ "$fail" -eq 0 ] && pass=$((pass + 1))

# --- summary -----------------------------------------------------------------
echo "[ROOT-ARITH] cases passed=$pass failed=$fail"
(( fail == 0 ))
