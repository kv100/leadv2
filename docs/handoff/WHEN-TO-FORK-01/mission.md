# MISSION — WHEN-TO-FORK-01: put the fork/agent/lane choice in the plugin, not in the lead's discipline

Plugin repo: `/Users/kostiantyn.vlasenko/Projects/leadv2`. Track 5.3, founder-raised, never advanced.

The lead has three ways to move work off its own context, and the choice between them lives nowhere
except the lead's judgement in the moment:

- **a fork** — inherits the lead's entire session context, so it already knows the task's history;
- **a fresh agent** — starts clean, cheaper, and cannot be poisoned by the session's wrong turns;
- **a dispatch lane** — runs out of process with a worktree, a review gate and a close.

A rule that lives only in judgement degrades exactly when a session is long and tired, which is when
it matters. Observed failure mode today: the lead reached for a dispatch lane for everything —
including one-line verifications that needed no worktree, and judgement calls that needed the
session's own context and lost it.

## What to deliver

A rule **in the plugin**, where the phase docs and the dispatch door can both cite it, deciding
between the three by properties the lead can check without deliberation:

- needs the session's own history (judging a decision made earlier in this session, rewriting what
  this session authored) → fork;
- a bounded question against the repo or prod, where session context is noise → fresh agent;
- produces a diff that must be reviewed and landed → dispatch lane.

State the boundaries as **tests, not adjectives**. "Complex" is not a test. "Produces a diff someone
must review" is.

## Also settle the two edge cases this session hit

1. A **report-only** mission produces a deliverable file, not a diff. The dispatch door was taught
   about this (REPORT-ONLY-GATE-01); the rule should say when such work belongs in a lane at all
   versus a fresh agent.
2. A **verification** ("is this ledger row still true?") cost a full lane for a 70-second answer,
   twice. Name where it belongs.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.
- Rules are markdown. If the rule needs enforcement, say what would enforce it rather than building a
  hook nobody asked for.

## Deliverable
The rule in its plugin home, cited from wherever the lead would look for it, plus
`docs/handoff/WHEN-TO-FORK-01/report.md` with one worked example per branch, taken from this
session's real lanes. End with DELIVERABLE_COMPLETE.
