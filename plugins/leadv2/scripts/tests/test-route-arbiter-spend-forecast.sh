#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: leadv2-route-arbiter
# test-route-arbiter-spend-forecast.sh — W1-FORECAST-THE-SPEND-01 (founder
# order 2026-09-09, PRE-WAVES-PLAN §1.4)
#
# Proves the route arbiter estimates the task's expected spend BEFORE choosing
# an arm and refuses loudly when the forecast exceeds the REMAINDER of a
# provider window (nonzero rc + a line naming the window, the remainder and
# the forecast), passes the same task when the remainder is larger, and derives
# the wait-vs-switch threshold from each window's OWN period (168h for codex's
# single weekly window per CODEX-TIER-100-NO-BURST-WINDOW-01, never from the
# 5h window codex no longer has).
#
# The forecast input is the events journal (worker_spawned -> worker_terminal
# durations, p90 per provider) -- the same ROUTE_ARBITER_EVENTS_JOURNAL seam
# failure memory reads. Every case below stubs it with a fixture whose only
# variables are the durations and the window numbers, so nothing ambient can
# move an assertion.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# LEADV2_TEST_ARBITER_BIN: injection seam for negative controls (nc-*.sh).
ARBITER="${LEADV2_TEST_ARBITER_BIN:-${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh}"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/free.sh"

cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
chmod +x "$TMP/live.sh"

# journal_fixture <out-file> — the measured-history side of the fixture: three
# joined spawn->terminal rows per provider. glm/claude arms run 4h tasks,
# codex arms 40h tasks (the "history of similar tasks" the forecast reads).
journal_fixture() {
  python3 - "$1" <<'PY'
import json, sys, datetime
rows=[]
def ts(base, hours):
    # timedelta, never "%02d"%(10+h): h>=14 overflows the hour field and the
    # arbiter's strptime silently drops the row (the first draft's codex 40h
    # rows all vanished and case (c3) passed vacuously).
    return (base+datetime.timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ")
def task(arm, tid, hours):
    base=datetime.datetime(2026,9,9,10,0)
    rows.append({"ts":ts(base,0),"repo":"leadv2","task":tid,"arm":arm,"kind":"worker_spawned","handle":"H"})
    rows.append({"ts":ts(base,hours),"repo":"leadv2","task":tid,"kind":"worker_terminal","detail":"done"})
for i in range(3):
    task("glm","fg%d"%i,4); task("sonnet","fc%d"%i,4); task("codex","fx%d"%i,40)
with open(sys.argv[1],"w") as f:
    for r in rows: f.write(json.dumps(r)+"\n")
PY
}
journal_fixture "$TMP/events.jsonl"

# quota_fc <glm5h_pct> <codex_pct> <codex_hours_to_reset> <claude5h_pct> <claude7d_pct>
# ONE fixture builder: every case differs ONLY in window numbers (the
# remainder) — same shapes, same journal, same descriptor.
quota_fc() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json,sys
g,c,ch,a,sd=sys.argv[1:]
print(json.dumps({
  'glm': {'status':'ok',
          'five_hour':{'pct':float(g),'hours_to_reset':96.0,'reset_iso':'forged-fixture'},
          'weekly':{'pct':5.0,'hours_to_reset':120.0,'reset_iso':'forged-fixture'}},
  'codex': {'status':'ok','binding_window':'primary',
            'windows':[{'kind':'primary','used_percent':float(c),
                        'limit_window_seconds':604800,
                        'hours_to_reset':float(ch),'reset_iso':'forged-fixture'}]},
  'anthropic': {'status':'ok','accounts':[{'active':True,'status':'ok',
            'five_hour_pct':float(a),'seven_day_pct':float(sd),
            'five_hour':{'pct':float(a),'hours_to_reset':96.0,'reset_iso':'forged-fixture'},
            'seven_day':{'pct':float(sd),'hours_to_reset':120.0,'reset_iso':'forged-fixture'}}]}
}))
PY
}

# The task descriptor is IDENTICAL in every forecast case; allowed_arms bounds
# the pool to the three window-bearing arms so freepool's windowless arm
# cannot mask the refusal.
DESC='{"kind":"code","size":"standard","task":"fcw1sig01","allowed_arms":["glm","codex","sonnet"]}'

run_fc() { # <quota-json> [env VAR=VAL ...]
  local q="$1"; shift
  # "$@" LAST: env takes repeated VAR=VAL operands and the LAST one wins, so
  # a per-case LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL override must come after
  # (not before) the default assignments below -- the first draft had "$@"
  # first and every per-case journal was silently crushed by the default.
  env \
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
  LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events.jsonl" LEADV2_ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger.jsonl" \
  ROUTE_TEST_QUOTA="$q" ROUTE_TEST_FREE_RC=0 "$@" \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$DESC"
}

