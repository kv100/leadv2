# BRIEF-02 — where the tokens actually go

Round 1 measured how many turns there are. It got two headline numbers wrong and both arms caught
it; see BRIEF.md's correction header. Round 2 measures **what a turn is made of**, and the answer
moves the whole problem. Three arms work disjoint halves against this one measurement.

Reproduce anything you rely on. If a number here fails your own measurement, **block and name
it** — that has now happened twice and was right both times.

## The measurement

Source: `~/.claude/burn/history.db` opened `file:...?mode=ro&immutable=1`, plus the transcripts.

**1. The bill is context re-read, not work.** Per assistant response, averaged over 5,304
usage-bearing records in session `fe5013c6`:

| component | per response | share of all tokens |
|---|---|---|
| `cache_read_input_tokens` | 296,784 | **98.9%** |
| `cache_creation_input_tokens` | 2,590 | 0.9% |
| `output_tokens` | 838 | **0.28%** |
| `input_tokens` (fresh) | 1 | 0.00% |

And `cr_total/turns` for that session is 299,375 — i.e. **credits ≈ cache_read tokens, roughly
1:1. The bill is literally the sum of context size over turns.** What the lead writes is 0.28%
of it. This retires a whole class of advice ("be terser") as a rounding error.

**2. Every session converges on the same ceiling.** Across 23 sessions over 7 days, the maximum
per-response context was 465,838–470,748 without exception — opus and sonnet alike. That is the
auto-compaction threshold. Context climbs to ~467k, compacts, climbs again.

**3. The floor is large, is paid by every turn, and differs 4.6× between repos.**
First-response context (prefix only, before any conversation):

    min 59,876   median 125,277   max 277,454      growth to ceiling: 1.7x - 7.8x

| repo | MCP servers | CLAUDE.md bytes | hook registrations | skills | observed floor |
|---|---|---|---|---|---|
| persona-engine | 4 (shadcn, repowise, codebase-memory-mcp, reddit) | 37,044 | 58 | 47 | 116k–277k |
| getmany-followup-bot | 2 (snovio, repowise) | 18,978 | 34 | 64 | 216k–260k |
| m3-market | **0** | 7,977 | 54 | 57 | **59,876** |

Global layer every repo also pays: user `CLAUDE.md` 9,407 bytes, `MEMORY.md` 25,258 bytes,
plugin `hooks.json` 174 command entries.

**This is a natural experiment.** m3-market with zero MCP servers starts at 59,876 while a
persona-engine session starts as high as 277,454. Something worth up to ~217k *per turn, on every
turn of every session* separates them. Nobody has decomposed it.

## Arithmetic that follows, and the correction it forces

Total cost ≈ Σ over turns of (context size at that turn). Three levers, and round 1 named only
the third:

1. **Lower the floor.** A floor of 125k median is paid on turn 1 and on turn 3,000 alike.
2. **Compact earlier.** Context is allowed to run to 467k; the average sits near 300k. This lever
   was explicitly dismissed in round 1 ("caching already absorbs it") — **that was wrong**, and
   the 98.9% figure is why.
3. **Fewer turns.** Measured in round 1: ≈30% of turns are batchable (95% range 19–44%), and
   1,557 responses (10.4%) are two bounded reads of the same file in a row.

## The three halves — disjoint, do not cross

Each arm writes exactly one file and reads only its own mission. Do not read another arm's
deliverable.

- **astra → `ANALYSIS-astra-floor.md`.** Decompose the floor. What are the 125k median and the
  217k spread actually made of — MCP tool schemas, CLAUDE.md files, skill frontmatter, memory
  injection, hook output, system prompt? Measure each component in tokens, do not estimate from
  file bytes (JSON schema inflates; markdown does not). Use the m3-market-vs-persona-engine
  contrast as your instrument. Then say which components are removable, which are conditional
  (loadable on demand, like deferred tools), and which are irreducible. Give the floor you
  believe is achievable and what it costs to get there.
- **sol → `ANALYSIS-sol-compaction.md`.** Attack lever 2 adversarially before anyone acts on it.
  Compacting earlier lowers average context but compaction itself is expensive and destroys
  context that then gets re-derived — a re-derivation is new turns at full price. Compute the
  break-even compaction threshold from the measured data. Does compacting at 250k beat running to
  467k, and under what re-derivation rate does it stop being true? Include the cost of the
  compaction call itself. It is entirely acceptable to conclude the current threshold is already
  near optimal.
- **fable → `ANALYSIS-fable-external.md`.** Survey external tooling that attacks any of the three
  levers — context compression, tool-schema minimisation, retrieval instead of preloading,
  transcript summarisation, MCP proxies that lazily expose schemas. For each: what it claims, what
  it would cost us here against the measured numbers above, its failure mode, and a verdict of
  adopt / trial / reject with the reason. **A survey without verdicts is not the deliverable.**
  Reject on measurement, not on taste: a tool that saves 5k of a 125k floor is a reject, and say
  so with the arithmetic. Check what we already have and are not using before proposing anything
  new — `ENABLE_TOOL_SEARCH` and deferred MCP tools already exist in this stack.

## Hard constraints

- `~/.claude/burn/history.db` is read-only, always. Never write to it or to anything under
  `~/.claude/burn/`.
- Do not read or modify `~/.claude/settings.json` or any permission file.
- Do not edit `~/.claude-work/CLAUDE.md` — it is the founder's file. Propose text, never apply it.
- No `plugins/` edits, no code, no test suites this round. Analysis only.
- Never `git stash`, `git reset --hard`, `git clean`, or `git worktree prune`.
- Commit with `git commit -m "..." -- <your one path>`; do not push.

## Report back

Under 400 words each: your numbers with their method, your ranked conclusions, and the one thing
in this brief you checked that was wrong or unsupportable.
