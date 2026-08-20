#!/usr/bin/env bash
# test-pump-junk-in-lane.sh — PUMP-JUNK-IN-LANE-01
# Red-first: run leadv2-backlog-pump.sh from a FAKE LANE WORKTREE cwd (no
# LEADV2_PROJECT_ROOT/CLAUDE_PROJECT_DIR set -- exactly how a worker session
# invokes it) and assert its liveness cache never lands under that worktree.
# Before the fix, CACHE_DIR was PROJECT_ROOT-relative and PROJECT_ROOT fell
# back to `git rev-parse --show-toplevel`, which returns the WORKTREE root
# (not the main checkout) -- so liveness.json/.sig/.ts landed inside the
# lane's own git tree (live: task 6cf5d07e, 2026-08-20 07:37).

set -euo pipefail

_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
TEST_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
SCRIPTS_DIR="$(cd -P "$TEST_DIR/.." && pwd)"
PUMP_BIN="$SCRIPTS_DIR/leadv2-backlog-pump.sh"

pass=0
fail=0
cleanup_items=()
cleanup() {
  for item in "${cleanup_items[@]:-}"; do
    rm -rf "$item" 2>/dev/null || true
  done
}
trap cleanup EXIT

# --- fixture: a main repo + a linked worktree (mirrors a real lane) --------
main_repo="$(mktemp -d)"
cleanup_items+=("$main_repo")
git -C "$main_repo" init -q
git -C "$main_repo" config user.email test@test.test
git -C "$main_repo" config user.name Test
mkdir -p "$main_repo/.claude/scripts"
ln -s "$SCRIPTS_DIR/leadv2-state-path.sh" "$main_repo/.claude/scripts/leadv2-state-path.sh"
ln -s "$SCRIPTS_DIR/leadv2-tasks-lib.sh" "$main_repo/.claude/scripts/leadv2-tasks-lib.sh" 2>/dev/null || true
touch "$main_repo/.gitkeep"
git -C "$main_repo" add -A
git -C "$main_repo" commit -qm init >/dev/null

worktree_dir="$(mktemp -d)"
rmdir "$worktree_dir"
cleanup_items+=("$worktree_dir")
git -C "$main_repo" worktree add -q -b "lane-fixture" "$worktree_dir" >/dev/null

# Stub liveness binary: avoid depending on the real leadv2-lane-liveness.sh
# (network/codex probes) -- this test targets CACHE_DIR resolution only.
stub_bin="$(mktemp -d)"
cleanup_items+=("$stub_bin")
cat >"$stub_bin/leadv2-lane-liveness.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"lanes":[]}\n'
EOF
chmod +x "$stub_bin/leadv2-lane-liveness.sh"

# --- run `status` from INSIDE the worktree, no PROJECT_ROOT override -- this
# is the exact shape of a worker session's environment (PROJECT_ROOT falls
# back to `git rev-parse --show-toplevel` of cwd, which is the worktree).
(
  cd "$worktree_dir"
  env -u LEADV2_PROJECT_ROOT -u CLAUDE_PROJECT_DIR -u PROJECT_ROOT \
    LEADV2_BACKLOG_PUMP_LIVENESS_BIN="$stub_bin/leadv2-lane-liveness.sh" \
    bash "$PUMP_BIN" status >/dev/null 2>&1 || true
)

after_junk="$(find "$worktree_dir" -path '*/.claude/cache/backlog-pump*' 2>/dev/null | wc -l | tr -d ' ')"

echo "[PUMP-JUNK-IN-LANE] case: liveness cache must not land inside the lane worktree"
if [ "$after_junk" -eq 0 ]; then
  echo "[PUMP-JUNK-IN-LANE]   worktree stayed clean (0 cache files) ✓"
  pass=$((pass + 1))
else
  echo "[PUMP-JUNK-IN-LANE]   FAIL: ${after_junk} cache file(s) leaked into the worktree:" >&2
  find "$worktree_dir" -path '*/.claude/cache/backlog-pump*' >&2
  fail=$((fail + 1))
fi

# --- positive assertion: the cache DID land under the MAIN CHECKOUT instead -
canon_junk="$(find "$main_repo/.claude/cache/backlog-pump" -name 'liveness.json' 2>/dev/null | wc -l | tr -d ' ')"
echo "[PUMP-JUNK-IN-LANE] case: liveness cache lands under the main checkout"
if [ "$canon_junk" -ge 1 ]; then
  echo "[PUMP-JUNK-IN-LANE]   found liveness.json under the main checkout ✓"
  pass=$((pass + 1))
else
  echo "[PUMP-JUNK-IN-LANE]   FAIL: no liveness.json found under $main_repo/.claude/cache/backlog-pump" >&2
  fail=$((fail + 1))
fi

echo "[PUMP-JUNK-IN-LANE] pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
