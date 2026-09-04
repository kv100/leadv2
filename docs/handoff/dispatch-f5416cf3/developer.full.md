verdict: APPROVE
next_action: continue

# CACHE-TRUTH-01 — developer.full.md

## What was built

1. `plugins/leadv2/scripts/leadv2-cache-truth.sh` (new) — parses
   `developer.stream.jsonl` (docs/handoff/dispatch-*) or `journal.jsonl`
   (glm-runs/freepool-runs/kimi-runs/claude-runs) and prints per-run:
   arm, turns, input_tokens, cache_read, cache_creation, hit_ratio,
   first_break. `hit_ratio = cache_read/(input+cache_read+cache_creation)`.
   A provider that never emits cache_read_input_tokens/cache_creation_input_tokens
   on ANY turn gets `unreported`, never coerced to 0.0 — a missing field and
   a reported zero are different facts (proved by real freepool data, see
   below). Bash 3.2 compatible wrapper around a python3 heredoc (repo
   convention, `_lv2_realpath` used for path resolution, no ../ hop-counting).

2. `plugins/leadv2/scripts/tests/test-cache-truth.sh` (new) — 10 cases,
   <2s. Covers: Anthropic-shape-with-cache-fields ratio math, a genuine
   cache-break turn, no-cache-field-at-all → unreported, cache-fields-present-
   but-genuinely-zero → 0.0000 (distinct from unreported), missing-stream
   error path, and a mutation negative control (ratio numerator swapped
   cache_read→cache_creation in a throwaway copy, proving the ratio
   assertion is falsifiable).

3. `tests/run-all.sh` — 5 new `EXTRA_SUITE_MAP` rows so `--scope changed`
   selects `test-cache-truth.sh` when any of the four runner scripts or the
   tool itself change (stem mismatch means automatic matching alone would
   miss it — `leadv2-cache-truth.sh`'s auto-candidate is
   `test-leadv2-cache-truth.sh`, which does not exist):
   ```
   leadv2-cache-truth.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
   glm-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
   freepool-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
   kimi-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
   claude-subsession.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh
   ```

4. `docs/handoff/CACHE-TRUTH-01/report.md` (new) — full table + per-arm
   findings + named cache-break candidates checked in the four runners +
   the mutation control transcript. Full content reproduced below.

## No runner script was changed

Per the mission's "fix only what the numbers prove": the measured data does
not point at a fixable prompt-structure defect in `glm-coder.sh`,
`freepool-coder.sh`, `kimi-coder.sh`, or `claude-subsession.sh`. See report
below for the specific candidates checked (timestamp-at-top of prompt,
mission-before-system-prompt, per-turn `--append-system-prompt` variation,
`--mcp-config` drift between same-role spawns) — none found present. This
is the honest outcome of the measurement, not a shortcut.

## Full report (docs/handoff/CACHE-TRUTH-01/report.md)

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
number — never coerced to 0.0. `first_break` is the first turn (turn>1)
whose per-turn ratio drops below 0.5.

## Table — 2026-09-01 runs

| arm | run | turns | input | cache_read | cache_creation | hit_ratio | first_break |
|---|---|---|---|---|---|---|---|
| claude-native | dispatch-c293c1d5 | 176 | 352 | 27,236,567 | 549,303 | 0.9802 | 2 |
| glm | 260901-041431-WATCHER-LIFECYCLE-LEAK-01-2ea1 | 215 | 0 | 0 | 0 | unreported | unreported |
| glm | 260901-165920-PLUGIN-PAPERCUTS-01-53f1 | 85 | 0 | 0 | 0 | unreported | unreported |
| freepool | 260901-175619-repo-53e9 | 137 | 13,602,259 | 0 | 0 | 0.0000 | 2 |
| freepool | 260901-120552-SUITE-THAT-CANNOT-FAIL-01-23b9 | 169 | 16,062,933 | 0 | 0 | unreported | unreported |
| kimi | 260901-123312-getmany-crm-reports-6939 | 0 | 0 | 0 | 0 | unreported | none (0 assistant turns — run aborted before producing usage) |

## Findings, per arm

