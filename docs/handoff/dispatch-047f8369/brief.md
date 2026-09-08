# Brief — ANTISILENCE-OUTSIDE, continuation round (lead-authored)

The lane already landed four commits in its own worktree
(`~/Projects/persona-engine/.claude/worktrees/ANTISILENCE-OUTSIDE`): the agent script, the
dead-lead suite, an fd-frugal `_collect_lanes` (the launchd 256-fd limit killed its first real
beat), and an `EXTRA_SUITE_MAP` registration. **That work stands. Do not restart it.**

This round exists for one reason: the agent was armed live before its output was fit to read,
and the founder received two unreadable beats. The plan for this round is therefore narrow.

## Plan

1. **Render the beat to the format now specified in ADDENDUM 2 of the mission** — live lanes
   only, human task ids (never a raw `dispatch-<hex>`), one line per lane with commits and diff
   size, at most ~8 lane lines plus a total, uncertainty stated once as a count rather than
   repeated per row, and a project with no live lanes saying so in one line.
2. **Prove the format, not just the plumbing:** render from a fixture of 4 live lanes and 250
   historical ones; assert the message is under a stated character budget and contains **zero**
   raw `dispatch-<hex>` ids; mutate the renderer back to enumerating everything and show the
   suite goes red.
3. **Keep the dead-lead control** — kill or simulate the absence of the lead session and show the
   beat still arrives. That is the acceptance criterion for the whole row.
4. **Do not install or load the launchd agent.** Hand it over; the lead arms it after running the
   controls. Installing it is what caused this round.

## Gate 1

Approved by the lead. Scope is unchanged from the mission plus its two addenda; no new surface,
no new dependency, and the write set is the same minus `tests/run-all.sh` — that file is held by
another live lane (B2) and a third collision on it today is not acceptable.
