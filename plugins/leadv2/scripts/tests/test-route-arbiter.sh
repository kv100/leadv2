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
# TEST-ROUTE-ARBITER-CASE-E-RED-ON-MAIN-01: this case was red on main from
# 2026-08-30 to 2026-09-05 and the failure named no cause. Pointing
# LEADV2_ROUTE_ARBITER_LIB at a deleted path stopped making the arbiter absent
# when df19ece6 added a structural guard that falls back to the CANONICAL
# checkout -- so the real arbiter loaded, `arbiter_broken` was never emitted, and
# the case asserted a state it could no longer produce. Measured 2026-09-05: of
# the two tokens it requires, route_resolved was present and arbiter_broken was
# not; the working directory changed only which noise preceded that same verdict.
# LEADV2_CANONICAL_ROOT is pinned into the fixture so the fallback misses too.
REPO="$TMP/repo"; mkdir -p "$REPO/.claude/ref" "$REPO/docs/leadv2"
git -C "$REPO" init -q -b main; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
touch "$REPO/seed"; git -C "$REPO" add seed; git -C "$REPO" commit -qm seed
WORKER="$TMP/worker.sh"; printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' >"$WORKER"; chmod +x "$WORKER"
out="$(CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" LEADV2_DISPATCH_CACHE_DIR="$TMP/cache" LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" LEADV2_ROUTE_ARBITER_LIB="$TMP/deleted-route-arbiter.sh" LEADV2_CANONICAL_ROOT="$TMP/no-canonical" GLM_POLICY_RESOLVER="$TMP/missing.py" bash "$SCRIPTS_DIR/leadv2-dispatch-code.sh" 'fallback test' --kind code --protected --no-spawn --writes src/x.py 2>&1 || true)"
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

# (g2) ARBITER-UNKNOWN-BECOMES-A-DEFAULT-IN-FIVE-DECISIONS-01: the OTHER shape of
# the same not-knowing. Here the probe says status='ok' -- it answered -- but not
# one window carries a number. util() walked its windows, found no pct, and took
# the `empty` early return: pct=0.0 with unknown=FALSE, i.e. "glm is completely
# free and we are sure". Two sibling exits of that same function (status!=ok, and
# no ok anthropic account) already returned pct=100 unknown=True; this third one
# disagreed with them. Same fixture shape as (g) on purpose, so the only variable
# between the two cases is WHICH kind of silence the probe returned.
quota_null_windows_glm(){ python3 - "$1" "$2" <<'PY'
import json,sys
c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':None},'weekly':{'pct':None}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok','five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
out="$(run "$(quota_null_windows_glm 20 20)" 1 '{"kind":"code","size":"standard"}')"
if [[ "$out" != *'arm=glm '* && "$out" != *'arm=glm-flash '* && "$out" == *'util_glm=unknown_capped'* ]]; then pass 'answering probe with no numbers reads unknown, not free'; else fail "null-windows-glm output=$out"; fi

# (g3) ARBITER-UNKNOWN-BECOMES-A-DEFAULT-IN-FIVE-DECISIONS-01 (D5): an
# unrecognised work_kind is coerced to 'code' so routing still happens -- but the
# decision line then prints kind=code, and a wrong value that looks right cannot
# be found in the journal afterwards. Live case, not hypothetical:
# leadv2-task-judge.sh:200 emits work_kind='diagnose' and 'diagnose' is not in
# KNOWN_KINDS. The coercion stays (fail-open); what must be true is that it is
# NAMED. Control pair: 'code' itself must NOT carry the token, or the assertion
# would pass on a line that always prints it.
out="$(run "$(quota 10 20 20)" 1 '{"work_kind":"diagnose","size":"standard","task":"t"}')"
ctl="$(run "$(quota 10 20 20)" 1 '{"work_kind":"code","size":"standard","task":"t"}')"
if [[ "$out" == *'kind_unmapped=diagnose'* && "$ctl" != *'kind_unmapped='* ]]; then pass 'coerced work_kind is named on the decision line, and a known kind is not'; else fail "kind-unmapped out=$out ctl=$ctl"; fi

# (g4) D14: one window readable, the other not. util() takes the worst of what it
# could READ and prints that as the provider's headroom, so `util_glm=10` may mean
# "10% used" or "10% used and the weekly window was never consulted". Skipping an
# unreadable window is right (refusing on it would bench a provider we can partly
# see); being silent about it is not. Control: both windows readable must NOT
# carry the token.
quota_partial_glm(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=sys.argv[1:]
wk=None if g=='null' else int(g)
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':10},'weekly':{'pct':wk}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':int(c)}]},'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok','five_hour_pct':int(a),'seven_day_pct':int(a)}]}}))
PY
}
out="$(run "$(quota_partial_glm null 20 20)" 1 '{"work_kind":"code","size":"standard","task":"t"}')"
ctl="$(run "$(quota_partial_glm 10 20 20)" 1 '{"work_kind":"code","size":"standard","task":"t"}')"
if [[ "$out" == *'partial_windows=glm:weekly'* && "$ctl" != *'partial_windows='* ]]; then pass 'headroom read from only some windows says so'; else fail "partial-windows out=$out ctl=$ctl"; fi