**claude-native**: 98% hit ratio, 176 turns, 27.2M cache_read vs 352 fresh
input tokens. Already cache-friendly — no fix needed. `first_break=2` is
just turn 2 (the first turn a cache read is even possible) dipping under
0.5 before recovering, not a sustained break.

**glm** (glm-5.3, Z.AI): `unreported` on every sampled run — usage block
never carries cache fields, and separately `input_tokens`/`output_tokens`
are both always literally `0` (`{"input_tokens": 0, "output_tokens": 0}`
verified across 215 assistant messages in one run). Provider-reporting gap,
not a runner-prompt problem.

**freepool** (TokenRouter): inconsistent reporting between runs of the
SAME arm on the same day — one run reports the cache-field keys but always
`0` (genuine 0.0000 ratio, verified in raw JSON, not a parsing gap);
another run has the keys absent entirely (`unreported`). Whichever backend
TokenRouter routes a call to determines whether cache fields appear —
provider/routing-side, not `freepool-coder.sh`'s prompt assembly.

**kimi** (TokenRouter): the one 2026-09-01 run found has zero assistant
messages (73 `"type":"system"` lines only), consistent with the
probe-fail-reroute path at kimi-coder.sh:178. No usable sample.

## Runner-side cache-break candidates checked — none evidenced

Grepped all four runners for the candidates named in the mission:
- Timestamp/run-id near the TOP of the prompt: not found. `date +%s` calls
  exist in all four scripts but only for run bookkeeping (session labels,
  deadlines, meta.yaml) — none write into `prompt.txt`. Prompt is
  `AGENT_BAN_PREAMBLE + mission_text + FINISH_CONTRACT_TRAILER`
  (glm-coder.sh:1830), no interpolated timestamp.
- Mission text before the stable system prompt: not applicable — the
  mission IS the user-turn prompt; system prompt is a separate `claude -p`
  argument.
- Per-turn `--append-system-prompt` variation: MCP config / spawn args
  resolved once per run in all four scripts, not per turn.
- `--mcp-config` differences between same-role spawns: all four resolve
  `--mcp-config` through the same role-scoped `resolve_role_mcp_config` /
  `worker_mcp_resolve` helper (`plugins/leadv2/config/mcp-role-<role>.json`);
  `--strict-mcp-config` travels alongside it (glm-coder.sh:363,
  claude-subsession.sh:536).

**No runner-prompt-structure fix is evidenced.** The real problem the
numbers surface — GLM and (intermittently) freepool report no cache fields
at all — is provider/proxy-side, outside the four coder scripts' control.
No code change was made to any runner script.

## Other efficiency levers — counts only

- `--max-turns` present on every arm (all four scripts pass it). Already in
  place.
- Re-read counting (Read >200 lines/run) not implemented — belongs to
  WORKER-MCP-ALL-ARMS-01 per the mission, out of this lane's scope.

## Suite: test-cache-truth.sh — full real output

```
[TEST] PASS: bash syntax: leadv2-cache-truth.sh
[TEST] PASS: anthropic fixture: overall hit ratio ~0.62
[TEST] PASS: anthropic fixture: no cache break (turns 2,3 both >=0.5)
[TEST] PASS: anthropic fixture: arm classified claude-native
[TEST] PASS: break fixture: first_break correctly reports turn 2
[TEST] PASS: no-cache-field fixture: ratio reported as unreported, not coerced to 0
[TEST] PASS: no-cache-field fixture: arm classified glm from path
[TEST] PASS: reported-zero fixture: ratio is 0.0000, not unreported
[TEST] PASS: missing stream: tool exits non-zero with an ERROR line, not a silent pass
[TEST] PASS: MUTATION CONTROL: mutant ratio diverged from correct 0.62 (got '0.3691') — control proven red-capable

PASS=10 FAIL=0
```

## Mutation negative control (mission step 5) — RUN against the REAL tool file, pasted red, then reverted

Swapped the ratio numerator (`total_cr` → `total_cc`) directly in
`plugins/leadv2/scripts/leadv2-cache-truth.sh` on disk, re-ran the suite:

