# Round 3 / R2 — deep research: compaction control and server-side context editing

You are a research arm. Do not read other arms' files. Deliverable at the bottom.

## The measurement you are optimising against

- 122 auto-compactions across 23 sessions: median pre-compaction context **467,627**, post
  **17,617**, duration 162 s. Effective post-compact floor **146,092**; growth **1,343
  tokens/response**. Session-start floor in the reference repo: **157,216**.
- The bill is **98.9% `cache_read`**, ~1:1 with credits. Total cost = sum of context size over
  turns.
- **0 of 122 compaction records carry an API `usage` object**, so the compaction call's own billed
  cost cannot be read from the transcripts. Anything you assert about it must come from a source.
- A cost model over this data puts the optimum threshold near **164k** for this repo and **~274k**
  for a higher-floor one — a single global threshold is not obviously safe.

The founder's live proposal is **450k** (down from ~467k), and **400k conditional** on the
session-start floor dropping below 130-150k. He needs to know whether 450k buys anything at all.

## Your job

**Do at least 10 distinct web searches and fetch the PRIMARY SOURCE for everything you
recommend** — `code.claude.com/docs`, `platform.claude.com/docs`, the Claude cookbook,
`anthropics/claude-code` issues. A blog post is a lead, never evidence.

1. **`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW`** — exact semantics,
   valid ranges, minimum version, and the decisive question: **can they be set in a project
   `.claude/settings.json` `env` block so that an INTERACTIVE session started by a human picks them
   up?** A knob that only works on the CLI launch line reaches subsessions and not the lead, which
   is a far smaller prize. Answer this one explicitly with its source.
2. **`--autocompact <auto|tokens>`** — range, interaction with the two env vars above, and which
   wins when both are set.
3. **"microcompact"** — what it is, whether it is live today, how it differs from auto-compact, and
   whether it is controllable.
4. **What a compaction actually costs.** Does the summarisation call bill the full pre-compaction
   context as input? Is there any public statement or measurement? If the answer is genuinely not
   public, say so — that is a legitimate result and it bounds the whole lever.
5. **Server-side context editing**: `clear_tool_uses_20250919` and `clear_thinking_20251015`, beta
   header `context-management-2025-06-27`, and the `USE_API_CONTEXT_MANAGEMENT` flag that exists in
   the Claude Code binary. **Is it wired into Claude Code today, or API-only?** Find the primary
   doc and any Claude Code issue. If it is API-only, say so plainly.
6. **The cache question, and this decides the verdict.** On a bill that is 98.9% `cache_read`, a
   rewrite that invalidates the cached prefix can cost more than it saves. Find the authoritative
   answer on how tool-result clearing interacts with prompt caching — the `clear_at_least`
   parameter exists precisely to amortise this. Quantify: if clearing N tokens forces a
   cache_creation re-write of the suffix, what is the break-even N?
7. **`/rewind` (Delete), `/clear`, fresh session vs `/compact`.** The claim is that `/rewind`
   preserves the cached prefix while dropping conversation. Verify, and rank the four by cost.
8. **Community reports with actual NUMBERS** on tuning the threshold — not opinions. Note who
   measured and how.

## The trap

The flattering answer is "450k is a sensible first step". Check whether it is a step at all: from
467,627 to 450,000 is under 4% of the ceiling on a sawtooth whose floor is 146k, so the saving may
be inside the noise. If it is, **say so in one sentence and name the threshold that would actually
pay**, with the arithmetic.

## Constraints

Analysis only. No installs, no `plugins/` edits, no code, no test suites. Do not read or modify
`~/.claude/settings.json` or any permission file. No destructive git. Commit with
`git commit -m "..." -- <your one path>`; do not push.

## Deliverable

`docs/handoff/LEAD-BURN-MECHANISM-01/RESEARCH-R2-compaction-editing.md` — nothing else.

## Report back

Under 500 words: (a) exactly how to set the compaction threshold for an INTERACTIVE session, with
the setting name, version and source; (b) whether server-side tool clearing is usable from Claude
Code today, yes/no with the source; (c) the cache-invalidation answer with its break-even; (d) what
450k is worth; (e) adopt/trial/reject per lever.
