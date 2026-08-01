#!/usr/bin/env bash
# scripts/tests/test-fanout-lease-dispatchable.sh
# S4-DEAD-LANE-REQUEUE-01 (D-1/D-3): offline test for the shared
# `_is_dispatchable()` predicate in leadv2-fanout.sh (canonical, plugin-
# owned -- this is the file the plugin actually runs), exercised via BOTH
# entry points the design calls out: the bare candidate scan, and the
# explicit `--task <id>` manual re-dispatch path. leadv2-fanout.sh has a
# real report/dry-run mode (--dry-run), so no launch-suppression flag is
# added just for this test.
#
# Drives the real script against a synthetic PROJECT_ROOT holding a
# hand-written docs/tasks.yaml + docs/leadv2/active.yaml, and asserts on the
# rendered report rows. --dry-run exits before any launch/dispatch-ledger
# write, but per the architect prepass's convention, never run this suite
# in parallel with tests/unit/test-work-item-requeue.sh in the same tree.
#
# Run: bash scripts/tests/test-fanout-lease-dispatchable.sh (from any repo
# that symlinks this plugin in — e.g. persona-engine's
# .claude/scripts/tests/test-fanout-lease-dispatchable.sh)

set -euo pipefail
_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FANOUT_SCRIPT="${_TEST_DIR}/../leadv2-fanout.sh"
[[ -x "${FANOUT_SCRIPT}" ]] || { echo "FATAL: ${FANOUT_SCRIPT} not found/executable" >&2; exit 1; }

FAILURES=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAILURES=$((FAILURES + 1)); }
assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    pass "${name}"
  else
    fail "${name}" "expected to find '${needle}'"
  fi
}
assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    pass "${name}"
  else
    fail "${name}" "did NOT expect to find '${needle}'"
  fi
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pe-fanout-dispatchable.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

mkdir -p "${TMP_ROOT}/docs/leadv2"
cat > "${TMP_ROOT}/docs/tasks.yaml" <<'EOF'
# GENERATED FILE — DO NOT EDIT BY HAND.
total_open: 3
tasks:
- id: aaaaaaaaaaaa
  node_id: n1
  probe_id: p1
  source: human
  status: pending
  priority: 5
  group_priority: 5
  group_key: null
  intent: "DEAD-LANE-TEST-01: expired lease, should become dispatchable"
  acceptance_probe_id: null
  needs_acceptance_probe: false
  external_id: null
  occurrence_count: 1
  first_failed_at: null
  last_failed_at: null
  recovered_at: null
  claim_lease_until: "2020-01-01T00:00:00+00:00"
  claimed_by: dead-lane-1
  dispatch_attempts: 0
  requeue_giveup_reason: null
- id: bbbbbbbbbbbb
  node_id: n2
  probe_id: p2
  source: human
  status: pending
  priority: 5
  group_priority: 5
  group_key: null
  intent: "GIVEUP-TEST-01: attempts exhausted, must stay a skip"
  acceptance_probe_id: null
  needs_acceptance_probe: false
  external_id: null
  occurrence_count: 1
  first_failed_at: null
  last_failed_at: null
  recovered_at: null
  claim_lease_until: "2020-01-01T00:00:00+00:00"
  claimed_by: dead-lane-2
  dispatch_attempts: 2
  requeue_giveup_reason: null
- id: cccccccccccc
  node_id: n3
  probe_id: p3
  source: human
  status: pending
  priority: 5
  group_priority: 5
  group_key: null
  intent: "LIVE-CLAIM-TEST-01: pending but lease not yet expired, must stay hidden"
  acceptance_probe_id: null
  needs_acceptance_probe: false
  external_id: null
  occurrence_count: 1
  first_failed_at: null
  last_failed_at: null
  recovered_at: null
  claim_lease_until: "2099-01-01T00:00:00+00:00"
  claimed_by: live-lane-3
  dispatch_attempts: 0
  requeue_giveup_reason: null
EOF
cat > "${TMP_ROOT}/docs/leadv2/active.yaml" <<'EOF'
meta:
  hard_limit: 10
  heavy_max: 5
sessions: []
EOF

# ---------------------------------------------------------------------------
# Bare candidate scan
# ---------------------------------------------------------------------------
SCAN_OUT="$(LEADV2_PROJECT_ROOT="${TMP_ROOT}" bash "${FANOUT_SCRIPT}" --dry-run --n 5 2>&1)"

assert_contains "scan: expired-lease row is selected for LAUNCH" \
  "${SCAN_OUT}" "LAUNCH \`DEAD-LANE-TEST-01"

assert_contains "scan: give-up row appears as a skip with the exhausted-attempts reason" \
  "${SCAN_OUT}" "requeue give-up (2/2)"
assert_not_contains "scan: give-up row is NOT selected for LAUNCH" \
  "${SCAN_OUT}" "LAUNCH \`GIVEUP-TEST-01"

assert_not_contains "scan: a pending row with an UNEXPIRED lease never appears at all (R-7)" \
  "${SCAN_OUT}" "LIVE-CLAIM-TEST-01"

# ---------------------------------------------------------------------------
# Explicit --task re-dispatch path (D-1's manual escape hatch)
# ---------------------------------------------------------------------------
EXPLICIT_LAUNCH_OUT="$(LEADV2_PROJECT_ROOT="${TMP_ROOT}" bash "${FANOUT_SCRIPT}" --dry-run --tasks aaaaaaaaaaaa 2>&1)"
assert_contains "explicit --task: expired-lease row launches by name" \
  "${EXPLICIT_LAUNCH_OUT}" "LAUNCH \`DEAD-LANE-TEST-01"
assert_not_contains "explicit --task: does NOT show the old undifferentiated 'not queued' skip" \
  "${EXPLICIT_LAUNCH_OUT}" "not queued (status=pending)"

EXPLICIT_GIVEUP_OUT="$(LEADV2_PROJECT_ROOT="${TMP_ROOT}" bash "${FANOUT_SCRIPT}" --dry-run --tasks bbbbbbbbbbbb 2>&1)"
assert_contains "explicit --task: give-up row is refused by name with the real reason" \
  "${EXPLICIT_GIVEUP_OUT}" "requeue give-up (2/2)"

EXPLICIT_LIVE_OUT="$(LEADV2_PROJECT_ROOT="${TMP_ROOT}" bash "${FANOUT_SCRIPT}" --dry-run --tasks cccccccccccc 2>&1)"
assert_contains "explicit --task: live (unexpired-lease) row is refused, names the lease timestamp" \
  "${EXPLICIT_LIVE_OUT}" "lease still held until"

echo ""
echo "─── Results ───"
if [[ "${FAILURES}" -eq 0 ]]; then
  echo "ALL PASSED"
  exit 0
else
  echo "${FAILURES} FAILURE(S)"
  exit 1
fi
