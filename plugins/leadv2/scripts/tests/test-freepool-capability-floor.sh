#!/usr/bin/env bash
# FP-08 (2026-08-28) capability-floor suite for the freepool arm.
#
# Contract: until FP-04's quality gate flips freepool-arm.yaml's
# `capability_floor` to `full`, freepool ranks BELOW codex/sonnet for
# Standard+ build work (raw --task-class standard|heavy|strategic, arbiter
# kind code), while trivial/light ("simple") and bulk classes and every
# non-build kind stay freepool-eligible. The demotion is applied on the
# EFFECTIVE cost (the arbiter sort's dominant key) and journaled via the
# floor_applied=1 floor_reason=<class>/<kind> tokens on the arbiter's output
# line, which leadv2-dispatch-code.sh turns into the
# `arm_floor_applied arm=freepool` decision line.
#
# NEGATIVE CONTROL (declared per suite contract, run RED by construction):
# the last case mutates a throwaway copy of the arbiter so the floor no
# longer applies, and asserts freepool then WINS the same Standard build
# invocation that the real arbiter keeps it out of. If that mutation does
# not flip the winner, the assertions above prove nothing.
#
# Hermetic: no network, no live proxy, no real dispatch. The arbiter's own
# test seams (LEADV2_ROUTE_ARBITER_QUOTA_LIVE / _FREEPOOL_GATE /
# _FREEPOOL_CONFIG / _STATE_FILE) carry every external input.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${SCRIPTS_ROOT}/lib/leadv2-route-arbiter.sh"
ROUTING="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"
DEFAULT_FP_CONFIG="${SCRIPTS_ROOT}/../config/freepool-arm.yaml"

