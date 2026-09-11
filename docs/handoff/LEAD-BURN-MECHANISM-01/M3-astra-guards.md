# Round 3 — astra: what our hooks and guards cost, and what they have actually caught

Read `docs/handoff/LEAD-BURN-MECHANISM-01/BRIEF-03-WHAT-WE-CARRY-AND-NEVER-USE.md` in this
worktree first; it carries the measurement and the constraints. If it is absent, stop and say so.

You are `gpt-6-astra`, requested by model, not by tier. Two other arms work the apparatus-usage
and compaction-threshold halves; do not read their files.

## The founder's question

Guards and hooks in this stack are numerous and were each added after a real defect. Nobody has
ever priced them. **What does the guard layer cost per turn and per session, and what has it
actually prevented?** Verdict per guard: keep / change / retire.

## Two facts the lead measured while writing this mission — start from them

Both happened within five minutes, in the live session, and both are data:

1. `leadv2-deny-floor` **blocked a document from being written** because the document's own text
   contained the phrase it bans. The command was a heredoc writing a brief whose constraints
   section said "never (destructive git command)". The guard pattern-matched the prose, not an
   operation. Cost: one full turn, re-read for the rest of the cycle.
2. `leadv2-block-bash-heredoc` then blocked the rewritten command for being a 4,138-byte heredoc
   and told the lead to use the `Write` tool — **correct advice, and the guard is right about the
   economics.** But it fires at `PreToolUse`, which is *after* the assistant message carrying the
   4,138-byte body has been emitted and billed. The guard prevented the file write, not the cost.
   The blocked body is now in the transcript permanently, and so is the guard's own error text.

The second is the important one and it generalises: **a `PreToolUse` deny never saves the tokens
of the call it denies; it costs them twice** (the denied call, plus the corrective turn). This was
established independently in round 1 against 375 real permission denials: 356 produced a one-tool
next response and 19 a zero-tool one — **zero** batched corrections. Carry that into the pricing.

## What to establish

1. **Census.** Every hook registration reachable on the live path: plugin `hooks.json` (174
   command entries), repo `.claude/settings.json` registrations, `SessionStart` / `UserPromptSubmit`
   / `PreToolUse` / `PostToolUse` / `Stop` / `PreCompact` and any other event in use. Count what is
   registered *and reached*, not what exists as a file. Note which are symlinks to the plugin and
   which are real copies (the FORK-GUARD output in a live session names at least one).

2. **Cost, in tokens, split by mechanism — they are not the same cost:**
   - **injected text**: `SessionStart` and `UserPromptSubmit` hooks that print into the context.
     This is floor: paid on every turn of the session, forever. Measure the actual emitted bytes,
     not the script length. The lead's own session shows a `SessionStart:compact` hook whose output
     was 17.2 KB (truncated to a 2 KB preview plus a file path) and a `UserPromptSubmit`
     `task-anchor` block reprinted on **every** founder message.
   - **denials**: `PreToolUse` blocks. Price per the mechanism above: the denied call plus the
     correction, both permanent.
   - **latency only**: hooks that pass silently and emit nothing. These are ~free in tokens; say so
     rather than padding the table.

3. **Benefit, and this is the half that is usually skipped.** For each guard, find evidence it
   fired on a *real* violation: journals, `~/.claude/leadv2-state/`, transcripts, the learnings
   file, the tasks backlog. A guard that has fired 0 times on a real violation and N times on a
   false positive is a retire candidate; a guard that fired once on a defect that cost a day is
   worth a lot of tokens. Give fires-total / true-positives / false-positives per guard wherever
   the record supports it, and mark it unresolved where it does not. **Do not infer a benefit from
   the guard's own commit message.**

4. **The reprinted-context class specifically.** `task-anchor` on every prompt, scheduled-decisions
   injection (the live session shows 98 rows due with `PE_SD_INJECT_MAX=8`), FORK-GUARD output,
   learnings tail, ship-truth line. Each is re-read on every subsequent turn. Price the set and say
   which of them a session actually acts on — the scheduled-decisions block, for instance, prints
   rows whose text says "ЗАКРЫТО" (closed) on several of its lines.

## Deliverable

`docs/handoff/LEAD-BURN-MECHANISM-01/ANALYSIS-astra-guards.md` — nothing else. No `plugins/` edits,
no code, no test suites.

## Report back

Under 400 words: the cost table by mechanism, the fire/true-positive/false-positive record, the
ranked keep / change / retire verdicts with tokens attached, and the one thing in BRIEF-03 you
checked that was wrong or unsupportable.
