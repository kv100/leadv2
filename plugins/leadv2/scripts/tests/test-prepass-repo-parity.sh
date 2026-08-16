#!/usr/bin/env bash
# PLUGIN-PREPASS-HANGS-01: regression harness for the two-population finding.
#
# Population A (design landed): c5daf449, 100a892d, 63e9aaff all show
# `architect_prepass status=ran` in their journal, then die LATER at
# `dispatch_terminal ... cause=e2e_regression`. The mission's premise --
# "every lane dies at architect_prepass with rc=124" -- is false for these.
#
# Population B (real rc=124): cd219000 and 85d0e45e (follow-up dispatches
# resumed into the SAME two worktrees) show `architect_prepass status=failed
# reason=timeout rc=124`. Their stream (architect.stream.jsonl) shows the
# architect issuing `timeout 900|2400 bash .../run-core-offline.sh` -- a
# Bash call whose OWN timeout exceeds ARCHITECT_PREPASS_TIMEOUT_SEC (420s
# default, leadv2-dispatch-code.sh:409). That is wall-clock spent on real
# work (a full offline regression suite the architect chose to run as part
# of its investigation), not a stall -- confirmed structurally below with a
# stubbed architect binary, no live Claude call, in the same style as
# test-dispatch-architect-prepass-orphan-timeout.sh.
#
# This file is a REGRESSION GUARD for the finding in
# docs/missions/PLUGIN-PREPASS-HANGS-01.report.md, not a live-repro tool --
# it does not spawn `claude`. It has two checks:
#   1. structural: a stub architect that runs longer than the timeout budget
#      produces status=failed reason=timeout rc=124, proving the mechanism
#      (long legitimate work > budget => rc=124), same as the real lanes.
#   2. fixture: the recorded journal lines for the five named lanes, if still
#      present on disk, must match the population split this report claims.
#      Skips (not fails) when the historical journals have been pruned --
#      journals are not permanent, the structural check is the durable part.
set -uo pipefail

ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
FAILS=0

# ---------------------------------------------------------------------------
# Check 1 -- structural: legitimate-work-exceeds-budget produces rc=124,
# exactly like cd219000/85d0e45e, without touching the real dispatch state.
# ---------------------------------------------------------------------------
REPO="$ROOT/repo"; mkdir -p "$REPO/.claude/ref"
(cd "$REPO" && git init -q && git config user.email t@e.com && git config user.name t && : > seed && git add seed && git commit -qm seed)
printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' > "$REPO/.claude/ref/leadv2-routing.yaml"

WORKER="$ROOT/worker"; ARCH_SLOW="$ROOT/architect_slow"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$$"\n' > "$WORKER"
# Models a real architect that, mid-mission, shells out to a bounded but
# long-running offline suite (run-core-offline.sh stand-in): sleeps 6s inside
# a `timeout 6 ...`-shaped wrapper while the prepass budget is 2s.
cat > "$ARCH_SLOW" <<'EOF'
#!/usr/bin/env bash
timeout 6 sleep 6
echo "would still be validating when the 2s prepass budget expires"
EOF
chmod +x "$WORKER" "$ARCH_SLOW"

DISPATCH="$(cd "$(dirname "$0")/.." && pwd)/leadv2-dispatch-code.sh"
LEADV2_DISPATCH_ARCHITECT_GATE=1 \
CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" LEADV2_DISPATCH_CACHE_DIR="$ROOT/cache" \
LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" LEADV2_DISPATCH_ARCHITECT_BIN="$ARCH_SLOW" \
LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=2 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
  bash "$DISPATCH" 'test PLUGIN-PREPASS-HANGS-01 parity: slow-but-legitimate architect work' \
  --kind product --protected --writes "a.txt" >"$ROOT/out.log" 2>&1

if grep -q 'architect_prepass .*status=failed reason=timeout rc=124' "$ROOT/out.log"; then
  echo "[ok] check1: legitimate work exceeding ARCHITECT_PREPASS_TIMEOUT_SEC reproduces rc=124 (matches cd219000/85d0e45e mechanism)"
else
  echo "[FAIL] check1: expected 'architect_prepass status=failed reason=timeout rc=124' in dispatch output"
  tail -40 "$ROOT/out.log"
  FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# Check 2 -- fixture: recorded journal lines for the five named lanes, if
# still on disk, must match the two-population split.
# ---------------------------------------------------------------------------
JDIR="$(cd "$(dirname "$0")/../../../.." && pwd)/docs/leadv2/tasks"
POP_A="c5daf449 100a892d 63e9aaff"
POP_B="cd219000 85d0e45e"

if [[ ! -d "$JDIR" ]]; then
  echo "[skip] check2: $JDIR not found (not run from a leadv2 checkout) -- structural check1 is the durable guard"
else
  any_present=0
  for t in $POP_A; do
    j="$JDIR/dispatch-$t/journal.md"
    [[ -f "$j" ]] || continue
    any_present=1
    if ! grep -q "architect_prepass task=$t status=ran" "$j"; then
      echo "[FAIL] check2: dispatch-$t journal no longer shows architect_prepass status=ran (population-A claim regressed)"
      FAILS=$((FAILS + 1))
    fi
    if grep -q "dispatch_terminal task=$t .*cause=architect_prepass\|dispatch_terminal task=$t .*rc=124" "$j"; then
      echo "[FAIL] check2: dispatch-$t journal now shows a prepass-attributed terminal cause -- premise-check in the report is stale"
      FAILS=$((FAILS + 1))
    fi
  done
  for t in $POP_B; do
    j="$JDIR/dispatch-$t/journal.md"
    [[ -f "$j" ]] || continue
    any_present=1
    if ! grep -q "architect_prepass task=$t status=failed reason=timeout rc=124" "$j"; then
      echo "[FAIL] check2: dispatch-$t journal no longer shows a real rc=124 timeout (population-B claim regressed)"
      FAILS=$((FAILS + 1))
    fi
  done
  if [[ "$any_present" == "0" ]]; then
    echo "[skip] check2: none of the five historical journals are present on disk (pruned) -- structural check1 is the durable guard"
  else
    echo "[ok] check2: historical journal fixtures match the population split (where present)"
  fi
fi

if [[ "$FAILS" -gt 0 ]]; then
  echo "=== $FAILS check(s) FAILED ==="
  exit 1
fi
echo "=== all checks passed ==="
