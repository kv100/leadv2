#!/usr/bin/env bash
# DISPATCH-KIMI-ARM-MISMATCH-01 (2026-08-05): arm-vocabulary suite.
#
# The resolver and launcher must agree on the set of dispatchable build arms.
# Kimi was retired as a build arm (founder order 2026-08-04). These tests prove:
#   1. A resolver that hands back kimi does NOT exit 1 — the launcher falls
#      back to sonnet and emits arm_vocabulary_mismatch.
#   2. The glm chain no longer contains kimi.
#   3/4. codex/sonnet chains are unchanged (regression guard).
#   5. A stale tenant yaml listing kimi in build_spill_order cannot resurrect it.
#   6. router_v2.arms parses non-empty and excludes kimi.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0; ERRORS=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

# ── Hermeticity: clean parent-session LEADV2_* env vars ──────────────────
# The dispatch code reads LEADV2_PROJECT_ROOT (active.yaml, LEAD_V2_STATE.md)
# and LEADV2_LANE_WORK_ROOT (WORK_ROOT override) directly from the environment
# — it never re-sets them from CLAUDE_PROJECT_ROOT.  An inherited value from
# the parent lead session leaks real registry state into the test sandbox.
# (E2E-GATE-RESIDUE-01)
unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID \
      LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME

# Skip the post-spawn early-verdict poll window — the stub worker bin never
# reports "complete", so the poll loop would sleep for 20s per spawn.
# (E2E-GATE-RESIDUE-01)
export LEADV2_ARM_EARLY_VERDICT_S=0

# Pin CACHE_BASE to a throwaway dir as a belt-and-suspenders default
# (individual tests override with per-test sub-dirs).  Prevents the dispatch
# ledger and quota-lockout files from touching the real shared HOME cache.
# (E2E-GATE-RESIDUE-01 round-3)
export LEADV2_DISPATCH_CACHE_DIR="/tmp/leadv2-vocab-default-cache"
mkdir -p "${LEADV2_DISPATCH_CACHE_DIR}" 2>/dev/null || true

# Prevent a real ~/.claude/leadv2-excluded-arms file from leaking in.
# (E2E-GATE-RESIDUE-01)
unset LEADV2_EXCLUDED_ARMS

# --- syntax gate ---------------------------------------------------------------
bash -n "$SCRIPT_DIR/test-dispatch-arm-vocabulary.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
REPO="$ROOT/repo"
mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2/.bus-offsets" "$REPO/docs/leadv2/tasks"
(cd "$REPO" && git init -q && git config user.email test@example.com && git config user.name test && : > seed && git add seed && git commit -qm seed)

DISPATCH="$SCRIPTS_ROOT/leadv2-dispatch-code.sh"
RESOLVER="$SCRIPTS_ROOT/lib/leadv2-glm-policy-resolve.py"
ROUTING_YAML_FILE="$SCRIPTS_ROOT/../config/leadv2-routing.yaml"

# A no-op worker stub that prints the handle line dispatch expects.
WORKER="$ROOT/worker.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$$"\n' > "$WORKER"
chmod +x "$WORKER"

# Fail-closed spawn fence: every provider bin is pointed at a poison script.
# Any code path that forgets to override one gets a loud, offline failure.
for _arm in glm kimi codex; do
  _poison="$ROOT/poison-${_arm}.sh"
  printf '#!/usr/bin/env bash\nprintf "POISON: real provider spawn attempted\\n" >&2\nexit 99\n' > "$_poison"
  chmod +x "$_poison"
done
export LEADV2_DISPATCH_GLM_BIN="$ROOT/poison-glm.sh"
export LEADV2_DISPATCH_KIMI_BIN="$ROOT/poison-kimi.sh"
export LEADV2_DISPATCH_CODEX_BIN="$ROOT/poison-codex.sh"
export LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER"  # sonnet uses SUBSESSION_BIN; stubbed above

