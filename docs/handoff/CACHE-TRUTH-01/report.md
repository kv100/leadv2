# CACHE-TRUTH-01 — prompt-cache measurement, all four arms

## Tool

`plugins/leadv2/scripts/leadv2-cache-truth.sh <run-dir|stream-file>...` parses
`developer.stream.jsonl` (docs/handoff/dispatch-*) or `journal.jsonl`
(`~/.claude/cache/{glm,freepool,kimi,claude}-runs/*`), and prints one row per
input: `arm run turns input_tokens cache_read cache_creation hit_ratio
first_break`.

`hit_ratio = cache_read / (input + cache_read + cache_creation)`, summed over
all turns. A provider that never emits `cache_read_input_tokens` /
`cache_creation_input_tokens` on ANY turn gets `unreported` in place of a
number -- never coerced to 0.0, because a missing field and a reported zero
are different facts (see freepool below, which does both, on different
runs). `first_break` is the first turn (turn>1) whose per-turn ratio drops
below 0.5.

## Table -- 2026-09-02 runs (ROUND 3: denominator rule — all-zero usage is `unreported`, hit_ratio only over reported turns with tokens)

Round-2 numbers are superseded and live in git history (commit 17ed34a).
Tool changes since round 2 (round-3 review fix): a turn whose usage block is
ALL ZEROS — cache keys present or not — is no longer counted as "reported";
`hit_ratio` is printed ONLY when reported>0 AND input+cache_read+cache_creation>0
over the reported set, otherwise the cell is `unreported`. This changes one
historical row: freepool `260901-175619-repo-53e9` was `0.0000 / 1/67` — its
single cache-keyed request had all-zero usage, so it is now correctly
`unreported / 0/67` (re-run against the patched tool, 2026-09-02).

| arm | run | turns (unique msg ids) | input | cache_read | cache_creation | hit_ratio | first_break | reported |
|---|---|---|---|---|---|---|---|---|
| glm | 260902-000355-GLM-ARM-THROUGHPUT-01-106c | 120 | 0 | 0 | 0 | unreported | unreported | 0/120 |
| glm | 260902-000635-WORKERS-MUST-COMMIT-01-1c53 | 59 | 0 | 0 | 0 | unreported | unreported | 0/59 |
| glm | 260902-000806-BLO-PROOF-FIXTURE-3d52 | 2 | 0 | 0 | 0 | unreported | unreported | 0/2 |
| glm | 260902-002210-RESUME-LANE-ACCEPTS-PATH-01-350b | 37 | 0 | 0 | 0 | unreported | unreported | 0/37 |
| glm | 260902-003228-BEAT-LOOP-ORPHANS-01-31c2 | 29 | 0 | 0 | 0 | unreported | unreported | 0/29 |
| glm | 260902-003641-GLM-ARM-THROUGHPUT-01-5b8c | 45 | 0 | 0 | 0 | unreported | unreported | 0/45 |
| glm | 260902-005811-WORKERS-MUST-COMMIT-01-24f2 | 31 | 0 | 0 | 0 | unreported | unreported | 0/31 |
| glm | 260902-010057-FABLE-THINK-TIER-01-46d9 | 47 | 0 | 0 | 0 | unreported | unreported | 0/47 |
| glm | 260902-010704-MERGE-QUEUE-DEAD-HEAD-01-349f | 22 | 0 | 0 | 0 | unreported | unreported | 0/22 |
| glm | 260902-013219-LEADV2-HOOK-CACHE-DEPLOY-01-5030 | 42 | 0 | 0 | 0 | unreported | unreported | 0/42 |
| glm | 260902-013239-CACHE-TRUTH-01-7e2a | 23 | 0 | 0 | 0 | unreported | unreported | 0/23 |
| glm | 260902-013347-MERGE-QUEUE-DEAD-HEAD-01-3a7a | 25 | 0 | 0 | 0 | unreported | unreported | 0/25 |
| glm | 260902-015121-WORKER-MCP-ALL-ARMS-01-55bd | 46 | 0 | 0 | 0 | unreported | unreported | 0/46 |
| glm | 260902-015210-GUARD-CENSUS-IS-WRONG-01-71cc | 32 | 0 | 0 | 0 | unreported | unreported | 0/32 |
| glm | 260902-015738-LEADV2-HOOK-CACHE-DEPLOY-01-1437 | 52 | 0 | 0 | 0 | unreported | unreported | 0/52 |
| glm | 260902-021625-CACHE-TRUTH-01-54ae | 18 | 0 | 0 | 0 | unreported | unreported | 0/18 |
| glm | 260902-021904-STATUS-CHURN-01-4957 | 32 | 0 | 0 | 0 | unreported | unreported | 0/32 |
| glm | 260902-023609-GLM-EFFICIENCY-01-24d7 | 106 | 0 | 0 | 0 | unreported | unreported | 0/106 |
| glm | 260902-023632-FABLE-THINK-TIER-01-21c2 | 78 | 0 | 0 | 0 | unreported | unreported | 0/78 |
| glm | 260902-023831-GUARD-CENSUS-IS-WRONG-01-42b5 | 70 | 0 | 0 | 0 | unreported | unreported | 0/70 |
| glm | 260902-025223-WORKER-MCP-ALL-ARMS-01-61a7 | 58 | 0 | 0 | 0 | unreported | unreported | 0/58 |
| glm | 260902-032523-CACHE-TRUTH-01-3104 | 32 | 0 | 0 | 0 | unreported | unreported | 0/32 |
| freepool | 260901-235840-FABLE-THINK-TIER-01-7f82 (no 260902 freepool runs exist; latest run, started 2026-09-01T23:58Z) | 43 | 1,913,304 | 0 | 0 | unreported | unreported | 0/43 |

