# MON-PULSE-01 fix-round 1 — review FAIL (1 critical, 4 high) (Heavy)

FIRST STEP, mandatory: in your lane worktree run `git merge worktree-2f3034dc` —
that branch carries the MON-PULSE-01 build commit c98cb1c you are fixing.

Full review (read it, fix ALL Critical and High findings):
.claude/worktrees/2f3034dc/docs/handoff/dispatch-2f3034dc/review-opus.md
Findings JSON: same dir, review-findings.json. Original mission: docs/handoff/MON-PULSE-01/mission.md.

Headline finding C1: leadv2-lane-pulse-watch.sh treats `review_gate` as terminal
(TERMINAL_PAT) and exits on first match — but review_gate is emitted repeatedly
MID-FLIGHT (18 emit sites in leadv2-review-run.sh: status=ran, arm_infra_died
action=retry, round0_skip, dedup...). The watcher must treat as terminal ONLY:
`dispatch_terminal` / `dispatch_refused` / `worker_died` for its sig. review_gate
transitions may still be PULSED (they are useful beats) but never end the watch.
Update the suite: a journal where review_gate status=ran appears before
dispatch_terminal -> watcher must pulse both and exit only at dispatch_terminal;
keep the W4 replay negative control; add a negative control for C1 (treat
review_gate as terminal again -> test must fail) and RUN it red.

Then fix the four High findings exactly as the review states them (read them from
review-opus.md §High — do not guess).

Re-run both suites (test-lane-pulse-watch.sh, test-single-lead-beat-loop.sh) green,
bash -n all touched scripts.
Commit: fix(leadv2): MON-PULSE-01 fix-round 1 — true terminal states + High findings.
Report: docs/handoff/MON-PULSE-01/fix-round-1-report.md (max 200 words, raw tails),
end DELIVERABLE_COMPLETE.
