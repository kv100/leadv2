#!/usr/bin/env bash
# test-plugin-sync-syntax-gate.sh — HOOK-EDIT-SPAWN-POISON-01 (T16 §9).
#
# A live sync used to copy hook files MID-EDIT: a session spawning at that
# moment received a syntax-broken snapshot and died at its first prompt
# (killed lane 75a42e3a, 2026-08-26). The sync gates every .sh through
# `bash -n` before the transfer; a failing file is excluded (rsync --delete
# never touches excluded paths) and the PREVIOUS copy survives at the
# destination.
#
# C1-RETIRE-RSYNC (2026-09-08) retargeted this suite from the plugin cache
# to the (b) shared-tree leg: the (a) cache leg is RETIRED (0.1.0 is an
# orphaned version dir — see leadv2-plugin-sync.sh header), so the gated
# rsync transfer that can ship a mid-edit file to a live destination is now
# the (b) shadow refresh. The gate ALSO protects link creation: the link-only
# producer pass refuses to LINK a bash -n -failing canonical file (a link is
# live-from-repo, so a mid-edit source would ship the moment the link lands).
#
# Runs the REAL plugin-sync against an isolated canonical tree + HOME
# (test-plugin-sync-claude-scripts.sh pattern).
# run-all-triggers: leadv2-plugin-sync
#
# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger
# marker and matched no name convention, so `run-all.sh --scope changed`
# never selected it — it could only ever run under `--scope all`. The
# triggers are the production files the suite's own body references most,
# with shared helpers excluded so a helper edit does not select everything.

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

# Pre-seed the (b) shared tree with the PREVIOUS good copy of the mid-edit
# hook — the exact state a live system holds while canonical is being edited.
shared_hooks="$home/.claude/leadv2-shared/hooks"
mkdir -p "$shared_hooks"
printf '#!/usr/bin/env bash\necho "previous good copy"\n' > "$shared_hooks/leadv2-mid-edit.sh"

# The retired (a) cache dir gets a canary: nothing may land there anymore.
cache_dir="$home/.claude/plugins/cache/leadv2-local/leadv2/0.1.0"
mkdir -p "$cache_dir"
printf 'canary\n' > "$cache_dir/CANARY"

run_sync() {
  local logfile="$1"
  local rc=0
  env -u LEADV2_PROJECT_ROOT -u LEADV2_STATE_ROOT -u PROJECT_ROOT \
    HOME="$home" LEADV2_CANONICAL_ROOT="$canon" \
    LEADV2_QUARANTINE_ROOT="$tmp/quarantine" \
    bash "$PLUGIN_SYNC" --write >"${logfile}.out" 2>"$logfile" || rc=$?
  return "$rc"
}

rc=0
run_sync "$tmp/run1.log" || rc=$?
run1_log="$(cat "$tmp/run1.log")"

# Case 1: the hold is visible — a silent hold is a silent stale destination.
check "$run1_log" "holding leadv2-mid-edit.sh" \
  "Case 1: syntax-gate logs the held file"

# Case 2: the broken file did NOT overwrite the destination — the previous
# good copy survives byte-for-byte (link pass left it as DRIFT; rsync held it).
if cmp -s "$shared_hooks/leadv2-mid-edit.sh" <(printf '#!/usr/bin/env bash\necho "previous good copy"\n'); then
  printf '[TEST] PASS: Case 2: destination keeps previous copy of mid-edit hook\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 2: destination copy changed under syntax hold: %s\n' "$(cat "$shared_hooks/leadv2-mid-edit.sh")" >&2
  fail=$((fail+1))
fi

# Case 3: clean files are NOT held — the gate must not degrade into "sync
# nothing". Under link-only they arrive as SYMLINKS into canonical.
if [[ -L "$home/.claude/leadv2-shared/hooks/leadv2-good.sh" ]] \
   && [[ "$(readlink "$home/.claude/leadv2-shared/hooks/leadv2-good.sh")" == "$canon/plugins/leadv2/hooks/leadv2-good.sh" ]] \
   && [[ -L "$home/.claude/leadv2-shared/scripts/tool.sh" ]]; then
  printf '[TEST] PASS: Case 3: clean files still sync (as links)\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 3: clean files missing from shared tree after sync\n' >&2
  fail=$((fail+1))
fi

# Case 4: recovery — once canonical holds a valid file again, the next sync
# delivers it (the hold is a hold, not a permanent exclude).
printf '#!/usr/bin/env bash\necho "fixed"\n' > "$canon/plugins/leadv2/hooks/leadv2-mid-edit.sh"
(cd "$canon" && git add -A && git commit -q -m "fix hook")
rc2=0
run_sync "$tmp/run2.log" || rc2=$?
if grep -q "fixed" "$shared_hooks/leadv2-mid-edit.sh" 2>/dev/null; then
  printf '[TEST] PASS: Case 4: repaired file syncs on the next run\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 4: repaired file never reached the destination\n' >&2
  fail=$((fail+1))
fi

# Case 5: the retired (a) cache leg writes nothing (C1-RETIRE-RSYNC).
if [[ "$(ls -A "$cache_dir" | tr -d ' \n')" == "CANARY" ]]; then
  printf '[TEST] PASS: Case 5: retired (a) wrote nothing to the 0.1.0 cache dir\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 5: cache 0.1.0 was written: %s\n' "$(ls -A "$cache_dir")" >&2
  fail=$((fail+1))
fi

printf '\n[TEST] plugin sync syntax gate: %s passed, %s failed\n' "$pass" "$fail"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