kimi / claude-runs: no runs dated 2026-09-02 exist in
`~/.claude/cache/{kimi,claude}-runs/` (checked 2026-09-02; latest kimi run is
`260901-123312-getmany-crm-reports-6939`, measured in round 2). The
claude-native sample (`dispatch-c293c1d5`, 95/95 reported, hit_ratio 0.9844)
is unchanged by the round-3 rule — all its reported turns carry real token
counts, none is all-zero.

Reproduce with:
```
plugins/leadv2/scripts/leadv2-cache-truth.sh ~/.claude/cache/glm-runs/260902-*/ \
  ~/.claude/cache/freepool-runs/260901-235840-FABLE-THINK-TIER-01-7f82
```

## Findings, per arm

### claude-native (`claude -p` direct spawn writing `developer.stream.jsonl`, `leadv2-dispatch-code.sh` line ~2997)
98.4% hit ratio across 95 unique assistant messages (176 raw stream events
before de-dup, confirming the round-1 review's 1.81x inflation claim):
15.07M cache_read tokens vs 190 fresh input tokens. `first_break=94` (not
`2` as round 1 reported -- that "2" was itself an artifact of counting
duplicate wire events as separate turns and hitting the per-turn <0.5 check
on a partial-delta message). Already cache-friendly; no fix needed.

### glm (glm-coder.sh, model `glm-5.3`, Z.AI)
`unreported` on every sampled run, unchanged after de-dup (102 and 38 unique
messages respectively, 0/102 and 0/38 reported). Raw usage object from run
`260901-041431-WATCHER-LIFECYCLE-LEAK-01-2ea1`, first assistant message,
pulled directly from `journal.jsonl`:
```
{"input_tokens": 0, "output_tokens": 0}
```
No `cache_read_input_tokens` / `cache_creation_input_tokens` key, and
`input_tokens`/`output_tokens` are both hardcoded/relayed as `0`.
**Conclusion (round 3): cache is UNMEASURABLE on api/anthropic (usage zeros)
— dashboard only.** This
matches Z.AI's documented Anthropic-compatible endpoint shape only
partially -- UNVERIFIED: whether Z.AI's own API (bypassing whatever proxy
glm-coder.sh talks to) ever includes prompt-cache fields; no doc URL was
checked this round, only the raw local artifact above. Conclusion stands:
provider-reporting gap, not a runner-prompt problem, based on the evidence
available (zero usage fields recorded, in every sampled run).