# (g5) D16: quota_ceilings configures glm/codex/claude only, while the capability
# matrix also carries freepool/kimi/anthropic/ordinary. over_ceiling() defaults an
# unconfigured provider to 100, i.e. it can NEVER be capped -- a favourable
# default nobody chose. The default stays (inventing a ceiling would bench a
# provider on no evidence); the winner riding one is named. Control: a glm win
# (configured ceiling) must NOT carry the token.
out="$(run "$(quota 10 20 20)" 0 '{"work_kind":"recon","size":"standard","task":"t"}')"
ctl="$(run "$(quota 10 20 20)" 1 '{"work_kind":"code","size":"standard","task":"t"}')"
if [[ "$out" == *'ceiling_default=freepool'* && "$ctl" != *'ceiling_default='* ]]; then pass 'a winner with no configured ceiling is named'; else fail "ceiling-default out=$out ctl=$ctl"; fi

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


# (g6) ARBITER-QUOTA-IS-A-CLIFF-NOT-A-GRADIENT-01: every other case in this suite
# asserts what the arbiter SAYS; this one asserts what it CHOOSES, because the
# headroom gradient is the only thing in this file that moves the winner. Quota
# used to be a cliff -- under the ceiling arms competed on cost alone, over it the
# arm vanished -- so two providers at the SAME utilisation were indistinguishable
# however differently fast they were burning down. Here glm is capped at 99
# (excluded by its ceiling, no probe-unknown involved), freepool is down, and
# codex and claude sit at the SAME 20% used: the cliff has nothing to separate
# them and cost alone always picks codex (3) over sonnet (5). The ONLY variable
# between the two runs is codex's remaining percentage-points per HOUR -- 20/h
# (weight 1.0, cost stays 3) vs 0.5/h (weight 0.4 from router_v2.headroom_weights,
# cost 3/0.4 = 7.5 > 5).
# The control is the point of the case, not decoration: at equal headroom the
# choice must be the OLD one and the line must carry NO headroom_priced= token,
# or what we built is a bias against codex rather than a gradient.
quota_headroom(){ python3 - "$1" "$2" <<'PY'
import json,sys
cx_un,cl_un=map(float,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':99},'weekly':{'pct':99}},
                  'codex':{'status':'ok','binding_window':'primary',
                           'windows':[{'kind':'primary','used_percent':20,'usable_now':cx_un}]},
                  'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok',
                           'five_hour':{'pct':20,'usable_now':cl_un},
                           'seven_day':{'pct':20,'usable_now':cl_un}}]}}))
