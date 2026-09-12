# Forecast cannot exceed its own window

## Decision

The estimator is now provider p75 of joined worker_spawned to worker_terminal
wall-clock durations (forecast_stat=p75). Open-lane wall clock includes idle
time, so p90 allowed a small long-open tail to price the ordinary task.
leadv2-cost-flush.sh records token telemetry for Claude streams, not
comparable GLM/Codex quota actuals, so it cannot yet replace this
cross-provider estimator.

For each readable window, forecast > 100 is now outside that window's domain:
the check is skipped, but named as
forecast_skipped=exceeds_window_period:<window>. Other readable windows
continue through the normal forecast > remaining fit rule.

## Controls before code

The live probe was run with bash -c source against
/Users/kostiantyn.vlasenko/.claude/cache/leadv2-events/leadv2.jsonl. The
measured state had moved from the brief; it is recorded rather than used as a
fixture:

\`\`\`text
CONTROL forecast=1
arm=codex ... reason=cheapest_capable ... util_glm=48 ... arm_excluded=freepool:price_ratio,glm:forecast,glm-flash:forecast,sonnet:forecast ... probe_outage=codex ... forecast_basis=no_windows ...
RC=0
CONTROL forecast=0
arm=glm ... reason=capability_fit ... util_glm=48 ... arm_excluded=codex:price_ratio,freepool:price_ratio,glm-flash:price_ratio,sonnet:price_ratio ... probe_outage=codex ...
RC=0
\`\`\`

## Controls after code

\`\`\`text
CONTROL AFTER forecast=1
arm=glm ... reason=capability_fit ... util_glm=49 ... forecast_hours=2.23h forecast_basis=journal:provider=209 forecast_stat=p75 ...
RC=0
CONTROL AFTER forecast=0
arm=glm ... reason=capability_fit ... util_glm=49 ... (no forecast tokens)
RC=0
\`\`\`

## Acceptance and negative controls

\`\`\`text
PASS: p90 beyond five-hour period skips that window loudly and keeps GLM eligible
PASS: in-domain forecast over genuinely exhausted remainder still refuses loudly
PASS: p75 excludes an idle 30-hour tail from the ordinary-task forecast
RED CONTROL: disabling forecast-window-domain guard restores the false refusal: arm=refuse ... reason=forecast_exceeds_window ... window=five_hour remaining=99.0pct forecast=120.0pct ...
PASS: negative control: own-window domain guard is load-bearing
RED CONTROL: disabling fit comparison removes the exhausted-window refusal: arm=glm ... remaining=21.0 ... forecast_hours=1.10h forecast_basis=journal:provider=4 forecast_stat=p75 ...
PASS: negative control: exhausted-window fit comparison is load-bearing
SUMMARY: pass=5 fail=0
\`\`\`

Both controls are anchored in the suite with count == 1 assertions before
replacement. The required leadv2-mutation-control.sh artifacts are:

- mutation-control/20260912T113656Z-69045.txt: baseline_rc=0, mutated_rc=1,
  with the false five-hour refusal on the domain-guard mutation.
- mutation-control/20260912T113718Z-84416.txt: baseline_rc=0, mutated_rc=1,
  with the exhausted-window refusal removed on the fit mutation.

## Guarding suites

\`\`\`text
test-route-arbiter-spend-forecast.sh: SUMMARY: pass=9 fail=0
test-route-arbiter-loud-refusal.sh: SUMMARY: pass=4 fail=0
test-forecast-cannot-exceed-its-own-window.sh: SUMMARY: pass=5 fail=0
test-route-arbiter.sh: SUMMARY: pass=28 fail=4
test-arbiter-seam-plugin-kind.sh: PASS=11 FAIL=3
\`\`\`

The seven failures in the two broad suites were dispatch/premise/fail-open
fixtures, all showing forecast_basis=no_history or never invoking forecast:
the source change is not on those paths. They are not represented as green.

## Changed-scope runner

\`\`\`text
suite-discovery: [UNTRACKED-SKIP] ... not tracked by git
[CORE-OFFLINE] waiting for lock ... holder=pid=28642 ... (held by a concurrent run)
[SUITE-TIMEOUT] plugins/leadv2/scripts/tests/run-core-offline.sh exceeded 90s ceiling
[SUITE-TIMEOUT] tests/test-status-surface-bash32.sh exceeded 90s ceiling
[FAIL] plugins/leadv2/scripts/tests/test-nested-count-fix.sh
[FAIL] plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh
RC=124
\`\`\`

bash tests/run-all.sh --scope changed was run foreground with a 300-second
outer bound and per-suite 90-second bound. It is red for the shown concurrent
lock/timeouts and unrelated suites.

## Syntax and diff

\`\`\`text
bash -n plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
bash -n plugins/leadv2/scripts/tests/test-forecast-cannot-exceed-its-own-window.sh
\`\`\`

Both commands exited 0. Final committed diff stat:

\`\`\`text
docs/handoff/dispatch-3fc974c6/report.md                    | 103
plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh           |  32
plugins/leadv2/scripts/tests/test-forecast-cannot-exceed-its-own-window.sh | 108
docs/handoff/dispatch-3fc974c6/mutation-control/*.txt        |  24
\`\`\`
