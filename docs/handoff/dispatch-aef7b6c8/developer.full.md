verdict: APPROVE
next_action: deploy

# CODEX-LANES-PRODUCE-NO-TOKEN-READING-01 — developer report (dispatch-aef7b6c8)

## 1. Premise check (method — binding, done first)

Mission brief claimed 0/8 codex lanes have `costs.yaml`. Widened the count across
`leadv2` + `persona-engine`, bucketed by each dispatch dir's last `worker_spawned`
arm in the events journal, before writing anything:

```
totals: {'sonnet': 140, 'codex': 143, 'other': 1204}
has costs.yaml: {'sonnet': 137, 'codex': 12, 'other': 317}
```
(`/tmp/aef7b6c8-count-costs.py`)

The 12 apparent codex counter-examples were inspected directly: each is a mixed-arm
sig8 where an *earlier* sonnet spawn wrote an all-zero `costs.yaml` before the lane
re-dispatched to codex — not real codex telemetry. No counter-example survives.
Premise holds: `costs.yaml` is a `claude-subsession.sh`-only artifact; a pure-codex
lane has never produced one.

## 2. Does codex's own run record usage? — yes (mission item 1, branch A)

`~/.codex/sessions/**/rollout-*.jsonl` (root: `CODEX_HOME`, default `~/.codex`)
contains `token_usage_record` lines. Verified live shape (6/6 sampled):

```
{"type":"token_usage_record","payload":{"thread_id":...,"turn_id":...,
 "usage":{"input_tokens":N,...,"output_tokens":N,...},
 "turn_token_usage":{...cumulative per turn...},
 "thread_token_usage":{...CUMULATIVE for the whole thread...}}}
```
Confirmed `total_tokens == input_tokens + output_tokens` (reasoning_output_tokens is
a subset of output_tokens, not additive) against 6 live records.

The exact join (no heuristics): a codex job's own record —
`$CODEX_GUARD_STATE_ROOT/<slug>/jobs/<jobId>.json` — carries `threadId`, which is
byte-identical to the trailing UUID in its own rollout filename. Verified 6/6 live
samples. Given the `jobId` recorded in `arm-registered` at spawn time
(`_dispatch_register_arm`), this resolves to exactly one rollout file with zero
ambiguity — unlike the pre-existing `_codex_newest_rollout_since` liveness heuristic,
which matches by cwd+mtime and can be ambiguous across sibling dispatches.

Since the seam exists, I did not stop at "no seam" — I built the join, writing the
same kind of real-token-total `leadv2_lane_token_total` already produces for claude,
without touching that function's stdout contract (bare integer or `-`; 3+ existing
suites assert exact string equality against it — `test-quota-telemetry-can-price-
an-arm.sh` in particular pins `TOK_A=="1800"`, `TOK_C=="-"`, `TOK_D=="-"`).

## 3. Changes (additive — off-limits Claude path untouched)

**`plugins/leadv2/scripts/lib/leadv2-cost-actuals.sh`**
- New tier `(a2) codex rollout`, inserted between the existing costs.yaml tier (a)
  and the turn_events tier (b) inside `leadv2_lane_token_total`. Reads
  `arm-registered` for `arm=codex handle=<jobId>` lines, resolves each job's
  `threadId` from its job JSON, globs for exactly one matching rollout file (0 or
  >1 matches → skip that spawn, never guess), reads the LAST `token_usage_record`
  in it, sums `thread_token_usage.input_tokens + output_tokens`. Sums across
  re-dispatches (N codex spawns → N distinct threads summed), mirroring how tier
  (a) already sums N claude sessions.