# ============================================================================
# Case 1: resolver returns kimi as PRIMARY → dispatch does NOT exit 1, falls
#         back to sonnet, emits arm_vocabulary_mismatch
# ============================================================================
case1() {
  local stub="$ROOT/resolver-stub.py"
  cat > "$stub" <<'EOF'
#!/usr/bin/env python3
print("arm=kimi")
print("rule=codex_quota_gate_80pct")
print("reason=codex_quota_gate")
print("tier=")
print("codex_quota_blocked=1")
EOF
  chmod +x "$stub"

  local out rc
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
    GLM_POLICY_RESOLVER="$stub" \
    LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
    bash "$DISPATCH" 'test mission for kimi mismatch' --kind code --writes src/main.py 2>&1
  )" || rc=$?
  rc=${rc:-0}

  # Must NOT exit 1
  if [[ "$rc" -eq 1 ]]; then
    fail "case1: dispatch exited 1 (the original bug) — rc=$rc"
    return
  fi

  # Journal must carry arm_vocabulary_mismatch with arm=kimi and fallback=sonnet
  local journal
  journal="$(find "$REPO/docs/leadv2/tasks" -name journal.md -print -quit 2>/dev/null)"
  if [[ -z "$journal" ]]; then
    # The emit function also goes to stdout via log()
    if printf '%s\n' "$out" | grep -q 'arm_vocabulary_mismatch.*arm=kimi.*fallback=sonnet'; then
      pass "case1: resolver returns kimi → dispatch survives on sonnet with mismatch line"
      return
    fi
    fail "case1: no journal and no stdout mismatch line found"
    return
  fi

  if grep -q 'arm_vocabulary_mismatch.*arm=kimi.*fallback=sonnet' "$journal" 2>/dev/null \
     || printf '%s\n' "$out" | grep -q 'arm_vocabulary_mismatch.*arm=kimi.*fallback=sonnet'; then
    pass "case1: resolver returns kimi → dispatch survives on sonnet with mismatch line"
  else
    fail "case1: missing arm_vocabulary_mismatch in journal and stdout"
  fi
}

# ============================================================================
# Cases 2/3/4: _build_candidate_chain via source-harness (repointed from the
# deleted _candidate_chain_for_arm — identical unknown-arm semantics).
# ============================================================================
harness() {
  local harness_script="$ROOT/harness.sh"
  cat > "$harness_script" <<'HEAD'
#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0
_MISMATCH_EMITTED=0
emit() { [[ "$*" == *"arm_vocabulary_mismatch"* ]] && _MISMATCH_EMITTED=1; }
log_err() { :; }
log() { :; }

HEAD
  # Extract _load_dispatch_ladder, _arm_provider, _filter_ladder_to_dispatchable,
  # and _build_candidate_chain from the dispatch script.
  sed -n '/^_load_dispatch_ladder()/,/^}$/p' "$DISPATCH" >> "$harness_script"
  sed -n '/^_dispatchable_arms()/,/^}$/p' "$DISPATCH" >> "$harness_script"
  sed -n '/^_build_candidate_chain()/,/^}$/p' "$DISPATCH" >> "$harness_script"
  sed -n '/^_arm_provider()/,/^}$/p' "$DISPATCH" >> "$harness_script"
  sed -n '/^_filter_ladder_to_dispatchable()/,/^}$/p' "$DISPATCH" >> "$harness_script"
  cat >> "$harness_script" <<'BODY'

run_test() {
  local arm="$1" expected="$2" desc="$3" expect_mismatch="${4:-0}"
  local -a candidate_arms=()
  _MISMATCH_EMITTED=0
  _build_candidate_chain "$arm" "TEST0000"
  local result="${candidate_arms[*]}"
  if [[ "$result" == "$expected" ]] && { [[ "$expect_mismatch" == "0" ]] || [[ "$_MISMATCH_EMITTED" == "1" ]]; }; then
    echo "PASS: $desc (got: $result)"
  else
    echo "FAIL: $desc (expected: '$expected', got: '$result', mismatch_emitted=$_MISMATCH_EMITTED)"
  fi
}

# Load the production ladder: glm, codex, sonnet (kimi dispatch:false, fable dispatch:false).
ROUTING_YAML="$1"
SCRIPT_DIR="$2"
_load_dispatch_ladder
_filter_ladder_to_dispatchable "TEST0000"

# Case 2: glm chain = glm onward in the ladder
run_test "glm" "glm codex sonnet" "case2: glm chain from ladder (excludes kimi)"

# Case 3: codex chain (regression guard)
run_test "codex" "codex sonnet" "case3: codex chain unchanged"

# Case 4: sonnet chain (regression guard)
run_test "sonnet" "sonnet" "case4: sonnet chain unchanged"

# Case 4b: kimi (not in ladder) -> sonnet + mismatch line
run_test "kimi" "sonnet" "case4b: kimi unknown arm -> sonnet + mismatch" 1
BODY

  bash "$harness_script" "$ROUTING_YAML_FILE" "$SCRIPTS_ROOT"
}

