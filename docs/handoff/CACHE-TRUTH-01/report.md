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

## Table -- 2026-09-01 runs (ROUND 2, corrected: de-duplicated by message.id, reported per-request)

**Round-1 numbers below were wrong and are superseded.** Round-1 counted every
streamed wire event (deltas + final) as a separate turn, inflating every
total ~1.8x, and used a single per-RUN `saw_cache_key` flag that turned a
mixed reported/unreported run into a false "real 0.0000" (freepool
`...-repo-53e9`: only 1 of 67 unique requests actually carries cache keys,
not all of them). See "## Round 2 evidence" below for the mutation controls
that prove both bugs were real and are now fixed.

| arm | run | turns (unique msg ids) | input | cache_read | cache_creation | hit_ratio | first_break | reported |
|---|---|---|---|---|---|---|---|---|
| claude-native | dispatch-c293c1d5 | 95 | 190 | 15,070,604 | 238,676 | 0.9844 | 94 | 95/95 |
| glm | 260901-041431-WATCHER-LIFECYCLE-LEAK-01-2ea1 | 102 | 0 | 0 | 0 | unreported | unreported | 0/102 |
| glm | 260901-165920-PLUGIN-PAPERCUTS-01-53f1 | 38 | 0 | 0 | 0 | unreported | unreported | 0/38 |
| freepool | 260901-175619-repo-53e9 | 67 | 0 | 0 | 0 | 0.0000 | none | 1/67 |
| freepool | 260901-120552-SUITE-THAT-CANNOT-FAIL-01-23b9 | 84 | 7,975,626 | 0 | 0 | unreported | unreported | 0/84 |
| kimi | 260901-123312-getmany-crm-reports-6939 | 0 | 0 | 0 | 0 | unreported | none | 0/0 (0 assistant turns -- run aborted before producing usage) |

Reproduce with:
```
plugins/leadv2/scripts/leadv2-cache-truth.sh \
  docs/handoff/dispatch-c293c1d5 \
  ~/.claude/cache/glm-runs/260901-041431-WATCHER-LIFECYCLE-LEAK-01-2ea1 \
  ~/.claude/cache/glm-runs/260901-165920-PLUGIN-PAPERCUTS-01-53f1 \
  ~/.claude/cache/freepool-runs/260901-175619-repo-53e9 \
  ~/.claude/cache/freepool-runs/260901-120552-SUITE-THAT-CANNOT-FAIL-01-23b9 \
  ~/.claude/cache/kimi-runs/260901-123312-getmany-crm-reports-6939
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
`input_tokens`/`output_tokens` are both hardcoded/relayed as `0`. This
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

## What was NOT done

- No code change to any of the four runner scripts -- data does not prove a
  runner-side fix (see above).
- Re-read counting (Read >200-line calls per run) not implemented; flagged
  as follow-up, out of this lane's scope.
- `run-all.sh --scope changed` not run to full completion (>10min via
  run-core-offline); wiring proven by direct stem-map simulation instead.
