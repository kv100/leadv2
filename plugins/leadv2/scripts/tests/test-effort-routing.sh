#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dispatch-code.sh leadv2-route-arbiter
# EFFORT-IS-NOT-WIRED-01: the route arbiter resolves an `effort` tier (data-
# driven, config/leadv2-routing.yaml router_v2.effort_matrix) alongside the
# arm it already picks, and leadv2-dispatch-code.sh forwards that value onto
# each arm's own launch parameter (or journals the drop for an arm with none).
# Never a live provider, never a real dispatch -- fixture quota/routing data
# and stub launcher binaries throughout, same harness shape as
# test-route-arbiter.sh and test-claim-evidence-gate.sh's C8 case.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
DC="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP" 2>/dev/null || true' EXIT
# `|| true`: the dispatch arms leadv2-lane-pulse-watch.sh (:5243 in
# leadv2-dispatch-code.sh), a deliberately async terminal-state watcher that
# can still be writing pulse/inbox artifacts under "$TMP" when this suite
# exits. Under `set -e` a racing rm fails the EXIT trap and turns a 9/9-green
# run into rc=1 (measured 2026-08-31). A stale TMP dir is acceptable litter;
# a false red is not.
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

# ── Arbiter-level fixture harness (identical shape to test-route-arbiter.sh) ──
cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"
quota(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
run(){ # <quota-json> <free-rc> <descriptor-json> [routing-yaml]
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="${4:-$ROUTING}" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-$$-$RANDOM" \
  ROUTE_TEST_QUOTA="$1" ROUTE_TEST_FREE_RC="${2:-0}" bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$3"
}

# (1) Acceptance #1: adversarial-review task resolves to the top tier.
out="$(run "$(quota 1 1 1)" 0 '{"kind":"review","size":"standard"}')"
if [[ "$out" == *' effort=high '*'reason=cheapest_capable'* || "$out" == *' effort=high reason='* ]]; then
  pass 'adversarial-review kind resolves effort=high'
else
  fail "review output=$out"
fi

# (2) Acceptance #2: mechanical/census task resolves to the bottom tier.
out="$(run "$(quota 1 1 1)" 0 '{"kind":"docs","size":"standard"}')"
if [[ "$out" == *' effort=low '* || "$out" == *' effort=low reason='* ]]; then
  pass 'mechanical/docs kind resolves effort=low'
else
  fail "docs output=$out"
fi

# (3) Acceptance #3: an ordinary build resolves to the middle tier. glm-flash
# (cost 0.4, tags cheap/mechanical) is only capable at size=standard, so pin
# size=heavy to land on a plain bulk/background cell (glm) with no
# mechanical/adversarial/safety/plan/protected tag -- the effort_matrix
# default row.
out="$(run "$(quota 1 1 1)" 0 '{"kind":"code","size":"heavy"}')"
if [[ "$out" == *' effort=medium '* || "$out" == *' effort=medium reason='* ]]; then
  pass 'ordinary heavy code build resolves effort=medium'
else
  fail "heavy-code output=$out"
fi

# (6) Acceptance #6 (anti-hardcode): adding a new effort_matrix rule to a
# ROUTING YAML changes the outcome with NO script edit. A fixture copy of the
# real routing.yaml, with one extra row inserted ahead of the default row
# that forces every `code` kind to `high`, must flip case (3)'s medium -> high
# using the SAME arbiter script, unmodified.
FIXTURE_YAML="$TMP/routing-extra-rule.yaml"
python3 - "$ROUTING" "$FIXTURE_YAML" <<'PY'
import sys, yaml
src, dst = sys.argv[1], sys.argv[2]
data = yaml.safe_load(open(src))
data['router_v2']['effort_matrix'].insert(0, {'kinds': ['code'], 'effort': 'high'})
yaml.safe_dump(data, open(dst, 'w'))
PY
out="$(run "$(quota 1 1 1)" 0 '{"kind":"code","size":"heavy"}' "$FIXTURE_YAML")"
if [[ "$out" == *' effort=high '* || "$out" == *' effort=high reason='* ]]; then
  pass 'new yaml-only effort_matrix rule flips the outcome (no script edit)'
else
  fail "anti-hardcode output=$out"
fi
# Control: the UNMODIFIED routing.yaml must still resolve medium for the same
# descriptor -- proves the flip above came from the yaml row, not from state
# bleed or a lucky cost tie.
out="$(run "$(quota 1 1 1)" 0 '{"kind":"code","size":"heavy"}')"
if [[ "$out" == *' effort=medium '* || "$out" == *' effort=medium reason='* ]]; then
  pass 'unmodified routing.yaml still resolves medium (control for the anti-hardcode case)'
else
  fail "anti-hardcode control output=$out"
fi

# ── Dispatch-level: resolved effort reaches the arm's OWN launch parameter ──
# Full dispatch run (no --no-spawn) through stub launcher binaries that record
# their own argv, with the arbiter pointed at the SAME fixture quota/routing
# seam as above so the arm+effort pick is deterministic and never touches a
# live provider.
mk_repo(){
  local repo="$1"
  mkdir -p "$repo"
  ( cd "$repo" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed ) >/dev/null 2>&1
}

dispatch_env(){ # <repo> <cache-dir> -> prints nothing; caller exports around bash "$DC"
  :
}

# (4a) codex arm: --tier and --effort are two DIFFERENT flags on the SAME
# launch line -- assert both are present and effort carries the arbiter's
# resolved value, never the tier's own silent default.
REPO="$TMP/repo-codex"; mk_repo "$REPO"
CODEX_STUB="$TMP/codex-stub.sh"; CODEX_ARGV="$TMP/codex-argv.txt"
cat > "$CODEX_STUB" <<SH
#!/usr/bin/env bash
# Only the 'task' launch call is the assertion target -- post-spawn liveness/
# early-verdict polling also calls this stub with 'status'/'log', which must
# not clobber the recorded launch argv.
case "\${1:-}" in
  task) printf '%s\n' "\$*" > "$CODEX_ARGV"; printf 'task-abc123-def456\n'; exit 0 ;;
  status) exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$CODEX_STUB"
