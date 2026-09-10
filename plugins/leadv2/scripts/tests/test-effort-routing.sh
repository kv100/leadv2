#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dispatch-code.sh leadv2-route-arbiter leadv2-routing.yaml
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
TMP_BASE="${LEADV2_TEST_TMPDIR:-/tmp}"
TMP="$(mktemp -d "${TMP_BASE%/}/test-effort-routing.XXXXXX")"; trap 'rm -rf "$TMP" 2>/dev/null || true' EXIT
export LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events.jsonl"
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

# (3) Acceptance #3: an ordinary build resolves to the middle internal tier;
# glm's low|high|max provider projection rounds it down to low. glm-flash
# (cost 0.4, tags cheap/mechanical) is only capable at size=standard, so pin
# size=heavy to land on a plain bulk/background cell (glm) with no
# mechanical/adversarial/safety/plan/protected tag -- the effort_matrix
# default row.
out="$(run "$(quota 1 1 1)" 0 '{"kind":"code","size":"heavy"}')"
if [[ "$out" == *' effort=low '* || "$out" == *' effort=low reason='* ]]; then
  pass 'ordinary heavy code build projects internal medium down to glm low'
else
  fail "heavy-code output=$out"
fi

# (6) Acceptance #6 (anti-hardcode): adding a new effort_matrix rule to a
# ROUTING YAML changes the outcome with NO script edit. A fixture copy of the
# real routing.yaml, with one extra row inserted ahead of the default row
# that forces every `code` kind to `high`, must flip case (3)'s medium -> high
# using the SAME arbiter script, unmodified.
# Pin the arm at the FIXTURE, not by quota shaping.
#
# The three dispatch-level cases below each need one specific arm, because what
# they assert is the SHAPE of that arm's launch (codex takes --tier, sonnet
# takes --effort and no --tier, glm has no effort control at all). They used to
# get it by capping every other provider's quota to its ceiling -- and that
# stopped isolating anything: GLM-53-FLASH-ARM-01 (2026-08-27) added a cheaper
# arm and GLM-DOES-ANY-WORK-01 (dbcb092f, 2026-09-04) made glm eligible for
# every kind, both AFTER this suite was written (3ff1c07c, 2026-08-31). The
# quota shape now leaves glm-flash the cheapest capable arm everywhere, so all
# three cases silently measured the wrong arm.
#
# A fixture routing yaml offering exactly ONE arm pins it directly, and does
# not hardcode an arm out of production routing: production's own preference
# order is what the arbiter cases above test, against the unmodified yaml.
# It also cannot rot the same way -- a future routing change adds arms to
# production, never to a one-arm fixture.
arm_only_yaml() {  # <arm_id> <dst>
  python3 - "$ROUTING" "$1" "$2" <<'PY'
import sys, yaml
src, arm, dst = sys.argv[1], sys.argv[2], sys.argv[3]
data = yaml.safe_load(open(src))
# router_v2.capability_matrix -- NOT router_v2.arms -- is the candidate set the
# arbiter reads (leadv2-route-arbiter.sh:323). Measured 2026-09-05: filtering
# `arms` pinned nothing at all, and the glm and codex cases still resolved
# arm=glm-flash and arm=glm. `arms` carries channel/model/bucket metadata for
# the dispatcher and is deliberately left whole.
cells = data['router_v2']['capability_matrix']
kept = [c for c in cells if c.get('arm') == arm]
assert kept, "arm %r has no capability_matrix cell in %s -- fixture must name a real arm (have: %s)" % (
    arm, src, sorted({c.get('arm') for c in cells}))
data['router_v2']['capability_matrix'] = kept
yaml.safe_dump(data, open(dst, 'w'))
PY
}

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
if [[ "$out" == *' effort=low '* || "$out" == *' effort=low reason='* ]]; then
  pass 'unmodified routing.yaml still projects medium down to glm low (anti-hardcode control)'
else
  fail "anti-hardcode control output=$out"
fi

# (8) SMART-ARBITER-01 / EFFORT-FOLLOWS-THE-ARM-NOT-THE-TASK-01 (founder
# 2026-09-04): effort is a property of the TASK, never of the winning arm's
# tags. The ranking may select either glm-family arm as capability-fit evolves;
# both use the same low|high|max provider projection, so the task-keyed
# internal medium must become provider low regardless. Before the fix an arm's
# tags could choose the task effort directly.
out="$(run "$(quota 1 1 1)" 0 '{"kind":"code","size":"standard"}')"
if [[ "$out" =~ arm=glm(-flash)?[[:space:]] && "$out" == *' effort=low '* ]]; then
  pass 'standard build projects internal medium to glm provider low regardless of glm-family winner'
else
  fail "task-keyed build output=$out"
fi

