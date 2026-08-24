#!/usr/bin/env bash
# tests/test-lv2guard.sh — CODEX-LEAD-FULL-01. Fixture-only: every case runs
# lv2guard.sh with LEADV2_CODEX_GUARD_EXEC=echo, a test seam that prints the
# reconstructed command instead of exec'ing it, so nothing real is ever
# destroyed even for the CATASTROPHIC-tier cases.
#
# Run: bash plugins/leadv2/codex-lead/tests/test-lv2guard.sh
# Exit 0 = all pass; non-zero = failures found.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_LEAD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="$CODEX_LEAD_DIR/lv2guard.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# assert_rc <expect-rc> <label> -- <argv...>
assert_rc() {
  local expect="$1" label="$2"; shift 2
  [[ "$1" == "--" ]] && shift
  local out rc
  out="$(LEADV2_CODEX_GUARD_EXEC=echo bash "$GUARD" "$@" 2>&1)"
  rc=$?
  if [[ "$rc" == "$expect" ]]; then
    pass "$label (rc=$rc)"
  else
    fail "$label (expected rc=$expect, got rc=$rc; output: $out)"
  fi
}

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/repo/plugins/leadv2/codex-lead" "$FIX/repo/plugins/leadv2/scripts" "$FIX/repo/plugins/leadv2/config"

cp "$CODEX_LEAD_DIR/lv2guard.sh" "$FIX/repo/plugins/leadv2/codex-lead/lv2guard.sh"
cp "$CODEX_LEAD_DIR/deny-extra.yaml" "$FIX/repo/plugins/leadv2/codex-lead/deny-extra.yaml"
cp "$SCRIPT_DIR/../../config/leadv2-deny-patterns.yaml" "$FIX/repo/plugins/leadv2/config/leadv2-deny-patterns.yaml"
cat > "$FIX/repo/plugins/leadv2/scripts/leadv2-state-path.sh" <<EOF
#!/bin/bash
echo "$FIX/state/active.yaml"
EOF
chmod +x "$FIX/repo/plugins/leadv2/scripts/leadv2-state-path.sh"
FG="$FIX/repo/plugins/leadv2/codex-lead/lv2guard.sh"
mkdir -p "$FIX/state"

# --- allow cases -------------------------------------------------------
assert_rc 0 "allow: git status"           -- git status
assert_rc 0 "allow: ls"                   -- ls
assert_rc 0 "allow: git clean -n"         -- -c "git clean -n"
assert_rc 0 "allow: git stash list"       -- -c "git stash list"
assert_rc 0 "allow: rm -rf ./build"       -- -c "cd '$FIX' && rm -rf ./build"

# --- CATASTROPHIC refuse (rc 97), no override possible ------------------
assert_rc 97 "refuse: rm -rf /"                    -- -c "rm -rf /"
assert_rc 97 "refuse: rm -rf ~"                     -- -c "rm -rf ~"
assert_rc 97 "refuse: rm -rf \$HOME/x"              -- -c 'rm -rf $HOME/x'
assert_rc 97 "refuse: git push --force origin main" -- -c "git push --force origin main"
assert_rc 97 "refuse: mkfs.ext4 /dev/x"             -- -c "mkfs.ext4 /dev/x"
assert_rc 97 "refuse: dd of=/dev/sda"               -- -c "dd if=/dev/zero of=/dev/sda"
assert_rc 97 "refuse: chmod -R 777 /"               -- -c "chmod -R 777 /"

# --- SOFT refuse then allow with inline token ----------------------------
assert_rc 97 "refuse: git reset --hard"                            -- -c "git reset --hard"
assert_rc 0  "allow: git reset --hard # deny-floor: allow"          -- -c "git reset --hard # deny-floor: allow"
assert_rc 97 "refuse: git clean -fd"                                -- -c "git clean -fd"
assert_rc 0  "allow: git clean -fd # deny-floor: allow"             -- -c "git clean -fd # deny-floor: allow"
assert_rc 97 "refuse: git stash"                                    -- -c "git stash"
assert_rc 0  "allow: git stash # deny-floor: allow"                 -- -c "git stash # deny-floor: allow"

