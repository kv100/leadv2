#!/usr/bin/env bash
# test-plugin-sync-syntax-gate.sh — HOOK-EDIT-SPAWN-POISON-01 (T16 §9).
#
# A live plugin-cache sync used to copy hook files MID-EDIT: a session
# spawning at that moment received a syntax-broken cache snapshot and died at
# its first prompt (killed lane 75a42e3a, 2026-08-26). The sync now gates
# every .sh through `bash -n` before the transfer; a failing file is excluded
# (rsync --delete never touches excluded paths) and the PREVIOUS copy
# survives at the destination.
#
# Runs the REAL plugin-sync against an isolated canonical tree + HOME
# (test-plugin-sync-claude-scripts.sh pattern).
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

# ── Fixture: isolated canonical tree (git repo, one good + one mid-edit hook) ─
canon="$tmp/canon"
mkdir -p "$canon/plugins/leadv2/hooks" "$canon/plugins/leadv2/scripts"
printf '#!/usr/bin/env bash\necho "canonical good"\n' > "$canon/plugins/leadv2/hooks/leadv2-good.sh"
printf '#!/usr/bin/env bash\necho ok\n' > "$canon/plugins/leadv2/scripts/tool.sh"
# Mid-edit snapshot: unbalanced if — bash -n fails. This is the file state a
# concurrent edit leaves on disk when sync races the writer.
printf '#!/usr/bin/env bash\nif [[ -n "x" ]]; then\n  echo "never closed\n' \
  > "$canon/plugins/leadv2/hooks/leadv2-mid-edit.sh"
if bash -n "$canon/plugins/leadv2/hooks/leadv2-mid-edit.sh" 2>/dev/null; then
  printf '[TEST] FAIL: fixture broken.sh unexpectedly passes bash -n\n' >&2
  exit 1
fi
(cd "$canon" && git init -q && git config user.email test@example.invalid \
  && git config user.name syntax-gate-test && git add -A && git commit -q -m "init")

home="$tmp/home"
mkdir -p "$home"

# Pre-seed the plugin cache with the PREVIOUS good copy of the mid-edit hook —
# the exact state a live system holds while canonical is being edited.
cache_hooks="$home/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/hooks"
mkdir -p "$cache_hooks"
printf '#!/usr/bin/env bash\necho "previous good copy"\n' > "$cache_hooks/leadv2-mid-edit.sh"

run_sync() {
  local logfile="$1"
  local rc=0
  env -u LEADV2_PROJECT_ROOT -u LEADV2_STATE_ROOT -u PROJECT_ROOT \
    HOME="$home" LEADV2_CANONICAL_ROOT="$canon" \
    bash "$PLUGIN_SYNC" --write >"${logfile}.out" 2>"$logfile" || rc=$?
  return "$rc"
}

rc=0
run_sync "$tmp/run1.log" || rc=$?

# Case 1: the hold is visible — a silent hold is a silent stale cache.
check "$(cat "$tmp/run1.log")" "[syntax-gate] holding leadv2-mid-edit.sh" \
  "Case 1: syntax-gate logs the held file"

# Case 2: the broken file did NOT reach the cache — the destination keeps the
# previous good copy byte-for-byte.
if cmp -s "$cache_hooks/leadv2-mid-edit.sh" <(printf '#!/usr/bin/env bash\necho "previous good copy"\n'); then
  printf '[TEST] PASS: Case 2: cache keeps previous copy of mid-edit hook\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 2: cache copy changed under syntax hold: %s\n' "$(cat "$cache_hooks/leadv2-mid-edit.sh")" >&2
  fail=$((fail+1))
fi

# Case 3: clean files are NOT held — the gate must not degrade into "sync
# nothing".
if [[ -f "$home/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/hooks/leadv2-good.sh" ]] \
   && [[ -f "$home/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/scripts/tool.sh" ]]; then
  printf '[TEST] PASS: Case 3: clean files still sync\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 3: clean files missing from cache after sync\n' >&2
  fail=$((fail+1))
fi

# Case 4: recovery — once canonical holds a valid file again, the next sync
# delivers it (the hold is a hold, not a permanent exclude).
printf '#!/usr/bin/env bash\necho "fixed"\n' > "$canon/plugins/leadv2/hooks/leadv2-mid-edit.sh"
(cd "$canon" && git add -A && git commit -q -m "fix hook")
rc2=0
run_sync "$tmp/run2.log" || rc2=$?
if grep -q "fixed" "$cache_hooks/leadv2-mid-edit.sh" 2>/dev/null; then
  printf '[TEST] PASS: Case 4: repaired file syncs on the next run\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 4: repaired file never reached the cache\n' >&2
  fail=$((fail+1))
fi

printf '\n[TEST] plugin sync syntax gate: %s passed, %s failed\n' "$pass" "$fail"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
