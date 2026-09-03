# DISPATCH-PIN-CLUSTER-01 — four dispatcher defects, one write set

Repo: /Users/kostiantyn.vlasenko/Projects/leadv2 (the plugin single source).
Primary file: plugins/leadv2/scripts/leadv2-dispatch-code.sh (7613 lines).
All four defects were observed 2026-08-29 on LANE-WRITESET-REGISTRY-01.

## D1 — DISPATCH-WORKER-WRITES-OUTSIDE-LANE-01 (P0)
A worker wrote its edits into the MAIN checkout instead of its pinned lane worktree.
ff-only merge refused because leadv2-active-registry.sh and leadv2-dispatch-code.sh were
dirty in the main checkout; the dirt was an earlier, less complete draft of the same task
(161 vs 202 insertions). Silent cross-lane contamination: a worker can overwrite another
live lane's files, and the writeset admission gate cannot see it because the write never
happens inside a registered lane.
Fix: WORKTREE PIN must be ENFORCED, not advisory — refuse or abort a worker whose writes
resolve outside its lane root.

## D2 — DISPATCH-COMMIT-NOT-AN-OBLIGATION-01
Workers finish with real edits on disk and no commit, and the dispatcher accepts it. Six
consecutive rounds across three arms (sonnet error_max_turns, codex, freepool) ended this
way; every commit was made by the lead by hand. The STOP-GATE auto-checkpoint is NOT a fix:
it committed 3 of 5 dirty files once, leaving the H1 security guard uncommitted, and the
next review read HEAD and reported the fix MISSING — a wasted review round.
Fix: the dispatcher treats an uncommitted lane as a FAILED round (or commits it itself,
atomically and completely, and says so). The arm-exit path must never report success with
a dirty lane.

## D3 — DISPATCH-PLAN-NOT-IN-LANE-01
The dispatcher delivers the mission and --writes into the lane worktree but NOT the binding
plan (docs/handoff/<task>/context.yaml). The lane branches from origin/main, so an untracked
handoff plan in the main checkout does not exist on the lane branch. The codex arm returned
BLOCKED in 2 minutes with "the binding plan is missing from the pinned worktree".
Fix: dispatcher copies (or commits) plan + mission into the lane before spawning, and fails
loudly if the plan path does not resolve inside the lane.

## D4 — DISPATCH-CLASS-FROM-MISSION-LENGTH-01
The dispatch classifier derives task_class from the mission TEXT, so a short resume/fix
mission for Heavy work is classified Light and routed to the cheapest arm. Identical work
was Heavy on the full mission and Light on a 40-line resume mission, sending a plugin-core
registry change to freepool. One freepool round burned 9.3M input tokens (cache_read=0 for
the whole run) and produced ONE line of documentation.
Fix: class comes from the lane/task record (or an explicit --task-class that is HONOURED),
never re-derived from the length of the current mission file.

## Constraints
- These four share one write set (leadv2-dispatch-code.sh) — one lane, not four.
- This is the dispatcher that launches every lane in every repo: a regression here is
  total. Every fix needs a negative control (mutation) that a test kills.
- Plugin repo rules: fix once here, never a real copy in a consuming repo.
