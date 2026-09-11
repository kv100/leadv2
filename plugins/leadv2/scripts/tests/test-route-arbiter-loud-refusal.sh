#!/usr/bin/env bash
# run-all-triggers: leadv2-route-arbiter leadv2-routing.yaml
# tests/test-route-arbiter-loud-refusal.sh — ROUTE-ARBITER-DIES-SILENTLY-ON-LINUX-01
#
# Split out of test-route-arbiter.sh (2026-09-09) deliberately: the primary
# arbiter suite carries three pre-existing reds (capability_fit policy drift,
# proven pre-existing by a HEAD-bytes baseline run the same day), and a suite
# that is red at baseline cannot host a mutation control — the control tool
# refuses baseline_not_green. Every case here is green on an unmutated tree,
# which is what makes the two mutation artifacts for this row possible.
#
# The contract under test (row 5d2f022674a6, 2026-09-09 half):
#   1. PyYAML is OPTIONAL. When it is missing (a bare debian container, lean
#      CI), a strict stdlib YAML-SUBSET loader routes instead of dying rc=2 —
#      parse-or-refuse, never guess. The seam LEADV2_ROUTE_ARBITER_YAML_LOADER
#      =stdlib forces the subset loader on a machine that HAS PyYAML, which is
#      what makes the differential provable: identical decision lines through
#      both loaders on the REAL configs. Bare-linux rc=0/route-line evidence
#      lives in the lane report (docker, debian bookworm).
#   2. Every non-zero exit prints. A config beyond the subset refuses LOUDLY
#      (FATAL on stderr naming the line); an invalid loader pin is a named
#      usage refusal; the bash preconditions keep their 2026-09-05 FATALs.
#
# Portable: no GNU-only date/sed -i/timeout/flock. bash 3.2 compatible.
# Run: bash plugins/leadv2/scripts/tests/test-route-arbiter-loud-refusal.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${LEADV2_TEST_ARBITER_BIN:-${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh}"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

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
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok','five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
# run_loader <loader-mode> <state-suffix> <quota-json> <free-rc> <descriptor>
# Distinct state files per invocation: last-arm state must never couple the
# two arms of the differential below.
run_loader(){ LEADV2_ROUTE_ARBITER_YAML_LOADER="$1" LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-$2" ROUTE_TEST_QUOTA="$3" ROUTE_TEST_FREE_RC="${4:-0}" bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$5"; }

# ── (1) differential: subset loader == real PyYAML on the real configs ─────
# floor_mode_source=yaml in the line proves freepool-arm.yaml also went
# through the subset loader. One drifted token in either config's parse would
# move a cell/cost/weight and flip this assert.
_q="$(quota 10 20 20)"
out_pyyaml="$(run_loader pyyaml 1 "$_q" 1 '{"kind":"code","size":"standard"}')"
out_stdlib="$(run_loader stdlib 2 "$_q" 1 '{"kind":"code","size":"standard"}')"
if [[ "$out_pyyaml" == "$out_stdlib" && "$out_stdlib" == 'arm='* \
      && "$out_stdlib" == *'floor_mode_source=yaml'* ]]; then
  pass 'stdlib YAML-subset loader routes byte-identically to real PyYAML on the real configs'
else
  fail "loader differential pyyaml='$out_pyyaml' stdlib='$out_stdlib'"
fi

# ── (2) parse-or-refuse: beyond-subset yaml refuses LOUDLY ──────────────────
# An anchor is outside the subset. It must refuse with FATAL rc=2
# reason=yaml_subset_unsupported on stderr and ZERO decision bytes on stdout —
# never approximate the construct and route on a guess.
cat >"$TMP/routing-anchor.yaml" <<'EOF'
router_v2:
  cells: &base
    - { arm: glm, provider: glm, model: glm-5.3, tier: standard, cost: 1, kinds: [code], sizes: [standard], review: true, protected: true, capability: 4 }
EOF
sub_out="$(LEADV2_ROUTE_ARBITER_YAML_LOADER=stdlib \
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing-anchor.yaml" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-anchor" \
  ROUTE_TEST_QUOTA="$(quota 10 20 20)" ROUTE_TEST_FREE_RC=1 \
  bash -c 'source "$0"; route_arbiter worker "$1"; printf "WRAP_RC=%s" "$?"' "$ARBITER" '{"kind":"code","size":"standard"}' 2>"$TMP/sub.err")"
if [[ "$sub_out" == 'WRAP_RC=2' && "$(cat "$TMP/sub.err")" == *'FATAL rc=2 reason=yaml_subset_unsupported'* ]]; then
  pass 'subset-unsupported yaml refuses loudly (rc=2, stderr names the line), never routes on a guess'
else
  fail "subset refusal out='$sub_out' err='$(head -c 300 "$TMP/sub.err")'"
fi

# ── (3) invalid loader pin: a named usage refusal, not a mute exit ──────────
bad_out="$(LEADV2_ROUTE_ARBITER_YAML_LOADER=sometimes \
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-badmode" \
  ROUTE_TEST_QUOTA="$(quota 10 20 20)" ROUTE_TEST_FREE_RC=1 \
  bash -c 'source "$0"; route_arbiter worker "$1"; printf "WRAP_RC=%s" "$?"' "$ARBITER" '{"kind":"code","size":"standard"}' 2>"$TMP/bad.err")"
if [[ "$bad_out" == 'WRAP_RC=2' && "$(cat "$TMP/bad.err")" == *'FATAL rc=2 reason=yaml_loader_mode_invalid'* ]]; then
  pass 'invalid LEADV2_ROUTE_ARBITER_YAML_LOADER value is a named refusal (rc=2, stderr bytes > 0)'
else
  fail "bad-mode out='$bad_out' err='$(head -c 300 "$TMP/bad.err")'"
fi

# ── (4) bash-half loud refusal (2026-09-05 contract, kept green here) ───────
# An unreadable routing yaml must die with the FATAL line on stderr and no
# decision bytes on stdout. This is the assertion the _arb_fatal mutation
# control targets; it lives in this suite (not only the primary suite) so the
# control has a green baseline to mutate from.
bash_out="$(LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/no-such-routing.yaml" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-fatal" \
  ROUTE_TEST_QUOTA="$(quota 10 20 20)" ROUTE_TEST_FREE_RC=1 \
  bash -c 'source "$0"; route_arbiter worker "$1"; printf "WRAP_RC=%s" "$?"' "$ARBITER" '{"kind":"code","size":"standard"}' 2>"$TMP/bash.err")"
if [[ "$bash_out" == 'WRAP_RC=65' && "$(cat "$TMP/bash.err")" == *'FATAL rc=65 reason=routing_yaml_unreadable'* ]]; then
  pass 'unreadable routing yaml: FATAL rc=65 on stderr, zero decision bytes on stdout'
else
  fail "bash-half refusal out='$bash_out' err='$(head -c 300 "$TMP/bash.err")'"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
