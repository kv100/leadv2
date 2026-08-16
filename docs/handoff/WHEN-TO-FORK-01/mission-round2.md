# MISSION — WHEN-TO-FORK-01, round 2: the fork is a first-class channel, not the exception

Resume the same worktree (`e7d05157`). Round 1's rule is in place and its two review findings are
fixed. **Founder direction, 2026-08-16:** the rule must not merely say *when a fork is allowed* — it
must put the fork on equal footing with the other two channels, and the lead should **use forks to
the maximum** rather than defaulting to a dispatch lane.

Today's real behaviour, which this rule exists to change: the lead reaches for a dispatch lane by
reflex. That is the most expensive channel — worktree, spawn, review gate, close — and it starts
blind, so the lead re-explains the task in a mission file that is always a lossy copy of what the
session already knows.

## What round 2 must add

1. **Three peer channels, one table.** Fork · dispatch-to-another-model · plain agent — presented as
   equals, same columns: what it costs, what it inherits, what it can produce, what it cannot. No
   channel described as "the normal one".
2. **A default that favours the fork where a fork is adequate.** State it explicitly: when two
   channels both fit, prefer the one that does not have to be re-briefed. The lead must justify
   choosing a lane over a fork, not the reverse.
3. **The cases where a fork must NOT be used** — keep these sharp, they are what makes the default
   safe: work that must land a reviewed diff; work needing isolation from the session's own
   uncommitted state; work that outlives the session.
4. **What "maximum use" looks like concretely.** Name work from this session that went to a lane and
   should have been a fork: ledger-row verifications (a 70-second answer that cost a full lane,
   twice), audit synthesis, and judgement calls about our own earlier decisions.

## Keep round 1's corrections

The "needs this session's history" precondition is asked **first, always**, before any branch, and
Phase 7 verification is **not** output-free. Do not regress either.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.
- Rules are markdown. If enforcement is needed, name what would enforce it.

## Deliverable
The three-channel table, the stated default, the must-not-fork list, and this session's worked
examples, in the same plugin home as round 1. End with DELIVERABLE_COMPLETE.
