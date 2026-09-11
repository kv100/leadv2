# Round 3 / R1 — deep research: every lever that lowers the fixed session floor

You are a research arm. Do not read other arms' files. Deliverable at the bottom.

## The measurement you are optimising against

Measured by the lead on 2026-09-11, same repo (`persona-engine`), reproducible:

    headless `claude -p` first-turn context      56,422
    interactive lead session first-turn context 157,216
    gap                                        100,794   <- hooks, skills, CLAUDE.md, memory, injections

`/context` run headless in that repo (haiku, 200k window) breaks the 41.3k it pays down as:

| category | tokens | note |
|---|---:|---|
| System prompt | 6,300 | |
| System tools | 4,400 | |
| Custom agents | 898 | |
| **Memory files** | **21,300** | 10.7% of the window |
| **Skills** | **6,000** | 47-64 skills in this repo |
| Messages | 2,500 | |
| MCP tools (**deferred**, not paid) | 85,800 | deferral IS working; unsetting `ENABLE_TOOL_SEARCH` moved the floor by 2 tokens |
| System tools (deferred, not paid) | 16,100 | |

Sizes on disk: project `CLAUDE.md` 37,044 B, user `CLAUDE.md` 9,407 B, `MEMORY.md` 25,258 B.
Plugin `hooks.json` carries 174 command entries; the repo has 58 hook registrations and 14
`SessionStart` hooks. A `UserPromptSubmit` hook reprints a "task-anchor" block on **every** user
message. A scheduled-decisions injector prints 8 of 98 rows at every session start.

**Every floor token is paid on turn 1 and on turn 3,000 alike**, because the bill is 98.9%
`cache_read` and total cost = sum of context size over turns.

## Your job

**Do at least 10 distinct web searches and fetch the PRIMARY SOURCE for everything you
recommend** — `code.claude.com/docs`, `platform.claude.com/docs`, `anthropics/claude-code` GitHub
issues, or a real repository. A blog post is a lead, never evidence. Where an official doc and a
blog disagree, the doc wins and you say the blog was wrong.

Cover at minimum, then go wider than this list:

1. **`/context`** — the exact meaning of each category, and specifically whether a category
   labelled "(deferred)" is paid or not. Our reading is that it is NOT paid; confirm or refute
   from the source, because a large part of the plan depends on it.
2. **`paths` frontmatter on rule/memory files** — the claim is that a rule file without it loads
   at every session start, and with it loads only when a matching file is first touched. Exact
   syntax, minimum version, whether it applies to `CLAUDE.md` itself or only to imported rule
   files, and whether anyone has published a measured before/after.
3. **`skillOverrides`** modes (`on` / `off` / `name-only` / `user-invocable-only`). `name-only`
   reportedly keeps the skill name and drops the description, which is the cheap-in-context mode.
   **But issues #50631, #54996 and #56494 claim it may be a no-op stub or fail to take effect.**
   Establish what actually works in the current version; a lever that silently does nothing is
   worse than no lever.
4. **`disableBundledSkills`** — scope, and what it costs in capability.
5. **Anything that trims the system prompt**: output styles, `--exclude-dynamic-system-prompt-sections`,
   `--append-system-prompt`, agent-level `tools:` restriction. Which of these is real today.
6. **anthropics/claude-code issue #46526** ("system prompt overhead consumes too much of the
   context window") — current status, any official fix in flight, and what maintainers said. If a
   fix is shipping, adopting a third-party workaround now may be wasted work; say so.
7. **`/rewind` (Delete) vs `/compact` vs `/clear` vs a fresh session.** The claim is that `/rewind`
   clears conversation while PRESERVING the cached prefix, so it is far cheaper than compaction.
   Verify from the source and give the cost of each of the four.
8. **Memory-file cost.** 21.3k of memory files is the single largest paid category here. What
   controls which memory files load, can they be made conditional, and what do teams that
   published numbers actually do.
9. **Hook-output cost.** Community and official guidance on `SessionStart` / `UserPromptSubmit`
   hooks that print into context; any mechanism to make injected text load once rather than be
   reprinted; whether hook output is cached or re-created each time.
10. **`.claudeignore`, `additionalDirectories`, plugin-level knobs** — anything that changes what
    is loaded at start.

## The rule that makes this useful

Every lever ends with: **exact setting / flag / file path**, **minimum version**, **measured or
best-estimated tokens saved against the 157,216 interactive floor**, **what breaks**, and a
verdict of adopt / trial / reject. A lever you cannot size is `trial` with the one experiment that
would size it, in a sentence. Mark clearly any lever that GitHub issues say is currently broken.

## Constraints

Analysis only. No installs, no `plugins/` edits, no code, no test suites. Do not read or modify
`~/.claude/settings.json` or any permission file. Do not edit `~/.claude-work/CLAUDE.md`. No
destructive git. Commit with `git commit -m "..." -- <your one path>`; do not push.

## Deliverable

`docs/handoff/LEAD-BURN-MECHANISM-01/RESEARCH-R1-floor-levers.md` — nothing else.

## Report back

Under 500 words: the ranked lever table by tokens saved from 157,216, the levers that are
confirmed broken with their issue numbers, the single biggest lever, and the floor you believe is
reachable in this repo without losing a capability.
