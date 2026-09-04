verdict: REVISE
next_action: review_round_2

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=1 high=4 medium=6 low=3

- C1: `_deliver_plan_into_lane` sits at dispatch-code:6024, above the ensure block that sets WORK_ROOT — no-ops on every ensure-created lane.
- H1: `_PC_BOOTSTRAP_PREFIX_RE` double-escaped in the new lib (probe: no match) — clean lanes graded dirty, never land.
- H2/H3/H4: containment blames any main-checkout writer; task-class floor is last-writer-wins; `plan-*.md` glob expands against cwd.

Full: critic.full.md