### freepool (freepool-coder.sh, TokenRouter proxy)
Round-1 said "cache keys PRESENT but always 0 across 137 requests, verified
by direct JSON inspection" -- this was FALSE per round-2 review: only 1 of
67 unique requests (137 raw events before de-dup) actually carries the
keys; the other 66 report nothing. Raw usage object for the one reported
request, pulled directly from `journal.jsonl` in run `...-repo-53e9`:
```
{"output_tokens_details": null, "input_tokens": 0, "output_tokens": 0,
 "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0,
 "server_tool_use": {"web_search_requests": 0, "web_fetch_requests": 0},
 "service_tier": null,
 "cache_creation": {"ephemeral_1h_input_tokens": 0, "ephemeral_5m_input_tokens": 0},
 "inference_geo": null, "iterations": null, "speed": null}
```
This IS a genuine Anthropic-shaped cache usage block (both flat and nested
`cache_creation` fields), all zero -- a real 0.0000 for that one request,
correctly distinct from the 66 unreported ones (reported=1/67). Run
`...-SUITE-THAT-CANNOT-FAIL-01-23b9`: 0/84 reported (`unreported`), same
day, same arm. Whichever backend TokenRouter routes a given request to
determines whether cache fields appear at all -- provider/routing-side,
inconsistent even WITHIN a single run, not something `freepool-coder.sh`'s
prompt assembly controls.

### kimi (kimi-coder.sh, TokenRouter)
The one 2026-09-01 run found (`260901-123312-getmany-crm-reports-6939`) has
zero assistant messages (73 `"type":"system"` lines only) -- consistent with
the probe-fail reroute path at kimi-coder.sh:178. No usable sample; reported
`unreported`/`none` rather than invented. Unchanged by de-dup (0 turns
either way).

## Runner-side cache-break candidates checked (mission step 2) -- none evidenced

Grepped all four runners for the candidates named in the mission:
- Timestamp/run-id near the TOP of the prompt: not found. `date +%s` calls
  exist in all four scripts but only for run bookkeeping (session labels,
  deadlines, meta.yaml) -- none write into `prompt.txt`. The prompt is
  `AGENT_BAN_PREAMBLE + mission_text + FINISH_CONTRACT_TRAILER`
  (glm-coder.sh:1830), no interpolated timestamp.
- Mission text before the stable system prompt: not applicable -- the
  mission IS the user-turn prompt; system prompt is a separate `claude -p`
  argument, not concatenated ahead of the mission in `prompt.txt`.
- Per-turn `--append-system-prompt` variation: MCP config / spawn args are
  resolved once per run in all four scripts, not per turn.
- `--mcp-config` differences between spawns of the same role: all four
  resolve `--mcp-config` through the same role-scoped
  `resolve_role_mcp_config` / `worker_mcp_resolve` helper
  (`plugins/leadv2/config/mcp-role-<role>.json`); `--strict-mcp-config`
  travels alongside it (glm-coder.sh:363, claude-subsession.sh:536).

Conclusion: no runner-prompt-structure fix is evidenced. The real problem
the numbers surface -- GLM and (intermittently) freepool report no cache
fields at all -- is provider/proxy-side, outside the four coder scripts'
control. Per "fix only what the numbers prove," no code change was made to
any runner script. Documented absence of evidence, not evidence of absence:
a future run against a TokenRouter/Z.AI endpoint that DOES report cache
fields consistently would falsify "provider-side" and point back at the
runner.

## Other efficiency levers (mission step 3) -- counts only

- `--max-turns` present on every arm (glm-coder.sh, freepool-coder.sh,
  kimi-coder.sh, claude-subsession.sh all pass it). Lever already in place.
- Re-read counting (Read calls >200 lines/run) not implemented -- out of
  scope (belongs to WORKER-MCP-ALL-ARMS-01 per the mission). Flagged as a
  follow-up measurement, not attempted here.

## Suite: `plugins/leadv2/scripts/tests/test-cache-truth.sh`

10 cases, <2s wall. Fixtures: (1) Anthropic shape with cache fields, ratio
~0.62, no break; (2) Anthropic shape with a genuine break at turn 2; (3) no
cache fields at all -> `unreported`, never coerced to 0; (4) cache fields
present but genuinely zero -> `0.0000`, distinct from (3) -- the exact
distinction real freepool data showed; (5) missing stream file -> non-zero
exit + `ERROR`, not a silent pass; (6) mutation negative control (below).

`EXTRA_SUITE_MAP` rows added to `tests/run-all.sh` (stem mismatch between
the runner scripts / the tool and `test-cache-truth.sh` means automatic
stem-matching alone would miss it):
```
leadv2-cache-truth.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
glm-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
freepool-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
kimi-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
claude-subsession.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
```
Verified by a stem-lookup simulation against the live `EXTRA_SUITE_MAP`
string: all five stems resolve to `test-cache-truth.sh`. `run-all.sh
--scope changed` itself invokes `run-core-offline.sh` first (83 suites,
>10min per prior-lane MEMORY finding), so it was not run to completion
inside this lane's turn budget; the wiring was proven directly against the
map instead of via a full canonical run.