# --- worktree-prune predicate --------------------------------------------
echo "sessions: []" > "$FIX/state/active.yaml"
out="$(LEADV2_CODEX_GUARD_EXEC=echo bash "$FG" -c "git worktree prune" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass "predicate: worktree prune, empty sessions -> allow" || fail "predicate: worktree prune, empty sessions -> allow (rc=$rc, $out)"

cat > "$FIX/state/active.yaml" <<'EOF'
sessions:
  - task_id: dispatch-abc123
    worktree: /tmp/x
EOF
out="$(LEADV2_CODEX_GUARD_EXEC=echo bash "$FG" -c "git worktree prune" 2>&1)"; rc=$?
[[ $rc -eq 97 ]] && pass "predicate: worktree prune, one active session -> refuse" || fail "predicate: worktree prune, one active session -> refuse (rc=$rc, $out)"

echo ": not: [valid yaml" > "$FIX/state/active.yaml"
out="$(LEADV2_CODEX_GUARD_EXEC=echo bash "$FG" -c "git worktree prune" 2>&1)"; rc=$?
[[ $rc -eq 97 ]] && pass "predicate: worktree prune, malformed active.yaml -> refuse (CB-4)" || fail "predicate: worktree prune, malformed active.yaml -> refuse (rc=$rc, $out)"

out="$(LEADV2_CODEX_GUARD_EXEC=echo bash "$FG" git status 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass "predicate: malformed active.yaml does not block unrelated commands (CB-4 blast radius)" || fail "predicate: malformed active.yaml blast radius (rc=$rc, $out)"
rm -f "$FIX/state/active.yaml"

# --- codex direct-exec predicate -----------------------------------------
assert_rc 97 "predicate: codex exec 'x' -> refuse naming codex-task.sh" -- -c "codex exec 'x'"
assert_rc 0  "predicate: codex-task.sh task 'x' -> allow"               -- -c "codex-task.sh task 'x'"

# --- heredoc advisory: warns, never refuses -------------------------------
BIGSTR="$(python3 -c "print('x' * 3000)")"
out="$(LEADV2_CODEX_GUARD_EXEC=echo bash "$FG" -c "cat <<EOF
$BIGSTR
EOF" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q "advisory threshold"; then
  pass "advisory: 3KB heredoc warns on stderr and still rc=0"
else
  fail "advisory: 3KB heredoc (rc=$rc, output: $out)"
fi

# --- fail-closed: patterns file pointed at nonexistent path ---------------
out="$(LEADV2_CODEX_GUARD_EXEC=echo LEADV2_DENY_PATTERNS_FILE="$FIX/nonexistent.yaml" bash "$FG" ls 2>&1)"; rc=$?
[[ $rc -eq 97 ]] && pass "fail-closed: missing patterns file -> refuse even 'ls'" || fail "fail-closed: missing patterns file (rc=$rc, $out)"

# --- CB-8: LEADV2_DENY_FLOOR is NOT honored by lv2guard -------------------
out="$(LEADV2_CODEX_GUARD_EXEC=echo LEADV2_DENY_FLOOR=0 bash "$FG" -c "rm -rf /" 2>&1)"; rc=$?
[[ $rc -eq 97 ]] && pass "CB-8: LEADV2_DENY_FLOOR=0 does not bypass lv2guard" || fail "CB-8: LEADV2_DENY_FLOOR=0 bypass (rc=$rc, $out)"

# --- usage ------------------------------------------------------------------
out="$(LEADV2_CODEX_GUARD_EXEC=echo bash "$GUARD" 2>&1)"; rc=$?
[[ $rc -eq 2 ]] && pass "usage: no args at all -> rc 2" || fail "usage: no args (rc=$rc)"

# --- bash -n over every shipped shell file --------------------------------
for f in "$CODEX_LEAD_DIR"/*.sh "$CODEX_LEAD_DIR"/shim/rm "$CODEX_LEAD_DIR"/shim/git "$CODEX_LEAD_DIR"/shim/codex "$CODEX_LEAD_DIR"/tests/*.sh; do
  [[ -f "$f" ]] || continue
  if bash -n "$f" 2>/dev/null; then
    pass "bash -n $f"
  else
    fail "bash -n $f"
  fi
done

echo
echo "==================================================="
echo "PASS: $PASS  FAIL: $FAIL"
echo "==================================================="
if [[ $FAIL -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
