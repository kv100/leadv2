#!/usr/bin/env bash
# ARBITER-REMEMBERS-FAILURES-01 — the arbiter remembers which arms failed THIS
# task, and stops reading "the probe did not answer" as "the arm is busy".
#
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01).
# run-all-triggers: leadv2-route-arbiter leadv2-routing.yaml
#
# WHAT IS REAL HERE. Every case calls the real route_arbiter() out of
# plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh, with the real
# config/leadv2-routing.yaml. Only the layer BELOW it is faked: the quota-live
# probe (a stub that echoes a JSON fixture) and the two outcome journals (real
# files on disk in $TMP, in the real dispatch-ledger.jsonl / leadv2-events
# formats). Nothing stubs the selection logic under assertion — no
# read_failure_memory, capped, ecost or route_arbiter replacement anywhere.
#
# DECLARED NEGATIVE CONTROLS (mutation-control/, and tests/mutations/catalog.yaml).
# Both are applied by REGEX to a line INSIDE a function body, never by line
# number — a line-number insert lands at top level and reddens every suite for
# the wrong reason, which reads like a pass.
#
#   ARBITER-FAILURE-MEMORY-STOPS-COUNTING
#     in read_failure_memory(): `counts[arm]=counts.get(arm,0)+1` -> `pass`
#     (the ledger-to-arm attribution stops counting). Kills (a1),(a2),(a6).
#
#   ARBITER-UNKNOWN-IS-CAPPED-AGAIN
#     in capped(): delete `if unk.get(provider): return False`
#     (an unmeasured arm is treated as busy again). Kills (b1).
#
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

# quota <glm-pct> <codex-pct> <claude-pct|unknown>
# `unknown` emits an anthropic account with NO status key — the exact shape a
# failed/401 probe produces live, which util() turns into pct=100 + unknown=True.
quota(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=sys.argv[1:]
acct={'active':True,'five_hour_pct':0,'seven_day_pct':0}
if a!='unknown':
    acct={'active':True,'status':'ok','five_hour_pct':int(a),'seven_day_pct':int(a)}
print(json.dumps({
  'glm':{'status':'ok','five_hour':{'pct':int(g)},'weekly':{'pct':int(g)}},
  'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':int(c)}]},
  'anthropic':{'status':'ok','accounts':[acct]}}))
PY
}

# journals <sig> <spec>   spec := "arm:terminal:cause,arm:terminal:cause,..."
# Writes a real events journal (worker_spawned rows carry the arm) and a real
# dispatch ledger (terminal rows carry task_sig+terminal+cause, never an arm) so
# the join under test is the same one it does in production. Timestamps are
# ordered so each ledger row falls after its own spawn.
journals(){ python3 - "$TMP" "$1" "$2" <<'PY'
import json,os,sys
tmp,sig,spec=sys.argv[1],sys.argv[2],sys.argv[3]
ev=[]; led=[]; n=0
for item in [x for x in spec.split(',') if x]:
    arm,terminal,cause=item.split(':')
    n+=1
    ev.append({'seq':n*2,'ts':'2026-09-05T%02d:00:00Z'%n,'repo':'leadv2','task':sig,'arm':arm,
               'handle':'h%d'%n,'kind':'worker_spawned'})
    led.append({'ts':'2026-09-05T%02d:30:00Z'%n,'task_sig':sig,'founder_task_id':'','task_id':'',
                'terminal':terminal,'cause':cause,'evidence':'','commit':'none',
                'deliverable':'unknown','attempt':'%s-%d'%(sig,n),'worker_reason':''})
with open(os.path.join(tmp,'events.jsonl'),'w') as f:
    for r in ev: f.write(json.dumps(r)+'\n')
with open(os.path.join(tmp,'ledger.jsonl'),'w') as f:
    for r in led: f.write(json.dumps(r)+'\n')
PY
}

# run <quota-json> <freepool-rc> <descriptor> [ledger-path] [events-path]
run(){
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
  LEADV2_ROUTE_ARBITER_FAILURE_LEDGER="${4:-$TMP/ledger.jsonl}" \
  LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="${5:-$TMP/events.jsonl}" \
  ROUTE_TEST_QUOTA="$1" ROUTE_TEST_FREE_RC="${2:-0}" \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$3"
}
armof(){ printf '%s\n' "$1" | sed -n 's/^arm=\([^ ]*\).*/\1/p'; }
chainof(){ printf '%s\n' "$1" | sed -n 's/.*[[:space:]]chain=\([^ ]*\).*/\1/p'; }

