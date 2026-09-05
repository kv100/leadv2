#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# SMART-ARBITER-01: this suite had NO trigger line, so a leadv2-route-arbiter.sh
# change selected every OTHER arbiter suite (effort-routing, quota-reset,
# symlink-install all declare the trigger) except its own primary suite.
# run-all-triggers: leadv2-route-arbiter leadv2-routing.yaml leadv2-dispatch-code.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh"
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
run(){ LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" ROUTE_TEST_QUOTA="$1" ROUTE_TEST_FREE_RC="${2:-0}" bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$3"; }

# (a) Codex capped: a capable non-Codex worker is selected, never parked.
# GLM-53-FLASH-ARM-01: glm-flash (cost 0.4) is the expected winner among the
# healthy glm-family arms now — glm/glm-flash/sonnet all satisfy the invariant.
out="$(run "$(quota 10 99 20)" 1 '{"kind":"code","size":"standard"}')"
if [[ "$out" == *'arm=glm '* || "$out" == *'arm=glm-flash '* || "$out" == *'arm=sonnet '* ]]; then pass 'codex 99% routes to a capable non-codex arm'; else fail "codex 99% output=$out"; fi

# (b) all windows capped (and freepool health down) gives the honest refusal.
# ARBITER-REMEMBERS-FAILURES-01 edit B: this case is only meaningful when all
# three arms are genuinely MEASURED and over ceiling. It used to pass with an
# unmeasured claude (see the quota() note above), which made it indistinguishable
# from the probe-outage case now covered by test-route-arbiter-failure-memory.sh
# case (b2) -- there the same refusal is the bug, not the invariant.
out="$(run "$(quota 99 99 99)" 1 '{"kind":"code","size":"standard"}' || true)"
if [[ "$out" == *'arm=refuse '* && "$out" == *'reason=all_arms_capped'* && "$out" != *'probe_outage='* ]]; then pass 'all capped (all three MEASURED) refuses all_arms_capped'; else fail "all capped output=$out"; fi

# (c) protected tasks cannot enter an UNTRUSTED arm. Which arms are untrusted is
#     policy, and the policy changed: GLM-DOES-ANY-WORK-01 (founder, 2026-09-04)
#     grants glm every kind of work in every repo, review included, so glm is a
#     trusted arm now and MUST appear on a protected path. freepool is untouched
#     and must still be excluded -- that is what keeps this case an assertion
#     rather than a formality. Asserting glm's presence (not merely freepool's
#     absence) is deliberate: a bug that dropped glm from the chain again would
#     otherwise pass this test silently, which is exactly how the old wiring hid
#     for months while sonnet was journalled `reason=cheapest_capable` at cost 5.
out="$(run "$(quota 1 1 1)" 0 '{"kind":"code","size":"standard","protected":true}')"
chain="$(printf '%s\n' "$out" | sed -n 's/.*chain=\([^ ]*\).*/\1/p')"
if [[ "$out" != *'arm=freepool '* && ",${chain}," != *',freepool,'* && ",${chain}," == *',glm,'* ]]; then pass 'protected chain excludes freepool and admits glm'; else fail "protected output=$out"; fi

# (d) Anti-stickiness: fixed live readings still rotate equal-cost arms.
# GLM-53-FLASH-ARM-01: size=standard now has a uniquely-cheapest arm
# (glm-flash, cost 0.4) with no equal-price alternative, so rotation there is
# structurally gone — by design, cost policy wins over rotation. The rotation
# invariant itself is unchanged and still tested on the size=bulk cell, where
# glm (cost 1) and freepool (cost 1) remain equal-priced competitors and
# glm-flash is not capable (sizes stop at standard).
rm -f "$TMP/state"
one="$(run "$(quota 70 20 20)" 0 '{"kind":"code","size":"bulk"}')"
two="$(run "$(quota 70 20 20)" 0 '{"kind":"code","size":"bulk"}')"
three="$(run "$(quota 70 20 20)" 0 '{"kind":"code","size":"bulk"}')"
arms="$(printf '%s\n%s\n%s\n' "$one" "$two" "$three" | sed -n 's/.*arm=\([^ ]*\).*/\1/p' | sort -u | wc -l | tr -d ' ')"
if [[ "$arms" -gt 1 ]]; then pass 'anti-sticky identical tasks rotate arms'; else fail "anti-sticky outputs=$one | $two | $three"; fi
# (d2) And the standard cell is deterministic-cheap, not sticky: glm-flash
# wins every time BECAUSE it is cheapest, never because it ran last.
rm -f "$TMP/state"
s1="$(run "$(quota 70 20 20)" 0 '{"kind":"code","size":"standard"}')"
s2="$(run "$(quota 70 20 20)" 0 '{"kind":"code","size":"standard"}')"
if [[ "$s1" == *'arm=glm-flash '* && "$s2" == *'arm=glm-flash '* ]]; then pass 'standard cell deterministically picks glm-flash (cost, not stickiness)'; else fail "standard-cell outputs=$s1 | $s2"; fi