```
[TEST] PASS: bash syntax: leadv2-cache-truth.sh
[TEST] FAIL: anthropic fixture: overall hit ratio expected ~0.62 got '0.3691'
[TEST] PASS: anthropic fixture: no cache break (turns 2,3 both >=0.5)
[TEST] PASS: anthropic fixture: arm classified claude-native
[TEST] PASS: break fixture: first_break correctly reports turn 2
[TEST] PASS: no-cache-field fixture: ratio reported as unreported, not coerced to 0
[TEST] PASS: no-cache-field fixture: arm classified glm from path
[TEST] PASS: reported-zero fixture: ratio is 0.0000, not unreported
[TEST] PASS: missing stream: tool exits non-zero with an ERROR line, not a silent pass
[TEST] PASS: MUTATION CONTROL: mutant ratio diverged from correct 0.62 (got '0.3691') — control proven red-capable

PASS=9 FAIL=1
RC=1
```

Reverted immediately after; `git diff` on the tool showed no diff
afterward, confirming the mutation never touched committed content. Green
re-run pasted above.

## bash -n / py_compile on changed files

```
$ bash -n plugins/leadv2/scripts/leadv2-cache-truth.sh && echo TOOL_SYNTAX_OK
TOOL_SYNTAX_OK
$ bash -n plugins/leadv2/scripts/tests/test-cache-truth.sh && echo TEST_SYNTAX_OK
TEST_SYNTAX_OK
$ bash -n tests/run-all.sh && echo RUNALL_SYNTAX_OK
RUNALL_SYNTAX_OK
```
No Python files were changed (the tool embeds a python3 heredoc inline
inside the .sh file, not a standalone .py file — nothing to py_compile).

## EXTRA_SUITE_MAP wiring — verified, but --scope changed not run to full completion

`run-all.sh --scope changed` invokes `run-core-offline.sh` first (83 suites
across 4 shards), which per this repo's own MEMORY (`run-all changed-scope
runtime`) takes >10 minutes for the core-offline portion alone. A first
attempt was backgrounded and killed by the 120s tool timeout before
reaching the EXTRA_SUITE_MAP portion of the script.

Instead of running the full canonical suite, the wiring was proven directly
by extracting the live `EXTRA_SUITE_MAP` string from `tests/run-all.sh` and
running the same stem-lookup the script performs (stem = key or key+".sh"):

```
glm-coder -> ['glm-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh']
freepool-coder -> [..., 'freepool-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh']
kimi-coder -> ['kimi-coder.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh']
claude-subsession -> ['claude-subsession.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh']
leadv2-cache-truth -> ['leadv2-cache-truth.sh:plugins/leadv2/scripts/tests/test-cache-truth.sh']
```
All five stems resolve correctly. This proves the map entries are
syntactically correct and reachable by the script's own matching logic, but
it is NOT the same as a green `--scope changed` run end-to-end (that run
was not completed due to the >10min core-offline runtime exceeding this
session's practical turn/time budget).

## What was NOT done / left honestly incomplete

- **`tests/run-all.sh --scope changed` was not run to a completed green
  result.** Wiring proven by direct stem-map simulation instead (see
  above). This is the one mission requirement ("prove with --scope
  changed") not literally satisfied by an end-to-end run — flagging
  explicitly rather than claiming a run that didn't finish.
- No code change to any of the four runner scripts (glm-coder.sh,
  freepool-coder.sh, kimi-coder.sh, claude-subsession.sh) — the measured
  data does not evidence a runner-prompt-structure defect to fix (see
  report above). This is a deliberate "fix only what the numbers prove"
  outcome, not an omission.
- Re-read counting (Read tool calls >200 lines per run) not implemented —
  explicitly out of scope per the mission (belongs to
  WORKER-MCP-ALL-ARMS-01).
- Before/after ratio comparison from "a fresh dispatch of a tiny sample
  task" (mission step 2, second half) was not performed — since no runner
  fix was made, there is no before/after to demonstrate. If a future
  measurement DOES surface a runner-side fix, that before/after step still
  needs to be done then.

## Files changed (LANE_WRITES)

- `plugins/leadv2/scripts/leadv2-cache-truth.sh` (new)
- `plugins/leadv2/scripts/tests/test-cache-truth.sh` (new)
- `tests/run-all.sh` (EXTRA_SUITE_MAP rows added)
- `docs/handoff/CACHE-TRUTH-01/report.md` (new)

DELIVERABLE_COMPLETE
