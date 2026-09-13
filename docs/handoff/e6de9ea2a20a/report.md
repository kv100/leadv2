# ARBITER-DECISION-RECORD-CARRIES-ITS-INPUTS-01

Commit checkpoint: `40bd4e46`.

## Item 1 — BUILT

`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` now writes
`record_schema_version: 2` on every new decision row.  New rows carry the
success-line inputs (`complexity`, `duration_class`, `req_eff`, `util_*`,
`reset_*`, `fit_bucket`, `reset_urgency`, and `cost_src`), the eligible
candidate set with its effective cost/capability/fit bucket, and the existing
per-arm `arm_excluded` reason map.  `leadv2-arbiter-replay.py` refuses old
unversioned rows rather than treating output-only history as replayable.

Probe (focused suite):

```text
PASS: arbiter success line carries the replay inputs
PASS: schema-v2 record contains winner inputs, both candidates, and exclusion reasons
PASS: complexity replay moves the recorded decision from capable to cheap
PASS: replay refuses output-only schema-v1 rows
PASS: estimate records the dispatch signature used by its terminal actual
PASS: cost_actual carries the reciprocal estimate_task_id join key
SUMMARY pass=6 fail=0
```

Replay output exercised the complexity axis with one recorded decision:

```text
task=record-fixture original=capable replay=cheap complexity=simple req_eff=2.10 fit_bucket=0 moved=1
SUMMARY replayable=1 movement=1 old_schema_refused=0 malformed=0
```

## Item 2 — BUILT; historical fit NOT REACHED

The estimate writer now records `dispatch_sig8`; the terminal writer records
the reciprocal `estimate_task_id`.  The dispatch and product-close funnels
thread their founder task id into that actual row.  Existing history was not
rewritten.

Live-corpus probe (2026-09-13):

```text
estimate_files=422
cost_actual_rows=69
historical_joined=0
```

Therefore an R-squared fit is still **undefined** (`joined=0`, below 2).  The
focused new-write fixture above proves one forward join; it does not fabricate
a historical fit.

## Item 3 — MEASURED AND REJECTED

The current launcher seam already maps a kind absent from the capability
matrix to `code`, the same vocabulary coercion the arbiter reports as
`kind_unmapped`.  It then derives launchability from that same matrix; no
second capability matrix was added.

Live event-journal probe:

```text
arm_not_capable_for_kind=0
kind_unmapped=0
paired-disagreement=0
```

The current live journal has no countable disagreement event, so this lane
does not claim a frequency beyond zero observed rows in that journal.

## Negative control

Raw mutation-control artifact:

```text
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-arbiter-decision-record-inputs.sh file=plugins/leadv2/scripts/leadv2-arbiter-replay.py red_line=PASS: schema-v2 record contains winner inputs, both candidates, and exclusion reasons diff_hash=083e0fc33d37518e16d1d6971a557a2a4f34b5056c456d4c507a6a850ec64bed lane_diff_hash=af69a219a339326d23228d17341258672cce463f2d564c5963c876c8ccb38a64
```

Artifact: `docs/handoff/e6de9ea2a20a/mutation-control/`.

## Required regressions

```text
test-reset-urgency.sh
SUMMARY: pass=10 fail=0

test-arbiter-prices-by-provider.sh
SUMMARY pass=7 fail=0

test-leadv2-task-judge.sh
=== Results: 31 passed, 0 failed ===
```

The provider-price suite requires a `mktemp` compatibility shim in this
sandbox because its bare `mktemp -d` selects an inaccessible macOS temporary
directory.  Under that shim it is 7/7 green; no repository test was changed.

## Changed-scope registration

After commit, the canonical command selected and passed the new suite:

```text
[RUN] .../plugins/leadv2/scripts/tests/test-arbiter-decision-record-inputs.sh
PASS: arbiter success line carries the replay inputs
PASS: schema-v2 record contains winner inputs, both candidates, and exclusion reasons
PASS: complexity replay moves the recorded decision from capable to cheap
PASS: replay refuses output-only schema-v1 rows
PASS: estimate records the dispatch signature used by its terminal actual
PASS: cost_actual carries the reciprocal estimate_task_id join key
SUMMARY pass=6 fail=0
[PASS] .../plugins/leadv2/scripts/tests/test-arbiter-decision-record-inputs.sh
```

The full changed-scope gate is red for unrelated ambient failures: its core
wrapper timed out after a concurrent-run lock, and existing status/routing
suites fail against missing sandbox paths and baseline fixture assumptions.
The new suite itself is green.

## Self-check

```text
bash -n plugins/leadv2/scripts/leadv2-cost-estimate.sh plugins/leadv2/scripts/leadv2-dispatch-code.sh plugins/leadv2/scripts/leadv2-dispatch-product-close.sh plugins/leadv2/scripts/lib/leadv2-cost-actuals.sh plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh plugins/leadv2/scripts/tests/test-arbiter-decision-record-inputs.sh
python3 -m py_compile plugins/leadv2/scripts/leadv2-arbiter-replay.py
```

Both commands exited 0 before the focused suite ran.