(
  cd "$REPO"
  CLAUDE_PROJECT_ROOT="$REPO" PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" \
  LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-codex" LEADV2_STATE_BASE="$TMP/state-codex" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_DISPATCH_CODEX_BIN="$CODEX_STUB" \
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-arb-codex" \
  ROUTE_TEST_QUOTA="$(quota 1 1 1)" ROUTE_TEST_FREE_RC=1 \
  timeout 60 bash "$DC" 'codex effort wiring probe' --kind review --writes src/x.py >"$TMP/codex-dispatch.out" 2>&1 || true
)
if [[ -f "$CODEX_ARGV" ]] && grep -q -- '--tier' "$CODEX_ARGV" && grep -q -- '--effort high' "$CODEX_ARGV"; then
  pass 'codex arm receives --effort high in its own launch args (distinct from --tier)'
else
  fail "codex argv=$(cat "$CODEX_ARGV" 2>/dev/null || echo '<no argv captured>') dispatch_out=$(tail -5 "$TMP/codex-dispatch.out" 2>/dev/null)"
fi

# (4b) sonnet arm: a DIFFERENT parameter shape (--effort only, no --tier) on
# claude-subsession.sh's own launch line.
REPO2="$TMP/repo-sonnet"; mk_repo "$REPO2"
SONNET_STUB="$TMP/sonnet-stub.sh"; SONNET_ARGV="$TMP/sonnet-argv.txt"
cat > "$SONNET_STUB" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$SONNET_ARGV"
printf 'PID=%s LABEL=t SESSION_ID=t\n' "\$\$"
SH
chmod +x "$SONNET_STUB"
# Force the arbiter's ONLY capable/uncapped arm to sonnet via allowed_arms is
# not a CLI knob on dispatch-code.sh itself, so cap every OTHER provider's
# quota to its ceiling and disable freepool health -- sonnet (protected:true,
# claude bucket) is the sole survivor for a protected kind=code/heavy task.
# PHASE-GATE-IS-INVERTED-01: a heavy code lane must carry plan+gate1 (and
# diverge for Heavy) BEFORE dispatch — the guard no longer accepts a caller's
# bootstrap attestation. Record the lead-authored evidence this suite's
# mission would realistically have.
PHASE_RECORD="${SCRIPTS_DIR}/leadv2-phase-record.sh"
SIG_SONNET="$(printf '%s' 'sonnet effort wiring probe' | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print substr($1, 1, 8)}')"
mkdir -p "$REPO2/docs/handoff/SONNET-$SIG_SONNET"
printf '# sonnet effort wiring probe\n\nfixture plan\n' > "$REPO2/docs/handoff/SONNET-$SIG_SONNET/brief.md"
( cd "$REPO2" && PROJECT_ROOT="$REPO2" LEADV2_PROJECT_ROOT="$REPO2" bash "$PHASE_RECORD" record "$SIG_SONNET" plan \
    --status done --artifact "docs/handoff/SONNET-$SIG_SONNET/brief.md" --owner lead:fixture ) >/dev/null 2>&1