HEALTHY="$(quota 10 10 10)"

# ---------------------------------------------------------------- edit A -----
# Baseline: with an empty history the arbiter picks whatever it picks. That pick
# is SETUP, not the assertion — the assertion is that the same descriptor stops
# choosing that arm once the arm has failed on it twice. Deriving the baseline
# instead of hardcoding an arm name keeps the case alive across matrix edits.
journals SIGAAAA1 ''
base_out="$(run "$HEALTHY" 0 '{"kind":"code","size":"standard","task":"SIGAAAA1"}')"
base_arm="$(armof "$base_out")"
base_chain="$(chainof "$base_out")"
if [[ -n "$base_arm" && "$base_arm" != refuse && "$base_out" == *'failure_memory=no_history'* ]]; then
  pass "empty history is no_history and still resolves (baseline arm=$base_arm)"
else
  fail "baseline output=$base_out"
fi

# (a1) THE RULE. Same descriptor, same signature; the baseline arm has now
# spawned twice and produced nothing. It must lose its turn to the next arm in
# the chain, and the decision line must say so by name and count.
journals SIGAAAA1 "${base_arm}:no_work:arm_produced_nothing,${base_arm}:no_work:arm_produced_nothing"
out="$(run "$HEALTHY" 0 '{"kind":"code","size":"standard","task":"SIGAAAA1"}')"
got="$(armof "$out")"
if [[ "$got" != "$base_arm" && "$got" != refuse && "$out" == *"failure_banned=${base_arm}:2"* && "$out" == *'failure_memory=ok'* ]]; then
  pass "arm that failed twice on this task is not chosen again (${base_arm} -> ${got})"
else
  fail "twice-failed arm still chosen output=$out"
fi

# (a1b) ...and it is gone from the CHAIN too, not merely from arm=. The spawn
# loop in leadv2-dispatch-code.sh iterates the chain, so an arm left there would
# still be spawned on the very next fallback step.
if [[ ",$(chainof "$out")," != *",${base_arm},"* ]]; then
  pass "banned arm is absent from the candidate chain, not only from arm="
else
  fail "banned arm still in chain=$(chainof "$out") (was $base_chain)"
fi

# (a2) ONE failure is not two. The threshold is a threshold, not a hair trigger.
journals SIGAAAA1 "${base_arm}:no_work:arm_produced_nothing"
out="$(run "$HEALTHY" 0 '{"kind":"code","size":"standard","task":"SIGAAAA1"}')"
if [[ "$(armof "$out")" == "$base_arm" && "$out" == *'failure_memory=ok'* && "$out" != *'failure_banned='* ]]; then
  pass "a single failure does not retire the arm (threshold is 2)"
else
  fail "single failure banned the arm output=$out"
fi

# (a3) THE DISTINCTION THE WHOLE EDIT TURNS ON. Five refusals BEFORE the spawn --
# the registry write-set window, exactly the shape that produced this task's own
# motivating incident -- are not the arm's fault and must not retire it.
journals SIGAAAA1 "${base_arm}:refused:writeset_pending,${base_arm}:refused:writeset_pending,${base_arm}:refused:writeset_conflict,${base_arm}:refused:all_arms_capped,${base_arm}:refused:undiffable_write_set"
out="$(run "$HEALTHY" 0 '{"kind":"code","size":"standard","task":"SIGAAAA1"}')"
if [[ "$(armof "$out")" == "$base_arm" && "$out" == *'failure_memory=no_history'* && "$out" != *'failure_banned='* ]]; then
  pass "pre-spawn refusals (write-set / registry window / capped gate) never ban an arm"
else
  fail "pre-spawn refusal banned a healthy arm output=$out"
fi