## Standalone mutation negative control (mission step 5) -- RUN, pasted red

```
$ sed 's/overall_ratio = (total_cr \/ denom) if denom > 0 else 0.0/overall_ratio = (total_cc \/ denom) if denom > 0 else 0.0/' \
    plugins/leadv2/scripts/leadv2-cache-truth.sh > mutant, moved into place
[TEST] FAIL: anthropic fixture: overall hit ratio expected ~0.62 got '0.3691'
PASS=9 FAIL=1
RC=1
```
Reverted immediately after (`git diff` on the tool showed no diff
afterward -- the mutation never touched the committed content).

## Round 2 evidence

Reviewer glm found two real bugs in round 1 (see brief above / fix-round-2.md):
1. no de-dup by `message.id` -> totals inflated ~1.81x (176 raw events vs 95
   unique ids on `dispatch-c293c1d5`; 27.24M cache_read vs 15.07M).
2. `saw_cache_key` was a per-RUN global, so a mixed reported/unreported
   stream (freepool `...-repo-53e9`, 1 of 137 raw requests carrying the
   keys) was misclassified as a real `0.0000` for the whole run instead of
   `1/67` reported (unique) requests, 66 unreported.

Both are fixed in `leadv2-cache-truth.sh`:
- Events are grouped by `message.id`, last event per id wins; unkeyed
  events (no id) are each kept as their own turn.
