# Round 2 — sol: attack the "compact earlier" lever before anyone acts on it

Read `docs/handoff/LEAD-BURN-MECHANISM-01/BRIEF-02-WHERE-THE-TOKENS-GO.md` in this worktree
first; it carries the measurement and the constraints. If it is absent, stop and say so.

You are `gpt-5.6-sol`, the adversarial arm. You already falsified round 1's census and were
right. Two other arms work the floor and external-tooling halves; do not read their files.

## The claim you are attacking — and it is the lead's own

The lead wrote in round 1 that context length is already absorbed by prompt caching and that
compaction therefore saves nothing. The round 2 measurement appears to refute that: cached
context re-read is 98.9% of all tokens, credits track `cache_read` roughly 1:1, and context
climbs to a 467k ceiling before auto-compaction across all 23 measured sessions. So the lead has
now flipped to "compact earlier" being the second-largest lever.

**Both positions cannot be right, and the flip was made without arithmetic. Do the arithmetic.**

## What to establish

1. **The cost of compaction itself.** A compaction is a model call over the whole context that
   produces a summary. Measure it: find compaction events in the transcripts (`isCompactSummary`,
   `PreCompact`/`PostCompact`, or the summary record shape) and their usage. A lever that costs
   one 467k call every N turns must beat what it saves.
2. **The re-derivation tax.** After a compaction the session has lost detail and re-fetches it —
   re-reading files, re-running probes it already ran. Those are new turns at full price. Measure
   it rather than assume it: compare the tool-call pattern in the 50 responses after a compaction
   against the 50 before. If re-derivation is large, compacting more often makes things worse and
   the lead's original position was accidentally right.
3. **The break-even threshold.** Given (1), (2) and the measured growth curve from floor to 467k,
   at what threshold is total cost minimised? Show the curve, not just the optimum. If the answer
   is "467k is already near optimal", say so plainly — that is a perfectly good result and it
   would be the second time the lead's confident claim did not survive you.
4. **Whether the ceiling is even ours to move.** Establish whether the ~467k threshold is
   configurable from this stack at all, or is a client default nobody here can change. If it
   cannot be moved, everything above is academic and the honest deliverable is that sentence plus
   whatever the session CAN control — when it starts a fresh session instead of continuing one.

## Deliverable

`docs/handoff/LEAD-BURN-MECHANISM-01/ANALYSIS-sol-compaction.md` — nothing else. No code, no
`plugins/` edits, no test suites.

## Report back

Under 400 words: the measured cost of a compaction, the measured re-derivation tax with your
method, the break-even curve and its optimum, whether the threshold is controllable here, and one
sentence saying whether "compact earlier" is a real lever or another thing the lead got wrong.