# (a) REFUSAL, the founder's exact scenario: glm 5h window at 59% used ->
# remainder 41 pct-points; the journal's 4h p90 forecasts 4/5*100 = 80 ->
# 80 > 41. codex: 40h p90 on its single 168h window, used 85 -> remainder 15,
# forecast 40/168*100 = 23.8 > 15. claude: 4h p90, 5h remainder 41 vs
# forecast 80. No eligible arm fits -> rc!=0 and the line names window,
# remainder and forecast.
rm -f "$TMP/state"
out_a="$(run_fc "$(quota_fc 59 85 96 59 50)")"; rc_a=$?
if (( rc_a != 0 )) && [[ "$out_a" == *'reason=forecast_exceeds_window'* && "$out_a" == *'window=five_hour'* && "$out_a" == *'remaining=41.0pct'* && "$out_a" == *'forecast=80.0pct'* ]]; then
  pass "(a) forecast>remainder refuses: rc=$rc_a, line names window/remainder/forecast"
else
  fail "(a) expected loud forecast refusal, rc=$rc_a: $out_a"
fi

# (b) SAME task, SAME journal, SAME window shapes -- ONLY the remainders are
# larger: every window holds the forecast -> the dispatch passes and the
# winning line still shows the forecast it was checked against.
rm -f "$TMP/state"
out_b="$(run_fc "$(quota_fc 5 5 96 5 5)")"; rc_b=$?
if (( rc_b == 0 )) && [[ "$out_b" == 'arm=glm '* && "$out_b" == *'forecast_hours=4.00h'* && "$out_b" == *'forecast_basis=journal:provider=3'* ]]; then
  pass "(b) same task with larger remainders passes (rc=0, arm=glm, forecast on the line)"
else
  fail "(b) expected pass, rc=$rc_b: $out_b"
fi

# (c) CODEX 168h THRESHOLD: codex under its 95 work ceiling (used 60 ->
# remainder 40) with a 100h expected task (forecast 100/168*100 = 59.5 > 40 ->
# forecast-blocked) whose window resets in 16h. 16h <= 10% of 168h (16.8h) ->
# WAIT, not switch; the ONLY threshold that can produce that is the window's
# own 168h period -- a 5h-based threshold (0.5h) would switch.
python3 - "$TMP/events-c.jsonl" <<'PY'
import json,sys,datetime
rows=[]
base=datetime.datetime(2026,9,9,10,0)
def task(arm,tid,hours):
    # arm is a parameter: the first draft hardcoded "codex", so the gw/sw rows
    # landed in the codex bucket and glm fell back to the all-rows p90 (100h) --
    # glm got forecast-blocked by rows that were never glm's.
    t0=base.strftime("%Y-%m-%dT%H:%M:%SZ")
    t1=(base+datetime.timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows.append({"ts":t0,"repo":"leadv2","task":tid,"arm":arm,"kind":"worker_spawned","handle":"H"})
    rows.append({"ts":t1,"repo":"leadv2","task":tid,"kind":"worker_terminal","detail":"done"})
for i in range(3):
    task("codex","cw%d"%i,100)
    task("glm","gw%d"%i,4); task("sonnet","sw%d"%i,4)
with open(sys.argv[1],"w") as f:
    for r in rows: f.write(json.dumps(r)+"\n")
PY
rm -f "$TMP/state"
out_c="$(run_fc "$(quota_fc 5 60 16 5 5)" LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events-c.jsonl")"; rc_c=$?
if (( rc_c == 0 )) && [[ "$out_c" == *'wait_applied=codex'* && "$out_c" != *'codex:forecast'* ]]; then
  pass "(c) single-weekly-window codex waits at 16h: threshold is 10% of 168h, not of 5h"
else
  fail "(c) expected forecast-wait on codex, rc=$rc_c: $out_c"
fi

# (c2) same shape, reset 20h away -- past the 16.8h threshold -> SWITCH: the
# codex arms carry the forecast stage on the decision line.
rm -f "$TMP/state"
out_c2="$(run_fc "$(quota_fc 5 60 20 5 5)" LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events-c.jsonl")"; rc_c2=$?
if (( rc_c2 == 0 )) && [[ "$out_c2" == *'codex:forecast'* ]]; then
  pass "(c2) far reset (20h > 16.8h) switches codex away: forecast stage on the line"
else
  fail "(c2) expected codex forecast exclusion, rc=$rc_c2: $out_c2"
fi