- Classification into reported/unreported is now PER TURN (checks
  `cache_read_input_tokens`/`cache_creation_input_tokens` presence on that
  turn's usage dict, not a single global flag); the output row's `hit_ratio`
  is computed over the reported subset only, and a new `reported` column
  (`N/M`) makes a mixed run visible instead of silently rounding to all-or-
  nothing.

Two new fixtures added to `test-cache-truth.sh`: fixture 4b (mixed
reported/unreported, expects `reported=1/3`) and the dup-id fixture (5 raw
events / 2 unique ids, expects `turns=2` and ratio computed on the
de-duplicated totals ~0.4569).

Mutation negative controls, RUN standalone against throwaway copies (not
the committed tool -- `git diff` on `leadv2-cache-truth.sh` after these runs
showed no incidental changes):

```
$ mutant (a): strip id de-dup, route every event through the unkeyed path
[TEST] FAIL: dup-id fixture: expected turns=2 got '5'
[TEST] FAIL: dup-id fixture: expected ratio ~0.4569 got '0.3636'
PASS=14 FAIL=2

$ mutant (b): make reported_turns global again (any() instead of per-item filter)
[TEST] FAIL: mixed fixture: expected reported=1/3 got '3/3'
PASS=15 FAIL=1
```

Both mutations reverted (they only ever existed as throwaway copies under
`mktemp -d`, never applied to the tracked file). Full suite against the
real (fixed) tool, all green:

```
PASS=16 FAIL=0
```

Falsifiability check:
```
$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-cache-truth.sh
leadv2-suite-falsifiable: suite=.../plugins/leadv2/scripts/tests/test-cache-truth.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=4
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

The table and per-arm findings above have been replaced with the corrected,
de-duplicated, per-request-classified numbers re-run against the same six
2026-09-01 inputs used in round 1. The freepool "cache keys PRESENT but
always 0" claim from round 1 is corrected to "1 of 67 unique requests
reports the keys (genuinely 0), the other 66 report nothing" -- reported=1/67,
matching the reviewer's math on the raw event count (1/137 raw events, same
1 unique request, the other 136 raw events being duplicates or unreported
turns).

## Round 3 evidence

Round-3 review verdict (reviewer opus, `review-opus.md`) — FAIL, high=3:

1. `leadv2-cache-truth.sh:178` — zero denominator printed a fabricated
   `hit_ratio 0.0000` instead of `unreported`, violating the tool's own
   missing-is-not-zero rule. Reviewer's probe: one reported turn with
   all-zero usage produced `unknown tmp 1 0 0 0 0.0000 none 1/1` rc=0.
2. `test-cache-truth.sh:236` — mutation controls 2 and 3 printed
   "control proven red-capable" when their python assert fired and the
   mutant was never created (empty output "diverges" from everything).
   Reviewer's probe: perturbed anchor -> turns='' -> suite still
   PASS=16 FAIL=0. The controls were theatre.
3. Round-2 diff carried lead-owned runtime files (fixed by pathspec commits).

### Fix 1 — denominator rule

`leadv2-cache-truth.sh` now classifies a turn as REPORTED only if it carries
a cache key AND its usage is not all zeros; `hit_ratio` is printed only when
reported>0 AND input+cache_read+cache_creation>0 over the reported set,
otherwise `unreported`. The reviewer's exact probe, re-run against the
patched tool:

```
$ printf '%s\n' '{"type":"assistant","message":{"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}' > "$T/glm-runs/260902-fixture-allzero/journal.jsonl"
$ bash plugins/leadv2/scripts/leadv2-cache-truth.sh "$T/glm-runs/260902-fixture-allzero"
arm	run	turns	input_tokens	cache_read	cache_creation	hit_ratio	first_break	reported
glm	260902-fixture-allzero	1	0	0	0	unreported	unreported	0/1
rc=0
```

This probe is now suite fixture 4d (expects `unreported` and `reported=0/1`).

### Fix 2 — mutation controls fail loud

Each control now (a) verifies its anchor exists in the source with
`grep -c` == 1 BEFORE mutating, (b) verifies the mutant file exists and is
non-empty, (c) verifies the mutant emitted a well-formed 9-column row with a
numeric turns cell — any miss fails the suite as `control_not_applied`
instead of printing "control proven red-capable".

RED — all three anchors perturbed in a throwaway copy of suite+tool (the
controls refuse to claim anything when the mutant cannot be created):

```
[TEST] FAIL: MUTATION CONTROL NOT APPLIED: control 1 (numerator swap): sed anchor did not match or mutant not created (control_not_applied)
[TEST] FAIL: MUTATION CONTROL NOT APPLIED: control 2 (dedup removal): python anchor did not match or mutant not created (control_not_applied)
[TEST] FAIL: MUTATION CONTROL NOT APPLIED: control 3 (global-key): python anchor did not match or mutant not created (control_not_applied)
PASS=0 FAIL=18
```

(In the first committed version of fix 2 the fail-loud machinery itself
caught two real plumbing bugs before anything was committed: sed's `s/…/…/`
delimiter clashed with the literal `/` in the anchor — `bad flag in
substitute command` — and the `is_row` awk probe used `END{exit 1}`, which
clobbers a match `exit 0`. Both were red before the controls went green —
the fail-loud path proving itself on its own author.)

GREEN — anchors intact, controls 1–3 each produce a real RED-capable mutant
against the unmutated suite:

```
[TEST] PASS: MUTATION CONTROL: mutant ratio diverged from correct 0.62 (got '0.3691') — control proven red-capable
[TEST] PASS: MUTATION CONTROL (dedup): mutant reported turns='5' (expected 5, not 2) — control proven red-capable
[TEST] PASS: MUTATION CONTROL (global-key): mutant reported='3/3' (expected 3/3, not 1/3) — control proven red-capable
PASS=18 FAIL=0
```

Each mutant's actual failing assertion, isolated (mutant run standalone):

- control 1 (numerator cache_read->cache_creation): fixture-1 ratio assertion
  would read `expected ~0.62 got '0.3691'` — the suite's `fail` branch.
- control 2 (dedup removed): mutant row `claude-native dispatch-fixture-dup 5 50 1800 3100 0.3636 2 5/5`
  -> `dup-id fixture: expected turns=2 got '5'` and `expected ratio ~0.4569 got '0.3636'`.
- control 3 (global-key): mutant row `freepool 260901-fixture-mixed 3 200 0 0 0.0000 2 3/3`
  -> `mixed fixture: expected reported=1/3 got '3/3'`.

Reverted = the mutants only ever existed as throwaway copies under
`mktemp -d`; `git diff` on `leadv2-cache-truth.sh` shows only the intended
round-3 changes.

### Full suite (real tool, all fixtures)

```
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-cache-truth.sh
PASS=18 FAIL=0
```

### Falsifiability

```
$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-cache-truth.sh
leadv2-suite-falsifiable: suite=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CACHE-TRUTH-01/plugins/leadv2/scripts/tests/test-cache-truth.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=6
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

### Changed-scope suite selection

## What was NOT done

- No code change to any of the four runner scripts -- data does not prove a
  runner-side fix (see above).
- Re-read counting (Read >200-line calls per run) not implemented; flagged
  as follow-up, out of this lane's scope.
- `run-all.sh --scope changed` not run to full completion (>10min via
  run-core-offline). R4 update: selection is now proven with an exact-scan
  harness (see R4 section) — and the R3 "direct stem-map simulation" claim
  was wrong anyway: the four arm rows it claimed did not exist (R4 finding 2,
  REAL).

## R4 findings (round-3 review, committed-tree diff a8ca06c2, verdict FAIL high=2)

| # | Finding | Verdict | Evidence |
|---|---------|---------|----------|
| 1 | `leadv2-cache-truth.sh` — on a mixed stream `input_tokens` sums only REPORTED turns while the `n_reported==0` branch sums ALL turns (one column, two definitions) | **REAL** | Pre-fix probe on the lane tip (reported turn in=100 + unreported turn in=400): tool printed `input_tokens=100` — 400 tokens of real input silently dropped. Suite red run (old tool + new suite): `[TEST] FAIL: mixed fixture: expected input_tokens=200 got '100'` (PASS=7 FAIL=13, rc=1). |
| 2 | `tests/run-all.sh` EXTRA_SUITE_MAP — deliverable claimed 5 cache-truth rows "verified", only `leadv2-cache-truth.sh` existed; `glm-coder.sh` / `freepool-coder.sh` / `kimi-coder.sh` / `claude-subsession.sh` did not map to `test-cache-truth.sh` | **REAL** | Pre-fix: `grep -n "test-cache-truth" tests/run-all.sh` → single hit at line 237 (`leadv2-cache-truth.sh:...`); the four arm rows were absent. |

### R4 fix — finding 1 (one definition per column)

Chosen: **`input_tokens` sums ALL turns in every branch; new `input_reported`
column sums the reported subset.** `hit_ratio` denominator stays the reported
subset (`input_reported + cache_read + cache_creation`); `cache_read` /
`cache_creation` remain reported-subset sums. Documented in the printed header
line (the new column name itself) and the file header comment. Post-fix probe
(same 100+400 stream):

```
arm	run	turns	input_tokens	input_reported	cache_read	cache_creation	hit_ratio	first_break	reported
unknown	tmp.NzsENbRR2X	2	500	100	0	0	0.0000	none	1/2
```

New suite assertions, hand-computed from the mixed fixture (m1=100 reported,
m2/m3=50 unreported): `input_tokens = 100+50+50 = 200`, `input_reported = 100`.

### R4 fix — finding 2 (4 missing map rows)

Rows added at `tests/run-all.sh:243-246`: `glm-coder.sh`, `freepool-coder.sh`,
`kimi-coder.sh`, `claude-subsession.sh` →
`plugins/leadv2/scripts/tests/test-cache-truth.sh`.

Selection proof — exact-scan harness (lines 1..411 of `tests/run-all.sh` = arg
parsing + the whole `--scope changed` scan, plus a `SELECTED:` print instead of
the execution loop), state file pinned to HEAD so the changed set is exactly
one dirty file, `plugins/leadv2/scripts/glm-coder.sh` (comment marker, reverted
after the run):

```
SELECTED: .../plugins/leadv2/scripts/tests/run-core-offline.sh
SELECTED: .../tests/test-status-surface-bash32.sh
SELECTED: .../tests/test-status-surface-single-lead.sh
SELECTED: .../tests/test-status-surface-fast-names.sh
SELECTED: .../plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh
SELECTED: .../plugins/leadv2/scripts/tests/test-glm-flash-handle.sh
SELECTED: .../plugins/leadv2/scripts/tests/test-cache-truth.sh
SELECTED: .../plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh
SELECTED: .../plugins/leadv2/scripts/tests/test-lane-outcome.sh
harness-rc=0
```

`test-cache-truth.sh` is selected from a glm-coder.sh-only change.
Attribution: after the R4 commit, no other dirty or in-range file maps to that
suite, so the new row itself is what fired. (`run-all.sh --dry-run` does not
exist — no such flag; the scan-exact harness is the equivalent listing.)

### R4 suite + falsifiable (from lane root as cwd)

```
$ bash plugins/leadv2/scripts/tests/test-cache-truth.sh
[TEST] PASS: mixed fixture: input_tokens sums ALL turns (hand-computed 100+50+50=200)
[TEST] PASS: mixed fixture: input_reported sums reported subset only (hand-computed 100)
...
PASS=20 FAIL=0

$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-cache-truth.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=6
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```
