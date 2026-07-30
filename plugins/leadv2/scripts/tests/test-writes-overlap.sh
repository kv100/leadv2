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

printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
