# FP-08 fix-round 1 — review FAIL findings (P1, Standard)

FIRST STEP, mandatory: in your lane worktree run
`git merge worktree-5fa969ac` — that branch carries the FP-08 build commit 3ffef47 you are
fixing. Do not re-implement from scratch; fix the findings below on top of it.

Full review: .claude/worktrees/5fa969ac/docs/handoff/dispatch-5fa969ac/review-glm.md
(REVIEW_VERDICT: FAIL). Original mission: docs/handoff/FP-08/mission.md.

Findings, in priority order:
1. H1 BLOCKING — the capability floor does not floor. 3ffef47 adds +50 to util_freepool,
   but arbiter selection compares COST (routing.yaml:74-79, values 3..9), not util%.
   Reviewer's live probe against 3ffef47: freepool STILL selected
   (`freepool selected ... util_freepool=50`). Fix: demote in the dimension the selector
   actually ranks by (cost/rank), or drop freepool from the candidate set for
   class>=Standard non-bulk work — whichever the arbiter layer natively supports. Keep the
   `arm_floor_applied arm=freepool reason=<r>` journal line, emitted when the demotion is
   APPLIED in the effective ranking.
2. M3 — dispatch-code reads a state file the arbiter writes inside `try/except: pass`:
   a failed write leaves last run's state attributed to the current task. Write atomically
   (tempfile + os.replace), stamp task id, and have the reader validate the task id or
   ignore the file.
3. L1/L2 — redundant `import json` inside try; `json.dump(..., open(...,'w'))` leaks the
   fd and is non-atomic. Fold into the M3 atomic-write fix.
4. TESTS — the original mission's tests a-d were never written; add them now
   (plugins/leadv2/scripts/tests/, hermetic):
   (a) stub freepool worker finishing at t+40s with a real diff -> waiter must not declare
       no_work early;
   (b) class=Standard work_kind=build -> freepool never effectively selected; assert
       arm_floor_applied AND assert the SELECTION outcome, not just the journal line
       (that is exactly the H1 trap);
   (c) bulk/simple work_kind -> freepool still selectable;
   (d) NEGATIVE CONTROL declared in header and RUN red: remove the floor -> (b) must fail.
   Add EXTRA_SUITE_MAP rows in tests/run-all.sh.
5. The reviewer measured 12 passed / 8 failed in the target suite against 3ffef47 — make
   the touched suites fully green and paste raw output in the report.

The wait-unification half (pc_worker_alive freepool case) was CONFIRMED by review — do not
touch it beyond what the fixes above require.

Commit: fix(leadv2): FP-08 fix-round 1 — floor in effective ranking + atomic state + tests a-d.
Report: docs/handoff/FP-08/fix-round-1-report.md (max 250 words), end DELIVERABLE_COMPLETE.