# (e) The dispatcher must retain the ladder when its arbiter file is absent.
REPO="$TMP/repo"; mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2"
git -C "$REPO" init -q -b main; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
touch "$REPO/seed"; git -C "$REPO" add seed; git -C "$REPO" commit -qm seed
WORKER="$TMP/worker.sh"; printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' >"$WORKER"; chmod +x "$WORKER"
out="$(CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" LEADV2_DISPATCH_CACHE_DIR="$TMP/cache" LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" LEADV2_ROUTE_ARBITER_LIB="$TMP/deleted-route-arbiter.sh" GLM_POLICY_RESOLVER="$TMP/missing.py" bash "$SCRIPTS_DIR/leadv2-dispatch-code.sh" 'fallback test' --kind code --protected --no-spawn --writes src/x.py 2>&1 || true)"
if [[ "$out" == *'arbiter_broken'* && "$out" == *'route_resolved'* ]]; then pass 'missing arbiter falls open to ladder and dispatch resolves'; else fail "fallback output=$out"; fi

# (f) T17 C1: an out-of-vocabulary --kind (the real caller values
# fanout-class-funnel/backlog-pump are now first-class matrix entries, so use
# a value no caller sends at all) normalizes to `code` and resolves an arm
# instead of refusing with no_capable_cell.
out="$(run "$(quota 10 20 20)" 0 '{"kind":"some-future-caller-kind","size":"standard"}')"
if [[ "$out" == *'arm='* && "$out" != *'arm=refuse'* ]]; then pass 'unknown --kind normalizes to code and resolves'; else fail "unknown-kind output=$out"; fi

# (f2) T17 C1: the real fanout-class-funnel/backlog-pump vocabulary resolves
# directly (matrix rows added in config/leadv2-routing.yaml), not merely via
# the code-normalization fallback above.
out="$(run "$(quota 10 20 20)" 0 '{"kind":"fanout-class-funnel","size":"bulk"}')"
if [[ "$out" == *'arm='* && "$out" != *'arm=refuse'* ]]; then pass 'fanout-class-funnel kind resolves an arm'; else fail "fanout-class-funnel output=$out"; fi
out="$(run "$(quota 10 20 20)" 0 '{"kind":"backlog-pump","size":"bulk"}')"
if [[ "$out" == *'arm='* && "$out" != *'arm=refuse'* ]]; then pass 'backlog-pump kind resolves an arm'; else fail "backlog-pump output=$out"; fi

# (g) T17 C3: a provider whose quota probe reports status != 'ok' must be
# fail-CLOSED (pessimistic, never selected as the "cheapest" arm) even though
# every OTHER capable provider looks worse on paper. freepool is disabled
# here (free_rc=1) so it cannot tie-break glm out of the picture on cost --
# without that, glm's own cost=1 vs freepool's cost=1 tie (broken by arm-name
# sort) would mask the mutation this case exists to catch. With freepool
# capped, glm competes against codex(20%)/claude(20%) only: if the broken
# probe were still scored optimistic (the pre-fix util()=0.0 on status!=ok),
# glm's cost=1 would win outright and this case would go red.
quota_broken_glm(){ python3 - "$1" "$2" <<'PY'
import json,sys
c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'error'},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
out="$(run "$(quota_broken_glm 20 20)" 1 '{"kind":"code","size":"standard"}')"
# GLM-53-FLASH-ARM-01: glm-flash shares the glm provider, so a broken glm probe
# must bench BOTH glm arms — assert neither is picked.
if [[ "$out" != *'arm=glm '* && "$out" != *'arm=glm-flash '* && "$out" == *'util_glm=unknown_capped'* ]]; then pass 'broken glm probe (status!=ok) is fail-closed, never selected'; else fail "broken-glm-probe output=$out"; fi

# (h) ARBITER-DECISION-LOGIC-CENSUS-01: the `active` flag on an anthropic
# account names which credential the session resolved to, not that its probe
# succeeded. A broken (status!='ok', all-null pct) active-flagged account
# sitting next to a DIFFERENT, non-active account for the SAME account_label
# that carries real, live pct must resolve to the real pct -- never the
# optimistic pct=0 the old code produced by reading only the active-flagged
# row's (null) fields.
quota_broken_active_claude(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,real=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},
                   'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},
                   'anthropic':{'status':'ok','accounts':[
                     {'active':True,'account_label':'max_20x','status':'unknown'},
                     {'active':False,'account_label':'max_20x','status':'ok','five_hour_pct':real,'seven_day_pct':real}]}}))
