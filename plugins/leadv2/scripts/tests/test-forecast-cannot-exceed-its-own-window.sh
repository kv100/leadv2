#!/usr/bin/env bash
# run-all-triggers: leadv2-route-arbiter
# test-forecast-cannot-exceed-its-own-window.sh -- a forecast outside a
# window's domain must not permanently refuse that provider. It also pins the
# complementary rule: an in-domain forecast that exceeds a truly exhausted
# remainder still refuses. The estimator uses p75 because open-lane wall clock
# contains idle tail time; the separate p75 case below makes that choice loud.
#
# Negative controls use private source copies. Each mutation first asserts its
# exact source anchor has count == 1, then prints RED when the assertion it
# protects flips. The working-tree arbiter is never mutated.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${LEADV2_TEST_ARBITER_BIN:-${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh}"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
# The sandbox can inherit a macOS TMPDIR that is not writable by foreground
# test processes. Match the other arbiter suites' fixture-only override.
TMP_BASE="${LEADV2_TEST_TMPDIR:-/tmp}"
TMP="$(mktemp -d "${TMP_BASE%/}/forecast-own-window.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; RUN=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$ROUTE_TEST_QUOTA"' > "$TMP/live.sh"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$TMP/free.sh"
chmod +x "$TMP/live.sh" "$TMP/free.sh"

quota_json() { # <glm five-hour pct> <glm weekly pct>
  python3 -c 'import json,sys; g,w=map(float,sys.argv[1:]); print(json.dumps({"glm":{"status":"ok","five_hour":{"pct":g,"hours_to_reset":96.0},"weekly":{"pct":w,"hours_to_reset":120.0}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":1.0,"limit_window_seconds":604800,"hours_to_reset":96.0}]},"anthropic":{"status":"ok","accounts":[{"active":True,"status":"ok","five_hour_pct":1.0,"seven_day_pct":1.0,"five_hour":{"pct":1.0,"hours_to_reset":96.0},"seven_day":{"pct":1.0,"hours_to_reset":120.0}}]}}))' "$1" "$2"
}

write_events() { # <file> <comma-separated GLM hours>
  python3 -c 'import datetime,json,sys; out,hours=sys.argv[1:]; base=datetime.datetime(2026,9,12,10,0); rows=[]
for i,h in enumerate(map(float,hours.split(","))):
 t="fit%d"%i; rows.extend(({"ts":base.strftime("%Y-%m-%dT%H:%M:%SZ"),"task":t,"arm":"glm","kind":"worker_spawned"},{"ts":(base+datetime.timedelta(hours=h)).strftime("%Y-%m-%dT%H:%M:%SZ"),"task":t,"kind":"worker_terminal"}))
open(out,"w").write("".join(json.dumps(r)+"\n" for r in rows))' "$1" "$2"
}

run_case() { # <arbiter> <quota-json> <events> <descriptor>
  RUN=$((RUN+1))
  env LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-$RUN" LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$3" LEADV2_ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger.jsonl" ROUTE_TEST_QUOTA="$2" bash -c 'source "$0"; route_arbiter worker "$1"' "$1" "$4"
}

DESC='{"kind":"code","size":"standard","task":"forecast-own-window","allowed_arms":["glm"]}'

# Half one: p90=6h (and p75=6h) is 120 points on a five-hour window, while
# that window has 99 points remaining. The five-hour check must be skipped
# loudly, but the healthy weekly window remains checked and GLM remains usable.
write_events "$TMP/events-long.jsonl" '6,6,6,6'
Q_LONG="$(quota_json 1 1)"
out_long="$(run_case "$ARBITER" "$Q_LONG" "$TMP/events-long.jsonl" "$DESC")"; rc_long=$?
if (( rc_long == 0 )) && [[ "$out_long" == 'arm=glm '* && "$out_long" == *'forecast_hours=6.00h'* && "$out_long" == *'forecast_skipped=exceeds_window_period:five_hour'* ]]; then
  pass 'p90 beyond five-hour period skips that window loudly and keeps GLM eligible'
else
  fail "self-window skip expected GLM route, rc=$rc_long: $out_long"
fi

