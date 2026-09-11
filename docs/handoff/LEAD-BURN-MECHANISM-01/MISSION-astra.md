# LEAD-BURN-MECHANISM-01 — astra's half

**Read `docs/handoff/LEAD-BURN-MECHANISM-01/BRIEF.md` in this worktree first.** It carries the
whole measurement, the constraint, and what not to propose. This file only says which half is
yours. If BRIEF.md is not in this worktree, stop and say so — do not proceed from this file
alone, because the numbers are all in there.

You are the **codex arm (`gpt-6-astra`)**. A second arm (fable) is answering the identical
question from a separate worktree at the same time, without seeing your answer or you seeing
theirs. Disagreement between the two is the reason both are running; do not try to guess what
the other will say and do not hedge toward a consensus.

## Your deliverable — exactly one file

    docs/handoff/LEAD-BURN-MECHANISM-01/PROPOSAL-astra.md

Write nothing else. No code, no `plugins/` edits, no test suites, no changes to BRIEF.md.
Do not read or create `PROPOSAL-fable.md`.

## The bias to correct for, since you are the codex arm

You read code well and you will be tempted to answer with an implementation. The deliverable is
a proposal with arithmetic attached, not a patch. But your strength is exactly where this task
is hardest: **verifying which hook surfaces actually exist.** Spend your effort there.

The single most valuable thing you can return is a verified answer to this: **is there any hook
event that fires on an assistant turn carrying no tool call at all?** Read
`plugins/leadv2/hooks/hooks.json` and the Claude Code hook event list and answer it from what
is there, not from what would be convenient. 45.8% of all turns are text-only; if no hook can
see them, that line item is unreachable by the mechanism class the brief asks for, and saying
so plainly is worth more than three mechanisms that assume otherwise.

Second: `PreToolUse` fires per tool call. Establish whether a PreToolUse hook can see enough
history to know that the previous N assistant turns each carried exactly one tool call with no
user message between them — i.e. whether the "refuse the Nth consecutive unbatched call"
mechanism is implementable at all, or whether the hook input lacks that context. Again: verify,
then say.

## Report back

Under 400 words: your top three mechanisms ranked by turns-removed-per-week against the brief's
measured data, each naming its hook surface and whether that surface **verifiably** exists, the
failure mode where it blocks legitimate work, and the one number in BRIEF.md you checked that
was wrong or unsupportable.
