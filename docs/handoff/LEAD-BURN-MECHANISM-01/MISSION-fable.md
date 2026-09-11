# LEAD-BURN-MECHANISM-01 — fable's half

**Read `docs/handoff/LEAD-BURN-MECHANISM-01/BRIEF.md` in this worktree first.** It carries the
whole measurement, the constraint, and what not to propose. This file only says which half is
yours. If BRIEF.md is not in this worktree, stop and say so — do not proceed from this file
alone, because the numbers are all in there.

You are the **fable arm**. A second arm (codex / `gpt-6-astra`) is answering the identical
question from a separate worktree at the same time, without seeing your answer or you seeing
theirs. Disagreement between the two is the reason both are running; do not try to guess what
the other will say and do not hedge toward a consensus.

## Your deliverable — exactly one file

    docs/handoff/LEAD-BURN-MECHANISM-01/PROPOSAL-fable.md

Write nothing else. No code, no `plugins/` edits, no test suites, no changes to BRIEF.md.
Do not read or create `PROPOSAL-astra.md`.

## The angle that is yours

The other arm is verifying hook surfaces. **Do not spend your round duplicating that.** Your
half is the question the measurement raises but does not answer: **why does a system whose
rules already forbid all four behaviours produce 0.0% compliance on the easiest one?**

Batching independent tool calls into one turn is free, costs nothing to get right, is stated in
the harness prompt itself, and was followed **zero times out of 13,437**. A rule with a zero
compliance rate is not a rule that was forgotten — something structural makes it unreachable.
Name that something. Candidates worth testing, none endorsed:

- The lead cannot know a second call is independent until it has seen the first result, so
  batching is only possible for calls whose independence is knowable in advance — in which case
  the reachable fraction of 13,437 is far below 100% and the brief's implied saving is inflated.
  If you believe this, **compute the fraction you think is actually batchable and show your
  reasoning**; that number is more useful than any mechanism.
- Each call is cheap to issue and its cost lands on a later turn the lead never attributes to
  that decision, so nothing in the loop ever connects the two.
- The instruction lives in a prompt read once, while the behaviour is chosen thousands of times.

Then propose mechanisms that follow from the cause you named — not from the list in BRIEF.md,
which is deliberately unendorsed. A mechanism aimed at a cause you have not established is worth
less than a clearly-argued cause with no mechanism, so if you only get one of the two, get the
cause.

## Report back

Under 400 words: the cause you name and what supports it, the batchable fraction you computed
with your reasoning, your mechanisms ranked by turns-removed-per-week, and the one number in
BRIEF.md you checked that was wrong or unsupportable.
