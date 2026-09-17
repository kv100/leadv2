#!/usr/bin/env bash
# MUT-HEAD disk-look probe for LANE-TRUTH-BATCH-01-MUTATION-GATE-HEAD-STILL-RED-01.
# Replicates the suite's run_dispatch_liveness_gate scenario VERBATIM (function
# is sed-extracted from the suite file, not re-implemented), then lists what is
# actually on disk at the paths the gate computes: handoff tree, registry rows.
set -uo pipefail
SCRIPT_DIR="/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/66f31ff9aca5/plugins/leadv2/scripts"
REAL_PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/muthead-probe.XXXXXX")"
PLUGIN_DIR="$tmp/plugin"; mkdir -p "$PLUGIN_DIR"
cp -a "$REAL_PLUGIN_DIR/scripts" "$PLUGIN_DIR/"
cp -a "$REAL_PLUGIN_DIR/workflows" "$PLUGIN_DIR/"
cp -a "$REAL_PLUGIN_DIR/config" "$PLUGIN_DIR/"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
export LEADV2_BURN_GOVERNOR=0
LIVENESS="$PLUGIN_DIR/scripts/leadv2-lane-liveness.sh"
DISPATCH="$PLUGIN_DIR/scripts/leadv2-dispatch-code.sh"

eval "$(sed -n '/^run_dispatch_liveness_gate()/,/^}/p' "$SCRIPT_DIR/tests/test-lane-truth-batch-01.sh")"
[[ "$(type -t run_dispatch_liveness_gate)" == "function" ]] || { echo "FATAL: gate fn not extracted" >&2; exit 91; }

echo "=== gate_root: $tmp/dispatch-gate-MUT-HEAD ==="
echo
echo "=== liveness JSON for lane MUT-HEAD (gate fn output, verbatim fixture) ==="
gate_out="$(run_dispatch_liveness_gate "$DISPATCH" 'MUT-HEAD')"
printf '%s\n' "$gate_out"
echo
echo "=== disk: full handoff tree under gate_root ==="
find "$tmp/dispatch-gate-MUT-HEAD/docs/handoff" -mindepth 1 2>/dev/null | sort
echo
sig8="$(printf '%s' 'behavioral lane liveness gate' | sha256sum | cut -c1-8)"
echo "=== disk: stamped stream dir dispatch-$sig8 ==="
ls -la "$tmp/dispatch-gate-MUT-HEAD/docs/handoff/dispatch-$sig8/" 2>/dev/null
echo
echo "=== registry rows: every active.yaml under gate_root ==="
find "$tmp/dispatch-gate-MUT-HEAD" -name 'active.yaml' | sort | while IFS= read -r f; do
  echo "--- $f"
  cat "$f"
done
echo
echo "PROBE_ROOT=$tmp"
