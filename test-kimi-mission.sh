#!/usr/bin/env bash
set -euo pipefail

# Simplified version of case1 from test-dispatch-arm-vocabulary.sh
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

REPO="$ROOT/repo"
mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2/.bus-offsets" "$REPO/docs/leadv2/tasks"
(cd "$REPO" && git init -q && git config user.email test@example.com && git config user.name test && : > seed && git add seed && git commit -qm seed)

DISPATCH="plugins/leadv2/scripts/leadv2-dispatch-code.sh"

# Create resolver stub that returns kimi
RESOLVER_STUB="$ROOT/resolver-stub.py"
cat > "$RESOLVER_STUB" <<'EOF'
#!/usr/bin/env python3
print("arm=kimi")
print("rule=codex_quota_gate_80pct")
print("reason=codex_quota_gate")
print("tier=")
print("codex_quota_blocked=1")
EOF
chmod +x "$RESOLVER_STUB"

# Create worker stub
WORKER="$ROOT/worker.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$$"\n' > "$WORKER"
chmod +x "$WORKER"

# Create poison scripts
for arm in glm kimi codex; do
  poison="$ROOT/poison-${arm}.sh"
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "$poison"
  chmod +x "$poison"
done

export LEADV2_DISPATCH_GLM_BIN="$ROOT/poison-glm.sh"
export LEADV2_DISPATCH_KIMI_BIN="$ROOT/poison-kimi.sh"
export LEADV2_DISPATCH_CODEX_BIN="$ROOT/poison-codex.sh"
export LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER"

echo "=== Running dispatch with kimi resolver stub ==="
echo "Mission: 'test mission for kimi mismatch'"
echo

out="$(
  CLAUDE_PROJECT_ROOT="$REPO" \
  LEADV2_PROJECT_ROOT="$REPO" \
  LEADV2_DISPATCH_CACHE_DIR="$ROOT/cache" \
  LEADV2_DISPATCH_E2E_GATE=0 \
  LEADV2_DISPATCH_REVIEW_GATE=0 \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_ROUTER_V2=0 \
  LEADV2_EXCLUDED_ARMS=__none__ \
  LEADV2_LANE_SHAPE=off \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$ROOT/ledger.tsv" \
  GLM_POLICY_RESOLVER="$RESOLVER_STUB" \
  LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
  bash "$DISPATCH" 'test mission for kimi mismatch' --kind code --writes src/main.py 2>&1
)" || rc=$?
rc=${rc:-0}

echo "Exit code: $rc"
echo
echo "=== Output ==="
echo "$out"
echo
echo "=== Checking for arm_vocabulary_mismatch ==="
if printf '%s\n' "$out" | grep -q 'arm_vocabulary_mismatch.*arm=kimi.*fallback=sonnet'; then
  echo "✓ Found mismatch line in stdout"
else
  echo "✗ No mismatch line in stdout"
fi

# Check journal
journal="$(find "$REPO/docs/leadv2/tasks" -name journal.md -print -quit 2>/dev/null)"
if [[ -n "$journal" ]]; then
  echo "=== Journal content ==="
  cat "$journal"
  echo
  if grep -q 'arm_vocabulary_mismatch.*arm=kimi.*fallback=sonnet' "$journal" 2>/dev/null; then
    echo "✓ Found mismatch line in journal"
  else
    echo "✗ No mismatch line in journal"
  fi
else
  echo "No journal file found"
fi

echo
echo "=== Test verdict ==="
if [[ "$rc" -eq 1 ]]; then
  echo "FAIL: Dispatch exited 1 (the bug that should be fixed)"
  exit 1
elif printf '%s\n' "$out" | grep -q 'arm_vocabulary_mismatch.*arm=kimi.*fallback=sonnet'; then
  echo "PASS: Dispatch survived with mismatch line"
  exit 0
else
  echo "FAIL: No mismatch line found"
  exit 1
fi