PY
}
out="$(run "$(quota_broken_active_claude 10 10 72)" 0 '{"kind":"code","size":"standard","protected":true}')"
if [[ "$out" == *'util_claude=72'* ]]; then pass 'broken-active claude account falls back to the real ok account, not pct=0'; else fail "broken-active-claude output=$out"; fi

# ── (g) DISPATCH-FAILS-OPEN-ON-NO-CAPABLE-CELL-01 ────────────────────────────
# The fail-open itself is deliberate (leadv2-dispatch-code.sh:8141 — a routing
# config vocabulary gap must not become a hard refusal) and is NOT what this
# case pins. What it pins is that the fail-open stops being SILENT.
#
# Measured 2026-09-05 over every lane journal in this repo: rc=68 fired 4 times
# (one task, 2026-09-04T19:58..09-05T00:33, 2 of them reaching a spawn), and in
# none of them was the missing capability recoverable afterwards — the boundary
# journalled the rc alone while the arbiter's own line said
# `reason=no_capable_cell`. The route that followed was an ordinary-looking
# `route_resolved by=router`, so the share of work taking this path could not be
# counted at all.
#
# Forcing a REAL rc=68: keep the ladder as shipped, and cut capability_matrix
# down to a cell no dispatchable ladder arm can match. The dispatcher sends its
# own post-filter chain as allowed_arms; the arbiter intersects that with the
# matrix; an empty intersection is exactly no_capable_cell.
G_REPO="$TMP/repo-g"; mkdir -p "$G_REPO/.claude/ref" "$G_REPO/docs/leadv2"
git -C "$G_REPO" init -q -b main; git -C "$G_REPO" config user.email t@t; git -C "$G_REPO" config user.name t
touch "$G_REPO/seed"; git -C "$G_REPO" add seed; git -C "$G_REPO" commit -qm seed
python3 - "$ROUTING" "$G_REPO/.claude/ref/leadv2-routing.yaml" <<'PY' || { fail "(g) fixture: could not build the empty-intersection routing yaml"; }
import sys, yaml
src, dst = sys.argv[1], sys.argv[2]
with open(src) as fh:
    data = yaml.safe_load(fh)
cells = data.get('router_v2', {}).get('capability_matrix')
if not cells:
    sys.exit("FIXTURE PRECONDITION GONE: router_v2.capability_matrix is empty or "
             "absent in leadv2-routing.yaml -- re-anchor this case, do not silence it")
# `haiku` is review-only and never dispatchable as a build arm, so no ladder
# candidate can intersect with it. Synthesised, not filtered, so the case does
# not depend on haiku having a cell today.
keep = dict(cells[0])
keep.update({'arm': 'haiku', 'provider': 'anthropic', 'model': 'haiku'})
data['router_v2']['capability_matrix'] = [keep]
with open(dst, 'w') as fh:
    yaml.safe_dump(data, fh)
PY
G_WORKER="$TMP/worker-g.sh"; printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' >"$G_WORKER"; chmod +x "$G_WORKER"

run_g() {  # <dispatch-bin> <tag> -> stdout+journal of one --no-spawn dispatch
  # Each call claims its OWN write path. `--writes src/x.py` (this file's
  # habit elsewhere) is refused before routing is reached:
  #   dispatch_refused reason=writeset_overlap blocked_by=dispatch-<other>
  # because the overlap guard reads a registry OUTSIDE the fixture repo, so a
  # row left by an earlier case -- or by a real lane on this machine -- wins.
  # Measured 2026-09-05: that refusal, not the routing config, was why this
  # case saw no rc=68 at all.
  #
  # And the cut-down matrix only reaches the ARBITER through
  # LEADV2_ROUTE_ARBITER_ROUTING_YAML. leadv2-route-arbiter.sh:52 defaults to
  # the PLUGIN's own config/leadv2-routing.yaml and never reads
  # $PROJECT_ROOT/.claude/ref/leadv2-routing.yaml -- that per-repo file is the
  # DISPATCHER's ladder source (see test-arm-capability-honoured). Two readers,
  # two files, one filename: without this seam the fixture yaml is inert and the
  # probe resolves arm=sonnet off the REAL matrix, with live util numbers.
  # cwd MUST be inside $G_REPO: the foreign-project-root guard
  # (FOREIGN-PROJECT-ROOT-GUARD-01) compares the env root against the
  # cwd-derived git root and, when they differ, re-roots to CWD — so a dispatch
  # launched from the real checkout silently reads the REAL routing yaml and the
  # fixture's empty intersection never happens. Measured here: without the cd,
  # this case failed with "WARN: foreign project root detected" and no rc=68 at
  # all. The same trap is documented in test-plugin-papercuts.sh's e2e_setup.
  ( cd "$G_REPO" && \
  CLAUDE_PROJECT_ROOT="$G_REPO" LEADV2_PROJECT_ROOT="$G_REPO" \
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$G_REPO/.claude/ref/leadv2-routing.yaml" \
  LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-g$2" LEADV2_DISPATCH_E2E_GATE=0 \
  LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_REQUIRE_PHASES=0 LEADV2_DISPATCH_SUBSESSION_BIN="$G_WORKER" \
  bash "$1" "no-capable-cell probe $2" --kind code --no-spawn --writes "src/no-capable-cell-$2.py" 2>&1 || true )
}

