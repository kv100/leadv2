#!/usr/bin/env bash
# LANE-TRUTH-BATCH-01: three P1 rows on lane registry/liveness truth.
# Row 1: dispatch-code.sh self-registers with wrong log_path → dead:no_handoff_dir
# Row 2: direct dispatch (no --task-id) was invisible to the registry
#         (already-fixed by STATUS-SURFACE-SHOWS-STALE-TRUTH-01 C5 — verified here)
# Row 3: exclude-mode DIRECTION-SAFETY had no quarantine safety net + convergence
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
tmp="$(lv2_mktemp_dir lane-truth)"; trap 'rm -rf "$tmp"' EXIT

PLUGIN_DIR="$tmp/plugin"
mkdir -p "$PLUGIN_DIR"
cp -a "${REAL_PLUGIN_DIR}/scripts" "$PLUGIN_DIR/"
cp -a "${REAL_PLUGIN_DIR}/workflows" "$PLUGIN_DIR/"
case "$PLUGIN_DIR" in
  "$tmp"/*) ;;
  *) printf '[TEST-SAFETY] ABORT: PLUGIN_DIR %s did not resolve under the scratch root %s\n' "$PLUGIN_DIR" "$tmp" >&2; exit 90 ;;
esac
case "$PLUGIN_DIR" in
  "$REAL_PLUGIN_DIR"|"$REAL_PLUGIN_DIR"/*)
    printf '[TEST-SAFETY] ABORT: PLUGIN_DIR %s resolves inside the real plugin tree %s -- refusing to run\n' "$PLUGIN_DIR" "$REAL_PLUGIN_DIR" >&2
    exit 90
    ;;
esac
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"

repo="$tmp/repo"; state="$tmp/state"; mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff" "$state"
(cd "$repo" && git init -q)
lv2_assert_scratch_repo "$repo"

# Copy state-path resolver so registry and liveness resolve to the same active.yaml
mkdir -p "$repo/scripts"
cp "${PLUGIN_DIR}/scripts/leadv2-state-path.sh" "$repo/scripts/"
chmod +x "$repo/scripts/leadv2-state-path.sh"

REGISTRY="${PLUGIN_DIR}/scripts/leadv2-active-registry.sh"
STATE_PATH="${PLUGIN_DIR}/scripts/leadv2-state-path.sh"
LIVENESS="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
DISPATCH="${PLUGIN_DIR}/scripts/leadv2-dispatch-code.sh"

export LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" PROJECT_ROOT="$repo"
active="$(bash "$STATE_PATH" --no-link active.yaml)"
mkdir -p "$(dirname "$active")"; printf 'sessions: []\n' > "$active"

pass=0; fail=0
check() {
  if grep -q "$2" <<<"$1"; then
    printf '[TEST] PASS: %s\n' "$3"; pass=$((pass+1))
  else
    printf '[TEST] FAIL: %s\n  got: %s\n' "$3" "$1" >&2; fail=$((fail+1))
  fi
}

# ── Row 1: leadv2_active_set_log_path correctly stamps log_path ───────────
# The registry must support the set_log_path op. After calling register
# (which sets log_path to pulse.md) and then set_log_path with the real stream
# path, liveness must resolve via the new path.

source "$REGISTRY" 2>/dev/null
leadv2_active_register "FOO-123" "Standard" "$repo" "main" 2>/dev/null || true

reg_read="$(cat "$active")"
check "$reg_read" 'pulse\.md' 'register sets default log_path to pulse.md'

leadv2_active_set_log_path "FOO-123" "docs/handoff/dispatch-deadbeef/developer.stream.jsonl" 2>/dev/null || true

reg_read2="$(cat "$active")"
check "$reg_read2" 'dispatch-deadbeef/developer\.stream\.jsonl' 'set_log_path stamps the real stream path'
# Verify the log_path line no longer shows pulse.md
if grep 'log_path:' <<<"$reg_read2" | grep -q 'pulse\.md'; then
  printf '[TEST] FAIL: log_path still shows pulse.md after set_log_path\n' >&2; fail=$((fail+1))
else
  printf '[TEST] PASS: log_path no longer defaults to pulse.md\n'; pass=$((pass+1))
fi

# Liveness resolves the lane via the stamped log_path
mkdir -p "$repo/docs/handoff/dispatch-deadbeef"
printf '{"type":"assistant","text":"working"}\n' > "$repo/docs/handoff/dispatch-deadbeef/developer.stream.jsonl"
lane_verdict="$(bash "$LIVENESS" --project-root "$repo" --lane FOO-123 --json)"
check "$lane_verdict" '"verdict":"alive"' 'Row 1: lane with set_log_path resolves alive via real stream'
check "$lane_verdict" 'dispatch-deadbeef' 'Row 1: liveness source is the stamped log_path'

# ── Row 1: set_log_path on unregistered task fails gracefully ──────────────
set_missing_rc=0
leadv2_active_set_log_path "NONEXISTENT-TASK" "docs/handoff/dispatch-f00f00f0/developer.stream.jsonl" 2>/dev/null || set_missing_rc=$?
if [[ "$set_missing_rc" -ne 0 ]]; then
  printf '[TEST] PASS: set_log_path on unregistered task returns non-zero\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: set_log_path on unregistered task should return non-zero\n' >&2; fail=$((fail+1))
fi

# ── Row 2: unregistered dispatch lane discoverable via glob ────────────────
mkdir -p "$repo/docs/handoff/dispatch-cafebabe"
printf '{"type":"assistant","text":"hello"}\n' > "$repo/docs/handoff/dispatch-cafebabe/developer.stream.jsonl"
all_lanes="$(bash "$LIVENESS" --project-root "$repo" --json)"
check "$all_lanes" 'dispatch-cafebabe' 'Row 2: unregistered dispatch lane discoverable via glob'

# ── Row 1 MUTATION GATE: execute the dispatch -> registry -> liveness path ──
# This intentionally runs a complete scratch copy of dispatch-code.sh, then
# reads its active.yaml through liveness.  A mutant whose stamped stream path
# is changed back to pulse.md must fail; HEAD must pass.  This is behavioral:
# it does not inspect dispatch source text for the call.
run_dispatch_liveness_gate() { # <dispatch-copy> [task-id] -> liveness JSON
  local dispatch_copy="$1" task_id="$2"
  local sig8 lane_id gate_root
  sig8="$(printf '%s' 'behavioral lane liveness gate' | sha256sum | cut -c1-8)"
  lane_id="${task_id:-dispatch-${sig8}}"
  gate_root="$tmp/dispatch-gate-${lane_id}"
  mkdir -p "$gate_root/.claude/ref" "$gate_root/docs/handoff" "$gate_root/scripts"
  cp "$PLUGIN_DIR/scripts/leadv2-state-path.sh" "$gate_root/scripts/"
  chmod +x "$gate_root/scripts/leadv2-state-path.sh"
  printf 'glm_policy:\n  sonnet_exceptions:\n    - id: safety_gate_publish_payments\n' \
    > "$gate_root/.claude/ref/leadv2-routing.yaml"
  (cd "$gate_root" && git init -q && git config user.email test@example.invalid && git config user.name lane-truth-test && git add -A && git commit -q -m init)

  # --no-spawn keeps this hermetic. Registration happens before the later
  # product/prepass gate, so it exercises exactly the lifecycle transition
  # that stamps log_path without launching a provider.
  local -a task_arg=()
  [[ -n "$task_id" ]] && task_arg=(--task-id "$task_id")
  CLAUDE_PROJECT_ROOT="$gate_root" PROJECT_ROOT="$gate_root" LEADV2_PROJECT_ROOT="$gate_root" LEADV2_STATE_ROOT="$gate_root/state" LEADV2_DISPATCH_CACHE_DIR="$gate_root/cache" \
    LEADV2_DISPATCH_SPAWN=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
    bash "$dispatch_copy" --no-spawn --kind tooling --worktree "$gate_root" "${task_arg[@]}" \
    'behavioral lane liveness gate' >/dev/null 2>&1 || true

  local stream_dir="$gate_root/docs/handoff/dispatch-${sig8}"
  mkdir -p "$stream_dir"
  printf '{"type":"assistant","text":"working"}\n' > "$stream_dir/developer.stream.jsonl"
  LEADV2_PROJECT_ROOT="$gate_root" LEADV2_STATE_ROOT="$gate_root/state" bash "$LIVENESS" --project-root "$gate_root" --lane "$lane_id" --json
}

head_dispatch="$DISPATCH"
direct_gate="$(run_dispatch_liveness_gate "$head_dispatch" '')"
if grep -q '"verdict":"alive"' <<<"$direct_gate"; then
  printf '[TEST] PASS: Row 2: direct dispatch registers its dispatch-<sig8> lane\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Row 2: direct dispatch must register its dispatch-<sig8> lane\n  got: %s\n' "$direct_gate" >&2; fail=$((fail+1))
fi

head_gate="$(run_dispatch_liveness_gate "$head_dispatch" 'MUT-HEAD')"
if grep -q '"verdict":"alive"' <<<"$head_gate"; then
  printf '[TEST] PASS: Row 1 mutation gate HEAD: dispatch registry read resolves stamped stream alive\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Row 1 mutation gate HEAD must resolve stamped stream alive\n  got: %s\n' "$head_gate" >&2; fail=$((fail+1))
fi

mutant_scripts="$tmp/mutant-scripts"
cp -a "$PLUGIN_DIR/scripts" "$mutant_scripts"
mutant_dispatch="$mutant_scripts/leadv2-dispatch-code.sh"
# The mutation changes the actual stamped registry log_path, rather than
# deleting a line or asserting its spelling.
sed -i.bak 's|"docs/handoff/dispatch-${sig8}/developer.stream.jsonl"|"pulse.md"|' "$mutant_dispatch"
rm -f "$mutant_dispatch.bak"
mutant_gate="$(run_dispatch_liveness_gate "$mutant_dispatch" 'MUT-MUTANT')"
if ! grep -q '"verdict":"alive"' <<<"$mutant_gate"; then
  printf '[TEST] PASS: Row 1 mutation gate mutant: registry read does not treat pulse.md as live stream\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Row 1 mutation gate mutant must not resolve stream alive\n  got: %s\n' "$mutant_gate" >&2; fail=$((fail+1))
fi

# ── Row 3: exclude-mode DIRECTION-SAFETY quarantines divergent copy ─────────
PLUGIN_SYNC="${PLUGIN_DIR}/scripts/leadv2-plugin-sync.sh"
QUARANTINE_ROOT="$tmp/quarantine"

# Build an isolated canonical tree and user home
canon="$tmp/canon"
mkdir -p "$canon/plugins/leadv2"
mkdir -p "$canon/plugins/leadv2/scripts"
printf '#!/usr/bin/env bash\necho "original v1"\n' > "$canon/plugins/leadv2/scripts/leadv2-test-target.sh"
(cd "$canon" && git init -q && git config user.email test@example.invalid && git config user.name lane-truth-test && git add -A && git commit -q -m "init")

home="$tmp/home"
user_scripts="$home/.claude/scripts"
mkdir -p "$user_scripts"
printf '#!/usr/bin/env bash\necho "fixed v2 with important change"\n' > "$user_scripts/leadv2-test-target.sh"

# Dry-run: reports block without writing quarantine
env -u LEADV2_PROJECT_ROOT -u LEADV2_STATE_ROOT -u PROJECT_ROOT \
  HOME="$home" LEADV2_CANONICAL_ROOT="$canon" LEADV2_QUARANTINE_ROOT="$QUARANTINE_ROOT" \
  bash "$PLUGIN_SYNC" --dry-run 2>"$tmp/sync-stderr.log" || true
if grep -q 'would-quarantine' "$tmp/sync-stderr.log"; then
  printf '[TEST] PASS: Row 3: dry-run reports block without writing quarantine\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Row 3: dry-run must report would-quarantine\n' >&2; fail=$((fail+1))
fi
# Dry-run must not write any quarantine
if [[ -z "$(find "$QUARANTINE_ROOT" -type f -print -quit 2>/dev/null)" ]]; then
  printf '[TEST] PASS: Row 3: dry-run writes no quarantine files\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: Row 3: dry-run must not write quarantine\n' >&2; fail=$((fail+1))
fi

# Real run: quarantine copy created with the fix
env -u LEADV2_PROJECT_ROOT -u LEADV2_STATE_ROOT -u PROJECT_ROOT \
  HOME="$home" LEADV2_CANONICAL_ROOT="$canon" LEADV2_QUARANTINE_ROOT="$QUARANTINE_ROOT" \
  bash "$PLUGIN_SYNC" 2>"$tmp/sync-stderr-real.log" || true

quarantined="$(find "$QUARANTINE_ROOT" -name 'leadv2-test-target.sh' -type f 2>/dev/null | head -1)"
if [[ -n "$quarantined" ]]; then
  printf '[TEST] PASS: Row 3: divergent user-script quarantined in exclude mode\n'; pass=$((pass+1))
  q_content="$(cat "$quarantined")"
  check "$q_content" 'fixed v2' 'Row 3: quarantined copy preserves the un-landed fix'
else
  printf '[TEST] FAIL: Row 3: no quarantine copy created in exclude mode\n' >&2
  cat "$tmp/sync-stderr-real.log" >&2
  fail=$((fail+1))
fi

# ── Row 3 CONVERGENCE: 3 syncs of the same divergent copy = 1 quarantine file
qcount_before="$(find "$QUARANTINE_ROOT" -name 'leadv2-test-target.sh' -type f 2>/dev/null | wc -l | tr -d ' ')"
for _ in 1 2 3; do
  env -u LEADV2_PROJECT_ROOT -u LEADV2_STATE_ROOT -u PROJECT_ROOT \
    HOME="$home" LEADV2_CANONICAL_ROOT="$canon" LEADV2_QUARANTINE_ROOT="$QUARANTINE_ROOT" \
    bash "$PLUGIN_SYNC" 2>/dev/null || true
done
qcount_after="$(find "$QUARANTINE_ROOT" -name 'leadv2-test-target.sh' -type f 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$qcount_after" -eq "$qcount_before" ]]; then
  printf '[TEST] PASS: Row 3 convergence: 3 additional syncs produced %s quarantine files (no duplicates)\n' "$qcount_after"; pass=$((pass+1))
else
  printf '[TEST] FAIL: Row 3 convergence: expected %s quarantine files after re-syncs, got %s\n' "$qcount_before" "$qcount_after" >&2; fail=$((fail+1))
fi

# ── Row 3 CONVERGENCE mutation: a CHANGED divergent copy does get a new quarantine
printf '#!/usr/bin/env bash\necho "fixed v3 entirely different"\n' > "$user_scripts/leadv2-test-target.sh"
env -u LEADV2_PROJECT_ROOT -u LEADV2_STATE_ROOT -u PROJECT_ROOT \
  HOME="$home" LEADV2_CANONICAL_ROOT="$canon" LEADV2_QUARANTINE_ROOT="$QUARANTINE_ROOT" \
  bash "$PLUGIN_SYNC" 2>/dev/null || true
qcount_v3="$(find "$QUARANTINE_ROOT" -name 'leadv2-test-target.sh' -type f 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$qcount_v3" -gt "$qcount_after" ]]; then
  printf '[TEST] PASS: Row 3 convergence: changed content produces new quarantine (%s → %s)\n' "$qcount_after" "$qcount_v3"; pass=$((pass+1))
else
  printf '[TEST] FAIL: Row 3 convergence: changed content should produce new quarantine, still %s\n' "$qcount_v3" >&2; fail=$((fail+1))
fi

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n[LANE-TRUTH-BATCH-01] pass=%d fail=%d\n' "$pass" "$fail"
(( fail == 0 ))