# (8b) A judge-estimated complex build keeps effort=high even though the
# winner (glm, tags bulk/background -- no adversarial tag) and the loser
# (glm-flash, penalized +100 by the complexity rule) would both say
# otherwise: effort follows the task's complexity estimate, not arm tags.
out="$(run "$(quota 1 1 1)" 0 '{"kind":"code","size":"standard","complexity":"complex"}')"
if [[ "$out" == *'arm=glm '* && "$out" == *' effort=high '* ]]; then
  pass 'complex build resolves effort=high (task complexity, not arm tags)'
else
  fail "complex build output=$out"
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
    && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed ) >/dev/null 2>&1 \
    || { printf 'FATAL mk_repo: fixture repo setup failed for %s\n' "$repo" >&2; return 1; }
}

dispatch_env(){ # <repo> <cache-dir> -> prints nothing; caller exports around bash "$DC"
  :
}

# (4a) codex arm: --tier and --effort are two DIFFERENT flags on the SAME
# launch line -- assert both are present and effort carries the arbiter's
# resolved value, never the tier's own silent default.
REPO="$TMP/repo-codex"; mk_repo "$REPO"
CODEX_YAML="$TMP/routing-codex-only.yaml"; arm_only_yaml codex "$CODEX_YAML"
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
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$CODEX_YAML" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
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
# The arm is pinned by a one-arm fixture routing yaml (see arm_only_yaml
# above). Quota shaping used to do this and no longer can.
SONNET_YAML="$TMP/routing-sonnet-only.yaml"; arm_only_yaml sonnet "$SONNET_YAML"
# PHASE-GATE-IS-INVERTED-01: a heavy code lane must carry plan+gate1 (and
# diverge for Heavy) BEFORE dispatch — the guard no longer accepts a caller's
# bootstrap attestation. Record the lead-authored evidence this suite's
# mission would realistically have.
PHASE_RECORD="${SCRIPTS_DIR}/leadv2-phase-record.sh"
SIG_SONNET="$(printf '%s' 'sonnet effort wiring probe' | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print substr($1, 1, 8)}')"
mkdir -p "$REPO2/docs/handoff/SONNET-$SIG_SONNET"
printf '# sonnet effort wiring probe\n\nfixture plan\n' > "$REPO2/docs/handoff/SONNET-$SIG_SONNET/brief.md"
# Ask the STORE which phases it wants, then record exactly those.
#
# This fixture used to name plan/gate1/diverge by hand, and by 2026-09-05 the
# Heavy contract had grown a `classify` the list never gained -- the dispatch
# refused before spawning and the case reported "<no argv captured>", which
# reads as a routing failure and is not one. A hand-copied list of somebody
# else's contract rots exactly like the quota shaping above: bind to the thing,
# not to a copy of it. leadv2-phase-record.sh's own `assert` answers with
# `missing=`, which is the same line the dispatcher's guard reads.
_sonnet_missing="$(cd "$REPO2" && PROJECT_ROOT="$REPO2" LEADV2_PROJECT_ROOT="$REPO2" \
  bash "$PHASE_RECORD" assert "$SIG_SONNET" --class heavy --pre-build --writes src/x.py 2>&1 \
  | sed -n 's/^missing=//p' | head -1 || true)"   # `|| true`: this suite runs under `set -o pipefail`, and a refusing
                                                    # assert (rc=4) would otherwise kill the run silently
if [[ -z "$_sonnet_missing" ]]; then
  # Legitimate, and measured: the guard admits a ZERO-record lane through its
  # own bootstrap exemption, so the store names nothing to record. Recording
  # nothing is then correct, and the two cases below -- which need a spawned
  # worker -- are what actually decide whether the gate let the lane through.
  printf '[TEST] NOTE: the phase store named no missing phases (zero-record lane, bootstrap exemption) -- nothing recorded, the gate verdict below decides\n'
fi
_sonnet_unrecorded=""
IFS=',' read -r -a _sonnet_phases <<< "$_sonnet_missing"
for _ph in "${_sonnet_phases[@]}"; do
  [[ -n "$_ph" ]] || continue
  case "$_ph" in
    plan)    _extra=(--artifact "docs/handoff/SONNET-$SIG_SONNET/brief.md") ;;
    diverge) _extra=(--reason 'fixture: no diverge round') ;;
    *)       _extra=(--reason "fixture: $_ph recorded by the lead") ;;
  esac
  # `|| true` and a collected list, never a bare call: this suite runs under
  # `set -e`, and a phase the store names but will not accept (measured
  # 2026-09-05: the pre-build `missing=` set includes phases whose record op
  # refuses here) killed the whole run at rc=4 with no message at all -- six
  # green cases and then silence, which reads as a hang, not as a failure.
  if ! ( cd "$REPO2" && PROJECT_ROOT="$REPO2" LEADV2_PROJECT_ROOT="$REPO2" bash "$PHASE_RECORD" record "$SIG_SONNET" "$_ph" \
      --status done "${_extra[@]}" --owner lead:fixture ) >/dev/null 2>&1; then
    _sonnet_unrecorded+="$_ph "
  fi
