# MISSION — WHEN-TO-FORK-01, round 3: the "prefer a fork" default must not route reviewed work away from a lane

Resume the same worktree (`e7d05157`). Review of round 2:
`docs/handoff/dispatch-e283a9f5/review-codex.md`, status **fail**, 0 critical, 1 high.

**`plugins/leadv2/docs/work-placement.md:29-64` — conflicting mandatory destinations bypass the
review lane.** Round 2 added the founder's "prefer the channel that needs no re-briefing" default,
and it now collides with the rule that work producing a landed diff must go through a dispatch lane.
Read literally, some work is mandated to two destinations at once, and the cheaper reading wins —
which is how a reviewed diff ends up in a fork with no review gate.

That inverts the founder's intent. "Use forks to the maximum" means *for work that does not need the
lane's machinery*; it never meant routing a landing diff past review.

## Fix

Make the precedence explicit, in this order:

1. **Hard constraints first** — if the work must land a reviewed diff, must be isolated from the
   session's uncommitted state, or must outlive the session, the destination is a lane. Not a
   preference; no default may override it.
2. **Then the preference** — among the channels still eligible, prefer the one that needs no
   re-briefing.

No rule may state a mandatory destination that another rule contradicts. If two sections both claim
a case, one of them is wrong — fix it rather than adding a tie-break sentence.

## Also still owed, from round 1's review

`plugins/leadv2/docs/phases.md:471` and `:474` — the summary inverts the canonical test order and
contradicts `work-placement.md` on Phase 7 verification. Derive the summary from the rule; if it
cannot be kept in sync, make it a pointer instead of a paraphrase.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.
- Keep rounds 1–2: precondition asked first, Phase 7 verification not output-free, three peer
  channels, the must-not-fork list, the worked examples.

## Deliverable
The precedence fix, `phases.md` reconciled with the rule, and no case left with two mandatory
destinations. End with DELIVERABLE_COMPLETE.
