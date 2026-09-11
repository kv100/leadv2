# ANALYSIS-fable-external — external tooling: adopt / trial / reject, with arithmetic

**First line: the biggest win is already installed and switched off.** The leadv2 installer pins
`ENABLE_TOOL_SEARCH=auto:50`, which in practice disables MCP schema deferral; and `repowise distill`
is installed and was executed 0 times in 2,151 lead Bash calls. Together: ~18–24k tokens per turn
(6–8% of the 297k average context, 13–17% of the post-compact floor) for zero new dependencies.
Nothing external beats that, and every external candidate below is either dominated by it or
attacks a component too small to matter.

Second finding, which corrects BRIEF-02: **"output is 0.28% so terseness is a rounding error" is
arithmetically wrong.** Each output token is re-read on every later turn of its compaction cycle
(~190 turns on average). Measured in `fe5013c6`, the lead's own `tool_use` inputs (Bash heredocs,
SendMessage bodies, Write bodies) are 73% of all above-floor context; tool results are 18%. No
external tool touches the 73%.

## 0. Method and the numbers I reproduced

Session `fe5013c6` (persona-engine, opus, 5,304 usage-bearing responses), read from the transcript
jsonl and `~/.claude/burn/history.db` opened `mode=ro&immutable=1`.

| quantity | BRIEF-02 | reproduced | artifact |
|---|---|---|---|
| cache_read per response | 296,784 | **296,785** (median 294,118; max 466,622) | python over jsonl, `usage_records=5304 avg_cr=296785` |
| cache_creation / output per response | 2,590 / 838 | **2,590 / 838** | same run |
| `cr_total/turns` | 299,375 | **299,375** (sessions row: turns=3101, cr_total=928,364,602) | sqlite `select … from sessions` |
| first-response context | (range 59,876–277,454) | **158,641** for this session | same python, `first_ctx=158641` |
| compactions | "climbs to ~467k, compacts" | **14** drops >50k, mean drop −337k, post-compact context 133,875–155,677 | per-response context deltas |
| per-response growth | — | **median 513, mean 920, p90 1,952** tokens | same |

New decomposition of what grows the context (whole session, bytes on disk ÷ 4 ≈ tokens):

| component | bytes | ≈ tokens | per response | share of growth |
|---|---|---|---|---|
| assistant `tool_use` inputs | 6,129,017 | 1,532k | **289** | **66%** |
| — of which Bash command bodies | 2,156,137 | 539k | 102 | |
| — of which SendMessage bodies | 2,009,004 | 502k | 95 | |
| — of which Write bodies | 1,442,267 | 361k | 68 | |
| assistant text | 638,514 | 160k | 30 | 7% |
| tool results (all tools) | 1,680,846 | 420k | 79 | 18% |
| — of which Bash results (2,151 calls, avg 671 B) | 1,445,065 | 361k | 68 | 16% |
| user-side text incl. injected reminders | 800,269 | 200k | 38 | 9% |
| thinking | 0 on disk (stripped from later turns) | — | — | 0% |

Sum ≈ 436 tokens/response against a measured median growth of 513: the books close to within
15%. Cost model used below: a **floor** token costs 1 cache-read per turn, every turn. A token
**added mid-cycle** persists for the rest of its cycle: 5,304 responses / 14 compactions ≈ 380
responses per cycle, so an added token is re-read ≈190× on average.

Tool usage in the same session (this decides several verdicts):

    Bash 2151 · Write 218 · SendMessage 205 · Monitor 43 · Agent 33 · Edit 31 · Read 14
    ToolSearch 11 (all `select:` of built-ins: Monitor, SendMessage, WebFetch…)
    mcp__* tool calls: 0        repowise distill executed: 0 of 2151 Bash calls

## 1. Already have, not using

### 1.1 `ENABLE_TOOL_SEARCH=auto:50` — MCP deferral is effectively OFF. **ADOPT: unset it.**

Where it comes from:

    plugins/leadv2/scripts/leadv2-repo-install.sh:366: "ENABLE_TOOL_SEARCH":"auto:50",
    introduced by baa861b8 2026-08-25 "feat(leadv2): one-command repo adoption" — no rationale in the commit body
    live in this child session: env ENABLE_TOOL_SEARCH=auto:50

