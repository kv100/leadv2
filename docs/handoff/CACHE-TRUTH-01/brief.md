# CACHE-TRUTH-01 — measure prompt-cache hit rate per arm, then make every arm cache-friendly

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CACHE-TRUTH-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-cache-truth.sh,plugins/leadv2/scripts/glm-coder.sh,plugins/leadv2/scripts/freepool-coder.sh,plugins/leadv2/scripts/kimi-coder.sh,plugins/leadv2/scripts/claude-subsession.sh,plugins/leadv2/scripts/tests/test-cache-truth.sh,tests/run-all.sh,docs/handoff/CACHE-TRUTH-01/
Run suites with `LEADV2_SUITE_LOCK_DISABLE=1`. Class: Standard. This is a MEASURE-FIRST lane:
step 1 produces numbers before any change to a runner.

## Why (founder, 2026-09-01)
"кеширование + другие способы экономии и эффективной работы всех моделей всех провайдеров — а так
ли у нас я хз". Nobody has measured. Every arm spawns `claude -p` (glm-coder.sh, freepool-coder.sh,
kimi-coder.sh, claude-subsession.sh) with a long mission prompt; whether the stable prefix (system
prompt, brief, CLAUDE.md, MCP tool schemas) is actually served from cache on each turn is unknown.
Facts: Anthropic caches automatically on `claude -p` and reports `cache_read_input_tokens` /
`cache_creation_input_tokens` in every `assistant` message's `usage` in the stream-json; Z.AI
(GLM) and Kimi (TokenRouter) either report their own cache fields or report none — a missing
field is itself a finding, not a zero. A haiku audit earlier today invented a `--cache-control`
flag that does not exist — do NOT trust prior prose; read the stream files.

## Do
1. `leadv2-cache-truth.sh <run-dir|stream.jsonl>...`: parse `developer.stream.jsonl` (and the
   run's progress.log) and print per run: arm, turns, input tokens, `cache_read`, `cache_creation`,
   hit ratio = cache_read / (input + cache_read + cache_creation), and the first turn where the
   ratio drops below 0.5 (a cache break). Run it over TODAY's runs
   (`~/.claude/cache/glm-runs/260901-*`, `freepool-runs/260901-*`,
   `docs/handoff/dispatch-*/developer.stream.jsonl`) and put the table in `report.md` — per arm.
   If a provider's stream carries no cache fields, the table says `unreported` for that arm.
2. From the table, name the cache breaks by cause. Candidates to check in the runners: a timestamp
   or run-id interpolated near the TOP of the prompt (breaks the prefix every run), the mission
   text placed BEFORE the stable system prompt, per-turn `--append-system-prompt` variation,
   `--mcp-config` differences between spawns of the same role (tool schemas are part of the
   prefix). Fix only what the numbers prove; each fix is one commit with the before/after ratio
   from the tool run on a fresh dispatch of a tiny sample task (use a hermetic fixture task, not a
   real lane).
3. Other efficiency levers, only where a measurement shows waste: `--max-turns` present on every
   arm? Does each worker re-read files a `get_context(include=[skeleton])` would replace (count
   `Read` tool calls > 200 lines per run)? Report counts; do not rewrite the MCP routing here —
   that is WORKER-MCP-ALL-ARMS-01.
4. Suite `test-cache-truth.sh` with a fixture stream (Anthropic shape with cache fields; a shape
   without them) asserting the ratio arithmetic and the `unreported` path. Under 10 s.
   `EXTRA_SUITE_MAP` row; prove with `--scope changed`.
5. Mutation negative control, RUN and paste red: swap numerator to `cache_creation` → ratio case
   red. Revert.
6. `report.md`: the table, the named breaks, before/after for each fix. Commit in the lane.