PY
}
starve="$(run "$(quota_headroom 0.5 20)" 1 '{"work_kind":"code","size":"standard","task":"t"}')"
plenty="$(run "$(quota_headroom 20 20)" 1 '{"work_kind":"code","size":"standard","task":"t"}')"
if [[ "$starve" == *'arm=sonnet '* && "$starve" == *'headroom_priced=codex:0.4'* \
      && "$plenty" == *'arm=codex '* && "$plenty" != *'headroom_priced='* ]]; then
  pass 'equal ceilings, different runway: the arm with hours left wins, and the price is named'
else
  fail "headroom-gradient starve=$starve plenty=$plenty"
fi

# (g6-off) the rollback is one flag and it is proven, not asserted: with the
# gradient off the starving fixture must go back to picking codex on raw cost.
# Without this, "rollback is one step" would be a claim about a flag nobody ran.
starve_off="$(LEADV2_ARBITER_HEADROOM_GRADIENT=0 run "$(quota_headroom 0.5 20)" 1 '{"work_kind":"code","size":"standard","task":"t"}')"
if [[ "$starve_off" == *'arm=codex '* && "$starve_off" != *'headroom_'* ]]; then
  pass 'LEADV2_ARBITER_HEADROOM_GRADIENT=0 restores the cliff in one flag'
else
  fail "headroom-killswitch starve_off=$starve_off"
fi


# (s1) ROUTE-ARBITER-DIES-SILENTLY-ON-LINUX-01: four input loads shared one
# `except Exception: raise SystemExit(2)`, and a bare SystemExit(int) prints
# nothing — rc=2 with zero bytes on stdout AND stderr, indistinguishable from a
# crash, a missing interpreter or a refusal. Measured on real linux 2026-09-05
# (python:3.11-slim, no PyYAML): before, rc=2 stderr_bytes=0; after, rc=2
# stderr_bytes=207 naming pyyaml_missing. With PyYAML installed the SAME call on
# the SAME linux returns rc=0 and a 552-byte route line, so the platform half of
# that row is refuted: it is a dependency, not a platform bug.
# Here the reachable-on-macOS half of the same guard is asserted: an unreadable
# routing yaml. Control: a healthy run must print no FATAL at all.
fatal_out="$(LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/no-such-routing.yaml" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-fatal" ROUTE_TEST_QUOTA="$(quota 10 20 20)" ROUTE_TEST_FREE_RC=1 \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" '{"kind":"code","size":"standard"}' 2>&1 || true)"
ok_out="$(run "$(quota 10 20 20)" 1 '{"kind":"code","size":"standard"}' 2>&1)"
# rc is 65 here, not 2: the mute exit the row named was python's SystemExit(2),
# but measuring it turned up four MORE mute exits in the bash preconditions, and
# an unreadable routing yaml is caught by that half first (return 65). The codes
# are deliberately unchanged -- callers journal them as arbiter_broken rc=<n>;
# only the silence is gone. My first version of this assertion said rc=2 and
# failed against a correct product line.
if [[ "$fatal_out" == *'FATAL rc=65 reason=routing_yaml_unreadable'* && "$ok_out" != *'FATAL'* ]]; then
  pass 'an unreadable input names itself instead of exiting mute'
else
  fail "silent-exit fatal=$fatal_out ok=$ok_out"
fi

# (s2) TEST-ROUTE-ARBITER-CASE-E-RED-ON-MAIN-01, the product half. When the
# resolved arbiter path does not exist, leadv2-dispatch-code.sh falls back to the
# CANONICAL checkout (df19ece6, 2026-08-30). That is right — a consumer repo with
# a broken symlink still routes — but it was mute, so a broken install and a
# healthy one produced byte-identical output, and case (e) above went red for six
# days with its failure naming no cause. Control: an untouched run resolves its
# own arbiter and must NOT claim a substitution.
sub_out="$(CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-sub" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" LEADV2_ROUTE_ARBITER_LIB="$TMP/deleted-route-arbiter.sh" \
  bash "$SCRIPTS_DIR/leadv2-dispatch-code.sh" 'substitution test' --kind code --no-spawn --writes src/x.py 2>&1 || true)"