# (a4) AN UNREADABLE JOURNAL IS NOT ZERO FAILURES. Nothing is banned (banning on
# no evidence is its own failure mode) but the line must not present the silence
# as a clean record.
out="$(run "$HEALTHY" 0 '{"kind":"code","size":"standard","task":"SIGAAAA1"}' "$TMP/nope/ledger.jsonl" "$TMP/nope/events.jsonl")"
if [[ "$out" == *'failure_memory=unavailable'* && "$(armof "$out")" != refuse && "$out" != *'failure_banned='* ]]; then
  pass "unreadable journal reports unavailable, never a clean zero"
else
  fail "unreadable journal output=$out"
fi

# (a5) A caller that passes no signature (the bench-fallback / exit76 / advisory
# / reviewer descriptors) says so, rather than borrowing another task's memory.
journals SIGAAAA1 "${base_arm}:no_work:arm_produced_nothing,${base_arm}:no_work:arm_produced_nothing"
out="$(run "$HEALTHY" 0 '{"kind":"code","size":"standard"}')"
if [[ "$out" == *'failure_memory=absent_key'* && "$(armof "$out")" == "$base_arm" ]]; then
  pass "descriptor without a task signature is absent_key, routed as before"
else
  fail "absent-key descriptor output=$out"
fi

# (a5b) The memory is per-task, not a global ban: a DIFFERENT signature with the
# same shape still gets the arm that failed on the first one.
out="$(run "$HEALTHY" 0 '{"kind":"code","size":"standard","task":"SIGOTHER9"}')"
if [[ "$(armof "$out")" == "$base_arm" && "$out" == *'failure_memory=no_history'* ]]; then
  pass "the ban is scoped to the failing task signature, not global"
else
  fail "ban leaked to another signature output=$out"
fi

# (a6) Every capable arm is a repeat offender. A memory must not become a
# deadlock: the ban yields, the work is still routed, and the line says the ban
# yielded rather than pretending the record was clean.
allspec=""
IFS=',' read -r -a _chain_arms <<< "$base_chain"
for a in "${_chain_arms[@]}"; do allspec+="${a}:no_work:arm_produced_nothing,${a}:no_work:arm_produced_nothing,"; done
journals SIGAAAA1 "$allspec"
out="$(run "$HEALTHY" 0 '{"kind":"code","size":"standard","task":"SIGAAAA1"}')"
if [[ "$(armof "$out")" != refuse && "$out" == *'failure_memory=exhausted'* ]]; then
  pass "all-arms-banned yields instead of deadlocking (failure_memory=exhausted)"
else
  fail "all-banned output=$out"
fi

# ---------------------------------------------------------------- edit B -----
journals SIGBBBB1 ''

# (b1) THE RULE. glm and codex are genuinely over ceiling; claude's probe did not
# answer at all. Refusing here was the measured production bug -- six lanes died
# on all_arms_capped because the instrument failed, not the quota. The unmeasured
# arm must be selectable, and named as an outage rather than as 100% busy.
out="$(run "$(quota 99 99 unknown)" 1 '{"kind":"code","size":"standard","task":"SIGBBBB1"}' || true)"
if [[ "$(armof "$out")" != refuse && "$out" == *'probe_outage=claude'* && "$out" != *'reason=all_arms_capped'* ]]; then
  pass "a failed probe does not read as a capped arm (probe_outage named, work still routed)"
else
  fail "probe outage still refused output=$out"
fi

# (b2) The opposite direction, so (b1) cannot be satisfied by simply never
# refusing: three MEASURED arms over their ceilings still produce the honest
# refusal, and no outage is claimed.
out="$(run "$(quota 99 99 99)" 1 '{"kind":"code","size":"standard","task":"SIGBBBB1"}' || true)"
if [[ "$(armof "$out")" == refuse && "$out" == *'reason=all_arms_capped'* && "$out" != *'probe_outage='* ]]; then
  pass "three measured over-ceiling arms still refuse all_arms_capped"
else
  fail "measured all-capped stopped refusing output=$out"
fi

# (b3) Unknown is demoted, not preferred. With claude unmeasured and glm healthy
# and cheap, the measured arm must win — otherwise "unknown is not capped" would
# have turned into "unknown is free".
out="$(run "$(quota 5 5 unknown)" 0 '{"kind":"code","size":"standard","task":"SIGBBBB1"}')"
got="$(armof "$out")"
if [[ "$got" != refuse && "$got" != sonnet && "$out" == *'probe_outage=claude'* ]]; then
  pass "an unmeasured arm is demoted behind every measured one (won: $got)"
