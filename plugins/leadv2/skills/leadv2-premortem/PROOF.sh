#!/usr/bin/env bash
set -euo pipefail
# proof-of: leadv2-premortem returns skip_recommended (exit 2) for high-risk change-sets and proceed (exit 0) for safe ones, proving the heuristic table is two-sided.
#
# Scope: exercises the zero-LLM bash+python heuristic. Two-sided: cannot pass
# by always emitting one verdict.

source "$LEADV2_PLUGIN_ROOT/scripts/leadv2-proof-lib.sh"

TMP=$(proof_tmpdir)
PREMORTEM_SH="$LEADV2_PLUGIN_ROOT/scripts/leadv2-premortem.sh"

FIXTURE="$TMP/projroot"

# ── High-risk fixture: critical footprint + blast radius + negative memory ──
RISK_DIR="$FIXTURE/docs/handoff/risk-task"
mkdir -p "$RISK_DIR"

cat > "$RISK_DIR/context.yaml" <<'EOF'
task:
  class: Heavy
graph_footprint:
  risk_score: critical
  impacted_callers_count: 30
  change_kind: cross_service
decisions:
  - d1
  - d2
  - d3
  - d4
  - d5
  - d6
off_limits:
  - some_file
EOF

cat > "$RISK_DIR/negative-memory.yaml" <<'EOF'
matches:
  - id: nm-001
    pattern: something_risky
EOF

cat > "$RISK_DIR/prior-art.yaml" <<'EOF'
- outcome: rollback
EOF

# ── Safe fixture: light class, low risk, all-success prior art ──────────────
SAFE_DIR="$FIXTURE/docs/handoff/safe-task"
mkdir -p "$SAFE_DIR"

cat > "$SAFE_DIR/context.yaml" <<'EOF'
task:
  class: Light
graph_footprint:
  risk_score: low
  impacted_callers_count: 0
  change_kind: additive
decisions: []
off_limits: []
EOF

cat > "$SAFE_DIR/prior-art.yaml" <<'EOF'
- outcome: success
- outcome: success
- outcome: success
EOF

# ── Run 1: high-risk → skip_recommended (exit 2) ────────────────────────────
rc=0
bash "$PREMORTEM_SH" \
  --task-id risk-task \
  --phase build \
  --project-root "$FIXTURE" \
  >/dev/null 2>&1 || rc=$?

assert_eq 2 "$rc" "high-risk change-set → skip_recommended (exit 2)"

# ── Run 2: safe → proceed (exit 0) ──────────────────────────────────────────
rc=0
bash "$PREMORTEM_SH" \
  --task-id safe-task \
  --phase build \
  --project-root "$FIXTURE" \
  >/dev/null 2>&1 || rc=$?

assert_eq 0 "$rc" "safe change-set → proceed (exit 0)"

# ── Verify output files exist with correct verdicts ─────────────────────────
assert_file_contains "$RISK_DIR/premortem-build.yaml" "skip_recommended" "risk-task output has skip_recommended"
assert_file_contains "$SAFE_DIR/premortem-build.yaml" "verdict: proceed" "safe-task output has proceed"

echo "[PROOF] leadv2-premortem: all assertions passed"