# ============================================================================
# Case 5: stale tenant yaml with kimi in build_spill_order → resolver does
#         NOT return kimi
# ============================================================================
case5() {
  local fixture="$ROOT/routing-kimi-spill.yaml"
  local quota_stub="$ROOT/quota-live-stub.sh"
  cat > "$fixture" <<'YAML'
router:
  glm_policy:
    codex_fitting_mission_kinds: [refactor]
    codex_quota_gate:
      build_threshold_pct: 80
      build_spill_order: [glm, kimi, codex, sonnet]
YAML
  # Stub quota-live: codex at 90% → above threshold → triggers spill walk
  cat > "$quota_stub" <<'QEOF'
#!/usr/bin/env bash
case "$1" in
  codex) printf '90.0\n' ;;
  *) printf '0.0\n' ;;
esac
QEOF
  chmod +x "$quota_stub"

  local out arm
  out="$(python3 "$RESOLVER" --routing-yaml "$fixture" --job build --base-arm glm \
    --signals '{"mission_kind":"refactor"}' --quota-live "$quota_stub" 2>&1)"
  arm="$(printf '%s\n' "$out" | sed -n 's/^arm=//p')"

  if [[ "$arm" != "kimi" ]]; then
    pass "case5: resolver spill with kimi in tenant yaml → arm=$arm (not kimi)"
  else
    fail "case5: resolver returned arm=kimi despite allowlist — stale tenant yaml resurrected a retired arm"
  fi
}

# ============================================================================
# Case 6: router_v2.arms parses non-empty and excludes kimi
# ============================================================================
case6() {
  local ids
  ids="$(python3 -c '
import yaml, sys
d = yaml.safe_load(open(sys.argv[1]))
ids = [a["id"] for a in d["router_v2"]["arms"]]
print(" ".join(ids))
' "$ROUTING_YAML_FILE" 2>&1)"

  local count
  count="$(printf '%s' "$ids" | wc -w | tr -d ' ')"
  if [[ "$count" -ge 3 && "$ids" != *"kimi"* ]]; then
    pass "case6: router_v2.arms has $count entries, kimi absent ($ids)"
  else
    fail "case6: router_v2.arms check failed — count=$count ids='$ids'"
  fi
}

# --- run all cases -------------------------------------------------------------
case1
harness | while IFS= read -r line; do
  case "$line" in
    PASS:*) pass "${line#PASS: }" ;;
    FAIL:*) fail "${line#FAIL: }" ;;
  esac
done
case5
case6

log ""
log "================================================"
log "  arm-vocabulary suite: PASS=$PASS FAIL=$FAIL"
log "================================================"

[[ "$FAIL" -eq 0 ]]
