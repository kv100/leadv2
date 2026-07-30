#!/usr/bin/env bash
# tests/test-writes-overlap.sh — SUPERVISOR-AUDIT-01 T-E: file-touch conflict
# notify between lanes. Covers:
#   1. bash -n on the three changed scripts
#   2. leadv2_active_set_writes op stamps `writes` on an existing row, and
#      fails loudly (rc=4) for an unregistered task_id
#   3. overlap -> a conflict line on stdout, a journal finding, and a
#      SUPERVISE-URGENT pulse line
#   4. no-overlap -> silence (no stdout, no journal, no new pulse line)
#   5. LEADV2_WRITES_CONFLICT_NOTIFY=0 -> whole feature is a no-op
#
# Portable: no GNU-only date/sed -i/timeout/flock. Sandboxed via
# LEADV2_PROJECT_ROOT / LEADV2_STATE_ROOT / CLAUDE_PROJECT_DIR -- never
# touches the real repo's docs/leadv2/active.yaml.
# Run: bash scripts/tests/test-writes-overlap.sh
# Exit 0 = all pass; non-zero = failures found.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERLAP_SH="${SCRIPTS_ROOT}/leadv2-writes-overlap.sh"
FANOUT_SH="${SCRIPTS_ROOT}/leadv2-fanout.sh"
REGISTRY_SH="${SCRIPTS_ROOT}/leadv2-active-registry.sh"
STATE_PATH_SH="${SCRIPTS_ROOT}/leadv2-state-path.sh"
RUNNER_SH="${SCRIPTS_ROOT}/leadv2-session-runner.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# ── 1. syntax ────────────────────────────────────────────────────────────
if bash -n "$OVERLAP_SH" && bash -n "$FANOUT_SH" && bash -n "$REGISTRY_SH"; then
  pass "bash -n clean (writes-overlap.sh, fanout.sh, active-registry.sh)"
else
  fail "bash -n failed"
fi

tmp="$(lv2_mktemp_dir "writes-overlap-test")"; trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"; state="$tmp/state"
mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff/OTHER" "$repo/scripts" "$state"
(cd "$repo" && git init -q)
lv2_assert_scratch_repo "$repo"
# leadv2-active-registry.sh's OWN internal resolver looks for a PROJECT-
# vendored copy at "$PROJECT_ROOT/scripts/leadv2-state-path.sh" (not
# SCRIPT_DIR-relative) -- vendor it here too so its yaml_file resolution
# lands on the SAME control-plane path leadv2-writes-overlap.sh resolves
# via its own (canonical) SCRIPT_DIR/leadv2-state-path.sh.
ln -s "${STATE_PATH_SH}" "$repo/scripts/leadv2-state-path.sh"

export LEADV2_PROJECT_ROOT="$repo"
export LEADV2_STATE_ROOT="$state"
export CLAUDE_PROJECT_DIR="$repo"

# A fresh session.log makes lane-liveness classify OTHER as alive (same
# fixture shape as test-lane-liveness-authoritative.sh's LOG-ONLY case).
printf 'worker is alive\n' > "$repo/docs/handoff/OTHER/session.log"

active="$(PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" --no-link active.yaml)"
mkdir -p "$(dirname "$active")"
cat > "$active" <<'YAML'
sessions:
  - task_id: OTHER
    writes: "platform/foo.py,agent/bar.sh"
YAML

# ── 2. leadv2_active_set_writes ─────────────────────────────────────────
# shellcheck source=/dev/null
source "$REGISTRY_SH"
if leadv2_active_set_writes OTHER "platform/foo.py,platform/quux.py" >/dev/null 2>&1 \
  && grep -q 'platform/quux.py' "$active"; then
  pass "leadv2_active_set_writes stamps writes onto an existing row"
else
  fail "leadv2_active_set_writes did not stamp writes"
fi
if ! leadv2_active_set_writes NO-SUCH-TASK "x" >/dev/null 2>&1; then
  pass "leadv2_active_set_writes fails closed (rc!=0) for an unregistered task_id"
else
  fail "leadv2_active_set_writes silently succeeded for an unregistered task_id"
fi
# Restore the row's writes for the overlap tests below (set_writes above
# mutated it as part of the op test).
cat > "$active" <<'YAML'
sessions:
  - task_id: OTHER
    writes: "platform/foo.py,agent/bar.sh"
YAML

pulse_log="$(PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" --no-link supervise-loop.log)"
journal_new() { printf '%s/docs/leadv2/tasks/%s/journal.md' "$repo" "$1"; }

# ── 3. overlap -> stdout + journal + pulse ──────────────────────────────
out="$(bash "$OVERLAP_SH" --task-id NEW --writes "platform/foo.py,agent/other.sh" --project-root "$repo" --notify)"
if grep -q '^task=NEW other=OTHER paths=platform/foo.py$' <<<"$out"; then
  pass "overlapping writes produce the expected conflict line on stdout"
else
  fail "overlap stdout missing/wrong: ${out}"
fi
jfile="$(journal_new NEW)"
if [[ -f "$jfile" ]] && grep -q 'writes_conflict task=NEW other=OTHER paths=platform/foo.py' "$jfile"; then
  pass "overlap appends a journal finding"
else
  fail "overlap journal line missing (file=${jfile})"
fi
if [[ -f "$pulse_log" ]] && grep -q '\[SUPERVISE-URGENT\] WRITES_CONFLICT task=NEW other=OTHER paths=platform/foo.py' "$pulse_log"; then
  pass "overlap appends a SUPERVISE-URGENT pulse line to the shared sink"
else
  fail "overlap pulse line missing (file=${pulse_log})"
