#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-admission-class leadv2-dispatch-code
# SAFETY-PIN-SECOND-DOOR-01 -- the L2 task judge can flag risk_class=
# safety_publish_payments (its own deterministic keyword estimator, or a live
# haiku call) without the caller ever passing --safety/--risk-tags. Before
# this fix, that signal only escalated ADMISSION_CLASS to Heavy
# (lib/leadv2-admission-class.sh's map) -- it never reached the `safety`
# local in cmd_resolve, so a judge-flagged hard-safety task with no explicit
# flag took the ordinary Heavy route with NO safety pin: DC_SAFETY stayed 0,
# the router's require_trusted exclusion (leadv2-dispatch-code.sh:2332) never
# fired, and route_resolved could land on an untrusted arm.
#
# This is a SEPARATE router from leadv2-session-route.sh (already fixed by
# HEAVY-TIER-VS-SAFETY-OPUS-01 round 2) -- that script only handles
# background /leadv2 session provider/model selection and has no risk_class
# concept at all (--class/--risk-tags only). The second door lives entirely
# inside leadv2-dispatch-code.sh's own resolve_arm/route_arbiter path, which
# is why the fix and this coverage live here, not in test-session-route.sh.
#
# Control: mutate a THROWAWAY COPY of the production dispatch script (strip
# the safety-pin fold-in this lane added to cmd_resolve), prove the exact
# pre-fix symptom comes back (RED -- no safety_pin_applied line, freepool
# survives on arm_not_capable_for_size rather than protected_path), then run
# the same scenario against the real, unmutated file and prove it stays
# fixed (GREEN). Hermetic: quota/freepool-gate/judge are all test seams;
# --no-spawn; real worker process never runs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_BIN="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"
ROUTING="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

