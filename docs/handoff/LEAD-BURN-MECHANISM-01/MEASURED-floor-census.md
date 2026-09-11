# Measured by the lead, 2026-09-11 — session-start floor census, every session on this machine

Method: for every `~/.claude-work/projects/**/**.jsonl` with >=30 usage-bearing assistant
responses, the FIRST response's `cache_read + cache_creation + input`. Read-only.

## Lead sessions vs worker sessions, same repo

| project | sessions | min | median | max |
|---|---:|---:|---:|---:|
| persona-engine (lead) | 33 | 53,532 | **153,228** | 277,456 |
| persona-engine worktrees (workers) | ~43 | 52,252 | **~56,500** | 217,311 |
| leadv2 (lead) | 37 | 36,227 | 110,176 | 199,752 |
| getmany-followup-bot (lead) | 16 | 37,886 | 175,557 | 260,330 |
| leadv2 worktrees (workers) | ~150 | 12,938 | ~17,000 | ~95,000 |
| `/private/tmp` plugin test sessions | ~14 | 16,456 | ~16,600 | 17,736 |

## What this settles

1. **The floor is not the repo. It is the role.** In the *same* repo (`persona-engine`, same
   `.mcp.json`, same project `CLAUDE.md`), a lead session starts at a median of **153,228** and a
   worktree worker at **~56,500**. The gap, **~97,000 tokens**, is paid on every turn of every lead
   session and is entirely lead-only apparatus: user-level memory, the skill catalogue, and the
   `SessionStart` / `UserPromptSubmit` injections (scheduled decisions, thread digests, learnings
   tail, FORK-GUARD, compact-resume).

2. **It is not structural — it is variable.** The same repo's lead sessions range 53,532 to
   277,456, a 5.2x spread. A lead session CAN start at 53k here. Something optional adds up to
   ~224k, and finding which injections vary is a direct, bounded piece of work.

3. **BRIEF-02's floor table was wrong in its attribution.** It compared repos (m3-market 0 MCP
   servers vs persona-engine 4) and attributed the gap to MCP servers. The controlled comparison —
   same repo, lead vs worker — puts ~97k of it in the apparatus. The separately measured
   `/context` breakdown agrees: MCP schemas show as **deferred and unpaid**, while Memory files
   (21.3k) and Skills (6k) are paid.

4. **The worker floor is the achievable target.** 56.5k in persona-engine and ~17k in leadv2
   worktrees are not theoretical — they are what sessions on this machine already start at today.

## Against the founder's condition

He offered a 400k auto-compact threshold conditional on session start not being 130-150k. The
persona-engine lead median is **153,228** — just above his bar, and the median is the right
statistic here, not the 157,216 of the one session that happened to be open.
