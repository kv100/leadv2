# BRAIN-CLASS-LIVE-01 — fix round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BRAIN-CLASS-LIVE-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-task-judge.sh,plugins/leadv2/scripts/leadv2-admission-class.sh,plugins/leadv2/scripts/lib/leadv2-brain-record.sh,plugins/leadv2/scripts/tests/test-brain-class-live.sh,tests/run-all.sh,docs/handoff/BRAIN-CLASS-LIVE-01/
Continue from the existing commits on this branch (`git log main..HEAD`); run with
`LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST (`git merge main`). Never commit `docs/leadv2/`,
`docs/LEAD_V2_STATE.md` or `docs/handoff/dispatch-nw*` (`git checkout -- …` before each commit; commit by
LANE_WRITES pathspecs). An uncommitted exit is a failed round. Write the review-facing text in ENGLISH
(sentinels `REVIEW_VERDICT:` / `FINDING:` are parsed literally).

## Review verdict on round 1 (reviewer glm) — FAIL, high=1
`test-brain-class-live.sh:98` — the main fix (`_judge_fail_floor`, `leadv2-dispatch-code.sh:3912-3921`:
judge failure + declared class above Standard must floor the admission class at the declared class,
not at the old hard-coded `ADMISSION_CLASS="Standard"`) has no coverage: case (c) fixes
`explicit=Standard`, which passes even with the old hard-coded value. Removing the fix leaves the
suite green — the reviewer proved it.

## Do
1. Add the missing cases: judge fails AND declared class = Heavy → admission class Heavy (floor
   applied, `brain.yaml` records `floor=judge_fail declared=Heavy`); same for Strategic; judge fails AND
   declared class = Light → Standard (floor never lowers below Standard). Judge succeeds → the judge's
   class wins over the declared one in both directions (one case each).
2. Mutation negative control, RUN and paste red: revert `_judge_fail_floor` to the hard-coded
   `ADMISSION_CLASS="Standard"` (the reviewer's exact mutation) → the Heavy case red. Revert.
3. `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-brain-class-live.sh`
   → paste FALSIFIABLE; `tests/run-all.sh --scope changed` → paste the selected-suite line.
4. Live proof on the merged tree: run the dispatcher in dry mode against one brief with
   `class: Heavy` and a forced judge failure (`LEADV2_JUDGE_FORCE_FAIL=1` or the fixture the suite
   uses) and paste the `model_select_telemetry … class=heavy` line.
5. "## Round 2 evidence" in report.md; commit (pathspecs only).