# Whether the safety signal reached routing enforcement (not just the
# admission journal line), across BOTH live router implementations dispatch
# can pick per-run (T17 fix-round: arbiter is primary, legacy v1 is the
# fail-open fallback on an arbiter fault -- leadv2-dispatch-code.sh:7574).
# Live-verified (not assumed) that both shapes occur for the SAME fixed
# binary on different platforms, same test scenario: on macOS (bash 3.2) the
# arbiter path wins and journals `arm_excluded ... arm=freepool ...
# reason=protected_path`; in a Debian container (bash 5) the arbiter falls
# back to legacy v1, which never emits that exclusion line at all and instead
# resolves straight to `rule=safety_gate_publish_payments reason=sonnet_exception`.
# Whichever path wins is pre-existing arbiter/ladder plumbing this lane's
# fix does not touch -- accepting either shape is not weakening the
# assertion, it is scoping it to what the risk_class fold-in actually
# guarantees (the safety signal reaches ONE of the two known enforcement
# points), while still being false on the mutated copy on both platforms
# (verified: mutated run resolves rule=none reason=glm_default on Linux,
# and drops the protected_path exclusion line on macOS).
_safety_reached_routing() { # <log_text> -> rc 0 if either enforcement shape present
  printf '%s\n' "$1" | grep -qE \
    'arm_excluded by=router arm=freepool task=[0-9a-f]{8} reason=protected_path|rule=safety_gate_publish_payments'
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/admission-safety-pin.XXXXXX")"
trap '[[ "${ASP_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

bash -n "$DISPATCH_BIN" || { fail "bash syntax: dispatch"; exit 1; }
pass "bash syntax: dispatch"

quota_json() { # <glm_pct> <codex_pct> <claude_pct> -- all healthy (low pct)
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
g, c, a = (int(x) for x in sys.argv[1:])
print(json.dumps({
    'glm': {'status': 'ok', 'five_hour': {'pct': g}, 'weekly': {'pct': g}},
    'codex': {'status': 'ok', 'binding_window': 'primary',
              'windows': [{'kind': 'primary', 'used_percent': c}]},
    'anthropic': {'status': 'ok', 'accounts': [
        {'active': True, 'five_hour_pct': a, 'seven_day_pct': a}]},
}))
PY
}
HEALTHY_QUOTA="$(quota_json 5 5 5)"

cat > "$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat > "$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

setup_repo() { # <dir>
  local repo="$1"
  mkdir -p "$repo/.claude/ref" "$repo/docs/leadv2" "$repo/docs/leadv2/tasks"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@e.com; git -C "$repo" config user.name t
  : > "$repo/seed"; git -C "$repo" add seed; git -C "$repo" commit -qm seed
  cp "$ROUTING" "$repo/.claude/ref/leadv2-routing.yaml"
}

WORKER="$TMP/worker.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' > "$WORKER"
chmod +x "$WORKER"

# Judge stub: risk_class=safety_publish_payments, no bearing on the CLI
# --safety flag at all -- this is exactly the judge-flags-without-caller-flag
# shape the census (HEAVY-TIER-VS-SAFETY-OPUS-01) and this lane's brief
# describe.
JUDGE_SAFETY="$TMP/judge-safety.sh"
cat > "$JUDGE_SAFETY" <<'EOF'
#!/usr/bin/env bash
printf '%s' '{"complexity":"complex","subsystems_touched":1,"risk_class":"safety_publish_payments","work_kind":"build","estimate_source":"judge"}'
EOF
chmod +x "$JUDGE_SAFETY"

# Baseline judge stub: same complexity/class shape (still Heavy, still
# routes=phases) but risk_class=none -- isolates the safety pin's effect from
# the unrelated Heavy-class routing so a diff between the two runs is
# attributable to risk_class alone.
JUDGE_NOSAFETY="$TMP/judge-nosafety.sh"
cat > "$JUDGE_NOSAFETY" <<'EOF'
#!/usr/bin/env bash
printf '%s' '{"complexity":"complex","subsystems_touched":1,"risk_class":"none","work_kind":"build","estimate_source":"judge"}'
EOF
chmod +x "$JUDGE_NOSAFETY"

run_dispatch() { # <dispatch_bin> <repo_dir> <state_suffix> <judge_bin>
  local bin="$1" repo="$2" suffix="$3" judge="$4"
  (cd "$repo" && LEADV2_STATE_ROOT="$TMP/state-root-$suffix" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-dispatch-$suffix" \
    ROUTE_TEST_QUOTA="$HEALTHY_QUOTA" \
    CLAUDE_PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" \
    LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-$suffix" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_REQUIRE_PHASES=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
    LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_TASK_JUDGE_BIN="$judge" \
    LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
    bash "$bin" "Refund a customer via the billing service." \
      --kind code --no-spawn --writes src/billing.py 2>&1 || true)
}

# ── GREEN #1: judge flags safety, no --safety flag -- pin must fire ───────
REPO_A="$TMP/repo-a"
setup_repo "$REPO_A"
out_a="$(run_dispatch "$DISPATCH_BIN" "$REPO_A" a "$JUDGE_SAFETY")"
printf '%s\n' "$out_a" > "$TMP/a.log"

if printf '%s\n' "$out_a" | grep -q 'safety_pin_applied by=admission task=[0-9a-f]\{8\} reason=risk_safety_publish_payments'; then
  pass "(green) judge-only safety signal, no --safety flag -- pin fires"
else
  fail "(green) safety_pin_applied line missing (log: $TMP/a.log)"
fi
if _safety_reached_routing "$out_a"; then
  pass "(green) pin reaches routing enforcement, not just the admission journal"
else
  fail "(green) pin did not reach DC_SAFETY/router exclusion (log: $TMP/a.log)"
fi

# ── Baseline: same Heavy shape, risk_class=none -- pin must NOT fire ──────
REPO_B="$TMP/repo-b"
setup_repo "$REPO_B"
out_b="$(run_dispatch "$DISPATCH_BIN" "$REPO_B" b "$JUDGE_NOSAFETY")"
printf '%s\n' "$out_b" > "$TMP/b.log"

if printf '%s\n' "$out_b" | grep -q 'safety_pin_applied by=admission'; then
  fail "(baseline) risk_class=none must not fire the pin (log: $TMP/b.log)"
else
  pass "(baseline) risk_class=none -- no safety_pin_applied line"
fi

# ── RED: throwaway mutated copy with the safety-pin fold-in stripped ──────
# Copy the complete scripts tree into TMP so sibling-library resolution stays
# real while production directories remain immutable even on interruption.
MUT_PLUGIN_ROOT="$TMP/mutated-plugin"
mkdir -p "$MUT_PLUGIN_ROOT"
cp -R "$SCRIPTS_ROOT" "$MUT_PLUGIN_ROOT/scripts"
cp -R "${SCRIPTS_ROOT}/../config" "$MUT_PLUGIN_ROOT/config"
MUT_BIN="${MUT_PLUGIN_ROOT}/scripts/leadv2-dispatch-code.sh"
python3 - "$MUT_BIN" <<'PY'
import sys
path = sys.argv[1]
src = open(path, encoding="utf-8").read()
anchor = (
    '  if [[ "${ADMISSION_RISK_CLASS:-}" == "safety_publish_payments" && "${safety}" != "1" ]]; then\n'
    '    safety=1\n'
    '    emit decision "safety_pin_applied by=admission task=${sig8} reason=risk_safety_publish_payments"\n'
    '  fi\n'
)
if anchor not in src:
    sys.exit("mutation anchor not found -- zero-match, hard failure")
open(path, "w", encoding="utf-8").write(src.replace(anchor, "", 1))
PY
if [[ $? -ne 0 ]]; then
  fail "(red) mutation anchor not found in production file -- cannot prove the control" "zero-match"
else
  bash -n "$MUT_BIN" || fail "(red) mutated copy fails bash -n"
  REPO_RED="$TMP/repo-red"
  setup_repo "$REPO_RED"
  out_red="$(run_dispatch "$MUT_BIN" "$REPO_RED" red "$JUDGE_SAFETY")"
  printf '%s\n' "$out_red" > "$TMP/red.log"
  if printf '%s\n' "$out_red" | grep -q 'safety_pin_applied by=admission'; then
    fail "(red) mutation did not flip the outcome -- control is not falsifiable (log: $TMP/red.log)"
  else
    pass "(red) with the fold-in stripped, the second door reopens -- no safety_pin_applied line"
  fi
  if _safety_reached_routing "$out_red"; then
    fail "(red) routing still shows safety enforcement despite stripped pin -- control is not falsifiable (log: $TMP/red.log)"
  else
    pass "(red) no safety enforcement in routing -- exact pre-fix symptom reproduced"
  fi
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
