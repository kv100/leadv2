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

## Table -- 2026-09-01 runs

| arm | run | turns | input | cache_read | cache_creation | hit_ratio | first_break |
|---|---|---|---|---|---|---|---|
| claude-native | dispatch-c293c1d5 | 176 | 352 | 27,236,567 | 549,303 | 0.9802 | 2 |
| glm | 260901-041431-WATCHER-LIFECYCLE-LEAK-01-2ea1 | 215 | 0 | 0 | 0 | unreported | unreported |
| glm | 260901-165920-PLUGIN-PAPERCUTS-01-53f1 | 85 | 0 | 0 | 0 | unreported | unreported |
| freepool | 260901-175619-repo-53e9 | 137 | 13,602,259 | 0 | 0 | 0.0000 | 2 |
| freepool | 260901-120552-SUITE-THAT-CANNOT-FAIL-01-23b9 | 169 | 16,062,933 | 0 | 0 | unreported | unreported |
| kimi | 260901-123312-getmany-crm-reports-6939 | 0 | 0 | 0 | 0 | unreported | none (0 assistant turns -- run aborted before producing usage) |

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
98% hit ratio across a 176-turn run: 27.2M cache_read tokens vs 352 fresh
input tokens. `first_break=2` is only turn 2 itself (the first turn a cache
read is even possible) dipping under 0.5 before recovering -- not a
sustained break. Already cache-friendly; no fix needed.

### glm (glm-coder.sh, model `glm-5.3`, Z.AI)
`unreported` on every sampled run. `journal.jsonl`'s assistant `usage`
block never carries `cache_read_input_tokens` / `cache_creation_input_tokens`
-- and separately `input_tokens`/`output_tokens` are both always `0`
(`{"input_tokens": 0, "output_tokens": 0}` on every one of 215 assistant
messages in one run, verified directly). Z.AI's relayed usage block simply
doesn't populate token counts. Provider-reporting gap, not a runner-prompt
problem -- no cache signal exists to optimize toward.

### freepool (freepool-coder.sh, TokenRouter proxy)
Inconsistent reporting between runs of the SAME arm -- exactly what this
measurement exists to catch. Run `...-repo-53e9`: cache_read/cache_creation
keys ARE present but always `0` across 137 turns (real 0.0000 ratio,
verified by direct JSON inspection, not a parsing gap). Run
`...-SUITE-THAT-CANNOT-FAIL-01-23b9`: keys absent entirely (`unreported`),
same day, same arm. Whichever backend TokenRouter routes to determines
whether cache fields appear -- provider/routing-side, not something
`freepool-coder.sh`'s prompt assembly controls.

### kimi (kimi-coder.sh, TokenRouter)
The one 2026-09-01 run found (`260901-123312-getmany-crm-reports-6939`) has
zero assistant messages (73 `"type":"system"` lines only) -- consistent with
the probe-fail reroute path at kimi-coder.sh:178. No usable sample; reported
`unreported`/`none` rather than invented.

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

## What was NOT done

- No code change to any of the four runner scripts -- data does not prove a
  runner-side fix (see above).
- Re-read counting (Read >200-line calls per run) not implemented; flagged
  as follow-up, out of this lane's scope.
- `run-all.sh --scope changed` not run to full completion (>10min via
  run-core-offline); wiring proven by direct stem-map simulation instead.