PASS=0; FAIL=0
pass() { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/freepool-floor.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

bash -n "$ARBITER" || { fail "bash syntax: arbiter"; exit 1; }
pass "bash syntax: arbiter"

# Fixture quota source: glm at $1%, codex at $2, claude at $3.
cat > "$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
# Fixture freepool gate: healthy unless the case says otherwise.
cat > "$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

quota_json() { # <glm_pct> <codex_pct> <claude_pct>
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

run_arbiter() { # <quota_json> <descriptor_json> [freepool_config] [arbiter_bin]
  local q="$1" desc="$2" cfg="${3:-$DEFAULT_FP_CONFIG}" arb="${4:-$ARBITER}"
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_CONFIG="$cfg" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
  ROUTE_TEST_QUOTA="$q" \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$arb" "$desc"
}

# glm capped (99%) so glm/glm-flash leave the picture; codex+claude healthy.
# Without the floor this is exactly the live FP-08 shape: freepool (cost 1)
# sorts ahead of codex (3) and sonnet (5) and wins as cheapest_capable.
STD_BUILD_QUOTA="$(quota_json 99 20 20)"

# (b) Standard build: freepool is NEVER the pick even though it is cheapest;
# the demotion is journaled on the arbiter's own output line.
out="$(run_arbiter "$STD_BUILD_QUOTA" '{"kind":"code","size":"standard"}')"
if [[ "$out" == *'arm=freepool '* ]]; then
  fail "(b) standard build: freepool selected despite capability floor ($out)"
else
  pass "(b) standard build: freepool not selected"
fi
if [[ "$out" == *'floor_applied=1 floor_reason=standard/code'* ]]; then
  pass "(b) standard build: floor journaled as floor_applied=1 floor_reason=standard/code"
else
  fail "(b) standard build: floor line missing ($out)"
fi
chain="$(printf '%s\n' "$out" | sed -n 's/.*chain=\([^ ]*\).*/\1/p')"
if [[ ",${chain}," == *,freepool, && "$chain" == *freepool ]]; then
  if [[ "${chain##*,}" == "freepool" || "$chain" == "freepool" ]]; then
    : # freepool last (or alone)
  fi
fi
if [[ "${chain##*,}" == "freepool" ]]; then
  pass "(b) standard build: freepool demoted to LAST chain position ($chain)"
else
  fail "(b) standard build: freepool not last in chain ($chain)"
fi
# ...and it must rank below codex AND sonnet, not merely below one of them.
codex_pos="${chain%%,codex*}"; sonnet_pos="${chain%%,sonnet*}"
if [[ "${#codex_pos}" -lt "${#chain}" && "${#sonnet_pos}" -lt "${#chain}" ]]; then
  pass "(b) standard build: codex and sonnet both rank ahead of freepool"
else
  fail "(b) standard build: codex/sonnet do not both rank ahead ($chain)"
fi

# (b2) heavy + strategic build: same floor.
for cls in heavy strategic; do
  out="$(run_arbiter "$STD_BUILD_QUOTA" "{\"kind\":\"code\",\"size\":\"${cls}\"}")"
  if [[ "$out" == *'arm=freepool '* ]]; then
    fail "(b2) ${cls} build: freepool selected despite floor"
  else
    pass "(b2) ${cls} build: freepool not selected"
  fi
  if [[ "$out" == *"floor_reason=${cls}/code"* ]]; then
    pass "(b2) ${cls} build: floor reason carries the raw class"
  else
    fail "(b2) ${cls} build: floor reason missing for raw class ${cls} ($out)"
  fi
done

# (c) bulk/simple stay freepool-eligible: freepool WINS bulk when it is the
# only uncapped capable arm (glm capped; codex/sonnet have no bulk cells).
out="$(run_arbiter "$STD_BUILD_QUOTA" '{"kind":"code","size":"bulk"}')"
if [[ "$out" == *'arm=freepool '* ]]; then
  pass "(c) bulk build: freepool still selectable"
else
  fail "(c) bulk build: freepool unexpectedly demoted ($out)"
fi
if [[ "$out" == *'floor_applied=1'* ]]; then
  fail "(c) bulk build: floor must NOT apply to bulk"
else
  pass "(c) bulk build: no floor token for bulk"
fi
# (c2) trivial/light ("simple") build: floor must not fold them into standard
# (the SIZE_MAP regression the previous in-util() attempt had).
for cls in trivial light; do
  out="$(run_arbiter "$(quota_json 99 99 99)" "{\"kind\":\"code\",\"size\":\"${cls}\"}")"
  if [[ "$out" == *'arm=freepool '* ]]; then
    pass "(c2) ${cls} build: freepool still selectable"
  else
    fail "(c2) ${cls} build: freepool demoted for a simple task ($out)"
  fi
done
# (c3) non-build kind (docs) at standard size: not build work, no floor.
out="$(run_arbiter "$STD_BUILD_QUOTA" '{"kind":"docs","size":"standard"}')"
if [[ "$out" == *'arm=freepool '* ]]; then
  pass "(c3) standard docs: freepool still selectable (floor is build-only)"
else
  fail "(c3) standard docs: freepool unexpectedly demoted ($out)"
fi

# (config) the flip: capability_floor: full lifts the floor entirely.
printf 'capability_floor: full\n' > "$TMP/fp-full.yaml"
out="$(run_arbiter "$STD_BUILD_QUOTA" '{"kind":"code","size":"standard"}' "$TMP/fp-full.yaml")"
if [[ "$out" == *'arm=freepool '* ]]; then
  pass "(config) capability_floor=full lifts the floor (freepool wins as cheapest)"
else
  fail "(config) capability_floor=full did not lift the floor ($out)"
fi
# (config2) an explicit bulk_only keeps the floor on.
printf 'capability_floor: bulk_only\n' > "$TMP/fp-bulk.yaml"
out="$(run_arbiter "$STD_BUILD_QUOTA" '{"kind":"code","size":"standard"}' "$TMP/fp-bulk.yaml")"
if [[ "$out" == *'arm=freepool '* ]]; then
  fail "(config2) capability_floor=bulk_only still demotes standard build"
else
  pass "(config2) capability_floor=bulk_only keeps the floor on"
fi

# (dispatch) the dispatcher turns the arbiter's floor tokens into the
# `arm_floor_applied arm=freepool` decision line. Full cmd_resolve, real
# arbiter lib, --no-spawn (resolve+journal only).
REPO="$TMP/repo"
mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2" "$REPO/docs/leadv2/tasks"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@e.com; git -C "$REPO" config user.name t
: > "$REPO/seed"; git -C "$REPO" add seed; git -C "$REPO" commit -qm seed
WORKER="$TMP/worker.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' > "$WORKER"
chmod +x "$WORKER"
REPO_CFG_DIR="$REPO/.claude/ref"
cp "$ROUTING" "$REPO_CFG_DIR/leadv2-routing.yaml"
# The dispatch must see the floor even when the freepool gate is healthy and
# the dispatch's own routing yaml is a tenant copy without a ladder.
arb_out="$(LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-dispatch" \
  ROUTE_TEST_QUOTA="$STD_BUILD_QUOTA" \
  CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" \
  LEADV2_DISPATCH_CACHE_DIR="$TMP/cache" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
  LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
  bash "$SCRIPTS_ROOT/leadv2-dispatch-code.sh" 'FP-08 floor journal probe' \
    --kind code --task-class standard --no-spawn --writes src/x.py 2>&1 || true)"
if printf '%s\n' "$arb_out" | grep -q 'arm_floor_applied arm=freepool reason=standard/code'; then
  pass "(dispatch) arm_floor_applied journal line emitted from the arbiter output"
else
  fail "(dispatch) arm_floor_applied journal line missing"
fi
if printf '%s\n' "$arb_out" | grep -q 'route_resolved by=arbiter arm=freepool'; then
  fail "(dispatch) arbiter route_resolved picked freepool for a standard build"
else
  pass "(dispatch) arbiter route_resolved did not pick freepool"
fi

# ---- NEGATIVE CONTROL (mission test d) -------------------------------------
# Mutate a throwaway copy of the arbiter so the floor can never apply, then
# re-run the EXACT (b) invocation: freepool must now WIN. If it still lost,
# the mutation did not neutralize the floor AND/OR the assertions above are
# tautological — either way the suite is lying and must go red.
sed 's/^floor_applies = (.*)$/floor_applies = False/' "$ARBITER" > "$TMP/arb-mutated.sh"
if grep -q 'floor_applies = False' "$TMP/arb-mutated.sh"; then
  pass "(negative-control) floor mutation applied to a throwaway arbiter copy"
else
  fail "(negative-control) floor mutation did not land — control is void"
fi
mut_out="$(run_arbiter "$STD_BUILD_QUOTA" '{"kind":"code","size":"standard"}' "$DEFAULT_FP_CONFIG" "$TMP/arb-mutated.sh")"
if [[ "$mut_out" == *'arm=freepool '* && "$mut_out" != *'floor_applied=1'* ]]; then
  pass "(negative-control) with the floor removed, freepool WINS the standard build (control is red by construction)"
else
  fail "(negative-control) mutated arbiter did not hand the standard build to freepool — assertions above are not load-bearing ($mut_out)"
fi

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
