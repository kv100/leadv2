# MISSION — WHEN-TO-FORK-01, fix round 1

Resume the same worktree (`e7d05157`). Review: `docs/handoff/dispatch-e7d05157/review-codex.md`,
status **fail**, 0 critical, 2 high. Both are in `plugins/leadv2/docs/work-placement.md`, and both
say the rule as written would send work to the wrong place.

## H1 — first-match ordering discards required session context (`:16-20`)

The rule is evaluated top-down and the first match wins, so work that genuinely needs the session's
history can be captured by an earlier branch and sent to a fresh agent, which starts blind. That is
the exact failure the rule exists to prevent, encoded into its own ordering.

Fix the ordering so the "needs this session's history" test is asked **before** the cheaper branches,
or make the branches mutually exclusive so order cannot decide it. State which you chose and why.

## H2 — Phase 7 verification is misclassified as output-free (`:70-76`)

Live verification produces a verdict that gates deploy and rollback — treating it as output-free
routes it to the branch with the weakest accountability. Reclassify it and say what its output is.

## While you are there

Re-read your own worked examples against the corrected rule. If an example now lands in a different
branch than the one you wrote it under, the example was doing the arguing instead of the rule — fix
the rule, then the example.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.

## Deliverable
The corrected rule, the reclassification, and the examples re-checked against it.
End with DELIVERABLE_COMPLETE.
