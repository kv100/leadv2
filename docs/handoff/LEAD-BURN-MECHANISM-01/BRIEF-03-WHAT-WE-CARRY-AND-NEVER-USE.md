# BRIEF-03 — what this stack carries on every turn and never uses

Round 2 settled where the tokens go. Round 3 asks a different question, and it is the founder's:
**we carry a large permanent apparatus — skills, MCP servers, hooks, guards — and the measured
usage of most of it is zero.** Decide, per surface, whether to improve it, start using it, or
retire it. A survey without verdicts is not the deliverable.

## Measured, reproduce anything you rely on

Source: `~/.claude/burn/history.db` opened `file:...?mode=ro&immutable=1`, plus the transcripts.
Reference session `fe5013c6` (persona-engine, opus, 5,304 usage-bearing assistant responses).

**The bill.** `cache_read` = 98.9% of all tokens, 296,785/response, ~1:1 with credits. Total cost
= sum of context size over turns. Output is 0.28% of the bill — but output tokens persist and are
re-read ~190x per compaction cycle (5,304 responses / 14 compactions = 380 responses/cycle), so
composition is not causation.

**What grows the context** (bytes on disk / 4; the books close to within 15% of measured growth):

| component | tokens | per response | share of growth |
|---|---:|---:|---:|
| assistant `tool_use` inputs | 1,532k | 289 | **66%** |
| - Bash command bodies | 539k | 102 | |
| - SendMessage bodies | 502k | 95 | |
| - Write bodies | 361k | 68 | |
| tool results (all tools) | 420k | 79 | 18% |
| user-side text incl. injected reminders | 200k | 38 | 9% |
| assistant text | 160k | 30 | 7% |

**Tool usage in that entire session:**

    Bash 2151 . Write 218 . SendMessage 205 . Monitor 43 . Agent 33 . Edit 31 . Read 14
    ToolSearch 11 (all `select:` of BUILT-INS: Monitor, SendMessage, WebFetch)
    mcp__* tool calls: 0          repowise distill executed: 0 of 2151 Bash calls

**MCP schema weight** (`tools/list` over stdio, JSON bytes / 3.3): repowise 11 tools / 6,354 tok;
codebase-memory-mcp 14 / 2,415; reddit 8 / 926; shadcn unverified ~1,000. **~10k tokens on every
turn of every persona-engine session for zero MCP calls.** `ENABLE_TOOL_SEARCH=auto:50` (from
`leadv2-repo-install.sh:366`) loads schemas upfront until they exceed ~100k of the window, so
deferral is effectively OFF. That one is already decided: it gets unset.

**Ceiling and floor.** 122 auto-compactions across 23 sessions: median pre 467,627, post 17,617,
duration 162 s. Effective post-compact floor F=146,092, growth g=1,343 tok/response.
`--autocompact <auto|tokens>` (100k-1M) exists in Claude 2.1.269 and `claude-subsession.sh`
already passes it — **the ceiling is ours to move.** First-response prefix varies 4.6x across
repos, and the round-2 floor table was falsified in part: the claimed m3-market floor of 59,876
does not reproduce (its two first events are 112,087 and 416,198), and `fe5013c6`'s own first
context is 158,641.

**Three round-1/2 numbers that did NOT survive** — treat every number here the same way:
45.8% text-only turns (real: 10.5%); 0% batched turns (real: 0.55%, and 0 was true by
construction); "caching absorbs context length so compaction saves nothing" (refuted by the 98.9%).

## Hard constraints

- `~/.claude/burn/history.db` is read-only, always. Never write anything under `~/.claude/burn/`.
- Do not read or modify `~/.claude/settings.json` or any permission file.
- Do not edit `~/.claude-work/CLAUDE.md` — it is the founder's file. Propose text, never apply it.
- Analysis only this round: no `plugins/` edits, no code, no test suites, no installs.
- Destructive git is forbidden: no stash, no hard resets, no clean, no worktree prune.
- Commit with `git commit -m "..." -- <your one path>`; do not push.
- Each arm writes exactly ONE file and reads only its own mission. Do not read another arm's
  deliverable or mission.

## Report back

Under 400 words: your numbers with their method, your ranked verdicts, and the one thing in this
brief you checked that was wrong or unsupportable. If a number here fails your own measurement,
**block and name it** — that has now happened three times and was right every time.
