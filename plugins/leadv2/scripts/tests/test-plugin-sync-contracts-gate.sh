#!/usr/bin/env bash
# test-plugin-sync-contracts-gate.sh — DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01
# residual gap 2, REBASED for link-mode (C1-RETIRE-RSYNC, 2026-09-08).
#
# (d) project contracts used to be a gated `cp -p` — gate 1 (uncommitted
# destination: hard refuse, no override) and gate 2 (VENDORED_NEWER
# destination: refuse without --allow-backward, quarantine + promote
# command). Since C1-RETIRE-RSYNC contracts are LINK-ONLY: an absent
# contract enters as a symlink into canonical, and an EXISTING real copy is
# structurally never written — so gate 2 is gone (a link overwrites nothing
# and a divergent copy is DRIFT, left untouched), while gate 1 survives
# inline: a tracked-and-modified project contract is still hard-refused,
# because swapping an uncommitted project file for a link mid-edit is not
# the sync's to do. This suite pins exactly that contract.
#
# Runs the REAL leadv2-plugin-sync.sh against real filesystem fixtures under
# an isolated HOME / LEADV2_CANONICAL_ROOT (test-plugin-sync-claude-scripts.sh
# pattern — no mocked function calls).
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

# proj starts as a NON-git directory (the dirty-refuse cannot fire; mirrors
# the real vendored repos whose .claude trees are untracked by design).
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
shadow_dst="$proj/.claude/contracts/leadv2-shadow-proposal.schema.json"

# ── Case 1: bare invocation = DRY_RUN, writes nothing (no links, no copies) ─
run_sync "$tmp/run1.log"
run1_log="$(cat "$tmp/run1.log")"
check "$(head -1 "$tmp/run1.log")" "Mode: DRY_RUN" "Case 1: first logged line is Mode: DRY_RUN"
if [[ ! -e "$scorecard_dst" && ! -L "$scorecard_dst" ]]; then
  printf '[TEST] PASS: Case 1: bare run wrote no contracts file\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 1: bare run created %s\n' "$scorecard_dst" >&2; fail=$((fail+1))
fi
check "$run1_log" "WOULD LINK: ${scorecard_dst}" "Case 1: dry run plans the contract as a LINK"

# ── Case 2: absent contract enters as a symlink under --write ───────────────
run_sync "$tmp/run2.log" --write
if [[ -L "$shadow_dst" && "$(readlink "$shadow_dst")" == "$canon/plugins/leadv2/contracts/leadv2-shadow-proposal.schema.json" ]]; then
  printf '[TEST] PASS: Case 2: absent contract linked into canonical\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 2: absent contract is not a link into canonical\n' >&2; fail=$((fail+1))
fi

# ── Case 3: divergent real contract is structurally never written ───────────
# (old semantics: VENDORED_NEWER refusal + quarantine; link-mode semantics:
# nothing overwrites a real copy — divergence is DRIFT, promote or discard.)
# Remove Case 2's link FIRST: planting content through a resolving symlink
# would write straight into the canonical fixture.
mkdir -p "$proj/.claude/contracts"
rm -f "$scorecard_dst"
printf '{"schema": "scorecard", "v": 2, "local-edit": true}\n' > "$scorecard_dst"
vendored_content="$(cat "$scorecard_dst")"
touch -t 209901010000 "$scorecard_dst"

run_sync "$tmp/run3.log" --write --allow-backward
run3_log="$(cat "$tmp/run3.log")"
check "$run3_log" "DRIFT: ${scorecard_dst}" "Case 3: divergent contract reported as DRIFT"
if [[ "$(cat "$scorecard_dst")" == "$vendored_content" ]]; then
  printf '[TEST] PASS: Case 3: divergent bytes unchanged even under --allow-backward\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 3: divergent bytes were clobbered\n' >&2; fail=$((fail+1))
fi
if [[ ! -L "$scorecard_dst" ]]; then
  printf '[TEST] PASS: Case 3: divergent contract stays a real file (SD-SYMLINK-FARM-CONVERT-01 owns conversion)\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 3: divergent contract was converted to a link\n' >&2; fail=$((fail+1))
fi

# ── Case 4: dirty tracked contract refused with NO override ────────────────
# Turn proj into a git repo with the contract tracked, then modify it — the
# inline hard-refuse must fire even under --write --allow-backward.
(cd "$proj" && git init -q && git config user.email test@example.invalid && git config user.name contracts-gate-test \
  && git add .claude/contracts/leadv2-scorecard.schema.json && git commit -q -m "track contract")
printf '{"schema": "scorecard", "v": 3, "uncommitted-edit": true}\n' > "$scorecard_dst"
dirty_content="$(cat "$scorecard_dst")"

run_sync "$tmp/run4.log" --write --allow-backward
run4_log="$(cat "$tmp/run4.log")"
check "$run4_log" "REFUSED (uncommitted destination): ${scorecard_dst}" "Case 4: dirty contract refused even with --allow-backward"
check_not "$run4_log" "LINK: ${scorecard_dst}" "Case 4: no link was created for the dirty contract"
check_not "$run4_log" "CONVERT: ${scorecard_dst}" "Case 4: no conversion happened for the dirty contract"
if [[ "$(cat "$scorecard_dst")" == "$dirty_content" && ! -L "$scorecard_dst" ]]; then
  printf '[TEST] PASS: Case 4: dirty bytes unchanged, file still real\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 4: dirty contract was touched\n' >&2; fail=$((fail+1))
fi

# ── Case 5: identical real contract converts to a link, losslessly ──────────
printf '{"schema": "scorecard", "v": 1}\n' > "$scorecard_dst"
(cd "$proj" && git add -A && git commit -q -m "realign with canonical")
run_sync "$tmp/run5.log" --write
if [[ -L "$scorecard_dst" && "$(cat "$scorecard_dst")" == "$(cat "$canon/plugins/leadv2/contracts/leadv2-scorecard.schema.json")" ]]; then
  printf '[TEST] PASS: Case 5: identical contract converted to a link, content preserved\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Case 5: identical contract not converted losslessly\n' >&2; ls -la "$scorecard_dst" >&2; fail=$((fail+1))
fi

printf '\n[TEST] contracts-gate: %s passed, %s failed\n' "$pass" "$fail"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
