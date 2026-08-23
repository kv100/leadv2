#!/usr/bin/env bash
# test-plugin-sync-claude-scripts.sh — PLUGIN-SYNC-CLAUDE-SCRIPTS-01 round 2
#
# Guards leadv2-plugin-sync.sh's (c) <project>/.claude/scripts/ link
# classifier: LINK, CONVERT, DRIFT (must survive + report + fail the run),
# idempotence, and a declared per-repo exception (D3). Every case runs the
# REAL script against real filesystem fixtures under an isolated HOME/
# LEADV2_CANONICAL_ROOT — no mocked function calls (test-lane-truth-batch-01.sh
# pattern).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_SYNC="${PLUGIN_DIR}/leadv2-plugin-sync.sh"

pass=0
fail=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check() {
  local got="$1" want_substr="$2" label="$3"
  if [[ "$got" == *"$want_substr"* ]]; then
    printf '[TEST] PASS: %s\n' "$label"; pass=$((pass+1))
  else
    printf '[TEST] FAIL: %s\n  got: %s\n  want substring: %s\n' "$label" "$got" "$want_substr" >&2
    fail=$((fail+1))
  fi
}

# ── Fixture: isolated canonical tree (git repo, 3 fake scripts) ─────────────
canon="$tmp/canon"
mkdir -p "$canon/plugins/leadv2/scripts"
printf '#!/usr/bin/env bash\necho "canonical a"\n' > "$canon/plugins/leadv2/scripts/a.sh"
printf '#!/usr/bin/env bash\necho "canonical b"\n' > "$canon/plugins/leadv2/scripts/b.sh"
printf '#!/usr/bin/env bash\necho "canonical c"\n' > "$canon/plugins/leadv2/scripts/c.sh"
printf '#!/usr/bin/env bash\necho "canonical d"\n' > "$canon/plugins/leadv2/scripts/d.sh"
(cd "$canon" && git init -q && git config user.email test@example.invalid && git config user.name plugin-sync-test && git add -A && git commit -q -m "init")

home="$tmp/home"
mkdir -p "$home"

proj="$tmp/proj"
mkdir -p "$proj/.claude/scripts"

# Case 2 fixture: b.sh already present, byte-identical to canonical
cp "$canon/plugins/leadv2/scripts/b.sh" "$proj/.claude/scripts/b.sh"

# Case 3 fixture: c.sh present, DIVERGENT from canonical
printf '#!/usr/bin/env bash\necho "project-local divergent c"\n' > "$proj/.claude/scripts/c.sh"
divergent_c_content="$(cat "$proj/.claude/scripts/c.sh")"

# Case 5 fixture: d.sh present, byte-identical to canonical, declared exception
cp "$canon/plugins/leadv2/scripts/d.sh" "$proj/.claude/scripts/d.sh"
exceptions_file="$tmp/exceptions.txt"
printf 'project/proj/d.sh\n' > "$exceptions_file"

run_sync() {
  local logfile="$1"
  local rc=0
  env -u LEADV2_PROJECT_ROOT -u LEADV2_STATE_ROOT -u PROJECT_ROOT \
    HOME="$home" LEADV2_CANONICAL_ROOT="$canon" \
    LEADV2_ONE_COPY_EXCEPTIONS_FILE="$exceptions_file" \
    bash "$PLUGIN_SYNC" --project-root "$proj" --write >"$logfile.out" 2>"$logfile" || rc=$?
  return "$rc"
}

rc=0
run_sync "$tmp/run1.log" || rc=$?
run1_log="$(cat "$tmp/run1.log")"

# ── Case 1: LINK — a.sh has no project counterpart, becomes a symlink ───────
a_dst="$proj/.claude/scripts/a.sh"
if [[ -L "$a_dst" ]]; then
  printf '[TEST] PASS: Case 1 LINK: a.sh created as symlink\n'; pass=$((pass+1))
  a_resolved="$(readlink "$a_dst")"
  check "$a_resolved" "$canon/plugins/leadv2/scripts/a.sh" "Case 1 LINK: symlink resolves to canonical a.sh"
else
  printf '[TEST] FAIL: Case 1 LINK: a.sh is not a symlink\n' >&2; fail=$((fail+1))
fi
check "$run1_log" "LINK: $a_dst" "Case 1 LINK: run reports LINK for a.sh"

# ── Case 2: CONVERT — b.sh (identical real file) becomes a symlink ──────────
b_dst="$proj/.claude/scripts/b.sh"
if [[ -L "$b_dst" ]]; then
  printf '[TEST] PASS: Case 2 CONVERT: b.sh converted to symlink\n'; pass=$((pass+1))
  b_content="$(cat "$b_dst")"
  check "$b_content" "canonical b" "Case 2 CONVERT: content still resolves to canonical"