- New function `leadv2_lane_token_reason(repo_root, sig8)` — a presence check over
  the SAME three artifacts `leadv2_lane_token_total` reads (`costs.yaml`,
  `arm-registered`'s codex handle, `sessions.map`), not a second value computation,
  so there is nothing for a second reader to drift out of sync with. Returns one of
  `no_seam_for_arm` (no artifacts at all) / `costs_yaml_absent` (codex handle
  present but rollout unresolved) / `turn_events_empty` (sessions.map present, no
  burn db) / `parse_failed` (costs.yaml present but unparseable). rc always 0, same
  fail-open licence as `leadv2_lane_token_total`.

**`plugins/leadv2/scripts/leadv2-dispatch-code.sh`** (`_dl_note`, ~line 2386)
- When `_ca_tokens` is still `-` after `leadv2_cost_actual_record`, appends
  `token_reason=<reason>` to the existing `cost_actual_recorded` decision line via
  `leadv2_lane_token_reason`. Appended as a trailing field, not folded into
  `leadv2_cost_actual_record`'s own k=v line — the join-key contract tests that
  call that function directly (`test-arbiter-decision-record-inputs.sh`) are
  unaffected; confirmed by re-running it (6/6 PASS, unchanged).

**`plugins/leadv2/scripts/tests/test-codex-lane-token-total.sh`** (new)
- Fixtures the whole join without touching real `~/.codex/sessions` data: 9
  assertions — single-spawn join (990), two-redispatch sum across distinct threads
  (1320), ambiguous >1 rollout match → `-` (never guesses), missing job json → `-`,
  and all four `leadv2_lane_token_reason` codes.
- Header: `# run-all-triggers: leadv2-cost-actuals.sh leadv2-cost-actuals
  leadv2-dispatch-code.sh leadv2-dispatch-code` — registers it against both files
  this mission touches.

No change to `leadv2_lane_token_total`'s stdout contract, `reset_urgency`,
`provider_cost`, decision-record schema, the launcher-refusal event, or any file
under `docs/leadv2/`, `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*`,
`docs/tasks.yaml`, `docs/leadv2/open-threads.md`. `docs/leadv2/.compact-freeze.md`
shows modified in the working tree (SessionStart:compact hook's own state file) —
left uncommitted, not part of this diff (confirmed via `git diff --stat` before
staging; only the 3 files above were `git add`ed).

## 4. Acceptance #1 — real token total on a LIVE lane (not a fixture)

Ran the patched `leadv2_lane_token_total` against every real `arm-registered` file
with a codex handle in both repos (`/tmp/aef7b6c8-live-example.sh`), newest 5:

```
repo=leadv2 sig=e33f2050 tokens=18950112
repo=leadv2 sig=2380dda8 tokens=17474234
repo=leadv2 sig=2511fd31 tokens=7647160
repo=leadv2 sig=4e2676a0 tokens=15450467
repo=leadv2 sig=0a148de1 tokens=18360886
```
These are the exact sig8 values the mission's own broken-example table cited as
"no costs.yaml" — now resolving to real, plausible multi-million-token totals via
the rollout join instead of a fabricated number.

## 5. Acceptance #2 — named reasons, not silent `-`

`leadv2_lane_token_reason` implemented and unit-tested (4 sub-assertions, 5a-5d,
all PASS — see §7 raw output). Wired into `_dl_note` so the `cost_actual_recorded`
journal line carries `token_reason=<code>` whenever tokens is unknown, instead of
`tokens=-` covering both "no seam" and "seam found nothing" indistinguishably.

## 6. Acceptance #3 — joined-pair count per provider + threshold

Counted every `dispatch-*` dir across leadv2+persona-engine with a codex handle in
`arm-registered`, resolved through the patched `leadv2_lane_token_total`
(`/tmp/aef7b6c8-count-joined-pairs.sh`):

```
codex lanes with a codex handle: resolved=113 unresolved=123
```

- **codex: 113 joined pairs** (up from 0 before this change).
- **sonnet/claude: 137 joined pairs** (unchanged — costs.yaml path, always worked).
- The 123 unresolved codex lanes are NOT silent: each now reports
  `token_reason=costs_yaml_absent` (codex handle present, but the job's rollout
  file has since rotated out of `~/.codex/sessions` retention, or its jobId's
  state-root record no longer exists) — never a fabricated total.

**Threshold, not a date.** This codebase's only existing precedent for "how many
samples before a fit is defensible instead of NOT-ENOUGH-DATA" is
`leadv2-drain-weights.py:57` (`MIN_INTERVALS = 12`), which gates its own quota-
window regression the same way — below it, the tool prints `NOT-ENOUGH-DATA`
named as such, "never a number this file cannot defend" (its own doc comment,
line 34-35). It is a different fitter (quota-window regression, not per-token
price), so this is cited as the repo's own precedent for the *shape* of this
question, not a literal shared implementation.

By that precedent: **113 (codex) and 137 (sonnet) both clear a floor of 12 by
roughly an order of magnitude.** A per-provider fit is now defensible for BOTH
providers — where codex was previously undefined (0 pairs, no seam at all). No
threshold is unmet; nothing here is blocked on more data.

## 7. Acceptance #4 — required suites still green (raw, fresh re-run)

```
=== plugins/leadv2/scripts/tests/test-launcher-refusal-event.sh ===
PASS: RED control: mutating capture reason made the real-refusal assertion red
launcher-refusal-event: PASS=4 FAIL=0
rc=0
=== plugins/leadv2/scripts/tests/test-arbiter-decision-record-inputs.sh ===
PASS: complexity replay moves the recorded decision from capable to cheap
PASS: replay refuses output-only schema-v1 rows
PASS: estimate records the dispatch signature used by its terminal actual
PASS: cost_actual carries the reciprocal estimate_task_id join key
SUMMARY pass=6 fail=0
rc=0
=== plugins/leadv2/scripts/tests/test-reset-urgency.sh ===
PASS: (g) urgency cannot buy capability: unsupported Claude docs arm is absent
PASS: (h) kill switch restores cost order and removes urgency provenance
PASS: (i RED) removing the urgency formula flips the founder case to codex
PASS: (i GREEN) unmutated arbiter restores the founder-case Claude pick
SUMMARY: pass=10 fail=0
rc=0
=== plugins/leadv2/scripts/tests/test-leadv2-task-judge.sh ===
[TEST] PASS: T16: default arm=haiku; valid Haiku answer does not invoke GLM
[TEST] PASS: T16: failed GLM -> Haiku fallback
[TEST] PASS: bash -n syntax OK on leadv2-task-judge.sh
=== Results: 31 passed, 0 failed ===
rc=0
=== plugins/leadv2/tests/test-arbiter-prices-by-provider.sh ===
PASS: (4) cost: block absent -> legacy row cost honoured, cost_src=codex:legacy_row
PASS: (5) max_cost=2 excludes codex (provider price 5.0 > 2) -> arm=glm
PASS: (5b) same max_cost against swapped prices -> exclusion flips to arm=codex
PASS: (6) malformed router_v2.cost.codex -> rc=2, reason=routing_yaml_invalid names the key
SUMMARY pass=7 fail=0
rc=0
```

Plus the new suite and the pre-existing (not required, natural regression check)
quota-telemetry suite:

```
=== plugins/leadv2/scripts/tests/test-codex-lane-token-total.sh ===
[TEST] PASS: 5a no artifacts at all -> no_seam_for_arm
[TEST] PASS: 5b codex handle but unresolved rollout -> costs_yaml_absent
[TEST] PASS: 5c only sessions.map, no burn db -> turn_events_empty
[TEST] PASS: 5d costs.yaml exists but unparseable -> parse_failed
SUMMARY pass=9 fail=0
rc=0
=== plugins/leadv2/scripts/tests/test-quota-telemetry-can-price-an-arm.sh ===
PASS: 7c unknown lane -> tokens='-' (not 0)
PASS: 7d zero-total costs.yaml -> '-' (a false zero would poison observed-cost)
PASS: 8 record: 8 args -> tokens=1500; 7 args/junk -> tokens=-; row emitted to journal
pass=17 fail=0
rc=0
```

## 8. Falsification set (raw)

```
$ bash -n plugins/leadv2/scripts/lib/leadv2-cost-actuals.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-codex-lane-token-total.sh && echo OK
OK
```
No `.py` files were changed in this commit (`git show --stat HEAD | grep '\.py'`
→ no matches) — `python3 -m py_compile` is not applicable; the only Python is an
inline heredoc inside the new bash tier, exercised live by every suite run above.

## 9. Acceptance #5 — new suite selection (commit first, then selection output)

Committed first (`bfc15453`, 3 files: `lib/leadv2-cost-actuals.sh`,
`leadv2-dispatch-code.sh`, `tests/test-codex-lane-token-total.sh`).

`tests/run-all.sh --scope changed` runs `run-core-offline.sh` unconditionally
(ALWAYS-ON nested wrapper, up to 900s gate budget) even under `--scope changed` —
confirmed by direct read of `tests/run-all.sh` and by this session's own attempt
timing out at the 600s tool ceiling. The repo's own documented workaround for
proving selection without paying that wall is `LEADV2_RUN_ALL_LIST_TRIGGERS=1`,
which dumps the full stem→suite trigger map `scan_suite_triggers()` builds.
Filtered to this commit's two changed stems:

```
$ LEADV2_TEST_CONTEXT=1 LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh --scope changed \
    | grep -iE "cost-actuals|codex-lane-token-total"
leadv2-cost-actuals.sh:plugins/leadv2/scripts/tests/test-account-truth-active-is-metered.sh
leadv2-cost-actuals:plugins/leadv2/scripts/tests/test-account-truth-active-is-metered.sh
leadv2-cost-actuals:plugins/leadv2/scripts/tests/test-arbiter-decision-record-inputs.sh
leadv2-cost-actuals:plugins/leadv2/scripts/tests/test-arbiter-uses-observed-cost.sh
leadv2-cost-actuals.sh:plugins/leadv2/scripts/tests/test-codex-lane-token-total.sh
leadv2-cost-actuals:plugins/leadv2/scripts/tests/test-codex-lane-token-total.sh
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-codex-lane-token-total.sh
leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-codex-lane-token-total.sh
leadv2-cost-actuals.sh:plugins/leadv2/scripts/tests/test-quota-telemetry-can-price-an-arm.sh
leadv2-cost-actuals:plugins/leadv2/scripts/tests/test-quota-telemetry-can-price-an-arm.sh
```

`test-codex-lane-token-total.sh` is registered under BOTH changed stems
(`leadv2-cost-actuals.sh`/`leadv2-cost-actuals` and
`leadv2-dispatch-code.sh`/`leadv2-dispatch-code`) — `--scope changed` selects it
whenever either changed file appears in the diff, which this commit's diff does.
The suite itself was re-run standalone and green (§7).

## 10. Definition-of-done gate

- Diff touches only `plugins/leadv2/scripts/lib/leadv2-cost-actuals.sh`,
  `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
  `plugins/leadv2/scripts/tests/test-codex-lane-token-total.sh` — no
  `docs/leadv2/`, `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*`,
  `docs/tasks.yaml`, or `docs/leadv2/open-threads.md` paths.
- New suite registered via `# run-all-triggers:` header (confirmed selected, §9).
- No mutation-control claim made in this report, so no
  `leadv2-mutation-control.sh` artifact is required.
- Committed on lane branch `worktree-d0282f6a0d13` (`bfc15453`) before ending
  session.

DELIVERABLE_COMPLETE
