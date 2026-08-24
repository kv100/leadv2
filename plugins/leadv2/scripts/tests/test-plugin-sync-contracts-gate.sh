#!/usr/bin/env bash
# test-plugin-sync-contracts-gate.sh — DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01
# residual gap 2: the (d) project-contracts copies must be gated exactly like
# scripts — gate 1 (uncommitted destination: hard refuse, no override) and
# gate 2 (VENDORED_NEWER destination: refuse without --allow-backward,
# quarantine + promote command) — and a bare invocation must be a dry run
# that writes nothing (incl. contracts).
#
# Runs the REAL leadv2-plugin-sync.sh against real filesystem fixtures under
# an isolated HOME / LEADV2_CANONICAL_ROOT (test-plugin-sync-claude-scripts.sh
# pattern — no mocked function calls).
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

check_not() {
  local got="$1" unwanted_substr="$2" label="$3"
  if [[ "$got" != *"$unwanted_substr"* ]]; then
    printf '[TEST] PASS: %s\n' "$label"; pass=$((pass+1))
  else
    printf '[TEST] FAIL: %s\n  got: %s\n  must NOT contain: %s\n' "$label" "$got" "$unwanted_substr" >&2
    fail=$((fail+1))
  fi
}

# ── Fixture: isolated canonical git tree with contracts (both schemas) ─────
canon="$tmp/canon"
mkdir -p "$canon/plugins/leadv2/scripts" "$canon/plugins/leadv2/contracts"
printf '#!/usr/bin/env bash\necho "canonical a"\n' > "$canon/plugins/leadv2/scripts/a.sh"
printf '{"schema": "scorecard", "v": 1}\n' > "$canon/plugins/leadv2/contracts/leadv2-scorecard.schema.json"
printf '{"schema": "shadow-proposal", "v": 1}\n' > "$canon/plugins/leadv2/contracts/leadv2-shadow-proposal.schema.json"
(cd "$canon" && git init -q && git config user.email test@example.invalid && git config user.name contracts-gate-test && git add -A && git commit -q -m "init")

home="$tmp/home"
mkdir -p "$home"

# proj starts as a NON-git directory (gate 1 cannot fire; untracked/unversioned
# destinations keep only gate-2 protection — mirrors the real vendored repos).
proj="$tmp/proj"
mkdir -p "$proj"

run_sync() {
  local logfile="$1"
  shift
  local rc=0
  env -u LEADV2_PROJECT_ROOT -u LEADV2_STATE_ROOT -u PROJECT_ROOT \
    HOME="$home" LEADV2_CANONICAL_ROOT="$canon" \
    LEADV2_QUARANTINE_ROOT="$tmp/quarantine" \
    bash "$PLUGIN_SYNC" --project-root "$proj" "$@" >"$logfile.out" 2>"$logfile" || rc=$?
  return "$rc"
}

scorecard_dst="$proj/.claude/contracts/leadv2-scorecard.schema.json"

# ── Case 1: bare invocation = DRY_RUN, writes nothing (incl. contracts) ────
run_sync "$tmp/run1.log"
run1_log="$(cat "$tmp/run1.log")"
check "$(head -1 "$tmp/run1.log")" "Mode: DRY_RUN" "Case 1: first logged line is Mode: DRY_RUN"
if [[ ! -e "$scorecard_dst" ]]; then
  printf '[TEST] PASS: Case 1: bare run wrote no contracts file\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 1: bare run created %s\n' "$scorecard_dst" >&2; fail=$((fail+1))
fi

# ── Case 2: VENDORED_NEWER contract refused under --write ──────────────────
mkdir -p "$proj/.claude/contracts"
printf '{"schema": "scorecard", "v": 2, "local-edit": true}\n' > "$scorecard_dst"
vendored_content="$(cat "$scorecard_dst")"
# Far-future mtime ⇒ copy_evidence > canonical_commit_time + 2 ⇒ VENDORED_NEWER
touch -t 209901010000 "$scorecard_dst"
vendored_mtime_before="$(stat -f '%m' "$scorecard_dst")"

run_sync "$tmp/run2.log" --write
run2_log="$(cat "$tmp/run2.log")"
check "$run2_log" "REFUSED (backward)" "Case 2: --write output contains REFUSED (backward)"
check "$run2_log" "cp ${scorecard_dst} ${canon}/plugins/leadv2/contracts/leadv2-scorecard.schema.json" "Case 2: refusal names the exact cp promote command into canonical"
if [[ "$(cat "$scorecard_dst")" == "$vendored_content" ]]; then
  printf '[TEST] PASS: Case 2: vendored bytes unchanged after refused --write\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 2: vendored bytes were clobbered\n' >&2; fail=$((fail+1))
fi
if [[ "$(stat -f '%m' "$scorecard_dst")" == "$vendored_mtime_before" ]]; then
  printf '[TEST] PASS: Case 2: vendored mtime unchanged (no quarantine-in-place rewrite)\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 2: vendored mtime changed\n' >&2; fail=$((fail+1))
fi
# Quarantine copy must preserve the newer content (protection WITH preservation).
if grep -rq 'local-edit' "$tmp/quarantine" 2>/dev/null; then
  printf '[TEST] PASS: Case 2: refused content preserved in quarantine\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 2: quarantine copy of vendored content missing\n' >&2; fail=$((fail+1))
fi

# ── Case 3: VENDORED_NEWER contract allowed under --write --allow-backward ─
run_sync "$tmp/run3.log" --write --allow-backward
run3_log="$(cat "$tmp/run3.log")"
check "$run3_log" "[project/contracts] copied leadv2-scorecard.schema.json -> proj" "Case 3: --allow-backward copies the contract"
if [[ "$(cat "$scorecard_dst")" == "$(cat "$canon/plugins/leadv2/contracts/leadv2-scorecard.schema.json")" ]]; then
  printf '[TEST] PASS: Case 3: destination now matches canonical\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 3: destination does not match canonical\n' >&2; fail=$((fail+1))
fi

# ── Case 4: dirty tracked contract refused with NO override ────────────────
# Turn proj into a git repo with the contract tracked, then modify it —
# gate 1 must refuse even under --write --allow-backward.
(cd "$proj" && git init -q && git config user.email test@example.invalid && git config user.name contracts-gate-test \
  && git add .claude/contracts/leadv2-scorecard.schema.json && git commit -q -m "track contract")
printf '{"schema": "scorecard", "v": 3, "uncommitted-edit": true}\n' > "$scorecard_dst"
dirty_content="$(cat "$scorecard_dst")"

run_sync "$tmp/run4.log" --write --allow-backward
run4_log="$(cat "$tmp/run4.log")"
check "$run4_log" "REFUSED" "Case 4: dirty contract refused even with --allow-backward"
check "$run4_log" "uncommitted" "Case 4: refusal reason is uncommitted destination"
check_not "$run4_log" "[project/contracts] copied leadv2-scorecard.schema.json -> proj" "Case 4: no copy happened for the dirty contract"
if [[ "$(cat "$scorecard_dst")" == "$dirty_content" ]]; then
  printf '[TEST] PASS: Case 4: dirty bytes unchanged\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 4: dirty bytes were clobbered\n' >&2; fail=$((fail+1))
fi

printf '\n[TEST] contracts-gate: %d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