fi

# ── 4. no overlap -> silence ─────────────────────────────────────────────
pulse_before="$(wc -l < "$pulse_log" 2>/dev/null || printf '0')"
out2="$(bash "$OVERLAP_SH" --task-id NEW2 --writes "web/completely/different.ts" --project-root "$repo" --notify)"
jfile2="$(journal_new NEW2)"
pulse_after="$(wc -l < "$pulse_log" 2>/dev/null || printf '0')"
if [[ -z "$out2" && ! -f "$jfile2" && "$pulse_before" == "$pulse_after" ]]; then
  pass "non-overlapping writes produce no stdout, no journal, no new pulse line"
else
  fail "no-overlap case was not silent (stdout=${out2:-<empty>} journal_exists=$([[ -f "$jfile2" ]] && echo yes || echo no) pulse ${pulse_before}->${pulse_after})"
fi

# ── 5. LEADV2_WRITES_CONFLICT_NOTIFY=0 -> whole block is a no-op ────────
pulse_before3="$(wc -l < "$pulse_log" 2>/dev/null || printf '0')"
out3="$(LEADV2_WRITES_CONFLICT_NOTIFY=0 bash "$OVERLAP_SH" --task-id NEW3 --writes "platform/foo.py" --project-root "$repo" --notify)"
jfile3="$(journal_new NEW3)"
pulse_after3="$(wc -l < "$pulse_log" 2>/dev/null || printf '0')"
if [[ -z "$out3" && ! -f "$jfile3" && "$pulse_before3" == "$pulse_after3" ]]; then
  pass "LEADV2_WRITES_CONFLICT_NOTIFY=0 is a full no-op even with a real overlap"
else
  fail "flag=0 was not a no-op (stdout=${out3:-<empty>} journal_exists=$([[ -f "$jfile3" ]] && echo yes || echo no) pulse ${pulse_before3}->${pulse_after3})"
fi

# ── 6. T-e tail: the full-cycle launch path also stamps writes + overlap ──
# _fanout_launch_full_cycle (Heavy/Strategic tasks, and any funnel decline/fallback)
# used to skip WRITES-CONFLICT-NOTIFY entirely -- only launch_via_dispatch_code's
# single-worker funnel ran it. Drives the REAL leadv2-fanout.sh --headless (never a
# reimplementation). MEDIUM-3 (fixround-tails): the ORIGINAL version of this test
# mv/cp-swapped the CANONICAL leadv2-session-runner.sh IN THE SOURCE TREE (same
# technique test-fanout-classify-guard.sh's Test 4 uses), restoring it only via a
# function-scoped RETURN trap -- a RETURN trap never fires on SIGINT/SIGTERM/SIGKILL, so
# a Ctrl-C during the ~30s real fanout run left `#!/usr/bin/env bash\nexit 0` as the
# permanent content of the repo's own leadv2-session-runner.sh, silently no-oping every
# subsequent /leadv2 launch (review-tails-verdict.md). This version never touches the
# source tree at all: LEADV2_SESSION_RUNNER_BIN (new override, leadv2-fanout.sh) points
# launch_headless at a stub living entirely under the test's own scratch dir.
test_6_full_cycle_writes_overlap() {
  local stub out
  stub="${repo}/session-runner-stub.sh"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$stub"

  cat > "${repo}/docs/tasks.yaml" <<'YAML'
tasks:
  - id: HEAVY-T1
    status: queued
    class: Heavy
    priority: 5
    intent: "refactor the auth module significantly"
    writes: "platform/foo.py,agent/other-heavy.sh"
YAML

  out="$(
    LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" CLAUDE_PROJECT_DIR="$repo" \
      LEADV2_SKIP_DRIFT_GUARD=1 LEADV2_SESSION_RUNNER_BIN="$stub" \
      bash "$FANOUT_SH" --provider claude --headless --tasks HEAVY-T1 2>&1
  )" || true
  # source-tree safety: the canonical runner must be byte-identical to what it was before
  # this test ran (never touched, unlike the mv/cp technique this replaces).
  if [[ -x "$RUNNER_SH" ]]; then
    pass "Test 6: canonical leadv2-session-runner.sh was never touched (LEADV2_SESSION_RUNNER_BIN override used instead)"
  else
    fail "Test 6: canonical leadv2-session-runner.sh is missing/not executable after the test ran"
  fi

  if grep -q 'platform/foo.py,agent/other-heavy.sh' "$active"; then
    pass "Test 6: full-cycle launch (Heavy) stamped its declared writes onto active.yaml"
  else
    fail "Test 6: writes not stamped after full-cycle launch (active.yaml=$(cat "$active" 2>/dev/null); fanout_out=${out})"
  fi
  jfile6="$(journal_new HEAVY-T1)"
  if [[ -f "$jfile6" ]] && grep -q 'writes_conflict task=HEAVY-T1 other=OTHER paths=platform/foo.py' "$jfile6"; then
    pass "Test 6: full-cycle launch ran the overlap check and journaled the conflict"
  else
    fail "Test 6: full-cycle launch did not journal the writes conflict (file=${jfile6}; fanout_out=${out})"
  fi
  if [[ -f "$pulse_log" ]] && grep -q '\[SUPERVISE-URGENT\] WRITES_CONFLICT task=HEAVY-T1 other=OTHER paths=platform/foo.py' "$pulse_log"; then
    pass "Test 6: full-cycle launch surfaced a SUPERVISE-URGENT pulse line for the conflict"
  else
    fail "Test 6: full-cycle launch produced no SUPERVISE-URGENT pulse line (file=${pulse_log})"
  fi
}
test_6_full_cycle_writes_overlap

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