plain_out="$(CLAUDE_PROJECT_ROOT="$REPO" LEADV2_PROJECT_ROOT="$REPO" LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-plain" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_DISPATCH_SUBSESSION_BIN="$WORKER" \
  bash "$SCRIPTS_DIR/leadv2-dispatch-code.sh" 'plain test' --kind code --no-spawn --writes src/x.py 2>&1 || true)"
if [[ "$sub_out" == *'arbiter_lib_substituted'* && "$plain_out" != *'arbiter_lib_substituted'* ]]; then
  pass 'a dispatcher running someone else'"'"'s arbiter says so'
else
  fail "arbiter-substitution sub=$(printf '%s' "$sub_out" | grep -c arbiter_lib_substituted) plain=$(printf '%s' "$plain_out" | grep -c arbiter_lib_substituted)"
fi


# (g7) GLM-NEVER-WINS-THE-ARBITER-01: a cell that fits kind AND size but is cut by
#      require_trusted must be NAMED. The 2026-09-03 line `arm=sonnet
#      reason=cheapest_capable chain=sonnet util_glm=13` was true and unreadable:
#      the whole glm family had been removed before any price was compared (glm
#      carried protected: false until 2026-09-04), and the line carried no token
#      saying so, which is why the defect was filed against two innocent filters.
#      The fixture pins its OWN matrix rather than the live yaml, so the case
#      keeps measuring the FILTER after a policy flip changes who is trusted.
cat >"$TMP/untrusted-glm.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 80, review_pct: 90}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 90, review_pct: 95}}
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, cost: 1, protected: false, sizes: [standard], kinds: [code]}
    - {arm: sonnet, provider: claude, model: sonnet, cost: 5, protected: true, sizes: [standard], kinds: [code]}
YML
run_y(){ LEADV2_ROUTE_ARBITER_ROUTING_YAML="$1" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" ROUTE_TEST_QUOTA="$2" ROUTE_TEST_FREE_RC=0 bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$3" 2>&1; }
rm -f "$TMP/state"
g7p="$(run_y "$TMP/untrusted-glm.yaml" "$(quota 13 20 45)" '{"kind":"code","size":"standard","protected":true}')"
rm -f "$TMP/state"
g7c="$(run_y "$TMP/untrusted-glm.yaml" "$(quota 13 20 45)" '{"kind":"code","size":"standard"}')"
if [[ "$g7p" == *'arm=sonnet '* && "$g7p" == *'arm_excluded=glm:untrusted'* \
   && "$g7c" == *'arm=glm '* && "$g7c" != *'arm_excluded='* ]]; then
  pass 'a require_trusted cut names the arm it removed (and is silent when nothing was cut)'
else
  fail "arm_excluded protected=$g7p | unprotected=$g7c"
fi

# (g7-gap) The same fact on the refusal line. `no_capable_cell` is read as a
#      routing.yaml vocabulary gap; when a POLICY filter emptied the set instead,
#      the refusal must say which arms it emptied it of, or the accusation lands
#      on the config.
cat >"$TMP/untrusted-only.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 80, review_pct: 90}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 90, review_pct: 95}}
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, cost: 1, protected: false, sizes: [standard], kinds: [code]}
YML
rm -f "$TMP/state"
g7g="$(run_y "$TMP/untrusted-only.yaml" "$(quota 13 20 45)" '{"kind":"code","size":"standard","protected":true}' || true)"
rm -f "$TMP/state"
g7gc="$(run_y "$TMP/untrusted-only.yaml" "$(quota 13 20 45)" '{"kind":"docs","size":"standard","protected":true}' || true)"
if [[ "$g7g" == *'reason=no_capable_cell'* && "$g7g" == *'arm_excluded=glm:untrusted'* \
   && "$g7gc" == *'reason=no_capable_cell'* && "$g7gc" != *'arm_excluded='* ]]; then
  pass 'no_capable_cell separates a policy cut from a real config gap'
