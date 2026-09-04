#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dispatch-code leadv2-route-arbiter
# FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 -- the arbiter must never pick an arm the
# router already excluded in the SAME dispatch.
#
# Bug reproduced live 2026-08-30 across tasks 37a9e8fa/d7b71ad4/f9ecad31:
#   arm_excluded by=router arm=freepool reason=arm_not_capable_for_size task_class=light when=standard,bulk
#   route_resolved by=arbiter reason=cheapest_capable arbiter_pick=freepool
# The router's ladder-level `when:` filter (_build_candidate_chain in
# leadv2-dispatch-code.sh) excludes freepool for a `light` task (freepool's
# ladder entry only declares `when: [standard, bulk]`), but the arbiter's own
# capability matrix independently folds light -> the "standard" size bucket
# (SIZE_MAP) and its capability floor deliberately keeps trivial/light
# freepool-COST-eligible -- so the arbiter re-admits exactly the arm the
# router just excluded.
#
# Fix: leadv2-dispatch-code.sh now passes the router's post-filter
# candidate_arms as `allowed_arms` in the descriptor handed to route_arbiter;
# the arbiter's matrix (leadv2-route-arbiter.sh:146) already intersects
# against `allowed_arms` when present -- it just never received one before.
#
# Control (mission rule): mutate a THROWAWAY COPY of the production dispatch
# script (strip the allowed_arms wiring), prove the exact repro line comes
# back (RED), then run the same scenario against the real, unmutated file
# and prove it stays fixed (GREEN). Hermetic: quota/freepool-gate/arbiter
# state are all test seams; --no-spawn; real worker process never runs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_BIN="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"
ROUTING="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/arm-cap-honoured.XXXXXX")"
trap '[[ "${ARMCAP_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

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
# glm capped so glm/glm-flash leave the picture (matches FP-08's shape) --
# codex+claude healthy, freepool (cost 0 when un-gated) is the only cheap arm
# left standing, so an un-filtered arbiter genuinely WANTS to pick it.
LOW_QUOTA="$(quota_json 99 20 20)"

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

# Admission classifier stub: reports complexity=trivial so
# leadv2_admission_map_class -> "Light", which becomes DC_TASK_CLASS=light
# for _build_candidate_chain's `when:` filter -- the exact task_class the
# live bug's repro lines show (task_class=light when=standard,bulk).
TASK_JUDGE="$TMP/task-judge.sh"
cat > "$TASK_JUDGE" <<'EOF'
#!/usr/bin/env bash
printf '%s' '{"complexity":"trivial","estimate_source":"judge"}'
EOF
chmod +x "$TASK_JUDGE"

run_dispatch() { # <dispatch_bin> <repo_dir> <state_suffix>
  local bin="$1" repo="$2" suffix="$3"
  (cd "$repo" && LEADV2_STATE_ROOT="$TMP/state-root-$suffix" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-dispatch-$suffix" \
    ROUTE_TEST_QUOTA="$LOW_QUOTA" \
    CLAUDE_PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" \
    LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-$suffix" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_REQUIRE_PHASES=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
    LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
    LEADV2_TASK_JUDGE_BIN="$TASK_JUDGE" \
    LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
    bash "$bin" "arm-capability-honoured probe ${TMP}" \
      --kind code --no-spawn --writes src/x.py 2>&1 || true)
}

# ── GREEN: real, unmutated dispatch script ────────────────────────────────
REPO_GREEN="$TMP/repo-green"
setup_repo "$REPO_GREEN"
out_green="$(run_dispatch "$DISPATCH_BIN" "$REPO_GREEN" green)"
printf '%s\n' "$out_green" > "$TMP/green.log"

if printf '%s\n' "$out_green" | grep -q 'arm_excluded by=router arm=freepool task=[0-9a-f]\{8\} reason=arm_not_capable_for_size task_class=light'; then
  pass "(green) router still excludes freepool for a light task (when=standard,bulk)"
else
  fail "(green) router exclusion line missing (log: $TMP/green.log)"
fi
if printf '%s\n' "$out_green" | grep -qE 'route_resolved by=arbiter role=worker arm=freepool|arbiter_pick=freepool'; then
  fail "(green) arbiter picked freepool despite router exclusion (log: $TMP/green.log)"
else
  pass "(green) arbiter honours the router's exclusion -- freepool never arbiter_pick"
fi

# ── RED: throwaway mutated copy with the allowed_arms wiring stripped ─────
# Copy the complete scripts tree into TMP so sibling-library resolution stays
# real while production directories remain immutable even on interruption.
MUT_PLUGIN_ROOT="$TMP/mutated-plugin"
mkdir -p "$MUT_PLUGIN_ROOT"
cp -R "$SCRIPTS_ROOT" "$MUT_PLUGIN_ROOT/scripts"
cp -R "${SCRIPTS_ROOT}/../config" "$MUT_PLUGIN_ROOT/config"
MUT_BIN="${MUT_PLUGIN_ROOT}/scripts/leadv2-dispatch-code.sh"
# Strip the allowed_arms python-side field and the csv arg, reverting the
# descriptor build to its pre-fix shape (no allowed_arms key at all).
python3 - "$MUT_BIN" <<'PY'
import re, sys
path = sys.argv[1]
src = open(path).read()
mutated = src.replace(
    '\'import json,sys; allowed=[a for a in sys.argv[6].split(",") if a]; print(json.dumps({"kind":sys.argv[1],"size":sys.argv[2],"protected":sys.argv[3]=="1","safety":sys.argv[4]=="1","ui_judgment":sys.argv[5]=="1","task":sys.argv[7],"allowed_arms":allowed}))\' "${kind:-code}" "${task_class:-standard}" "${_arb_protected}" "${_arb_safety}" "${_arb_ui}" "${_arb_allowed_csv}" "${sig8}"',
    '\'import json,sys; print(json.dumps({"kind":sys.argv[1],"size":sys.argv[2],"protected":sys.argv[3]=="1","safety":sys.argv[4]=="1","ui_judgment":sys.argv[5]=="1","task":sys.argv[6]}))\' "${kind:-code}" "${task_class:-standard}" "${_arb_protected}" "${_arb_safety}" "${_arb_ui}" "${sig8}"'
)
if mutated == src:
    sys.exit("mutation anchor not found -- zero-match, hard failure")
open(path, 'w').write(mutated)
PY
if [[ $? -ne 0 ]]; then
  fail "(red) mutation anchor not found in production file -- cannot prove the control" "zero-match"
else
  bash -n "$MUT_BIN" || fail "(red) mutated copy fails bash -n"
  REPO_RED="$TMP/repo-red"
  setup_repo "$REPO_RED"
  out_red="$(run_dispatch "$MUT_BIN" "$REPO_RED" red)"
  printf '%s\n' "$out_red" > "$TMP/red.log"
  if printf '%s\n' "$out_red" | grep -qE 'route_resolved by=arbiter role=worker arm=freepool|arbiter_pick=freepool'; then
    pass "(red) with allowed_arms wiring stripped, the exact live bug reproduces -- arbiter re-picks the router-excluded arm"
  else
    fail "(red) mutation did not flip the outcome -- control is not falsifiable (log: $TMP/red.log)"
  fi
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