done
# Not fatal on its own: what matters is whether the gate then admits the lane,
# and the case below measures exactly that. But an unrecorded phase is the
# first thing to look at if it does not, so it is named rather than swallowed.
if [[ -n "$_sonnet_unrecorded" ]]; then
  printf '[TEST] NOTE: sonnet fixture could not record: %s(store named them missing; the gate verdict below is what decides)\n' "$_sonnet_unrecorded"
fi
(
  cd "$REPO2"
  CLAUDE_PROJECT_ROOT="$REPO2" PROJECT_ROOT="$REPO2" LEADV2_PROJECT_ROOT="$REPO2" \
  LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-sonnet" LEADV2_STATE_BASE="$TMP/state-sonnet" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_DISPATCH_SUBSESSION_BIN="$SONNET_STUB" \
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$SONNET_YAML" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-arb-sonnet" \
  ROUTE_TEST_QUOTA="$(quota 99 99 1)" ROUTE_TEST_FREE_RC=1 \
  timeout 60 bash "$DC" 'sonnet effort wiring probe' --kind code --task-class heavy --protected --writes src/x.py >"$TMP/sonnet-dispatch.out" 2>&1 || true
)
if grep -qE 'route_resolved .*\barm=sonnet\b' "$TMP/sonnet-dispatch.out"; then
  pass 'sonnet fixture pins the arm: the decision line says arm=sonnet'
else
  fail "sonnet arm pin did not take: $(grep 'route_resolved' "$TMP/sonnet-dispatch.out" 2>/dev/null | tail -1)"
fi
if [[ -f "$SONNET_ARGV" ]] && grep -q -- '--effort' "$SONNET_ARGV" && ! grep -q -- '--tier' "$SONNET_ARGV"; then
  pass 'sonnet arm receives --effort in its own launch args, no --tier flag (different shape than codex)'
else
  fail "sonnet argv=$(cat "$SONNET_ARGV" 2>/dev/null || echo '<no argv captured>') dispatch_out=$(tail -5 "$TMP/sonnet-dispatch.out" 2>/dev/null)"
fi

# (5) Acceptance #5: an arm with no effort control (glm) drops the resolved
# effort with a named log line, and the dispatch does not crash.
REPO3="$TMP/repo-glm"; mk_repo "$REPO3"
# No fixture yaml here, deliberately -- see the note at the assertion below.
# The dispatcher's OWN candidate ladder does not admit `glm` for this task
# shape (measured 2026-09-05: candidate_arms=glm-flash,codex,sonnet,freepool),
# and the arbiter intersects allowed_arms with the matrix, so a glm-only
# fixture yields no_capable_cell (rc=68) and the dispatch fails open to the v1
# ladder. TWO admission lists must agree, not one: pinning the matrix alone is
# necessary and not sufficient.
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
# Asserted as PRESENCE, never as the absence of other arms: an empty candidate
# set that fell through to a substituted default would otherwise read as a pass.
if grep -qE 'route_resolved .*\barm=glm-flash\b' "$TMP/glm-dispatch.out"; then
  pass 'the glm-family arm is the one that ran: the decision line says arm=glm-flash'
else
  fail "glm-family arm did not run: $(grep 'route_resolved' "$TMP/glm-dispatch.out" 2>/dev/null | tail -1)"
fi
# This case used to assert `effort_dropped reason=no_effort_control` for glm.
# glm HAS an effort knob now (leadv2-dispatch-code.sh:5730 emits
# effort_applied ... mechanism=flag), so the old assertion described a product
# that no longer exists -- a later change wired the knob and this case was
# never updated. What it pinned is still worth pinning, in the direction the
# product now goes: the resolved effort reaches the glm-family launcher as a
# flag, and the dispatch does not crash doing it.
#
# GAP, stated rather than faked: the arms that genuinely have NO effort control
# are kimi (leadv2-dispatch-code.sh:5794, reasoning_effort locked to max at
# Moonshot) and freepool (:5844). Neither is exercised here -- both need their
# own launcher and gate stubs -- so `effort_dropped reason=no_effort_control`
# is UNCOVERED by this suite. Do not read the green below as covering it.
if grep -qE 'effort_applied by=router arm=glm-flash .*mechanism=flag' "$TMP/glm-dispatch.out" \
   && ! grep -qE 'unbound variable|Traceback|command not found' "$TMP/glm-dispatch.out"; then
  pass 'the glm-family arm receives the resolved effort as a launcher flag, and does not crash'
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