else
  fail "no_capable_cell policy=$g7g | vocabulary=$g7gc"
fi


# (g8) SONNET-WON-21-MEASURED-GLM-LINES-ON-0905-01, hole 1: a decision line names
#      no version of anything, so a line cannot be tied to the code or the matrix
#      that produced it. Measured 2026-09-05: 21 live decisions picked sonnet with
#      glm MEASURED at 39-45% under an 80% ceiling, the shape does not reproduce on
#      today's arbiter, and there is no way to learn which arbiter produced them.
#      The digests must MOVE when the bytes move -- an identifier that is constant
#      across different files identifies nothing, so the case pins the change, not
#      the presence.
cat >"$TMP/alt-matrix.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 80, review_pct: 90}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 90, review_pct: 95}}
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, cost: 1, protected: true, sizes: [standard], kinds: [code]}
YML
cp "$ARBITER" "$TMP/alt-arbiter.sh"
printf '\n# a byte that changes the file and nothing else\n' >> "$TMP/alt-arbiter.sh"
revs(){ LEADV2_ROUTE_ARBITER_ROUTING_YAML="$2" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" ROUTE_TEST_QUOTA="$(quota 13 20 45)" ROUTE_TEST_FREE_RC=0 bash -c 'source "$0"; route_arbiter worker "$1"' "$1" '{"kind":"code","size":"standard"}' 2>&1; }
rm -f "$TMP/state"; g8_base="$(revs "$ARBITER" "$ROUTING")"
rm -f "$TMP/state"; g8_alt_m="$(revs "$ARBITER" "$TMP/alt-matrix.yaml")"
rm -f "$TMP/state"; g8_alt_a="$(revs "$TMP/alt-arbiter.sh" "$ROUTING")"
tok(){ printf '%s\n' "$1" | sed -n "s/.*$2=\([0-9a-f]\{12\}\).*/\1/p" | head -1; }
b_a="$(tok "$g8_base" arb_rev)"; b_m="$(tok "$g8_base" matrix_rev)"
m_a="$(tok "$g8_alt_m" arb_rev)"; m_m="$(tok "$g8_alt_m" matrix_rev)"
a_a="$(tok "$g8_alt_a" arb_rev)"
if [[ -n "$b_a" && -n "$b_m" \
   && "$m_m" != "$b_m" && "$m_a" == "$b_a" \
   && "$a_a" != "$b_a" ]]; then
  pass '(g8) the decision line names the arbiter bytes and the matrix bytes, and each moves only with its own file'
else
  fail "(g8) arb_rev/matrix_rev base=$b_a/$b_m alt-matrix=$m_a/$m_m alt-arbiter=$a_a"
fi

# (g8-refuse) The same identity on the refusal path -- and this half is not a
#      formality: the digest is computed once, high up, precisely because
#      _record()/the refusal prints run long before the winner's line is built.
#      A first version of this edit computed it beside the winner tokens and
#      would have raised NameError on every refusal; only a refusal case catches
#      that, because every green path takes the winner branch.
cat >"$TMP/empty-matrix.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 80, review_pct: 90}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 90, review_pct: 95}}
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, cost: 1, protected: true, sizes: [standard], kinds: [docs]}
YML
rm -f "$TMP/state"; g8r="$(revs "$ARBITER" "$TMP/empty-matrix.yaml" || true)"
if [[ "$g8r" == *'reason=no_capable_cell'* && "$g8r" == *"arb_rev=${b_a}"* && "$g8r" != *'Traceback'* ]]; then
  pass '(g8-refuse) a refusal names the same arbiter bytes, and does not die building the token'
else
  fail "(g8-refuse) refusal=$(printf '%s' "$g8r" | tr '\n' ' ' | cut -c1-200)"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
