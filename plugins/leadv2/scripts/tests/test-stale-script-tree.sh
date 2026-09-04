#!/usr/bin/env bash
# tests/test-stale-script-tree.sh — PLUGIN-REVIEW-ARMS-01 §3.2 regression suite.
# run-all-triggers: leadv2-dispatch-code.sh
#
# The plugin's own repo once ran a whole dispatch (4c9ddb05) out of a STALE
# real-copy script tree (.claude/scripts/, pre-07-30 writers): status:
# no_reviewer, empty pool, rc=127 phase records -- all traced to the same root
# cause, dispatch-code.sh executing from a copy instead of the canonical tree.
# cmd_resolve() now refuses (exit 4) when SCRIPT_DIR is not a
# plugins/leadv2/scripts suffix AND a canonical tree is discoverable at
# PROJECT_ROOT/plugins/leadv2/scripts, unless LEADV2_ALLOW_STALE_SCRIPT_TREE=1
# downgrades it to a warn.
#
#   T3  stale-tree dispatch refuses: exit 4, stderr names the tree + remedy,
#       journal carries dispatch_refused reason=stale_script_tree.
#   T4  LEADV2_ALLOW_STALE_SCRIPT_TREE=1 downgrades the refusal to a warn.
#   T5  legitimate run trees pass: the plugin tree itself and a worktree-style
#       copy (.claude/worktrees/<id>/plugins/leadv2/scripts) -- suffix match
#       only, never an absolute prefix (R3/R4).
#
# Hermetic: scratch git repo + poison provider bins; no live quota/network read.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISPATCH="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID \
      LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME LEADV2_ROUTING_YAML
export LEADV2_ARM_EARLY_VERDICT_S=0

bash -n "$DISPATCH" 2>/dev/null || { echo "ERROR: dispatch-code.sh syntax"; exit 1; }

ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t leadv2-sst01)"; trap 'rm -rf "$ROOT"' EXIT
REPO="$ROOT/repo"
mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2/.bus-offsets" "$REPO/docs/leadv2/tasks"
(cd "$REPO" && git init -q && git config user.email test@example.com && git config user.name test \
  && printf 'seed\n' > seed && git add seed && git commit -qm seed)

for _arm in glm kimi codex; do
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "$ROOT/poison-${_arm}.sh"
  chmod +x "$ROOT/poison-${_arm}.sh"
done
export LEADV2_DISPATCH_GLM_BIN="$ROOT/poison-glm.sh"
export LEADV2_DISPATCH_KIMI_BIN="$ROOT/poison-kimi.sh"
export LEADV2_DISPATCH_CODEX_BIN="$ROOT/poison-codex.sh"
export LEADV2_DISPATCH_CACHE_DIR="$ROOT/cache"
export LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$ROOT/ledger.tsv"
export LEADV2_QUOTA_LOCKOUT_DIR="$ROOT/lockouts"

dispatch_env() {
  env CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
    "$@"
}

# ── T3: stale-tree dispatch refuses (exit 4) ────────────────────────────────
STALE="$ROOT/stale-tree/scripts"
mkdir -p "$STALE" "$REPO/plugins/leadv2/scripts"
cp "$DISPATCH" "$STALE/leadv2-dispatch-code.sh"
cp "${SCRIPTS_ROOT}/leadv2-lane-child-suffixes.sh" "${SCRIPTS_ROOT}/leadv2-portable-lock.sh" "$STALE/" 2>/dev/null
# The discoverable canonical tree (suffix-matched path inside the scratch project).
cp "$DISPATCH" "$REPO/plugins/leadv2/scripts/leadv2-dispatch-code.sh"
FAKE_JOURNAL="$ROOT/fake-journal.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/journal-capture.txt"\n' "$ROOT" > "$FAKE_JOURNAL"
chmod +x "$FAKE_JOURNAL"

out3="$(dispatch_env LEADV2_JOURNAL_BIN="$FAKE_JOURNAL" bash "$STALE/leadv2-dispatch-code.sh" \
    'stale tree refusal probe' --kind code --writes src/main.py --no-spawn 2>&1)"; rc3=$?
if [[ "$rc3" -eq 4 ]]; then
  pass "T3a: stale-tree dispatch exits 4"
else
  fail "T3a: stale-tree exit" "expected rc=4, got ${rc3} -- $(printf '%s' "$out3" | tail -3)"
fi
if printf '%s\n' "$out3" | grep -q 'dispatch refused: running from a stale script copy'; then
  pass "T3b: refusal names the stale tree on stderr"
else
  fail "T3b: refusal text" "stderr lacks the refuse line"
fi
if printf '%s\n' "$out3" | grep -q 'remedy: ln -sf'; then
  pass "T3c: remedy lands on stderr"
else
  fail "T3c: remedy" "no remedy line"
fi
if grep -q 'dispatch_refused reason=stale_script_tree' "$ROOT/journal-capture.txt" 2>/dev/null; then
  pass "T3d: journal carries dispatch_refused reason=stale_script_tree"
else
  fail "T3d: journal line" "capture lacks dispatch_refused: $(cat "$ROOT/journal-capture.txt" 2>/dev/null | tail -2)"
fi

# ── T4: escape hatch downgrades to warn ──────────────────────────────────────
rm -f "$ROOT/journal-capture.txt"
out4="$(dispatch_env LEADV2_ALLOW_STALE_SCRIPT_TREE=1 LEADV2_JOURNAL_BIN="$FAKE_JOURNAL" \
  bash "$STALE/leadv2-dispatch-code.sh" \
    'stale tree escape hatch probe' --kind code --writes src/main.py --no-spawn 2>&1)"; rc4=$?
if [[ "$rc4" -ne 4 ]]; then
  pass "T4a: escape hatch does not refuse (rc=${rc4})"
else
  fail "T4a: escape hatch" "still refused with LEADV2_ALLOW_STALE_SCRIPT_TREE=1"
fi
if printf '%s\n' "$out4" | grep -q 'dispatch_stale_script_tree_warn'; then
  pass "T4b: escape hatch emits the downgrade warn"
else
  fail "T4b: downgrade warn" "no dispatch_stale_script_tree_warn line"
fi

# ── T5: legitimate run trees pass ────────────────────────────────────────────
WT="$ROOT/wt-copy/.claude/worktrees/fake01/plugins/leadv2/scripts"
mkdir -p "$WT"
cp "$DISPATCH" "$WT/leadv2-dispatch-code.sh"

run_pass_tree() { # <script_path> <label>
  local out rc
  out="$(dispatch_env LEADV2_JOURNAL_BIN="$FAKE_JOURNAL" bash "$1" \
      "legitimate tree probe $2" --kind code --writes src/main.py --no-spawn 2>&1)"; rc=$?
  if [[ "$rc" -eq 4 ]]; then
    fail "T5($2)" "refused (rc=4) -- legitimate tree must pass the suffix check"
    return
  fi
  if printf '%s\n' "$out" | grep -q 'dispatch_refused reason=stale_script_tree'; then
    fail "T5($2)" "emitted dispatch_refused from a legitimate tree"
    return
  fi
  pass "T5($2): passes provenance check (rc=${rc})"
}
run_pass_tree "$REPO/plugins/leadv2/scripts/leadv2-dispatch-code.sh" "canonical"
run_pass_tree "$WT/leadv2-dispatch-code.sh" "worktree-copy"

echo "=== ${PASS} passed, ${FAIL} failed ==="
[[ "$FAIL" -eq 0 ]]