# (c3) the forecast denominator itself is 168h: a 50h task forecasts
# 50/168*100 = 29.8 <= 40 remainder -> codex stays eligible with NO forecast
# stage. A 5h denominator (1000 pct-points) would have excluded it.
python3 - "$TMP/events-d.jsonl" <<'PY'
import json,sys,datetime
rows=[]
base=datetime.datetime(2026,9,9,10,0)
def task(arm,tid,hours):
    t0=base.strftime("%Y-%m-%dT%H:%M:%SZ")
    t1=(base+datetime.timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows.append({"ts":t0,"repo":"leadv2","task":tid,"arm":arm,"kind":"worker_spawned","handle":"H"})
    rows.append({"ts":t1,"repo":"leadv2","task":tid,"kind":"worker_terminal","detail":"done"})
for i in range(3):
    task("codex","dw%d"%i,50)
    task("glm","gw%d"%i,4); task("sonnet","sw%d"%i,4)
with open(sys.argv[1],"w") as f:
    for r in rows: f.write(json.dumps(r)+"\n")
PY
rm -f "$TMP/state"
out_c3="$(run_fc "$(quota_fc 5 60 96 5 5)" LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events-d.jsonl")"; rc_c3=$?
if (( rc_c3 == 0 )) && [[ "$out_c3" != *'codex:forecast'* ]]; then
  pass "(c3) 50h task fits a 168h window at 40pct remainder (forecast 29.8): denominator is the window's own period"
else
  fail "(c3) codex wrongly forecast-excluded, rc=$rc_c3: $out_c3"
fi

# (d) NO HISTORY -> loud third value, never a silent default and never a
# refusal: a journal with a spawn but no terminal row gives no basis, glm at
# 59% (which case (a) refused with history) simply dispatches and says so.
printf '%s\n' '{"ts":"2026-09-09T10:00:00Z","task":"zz1","arm":"glm","kind":"worker_spawned"}' > "$TMP/events-empty.jsonl"
rm -f "$TMP/state"
out_d="$(run_fc "$(quota_fc 59 5 96 5 5)" LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events-empty.jsonl")"; rc_d=$?
if (( rc_d == 0 )) && [[ "$out_d" == 'arm=glm '* && "$out_d" == *'forecast_basis=no_history'* ]]; then
  pass "(d) no measurable history: no refusal, forecast_basis=no_history on the line"
else
  fail "(d) expected no_history pass-through, rc=$rc_d: $out_d"
fi

# (e) KILL-SWITCH: LEADV2_ARBITER_SPEND_FORECAST=0 removes every forecast
# token and every forecast exclusion -- the rollback is one flag.
rm -f "$TMP/state"
out_e="$(run_fc "$(quota_fc 59 85 96 59 50)" LEADV2_ARBITER_SPEND_FORECAST=0)"; rc_e=$?
if (( rc_e == 0 )) && [[ "$out_e" != *'forecast'* ]]; then
  pass "(e) kill-switch: rc=$rc_e and no forecast token anywhere on the line"
else
  fail "(e) kill-switch did not disable the check, rc=$rc_e: $out_e"
fi

# (f) NEGATIVE CONTROL on a PRIVATE COPY (house convention, mirrors
# test-quota-reset-arbiter.sh case (e)): remove the remainder comparison
# INSIDE _forecast_check's body -- the fit can never fail -- and case (a)'s
# named refusal assertion must go RED. Proves the comparison is load-bearing.
mutated="$TMP/mutated-route-arbiter.sh"
sed 's/if fc > rem:  # fit-vs-remainder (W1-FORECAST-THE-SPEND-01 mutation anchor)/if False:  # fit-vs-remainder (W1-FORECAST-THE-SPEND-01 mutation anchor)/' "$ARBITER" > "$mutated"
if diff -q "$ARBITER" "$mutated" >/dev/null; then
  fail '(f) mutation anchor not found -- cannot prove the control'
else
  rm -f "$TMP/state"
  out_mut="$(env LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
    LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/events.jsonl" LEADV2_ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger.jsonl" \
    ROUTE_TEST_QUOTA="$(quota_fc 59 85 96 59 50)" ROUTE_TEST_FREE_RC=0 \
    bash -c 'source "$0"; route_arbiter worker "$1"' "$mutated" "$DESC")"; rc_mut=$?
  if (( rc_mut == 0 )) || [[ "$out_mut" != *'forecast_exceeds_window'* ]]; then
    pass "(f RED) fit comparison removed -> case (a)'s refusal disappears (rc=$rc_mut): control is load-bearing"
  else
    fail "(f RED) mutation did not flip case (a): rc=$rc_mut $out_mut"
  fi
fi

# (f2) REVERT: the real file, same fixture as (a), red-again (refuses) --
# proves the mutation, not something else, caused (f)'s flip.
rm -f "$TMP/state"
out_rev="$(run_fc "$(quota_fc 59 85 96 59 50)")"; rc_rev=$?
if (( rc_rev != 0 )) && [[ "$out_rev" == *'forecast_exceeds_window'* ]]; then
  pass "(f2 GREEN) revert to the real file: refusal restored"
else
  fail "(f2 GREEN) revert did not restore the refusal, rc=$rc_rev: $out_rev"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
