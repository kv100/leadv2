#!/usr/bin/env bash
# tests/test-hook-fork-guard.sh — PULSE-HOOK-IS-A-FORKED-COPY-01 deliverable 3.
#
# Proves leadv2-hook-fork-guard.sh both ways against a scratch fixture:
#   1. clean consumer repo            -> exit 0
#   2. real copy of a plugin hook     -> exit 1  (the fork the guard exists for)
#   3. symlink to canonical           -> exit 0  (the sanctioned shape)
#   4. canonical checkout (leadv2 itself) is skipped, even with a real copy
#
# Run: bash plugins/leadv2/scripts/tests/test-hook-fork-guard.sh
set -uo pipefail

GUARD="$(cd "$(dirname "$0")/.." && pwd)/leadv2-hook-fork-guard.sh"
CANONICAL_HOOKS="$(cd "$(dirname "$0")/../.." && pwd)/hooks"

PASS=0; FAIL=0
log()  { printf -- '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$GUARD" || { echo "ERROR: guard syntax check failed"; exit 1; }

HOOK_NAME="$(ls "$CANONICAL_HOOKS" | head -1)"
if [ -z "$HOOK_NAME" ]; then
  echo "ERROR: no plugin hooks found in $CANONICAL_HOOKS"; exit 1
fi

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/hook-fork-guard-test.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
mk_consumer() { mkdir -p "$FIXTURE/$1/.claude/hooks"; }
run_guard() {
  LEADV2_HOOK_FORK_SCAN_ROOT="$FIXTURE" \
  LEADV2_HOOK_FORK_CANONICAL="$CANONICAL_HOOKS" \
    bash "$GUARD" >/dev/null 2>&1
}

# Case 1: clean consumer repo.
mk_consumer clean-repo
if run_guard; then pass "clean consumer repo -> guard exits 0"
else fail "clean consumer repo -> guard exited non-zero"; fi

# Case 2: real (non-symlink) copy — the defect this guard exists for.
mk_consumer forked-repo
cp "$CANONICAL_HOOKS/$HOOK_NAME" "$FIXTURE/forked-repo/.claude/hooks/$HOOK_NAME"
if run_guard; then fail "real copy in consumer repo -> guard exited 0 (must fail)"
else pass "real copy in consumer repo -> guard fails"; fi

# Case 3: symlink to canonical — sanctioned shape.
mk_consumer symlinked-repo
ln -s "$CANONICAL_HOOKS/$HOOK_NAME" "$FIXTURE/symlinked-repo/.claude/hooks/$HOOK_NAME"
rm "$FIXTURE/forked-repo/.claude/hooks/$HOOK_NAME"
if run_guard; then pass "symlink to canonical -> guard exits 0"
else fail "symlink to canonical -> guard exited non-zero"; fi

# Case 4: canonical checkout (carries plugins/leadv2/hooks/) is not a consumer.
mkdir -p "$FIXTURE/canonical-repo/plugins/leadv2/hooks"
mkdir -p "$FIXTURE/canonical-repo/.claude/hooks"
cp "$CANONICAL_HOOKS/$HOOK_NAME" "$FIXTURE/canonical-repo/.claude/hooks/$HOOK_NAME"
if run_guard; then pass "canonical checkout skipped even with .claude/hooks copy"
else fail "canonical checkout was treated as a consumer"; fi

printf -- '\nResults: %d pass, %d fail\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