else
  printf '[TEST] FAIL: Case 2 CONVERT: b.sh is not a symlink\n' >&2; fail=$((fail+1))
fi
check "$run1_log" "CONVERT: $b_dst" "Case 2 CONVERT: run reports CONVERT for b.sh"

# ── Case 3: DRIFT — c.sh (divergent real file) survives untouched, run fails ─
c_dst="$proj/.claude/scripts/c.sh"
if [[ ! -L "$c_dst" ]]; then
  printf '[TEST] PASS: Case 3 DRIFT: c.sh is still a real file\n'; pass=$((pass+1))
  c_content="$(cat "$c_dst")"
  check "$c_content" "$divergent_c_content" "Case 3 DRIFT: divergent content survives byte-for-byte"
else
  printf '[TEST] FAIL: Case 3 DRIFT: c.sh was converted to a symlink (should have been left untouched)\n' >&2; fail=$((fail+1))
fi
check "$run1_log" "DRIFT: $c_dst" "Case 3 DRIFT: run reports DRIFT for c.sh"
check "$run1_log" "ACTION REQUIRED" "Case 3 DRIFT: run emits ACTION REQUIRED summary line"
if [[ "$rc" -eq 4 ]]; then
  printf '[TEST] PASS: Case 3 DRIFT: run exits rc=4\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 3 DRIFT: expected rc=4, got rc=%s\n' "$rc" >&2; fail=$((fail+1))
fi

# ── Case 5: EXCEPTION — d.sh (identical, declared override) left as real file ─
d_dst="$proj/.claude/scripts/d.sh"
if [[ ! -L "$d_dst" ]]; then
  printf '[TEST] PASS: Case 5 EXCEPTION: d.sh left as a real file (not converted)\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 5 EXCEPTION: d.sh was converted to a symlink despite declared exception\n' >&2; fail=$((fail+1))
fi
check "$run1_log" "EXCEPTION: $d_dst" "Case 5 EXCEPTION: run reports the declared override"

# ── Case 4: Idempotence — second run changes nothing for LINK/CONVERT cases ─
a_inode_before="$(ls -ldi "$a_dst" | awk '{print $1}')"
b_inode_before="$(ls -ldi "$b_dst" | awk '{print $1}')"
a_target_before="$(readlink "$a_dst")"
b_target_before="$(readlink "$b_dst")"

rc2=0
run_sync "$tmp/run2.log" || rc2=$?
run2_log="$(cat "$tmp/run2.log")"

if ! grep -qE "LINK: $a_dst|CONVERT: $a_dst" <<<"$run2_log" && ! grep -qE "LINK: $b_dst|CONVERT: $b_dst" <<<"$run2_log"; then
  printf '[TEST] PASS: Case 4 Idempotence: second run has no LINK/CONVERT churn for a.sh/b.sh\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 4 Idempotence: second run re-reported LINK/CONVERT for an already-settled file\n  log: %s\n' "$run2_log" >&2
  fail=$((fail+1))
fi

a_inode_after="$(ls -ldi "$a_dst" | awk '{print $1}')"
b_inode_after="$(ls -ldi "$b_dst" | awk '{print $1}')"
a_target_after="$(readlink "$a_dst")"
b_target_after="$(readlink "$b_dst")"

if [[ "$a_inode_before" == "$a_inode_after" && "$a_target_before" == "$a_target_after" ]]; then
  printf '[TEST] PASS: Case 4 Idempotence: a.sh symlink inode/target unchanged\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 4 Idempotence: a.sh symlink churned (inode %s->%s, target %s->%s)\n' \
    "$a_inode_before" "$a_inode_after" "$a_target_before" "$a_target_after" >&2
  fail=$((fail+1))
fi
if [[ "$b_inode_before" == "$b_inode_after" && "$b_target_before" == "$b_target_after" ]]; then
  printf '[TEST] PASS: Case 4 Idempotence: b.sh symlink inode/target unchanged\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 4 Idempotence: b.sh symlink churned (inode %s->%s, target %s->%s)\n' \
    "$b_inode_before" "$b_inode_after" "$b_target_before" "$b_target_after" >&2
  fail=$((fail+1))
fi

if [[ "$rc2" -eq 4 ]]; then
  printf '[TEST] PASS: Case 4 Idempotence: second run still exits rc=4 (c.sh drift persists)\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 4 Idempotence: expected second run rc=4, got rc=%s\n' "$rc2" >&2; fail=$((fail+1))
fi

printf '\n[TEST] plugin sync .claude/scripts link classification: %s passed, %s failed\n' "$pass" "$fail"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
