# Round 2 — astra: decompose the context floor

Read `docs/handoff/LEAD-BURN-MECHANISM-01/BRIEF-02-WHERE-THE-TOKENS-GO.md` in this worktree
first; it carries the measurement and the constraints. If it is absent, stop and say so.

You are the codex arm (`gpt-6-astra`). Two other arms work the compaction and external-tooling
halves from separate worktrees. Do not read their files.

## Your half

The bill is 98.9% cached-context re-read, and every turn of every session pays the floor. The
floor's median is 125,277 tokens and it ranges 59,876 to 277,454 — a 4.6x spread with a clean
natural experiment inside it: m3-market carries **zero** MCP servers and starts at 59,876, while
persona-engine carries four and starts as high as 277,454.

**Decompose that floor into named components, in tokens.** Do not estimate from file bytes — JSON
tool schemas inflate badly against their source, markdown barely at all, so byte counts will lie
to you. Measure what actually enters the context.

Components to account for, and say plainly if one is unmeasurable from where you sit:

- MCP tool schemas, per server and per tool. This stack has `repowise`, `codebase-memory-mcp`,
  `reddit`, `shadcn` in persona-engine and none in m3-market.
- Built-in tool definitions.
- `CLAUDE.md` at both levels (project 37,044 bytes in persona-engine vs 7,977 in m3-market; user
  9,407) and `MEMORY.md` (25,258).
- Skill frontmatter — 47 to 64 skills per repo. Only frontmatter loads eagerly; establish what
  that costs at that count.
- SessionStart hook output. The plugin has 174 command entries; several inject text (scheduled
  decisions, thread digests, learnings, FORK-GUARD).
- Whatever else you find that the above does not explain.

Then split them three ways: **removable** (nothing depends on it), **conditional** (could load on
demand rather than eagerly — deferred MCP tools and `ENABLE_TOOL_SEARCH` already do this here, so
establish whether they are on and what they already save), and **irreducible**.

Close with the floor you believe is achievable, what it costs to get there, and what breaks.

## The trap to avoid

The obvious conclusion — "drop the MCP servers" — is probably wrong, because the repo with zero
servers is also the repo with the smallest CLAUDE.md, and the two are confounded in exactly the
comparison you are using as an instrument. Separate them before attributing the 217k, or state
that you could not and give bounds rather than a point estimate.

## Deliverable

`docs/handoff/LEAD-BURN-MECHANISM-01/ANALYSIS-astra-floor.md` — nothing else. No code, no
`plugins/` edits, no test suites.

## Report back

Under 400 words: the component table in tokens with your method, the removable / conditional /
irreducible split, the achievable floor and its cost, and the one number in BRIEF-02 you checked
that was wrong or unsupportable.
