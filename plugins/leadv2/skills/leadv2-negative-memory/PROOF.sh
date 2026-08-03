#!/usr/bin/env bash
set -euo pipefail
# proof-of: leadv2-negative-memory trigger-scan fires on active trigger patterns and skips expired ones, proving the status-based filter works.
#
# Scope: exercises the regex trigger-scan script against a fixture git repo.
# Proves active patterns block (exit 2) and expired patterns are silently
# skipped even when their regex matches the diff.

source "$LEADV2_PLUGIN_ROOT/scripts/leadv2-proof-lib.sh"

TMP=$(proof_tmpdir)
SCAN_SH="$LEADV2_PLUGIN_ROOT/scripts/leadv2-negative-memory-trigger-scan.sh"

# ── Build a fixture git repo ────────────────────────────────────────────────
REPO="$TMP/nmrepo"
mkdir -p "$REPO/docs"

cd "$REPO"
git init -q
git config user.email test@test.test
git config user.name Test
git checkout -b main 2>/dev/null || git checkout -b main
echo "baseline safe content" > base.txt
git add . && git commit -qm "init main"

git checkout -b work 2>/dev/null || git checkout -b work
echo "dangerous_pattern_here" > danger.txt
echo "expired_pattern_here" > expired.txt
git add . && git commit -qm "risky changes on work branch"

# ── Negative-memory store: one active, one expired ─────────────────────────
cat > docs/leadv2-negative-memory.yaml <<'EOF'
entries:
  - id: nm-active
    status: active
    trigger_pattern: "dangerous_pattern"
    failure_mode: "active failure mode"
  - id: nm-expired
    status: expired
    trigger_pattern: "expired_pattern"
    failure_mode: "resolved failure mode"
EOF

# ── Run trigger scan ─────────────────────────────────────────────────────────
rc=0
output=""
output=$(bash "$SCAN_SH" --base main 2>&1) || rc=$?

assert_eq 2 "$rc" "active trigger fires with exit 2"
assert_contains "$output" "nm-active"   "active pattern reported as blocking"
assert_contains "$output" "dangerous_pattern" "active pattern details shown"

# The expired pattern must NOT appear in the output even though its regex
# matches the diff body.
if echo "$output" | grep -q "nm-expired"; then
  proof_fail "expired trigger pattern should not fire (found nm-expired in output)"
fi

echo "[PROOF] leadv2-negative-memory: all assertions passed"
