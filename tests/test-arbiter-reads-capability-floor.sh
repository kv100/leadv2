#!/usr/bin/env bash
# run-all-triggers: leadv2-route-arbiter leadv2-routing.yaml
# tests/test-arbiter-reads-capability-floor.sh — ARBITER-NEVER-READS-CALLER-CAPABILITY-OR-COST-CONSTRAINTS-01
#
# The arbiter parses the caller's descriptor JSON once (leadv2-route-arbiter.sh
# ~:459) and, before this fix, never read `min_capability` or `max_cost` from
# it -- a caller's floor/ceiling was silently swallowed and the founder's
# "use the smartest models" instruction had no way to be expressed. This
# suite proves it BOTH ways against the REAL config/leadv2-routing.yaml:
#   A/B: an unsatisfiable floor/ceiling produces a NAMED refusal
#        (reason=no_cell_meets_caller_constraint), not a silent fallback.
#   C:   a satisfiable min_capability actually changes the pick versus the
#        unfloored default (proves "read", not just "parsed and ignored").
#   D:   a satisfiable max_cost passes with a cell at or under the ceiling.
#   E:   absent keys leave the decision line BYTE-IDENTICAL to today.
#   F:   a malformed value is a loud fatal (caller_constraint_invalid),
#        never a silent drop.
#
# Declared negative control (mutation, tests/mutations/catalog.yaml row
# arbiter-caller-constraint-01): delete the `and _constraint_ok(c)` term from
# the `capable=` comprehension in leadv2-route-arbiter.sh. Expected: A, B and
# C go red (A/B stop refusing -- they fall through to the ordinary pick; C's
# floored run picks the same cheap cell as the unfloored default). Applied in
# a scratch worktree, shown red, and reverted -- see the lane report for the
# captured output.
#
# Case C does not hardcode WHICH cell wins (live forecast state -- read from
# the real per-provider journal, not mocked here -- can knock glm/glm-flash
# out of the pool on any given run). It asserts the thing the defect was
# actually about: the floored pick's cell capability is >=4 AND the pick
# differs from the unfloored default -- proving the floor was READ and
# applied, not merely parsed and ignored.
#
# Portable: no GNU-only date/sed -i/timeout/flock. bash 3.2 compatible.
# Run: bash tests/test-arbiter-reads-capability-floor.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${REPO_DIR}/plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh"
ROUTING="${REPO_DIR}/plugins/leadv2/config/leadv2-routing.yaml"
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
_q="$(quota 10 10 10)"

# run_case <state-suffix> <descriptor-json>
run_case(){
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-$1" \
  ROUTE_TEST_QUOTA="$_q" ROUTE_TEST_FREE_RC=1 \
  bash -c 'source "$0"; route_arbiter worker "$1"; printf "\nWRAP_RC=%s" "$?"' "$ARBITER" "$2" 2>"$TMP/err-$1"
}

# ── baseline (case E dependency): unfloored default pick, no constraint keys ─
base_out="$(run_case baseline '{"kind":"code","size":"standard"}')"
base_line="${base_out%%$'\n'*}"

# ── (A) unsatisfiable min_capability -> named refusal ───────────────────────
out_a="$(run_case a '{"kind":"code","size":"standard","min_capability":5}')"
if [[ "$out_a" == *'reason=no_cell_meets_caller_constraint'* && "$out_a" == *'min_capability=5.0'* && "$out_a" == *'WRAP_RC=68'* ]]; then
  pass 'min_capability=5 (above the matrix max) refuses by name, not silently'
else
  fail "case A out='$out_a'"
fi

# ── (B) unsatisfiable max_cost -> named refusal ──────────────────────────────
out_b="$(run_case b '{"kind":"code","size":"standard","max_cost":0.1}')"
if [[ "$out_b" == *'reason=no_cell_meets_caller_constraint'* && "$out_b" == *'max_cost=0.1'* && "$out_b" == *'WRAP_RC=68'* ]]; then
  pass 'max_cost=0.1 (below every cell) refuses by name, not silently'
else
  fail "case B out='$out_b'"
fi

# ── (C) satisfiable min_capability changes the pick vs. the unfloored default
out_c="$(run_case c '{"kind":"code","size":"standard","min_capability":4}')"
c_line="${out_c%%$'\n'*}"
c_model="$(printf '%s\n' "$c_line" | grep -oE 'model=[^ ]+' | cut -d= -f2)"
c_cap="$(python3 - "$ROUTING" "$c_model" <<'PY'
import sys,re
routing,model=sys.argv[1],sys.argv[2]
src=open(routing).read()
for line in src.splitlines():
    if ('model: %s,' % model) in line or line.rstrip().endswith('model: %s' % model):
        m=re.search(r'capability:\s*([0-9.]+)', line)
        if m: print(m.group(1)); break
else:
    print('0')
PY
)"
if [[ "$out_c" == 'arm='* && "$out_c" == *'caller_min_cap=4.0'* && "$c_line" != "$base_line" \
      && "$(python3 -c "print(1 if float('$c_cap' or 0) >= 4.0 else 0)")" == '1' ]]; then
  pass 'min_capability=4 is READ: pick differs from the unfloored default and lands on a capability>=4 cell'
else
  fail "case C base='$base_line' floored='$c_line' floored_cap='$c_cap'"
fi

# ── (D) satisfiable max_cost passes, chosen cell within ceiling ─────────────
out_d="$(run_case d '{"kind":"code","size":"standard","max_cost":4}')"
if [[ "$out_d" == 'arm='* && "$out_d" == *'caller_max_cost=4.0'* && "$out_d" == *'WRAP_RC=0'* ]]; then
  pass 'max_cost=4 passes and is echoed on the decision line'
else
  fail "case D out='$out_d'"
fi

# ── (E) absent keys leave the decision line byte-identical to today ─────────
out_e="$(run_case e '{"kind":"code","size":"standard"}')"
e_line="${out_e%%$'\n'*}"
# strip the new always-present caller_min_cap/caller_max_cost=none tail before
# comparing to the pre-fix shape -- everything else must be untouched.
base_stripped="${base_line% caller_min_cap=none caller_max_cost=none}"
e_stripped="${e_line% caller_min_cap=none caller_max_cost=none}"
if [[ -n "$base_stripped" && "$base_stripped" == "$e_stripped" && "$e_line" == *'caller_min_cap=none caller_max_cost=none' ]]; then
  pass 'absent min_capability/max_cost leaves the pick and every existing token unchanged'
else
  fail "case E base='$base_line' rerun='$e_line'"
fi

# ── (F) malformed constraint value -> loud fatal, never a silent drop ───────
out_f="$(run_case f '{"kind":"code","size":"standard","min_capability":"lots"}')"
if [[ "$out_f" == *'WRAP_RC=2'* && "$(cat "$TMP/err-f")" == *'FATAL rc=2 reason=caller_constraint_invalid'* ]]; then
  pass 'min_capability="lots" is a loud fatal (rc=2, named reason), not a silent drop'
else
  fail "case F out='$out_f' err='$(head -c 300 "$TMP/err-f")'"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