else
  fail "unmeasured arm was not demoted output=$out"
fi


# ---- TERMINALIZER-DOES-NOT-RECORD-A-SILENT-DEATH-01, both halves -------------
# The row was filed as "the failure memory cannot see a silent death". Measured
# on the live ledger (1374 rows, 2026-09-05) it is two separate holes, and the
# memory answers `no_history` -- indistinguishable from a clean record -- in both.
#
#  (fm1) A death the VOCABULARY has no name for. arm_failure_causes is a
#        hand-kept list; 305 real rows carry a terminal it does not name
#        (dead:e2e_regression 215, dead:all_arms_unavailable 75, review failures
#        14), while dead:worker_died_with_session -- one of the eight names in
#        the list -- has exactly ONE row in all 1374. Whether a given cause
#        SHOULD count is a vocabulary decision and lives in the yaml; that the
#        skip is silent is this file's problem.
#  (fm2) A spawn with no terminal row at all -- the defect exactly as filed.
#        Signature b5abfcfd, 2026-09-04: glm spawned, and all 24 ledger rows for
#        that signature are refused:* from BEFORE the spawn, which by
#        construction are not the arm's fault. The token does NOT claim death (a
#        spawn with no terminal may still be running); it reports the fact.
#
# Both cases carry a control on the SAME shape without the condition, because an
# assertion on a token that a line always prints proves nothing.

# journals_open <sig> <arm>[,<arm>...] -- spawns with NO terminal row at all,
# plus refusals that predate them, i.e. the b5abfcfd shape.
journals_open(){ python3 - "$TMP" "$1" "$2" <<'PY'
import json,os,sys
tmp,sig,arms=sys.argv[1],sys.argv[2],sys.argv[3]
ev=[]; led=[]
for i,arm in enumerate([a for a in arms.split(',') if a], start=1):
    ev.append({'seq':i,'ts':'2026-09-05T%02d:00:00Z'%(i+5),'repo':'leadv2','task':sig,'arm':arm,
               'handle':'h%d'%i,'kind':'worker_spawned'})
    # a refusal recorded BEFORE the spawn: present in the ledger, never the arm's fault
    led.append({'ts':'2026-09-05T0%d:00:00Z'%i,'task_sig':sig,'terminal':'refused',
                'cause':'writeset_pending','evidence':'','commit':'none','attempt':'%s-%d'%(sig,i)})
with open(os.path.join(tmp,'events.jsonl'),'w') as f:
    for r in ev: f.write(json.dumps(r)+'\n')
with open(os.path.join(tmp,'ledger.jsonl'),'w') as f:
    for r in led: f.write(json.dumps(r)+'\n')
PY
}

journals SIGUNMAP 'glm:dead:e2e_regression'
out_unmapped="$(run "$HEALTHY" 1 '{"kind":"code","size":"standard","task":"SIGUNMAP"}')"
journals SIGMAPPED 'glm:dead:timeout'
out_mapped="$(run "$HEALTHY" 1 '{"kind":"code","size":"standard","task":"SIGMAPPED"}')"
if [[ "$out_unmapped" == *'failure_unmapped=dead:e2e_regression:1'* && "$out_mapped" != *'failure_unmapped='* ]]; then
  pass '(fm1) a death the vocabulary cannot name is counted out loud, a named one is not'
else
  fail "(fm1) unmapped=$out_unmapped mapped=$out_mapped"
fi

journals_open SIGOPEN1 'glm'
out_open="$(run "$HEALTHY" 1 '{"kind":"code","size":"standard","task":"SIGOPEN1"}')"
journals SIGCLOSED 'glm:dead:timeout'
out_closed="$(run "$HEALTHY" 1 '{"kind":"code","size":"standard","task":"SIGCLOSED"}')"
if [[ "$out_open" == *'spawn_unaccounted=glm:1'* && "$out_closed" != *'spawn_unaccounted='* ]]; then
  pass '(fm2) a spawn nobody ever accounted for is named; an accounted one is not'
else
  fail "(fm2) open=$out_open closed=$out_closed"
fi

printf 'SUMMARY: pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