Semantics (doc: https://code.claude.com/docs/en/agent-sdk/tool-search, via web search 2026-09-11):
unset ⇒ all MCP tools deferred; `auto` ⇒ load MCP definitions upfront while they total under 10%
of the context window, defer past that; `auto:N` ⇒ same with N%. So `auto:50` loads MCP schemas
upfront until they exceed ~100k tokens. Ours never will, so they are always loaded.

What they weigh, measured by `tools/list` over stdio (JSON bytes ÷ 3.3):

| server (persona-engine `.mcp.json`) | tools | schema bytes | ≈ tokens |
|---|---|---|---|
| repowise | 11 | 20,971 | 6,354 |
| codebase-memory-mcp | 14 | 7,971 | 2,415 |
| reddit | 8 | 3,058 | 926 |
| shadcn | UNVERIFIED: no `tools/list` reply within 90 s | — | ~1,000 (estimate) |
| **sum** | | | **≈ 9,700 verified + ~1,000** |

Arithmetic: ~10k tokens on every turn of every persona-engine session. In `fe5013c6` that is
10k × 5,304 ≈ 53M cache-read tokens (5.7% of the session's 928M) for **zero MCP calls by the
lead**. On m3-market (0 MCP servers) the saving is 0, which is consistent with its 59,876 floor.
Share: 3.4% of the 297k average, 7% of the ~145k post-compact floor.

Failure mode: a subagent that does call an MCP tool pays one `ToolSearch` round trip on first
use (+1 turn, ~1–2k tokens). The 11 ToolSearch uses in this session show the mechanism already
works for built-ins on this build. Check that headless `claude -p` role spawns
(`config/mcp-role-*.json`) still resolve tools after the change; that is the one experiment
before flipping the installer default. Do not "fix" it with `auto:5` either — default (unset)
defers everything and is the documented mode.

The claude.ai connectors (Gmail 29 tools, Drive 11, Slack 20) are listed as deferred in this
session's prompt. UNVERIFIED: whether they are deferred in lead sessions; if not, that is another
~15–25k (estimate from schema verbosity, not measured). Confirm from the first request of a lead
session before counting it.

### 1.2 `repowise distill` — installed, executed zero times. **ADOPT (it is free), but it is not the lever.**

    ~/.repowise-venv/bin/repowise distill --help → "Run COMMAND and print a distilled rendering of its output."
    executed in fe5013c6: 0 / 2151 Bash calls   (573 textual mentions = injected CLAUDE.md, not runs)
    `repowise` is NOT on PATH in a child session ("repowise not found") — only reachable via the venv path

Arithmetic: Bash results are 361k tokens over the session = 68 tokens/response, re-read ~190× ⇒
≈13k of the 297k average context (4.4%). A 60% cut (the brief's own claim range for output
filters; UNVERIFIED for distill on our command mix) saves **≈8k/turn (2.7%)**. Ceiling if every
Bash result vanished: 13k. It is worth having only because it costs nothing; putting it on PATH
and prefixing the noisy commands (tests, `git log`, listings) is the whole job.

Failure mode: an elided line was the error you needed ⇒ `repowise expand <ref>` round trip, +1
turn (~500 tokens). Bounded, recoverable.

### 1.3 Prompt caching 1h TTL — already on. **REJECT as a lever for this bill.**

`ENABLE_PROMPT_CACHING_1H` exists in the binary and this session reports a 1-hour TTL. It reduces
cache *misses* (cache_creation, 0.9% of tokens). The bill is cache_read count, ~1:1 with credits
per BRIEF-02; TTL does not change how many tokens are read. Saving against the floor: 0.

## 2. External candidates, ranked by tokens saved per turn

| # | candidate | attacks | saving/turn vs 297k avg (125k floor) | verdict |
|---|---|---|---|---|
| 1 | Server-side tool-result clearing (`clear_tool_uses_20250919`; `USE_API_CONTEXT_MANAGEMENT` flag exists in this build) | tool results (18% of growth) | ≤27k ceiling, realistic 10–15k minus cache re-writes | **trial** |
| 2 | Lazy-loading MCP gateways: RaiAnsar/mcp-gateway, kira-autonoma/mcp-context-proxy | MCP schemas | ≤10k, identical to §1.1 | **reject** — dominated |
| 3 | RTK (shell-output compressor CLI, "60–90%" claimed) | Bash results | ≤8–12k, identical target to §1.2 | **reject** — dominated |
| 4 | Prompt compressors (LLMLingua-2 style) on CLAUDE.md/memory | prose part of floor (~10–15k) | ≤7k with instruction loss | **reject** |
| 5 | Hosted memory / transcript summarisers (Mem0, Zep, Letta, claude-mem-type plugins) | compaction | adds 3–10k preload to floor; saving unmeasurable | **reject** |
| 6 | More retrieval MCPs (Serena, claude-context, context7) | Read volume | Read = 14 calls/session; each MCP adds 2–7k to floor | **reject** |
| 7 | "Code mode" / tools-as-code progressive disclosure | MCP schemas | needs a proxy layer in Claude Code; ≤10k | **reject** — dominated |

Detail and failure modes:

**2.1 Server-side context editing — trial.** Doc (https://platform.claude.com/docs/en/docs/build-with-claude/context-editing,
fetched 2026-09-11): "clears tool results when conversation context grows beyond your configured
threshold"; "Invalidates cached prompt prefixes when content is cleared… You'll incur cache write
costs each time content is cleared, but subsequent requests can reuse the newly cached prefix";
"Anthropic recommends server-side compaction over SDK compaction." Arithmetic: tool results are
79 tokens/response × ~190 residual ≈ 15k of average context (measured-share method gives up to
27k). Clearing them before compaction would trim that, at the price of a cache re-write of the
prefix each clear (a ~150–300k cache_creation event, same order as a compaction). Net saving
depends entirely on clear frequency and on how often the lead re-derives a cleared result — the
sibling arm's re-derivation rate is the missing input. UNVERIFIED: whether the CLI flag
`USE_API_CONTEXT_MANAGEMENT` (string present in `claude` 2.1.268 binary) enables this strategy or
another. Experiment, one sentence: run one lead session with the flag set, compare `avg(cr)` per
response and compaction count from `history.db` against a same-repo baseline; adopt only if
avg cache_read drops >5% net of cache_creation.

**2.2 MCP gateways — reject.** They expose 4 meta-tools and start backends on demand (README
claims "~95%" / "4–32×" of *schema* tokens). Our whole schema mass is ~10k; §1.1 removes it with
a config change. A gateway adds a process on every MCP call, a new failure point, and its own
tool schema (~1–2k) back into the floor. Net ≤ 8k, strictly worse than unsetting `auto:50`.

**2.3 RTK — reject.** Same target as `repowise distill` (Bash stdout), needs a Rust binary and a
Bash-rewriting hook on every command; the stack already has 174 hook entries and a Bash hook
that blocks command text patterns. Ceiling 13k/turn, realistic 8k, and we already own a tool for
it that has never been run. Revisit only if a measured distill run cuts <30% on our command mix.

**2.4 Prompt compressors — reject.** The compressible prose in the floor is user CLAUDE.md
(9,407 B ≈ 2.4k tokens), project CLAUDE.md (6,100 B ≈ 1.5k), MEMORY.md (11,518 B ≈ 2.9k for
leadv2; 25,258 B ≈ 6.3k for persona-engine). Even a 50% lossy compression of all of it is
≤6.5k/turn and every dropped instruction is a re-derivation or a rule violation. Rewrite by hand
if anything; that is astra's floor work, not a tool.

**2.5 Hosted memory/summarisation — reject.** Repo contents and founder transcripts leave the
machine; the saving is on compaction quality, which sol is measuring, and every such plugin
injects its own memory block into the floor on each turn (claude-mem-style plugins add
3–10k, UNVERIFIED for any specific one). Wrong direction on both axes.

**2.6 More retrieval MCPs — reject, and judge the two we have by the same rule.** repowise and
codebase-memory-mcp cost 8.8k/turn on every lead turn and were called 0 times in 5,304 lead
responses; the lead read 14 files. For the *lead* they are pure cost; for subagents they replace
multi-file reads and are worth their schema. The right shape is exactly what §1.1 gives: present
by name, schema on demand. Adding a third (Serena ≈ 30 tools, context7, claude-context) adds
floor for a Read volume that does not exist in the lead.

## 3. What actually dominates, and why no tool here fixes it

Above-floor context in `fe5013c6` is ~150k of the 297k average. Of what is added per response,
66% is the lead's own `tool_use` input: Bash heredocs (2.16 MB), SendMessage bodies (2.0 MB),
Write bodies (1.44 MB). Each of those tokens is re-read ~190×. That is the mass behind "≈30% of
turns are batchable" from round 1, and it is a *behaviour* lever (write the file once, message
once, no heredoc prompts) that the harness already has the primitives for. It is out of my half
and I only name it so the ranking above is read correctly: §1.1 + §1.2 are the whole external
win, ~18–24k/turn, and the next lever is not a tool.

## 4. The BRIEF-02 items I checked that were wrong or unsupportable

1. **"What the lead writes is 0.28% of it. This retires 'be terser' as a rounding error."** The
   0.28% is the bill's *composition*; it is not the *cause*. Output tokens persist and are
   re-read ~190 times per cycle. Assistant `tool_use` inputs alone are 1.53M tokens on disk for
   this session, 66% of everything added to context. Terseness of tool inputs (not chat prose)
   is the second-largest lever after the floor.
2. **"Global layer every repo also pays: … MEMORY.md 25,258 bytes."** MEMORY.md is per project
   (`~/.claude/projects/<repo>/memory/MEMORY.md`). 25,258 is persona-engine's; leadv2's is 11,518.
   It belongs in the per-repo column, not the global one.
3. **"1,557 responses (10.4%) are two bounded reads of the same file in a row."** In `fe5013c6`
   the Read tool was used 14 times total and consecutive same-path Reads were 0. If the round-1
   figure is real it is Bash-mediated (`sed -n`/`head`), which matters for §1.2: distill does not
   dedupe, it only shortens.

## 5. Constraints honoured

No installs, no `plugins/` edits, no code. `history.db` opened read-only/immutable. Did not read
`~/.claude/settings.json` (the repo-local `.claude/settings.json` surfaced one grep line for the
env var; no other content read). Did not read the astra or sol files.