g_out="$(run_g "$SCRIPTS_DIR/leadv2-dispatch-code.sh" 1)"
g_green_held=1
# PRESENCE, not absence: the line must appear and must NAME the missing thing.
if printf '%s\n' "$g_out" | grep -q 'arbiter_broken .*rc=68 .*arb_reason=no_capable_cell'; then
  pass '(g) rc=68 fail-open journals the arbiter reason by name'
else
  g_green_held=0
  fail "(g) rc=68 fail-open did not name its reason" "$(printf '%s\n' "$g_out" | grep -m1 'arbiter_broken' || echo '<no arbiter_broken line at all — the fixture did not reach a fail-open>')"
fi
if printf '%s\n' "$g_out" | grep -q 'route_resolved .*after=fail_open'; then
  pass '(g) the route produced by a fail-open is marked and can be counted'
else
  g_green_held=0
  fail "(g) route_resolved carries no after=fail_open marker" "$(printf '%s\n' "$g_out" | grep -m1 'route_resolved' || echo '<no route_resolved>')"
fi

# (g-red) DECLARED NEGATIVE CONTROL, run here rather than once by hand: strip
# the detail from the emit in a THROWAWAY copy and both assertions above must
# stop holding. Anchored on the smallest fragment that carries the meaning, and
# a zero match is a hard failure — a control that cannot find its anchor must be
# loud, never a silent pass.
G_MUT_ROOT="$TMP/mutated-g"; mkdir -p "$G_MUT_ROOT"
cp -R "$SCRIPTS_DIR" "$G_MUT_ROOT/scripts"
G_MUT_BIN="$G_MUT_ROOT/scripts/leadv2-dispatch-code.sh"
g_mut_rc=0
python3 - "$G_MUT_BIN" <<'PY' || g_mut_rc=$?
import sys
p = sys.argv[1]; s = open(p).read()
anchor = '_ROUTE_FAIL_OPEN=" after=fail_open arb_rc=${_arb_rc} ${_arb_fault_fail_open_to_ladder}"'
n = s.count(anchor)
if n != 1:
    sys.exit('mutation anchor found %d times (expected 1) -- the fail-open marker '
             'moved or was renamed; re-anchor this control, do not silence it' % n)
s = s.replace(anchor, '_ROUTE_FAIL_OPEN=""')
s = s.replace('reason=fail_open_to_ladder ${_arb_fault_fail_open_to_ladder}"',
              'reason=fail_open_to_ladder"')
open(p, 'w').write(s)
PY
if [[ ${g_mut_rc} -ne 0 ]]; then
  fail "(g-red) mutation anchor not found — control cannot be proven" "zero-match"
else
  g_red="$(run_g "$G_MUT_BIN" 2)"
  if printf '%s\n' "$g_red" | grep -q 'arb_reason=no_capable_cell' \
     || printf '%s\n' "$g_red" | grep -q 'after=fail_open'; then
    fail "(g-red) mutation did not flip the outcome — the control is not falsifiable" "$(printf '%s\n' "$g_red" | grep -m1 'arbiter_broken')"
  elif [[ "${g_green_held}" != "1" ]]; then
    # Absence proves nothing when the thing was never present: with a broken
    # fixture the mutated run shows nothing either, and this case would pass for
    # the wrong reason. Measured 2026-09-05, first run of this case.
    fail "(g-red) control NOT EVALUATED — the green half did not hold, so the mutation had nothing to remove" "fix (g) first"
  else
    pass '(g-red) with the detail stripped, both the reason and the marker disappear'
  fi
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