( cd "$REPO2" && PROJECT_ROOT="$REPO2" LEADV2_PROJECT_ROOT="$REPO2" bash "$PHASE_RECORD" record "$SIG_SONNET" gate1 \
    --status done --reason 'fixture Gate 1 decision' --owner lead:fixture ) >/dev/null 2>&1
( cd "$REPO2" && PROJECT_ROOT="$REPO2" LEADV2_PROJECT_ROOT="$REPO2" bash "$PHASE_RECORD" record "$SIG_SONNET" diverge \
    --status n/a --reason 'fixture: no diverge round' --owner lead:fixture ) >/dev/null 2>&1
(
  cd "$REPO2"
  CLAUDE_PROJECT_ROOT="$REPO2" PROJECT_ROOT="$REPO2" LEADV2_PROJECT_ROOT="$REPO2" \
  LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-sonnet" LEADV2_STATE_BASE="$TMP/state-sonnet" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_DISPATCH_SUBSESSION_BIN="$SONNET_STUB" \
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-arb-sonnet" \
  ROUTE_TEST_QUOTA="$(quota 99 99 1)" ROUTE_TEST_FREE_RC=1 \
  timeout 60 bash "$DC" 'sonnet effort wiring probe' --kind code --task-class heavy --protected --writes src/x.py >"$TMP/sonnet-dispatch.out" 2>&1 || true
)
if [[ -f "$SONNET_ARGV" ]] && grep -q -- '--effort' "$SONNET_ARGV" && ! grep -q -- '--tier' "$SONNET_ARGV"; then
  pass 'sonnet arm receives --effort in its own launch args, no --tier flag (different shape than codex)'
else
  fail "sonnet argv=$(cat "$SONNET_ARGV" 2>/dev/null || echo '<no argv captured>') dispatch_out=$(tail -5 "$TMP/sonnet-dispatch.out" 2>/dev/null)"
fi

# (5) Acceptance #5: an arm with no effort control (glm) drops the resolved
# effort with a named log line, and the dispatch does not crash.
REPO3="$TMP/repo-glm"; mk_repo "$REPO3"
GLM_STUB="$TMP/glm-stub.sh"; GLM_RUNS="$TMP/glm-runs"
cat > "$GLM_STUB" <<SH
#!/usr/bin/env bash
RUNS="$GLM_RUNS"
case "\${1:-}" in
  bg) mkdir -p "\$RUNS"; h="stub-\$(date +%s)-\$\$"; printf '%s' "\$h" > "\$RUNS/\$h"; printf '%s\n' "\$h"; exit 0 ;;
  status) [[ -n "\${2:-}" && -f "\$RUNS/\$2" ]] && exit 0; exit 1 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$GLM_STUB"
(
  cd "$REPO3"
  CLAUDE_PROJECT_ROOT="$REPO3" PROJECT_ROOT="$REPO3" LEADV2_PROJECT_ROOT="$REPO3" \
  LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-glm" LEADV2_STATE_BASE="$TMP/state-glm" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_DISPATCH_GLM_BIN="$GLM_STUB" \
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-arb-glm" \
  ROUTE_TEST_QUOTA="$(quota 1 1 1)" ROUTE_TEST_FREE_RC=1 \
  timeout 60 bash "$DC" 'glm effort drop probe' --kind docs --writes docs/x.md >"$TMP/glm-dispatch.out" 2>&1
  echo "RC=$?" >>"$TMP/glm-dispatch.out"
)
if grep -q 'effort_dropped' "$TMP/glm-dispatch.out" && grep -q 'reason=no_effort_control' "$TMP/glm-dispatch.out" \
   && ! grep -qE 'unbound variable|Traceback|command not found' "$TMP/glm-dispatch.out"; then
  pass 'glm arm (no effort control) journals effort_dropped and does not crash'
else
  fail "glm dispatch_out=$(tail -15 "$TMP/glm-dispatch.out" 2>/dev/null)"
fi

# (7) Acceptance #7: the decision line names BOTH the arm and the effort.
if grep -qE 'route_resolved .*\barm=codex\b.* effort=[a-z]+ ' "$TMP/codex-dispatch.out"; then
  pass 'decision line names both arm and effort (codex run)'
else
  fail "decision line missing arm+effort: $(grep 'route_resolved' "$TMP/codex-dispatch.out" 2>/dev/null | tail -1)"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
