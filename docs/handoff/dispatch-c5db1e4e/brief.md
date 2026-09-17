# Round 2 brief — WRITESET-GATE-BLOCKS-THE-BOARD-ON-A-FOREIGN-LANES-UNDECLARED-WRITE-01

Lead-authored plan evidence for the resumed lane `c5db1e4e` (row `fe674d7918f3`).

## Why there is a round 2

Round 1 was killed by review: `critical=1 high=2`, `terminal=dead cause=review_verdict_fail`.
The findings were correct and measured, not stylistic. Full text:
`docs/handoff/dispatch-c5db1e4e-review/critic.full.md`.

## What changed in the plan, not just in the wording

1. **The option the round-1 mission suggested is withdrawn.** "Refuse only on overlap with the
   incumbent's working-tree dirt" reopens the TOCTOU that the unconditional refusal closes: dirt is
   what the incumbent has *already touched*, which during the guarded window is by construction
   nothing. That was my error in the original mission, and H1 caught it.

2. **Three surviving options**, each stated with its constraint: a shorter window with a warning
   after it; a set derived from the worktree diff at gate time (subject to H2 — a row whose
   worktree *is* the shared checkout must not inherit that tree's dirt); or dirt-overlap **plus** a
   symmetric late-declaration check in `set_writes`, which is then part of this diff and not a
   follow-up row.

3. **Five contract suites named explicitly** and added as a third mandatory check with pasted rc
   each: `test-writeset-pending-overlap`, `test-writeset-refusal-names-blocker`,
   `test-lane-adopt-writeset-refusal`, `test-writeset-admission-block`, `test-writeset-carousel`.
   Round 1 turned all five from green to red and shipped no test of its own.

## Invariants that do not move

- A lane whose declared set is disjoint from everything observable is admitted.
- A lane whose declared set genuinely overlaps a live holder is still refused.
- The 900s window and `_lv2_ws_live_worker` stay; a dead holder keeps being ignored.
- `leadv2-dispatch-code.sh` is off limits — another lane holds it.

## Gate 1

Accepted by the lead. The premise is unchanged and still live (the board was serialised by this
exact mechanism on 2026-09-16/17, three refusals of lane `f11c97a14f88` against a disjoint set),
and the round-1 review narrowed the solution space rather than invalidating the row.