# Half two: a 1.1-hour p75 costs 22 points of a five-hour window. At 79% used
# it is within the window's domain but exceeds the 21-point remainder (while
# remaining below the independent 80% work ceiling), so the
# same fit protection must still refuse.
write_events "$TMP/events-short.jsonl" '1.1,1.1,1.1,1.1'
Q_EXHAUSTED="$(quota_json 79 1)"
out_exhausted="$(run_case "$ARBITER" "$Q_EXHAUSTED" "$TMP/events-short.jsonl" "$DESC")"; rc_exhausted=$?
if (( rc_exhausted == 3 )) && [[ "$out_exhausted" == *'reason=forecast_exceeds_window'* && "$out_exhausted" == *'window=five_hour'* && "$out_exhausted" == *'remaining=21.0pct'* && "$out_exhausted" == *'forecast=22.0pct'* ]]; then
  pass 'in-domain forecast over genuinely exhausted remainder still refuses loudly'
else
  fail "exhausted-window refusal expected, rc=$rc_exhausted: $out_exhausted"
fi

# The idle-tail regression: p90 would be 30h, but p75 of 1,1,1,30 is 1h.
# The named token makes the estimator choice inspectable in every winning line.
write_events "$TMP/events-tail.jsonl" '1,1,1,30'
out_tail="$(run_case "$ARBITER" "$(quota_json 50 1)" "$TMP/events-tail.jsonl" "$DESC")"; rc_tail=$?
if (( rc_tail == 0 )) && [[ "$out_tail" == *'forecast_hours=1.00h'* && "$out_tail" == *'forecast_stat=p75'* ]]; then
  pass 'p75 excludes an idle 30-hour tail from the ordinary-task forecast'
else
  fail "p75 tail trim expected 1h forecast, rc=$rc_tail: $out_tail"
fi

# Negative control 1: disable the own-window domain guard. The exact anchor
# must occur once, and the former pass must turn RED by refusing on 120 > 99.
MUT_DOMAIN="$TMP/mut-domain.sh"
python3 -c 'import sys; src,dst=sys.argv[1:]; old="if fc > 100.0:  # forecast-window-domain mutation anchor"; new="if False:  # forecast-window-domain mutation anchor"; text=open(src).read(); n=text.count(old); assert n==1, "anchor count=%d (expected 1)"%n; open(dst,"w").write(text.replace(old,new))' "$ARBITER" "$MUT_DOMAIN"
out_domain="$(run_case "$MUT_DOMAIN" "$Q_LONG" "$TMP/events-long.jsonl" "$DESC")"; rc_domain=$?
if (( rc_domain == 3 )) && [[ "$out_domain" == *'reason=forecast_exceeds_window'* ]]; then
  printf 'RED CONTROL: disabling forecast-window-domain guard restores the false refusal: %s\n' "$out_domain"
  pass 'negative control: own-window domain guard is load-bearing'
else
  fail "negative control domain guard did not go red, rc=$rc_domain: $out_domain"
fi

# Negative control 2: disable the ordinary remainder comparison. The exact
# anchor must occur once, and the exhausted-window refusal must turn RED.
MUT_FIT="$TMP/mut-fit.sh"
python3 -c 'import sys; src,dst=sys.argv[1:]; old="if fc > rem:  # fit-vs-remainder (W1-FORECAST-THE-SPEND-01 mutation anchor)"; new="if False:  # fit-vs-remainder (W1-FORECAST-THE-SPEND-01 mutation anchor)"; text=open(src).read(); n=text.count(old); assert n==1, "anchor count=%d (expected 1)"%n; open(dst,"w").write(text.replace(old,new))' "$ARBITER" "$MUT_FIT"
out_fit="$(run_case "$MUT_FIT" "$Q_EXHAUSTED" "$TMP/events-short.jsonl" "$DESC")"; rc_fit=$?
if (( rc_fit == 0 )) && [[ "$out_fit" == 'arm=glm '* && "$out_fit" != *'reason=forecast_exceeds_window'* ]]; then
  printf 'RED CONTROL: disabling fit comparison removes the exhausted-window refusal: %s\n' "$out_fit"
  pass 'negative control: exhausted-window fit comparison is load-bearing'
else
  fail "negative control fit comparison did not go red, rc=$rc_fit: $out_fit"
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
