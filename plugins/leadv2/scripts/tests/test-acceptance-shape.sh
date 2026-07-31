#!/usr/bin/env bash
# tests/test-acceptance-shape.sh — RED-FIRST-GATE-01 DoD test for leadv2-acceptance-shape.sh.
#
# Exercises R2: `validate` refuses a missing block, a non-enum surface, and
# internal-contract phrasing in `observable`; accepts a well-formed block.
# `assert-precedence` refuses an authored_at written AFTER the diff's own
# files already existed, and accepts one written before.
#
# This file is itself new — pre-fix (before leadv2-acceptance-shape.sh exists)
# every assertion that shells out to it fails with "No such file or
# directory"; that IS this file's own red-first proof.
#
# Run: bash scripts/tests/test-acceptance-shape.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${SCRIPT_DIR}/leadv2-acceptance-shape.sh"
source "${SCRIPT_DIR}/leadv2-temp.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$(( PASS + 1 )); log "PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); log "FAIL: $1"; }

if bash -n "${BIN}" 2>/dev/null; then pass "bash -n leadv2-acceptance-shape.sh"; else fail "bash -n leadv2-acceptance-shape.sh"; fi

T="$(lv2_mktemp_dir as-fixtures)"

# ── validate: well-formed block ──
cat > "${T}/good.yaml" <<'EOF'
acceptance:
  authored_at: 2026-07-30T21:48:00Z
  surface: rendered_line
  observable: "supervise status line shows exactly the 5 live lanes, full labels, no trailing segment"
  probe_cmd: "leadv2-lane-liveness.sh render"
  regression_only: []
EOF
if bash "${BIN}" validate "${T}/good.yaml" >/dev/null 2>&1; then
  pass "validate: well-formed acceptance block accepted"
else
  fail "validate: well-formed acceptance block refused"
fi

# ── validate: block missing entirely ──
cat > "${T}/missing.yaml" <<'EOF'
some_other_field: yes
EOF
if bash "${BIN}" validate "${T}/missing.yaml" >/dev/null 2>&1; then
  fail "validate: missing acceptance block should refuse"
else
  pass "validate: missing acceptance block refused"
fi

# ── validate: surface not in the enum ──
cat > "${T}/bad_surface.yaml" <<'EOF'
acceptance:
  authored_at: 2026-07-30T21:48:00Z
  surface: some_made_up_surface
  observable: "the status line shows 5 lanes"
EOF
if bash "${BIN}" validate "${T}/bad_surface.yaml" >/dev/null 2>&1; then
  fail "validate: bad surface enum should refuse"
else
  pass "validate: bad surface enum refused"
fi

# ── validate: internal-contract phrasing in observable (the R2 root cause) ──
cat > "${T}/internal_contract.yaml" <<'EOF'
acceptance:
  authored_at: 2026-07-30T21:48:00Z
  surface: rendered_line
  observable: "the render function returns the correct exit code"
EOF
if bash "${BIN}" validate "${T}/internal_contract.yaml" >/dev/null 2>&1; then
  fail "validate: internal-contract phrasing should refuse"
else
  pass "validate: internal-contract phrasing refused"
fi

# ── validate: authored_at not parseable ──
cat > "${T}/bad_date.yaml" <<'EOF'
acceptance:
  authored_at: "not a date"
  surface: rendered_line
  observable: "the status line shows 5 lanes"
EOF
if bash "${BIN}" validate "${T}/bad_date.yaml" >/dev/null 2>&1; then
  fail "validate: unparseable authored_at should refuse"
else
  pass "validate: unparseable authored_at refused"
fi

# ── assert-precedence: authored_at before LANE_WRITES files exist -> ok ──
FAKE_ROOT="$(lv2_mktemp_dir as-fakeroot)"
mkdir -p "${FAKE_ROOT}/docs/handoff/AS-PRE-1" "${FAKE_ROOT}/some/dir"
cat > "${FAKE_ROOT}/docs/handoff/AS-PRE-1/context.yaml" <<'EOF'
lane_writes:
  - some/dir/target.sh
acceptance:
  authored_at: 2020-01-01T00:00:00Z
  surface: file_artifact
  observable: "target.sh exists on disk with the new flag wired"
EOF
echo "content" > "${FAKE_ROOT}/some/dir/target.sh"
touch -t 202601010000 "${FAKE_ROOT}/some/dir/target.sh"
if LEADV2_PROJECT_ROOT="${FAKE_ROOT}" bash "${BIN}" assert-precedence --task-id AS-PRE-1 >/dev/null 2>&1; then
  pass "assert-precedence: authored before LANE_WRITES mtime accepted"
else
  fail "assert-precedence: authored-before case wrongly refused"
fi

# ── assert-precedence: authored_at AFTER LANE_WRITES files exist -> refuse ──
cat > "${FAKE_ROOT}/docs/handoff/AS-PRE-1/context.yaml" <<'EOF'
lane_writes:
  - some/dir/target.sh
acceptance:
  authored_at: 2026-12-01T00:00:00Z
  surface: file_artifact
  observable: "target.sh exists on disk with the new flag wired"
EOF
if LEADV2_PROJECT_ROOT="${FAKE_ROOT}" bash "${BIN}" assert-precedence --task-id AS-PRE-1 >/dev/null 2>&1; then
  fail "assert-precedence: authored-after case should refuse"
else
  pass "assert-precedence: authored after LANE_WRITES mtime refused"
fi

log ""
log "=== ${PASS} passed, ${FAIL} failed ==="
[[ "$FAIL" -eq 0 ]]
