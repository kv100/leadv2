# MISSION — FORK-RUNS-FULL-SESSION-01, round 2 (your change broke the core suite; finish the job)

Your work is in `.claude/worktrees/63e9aaff` — `commands/leadv2.md`, `docs/phases.md`,
`leadv2-active-registry.sh` and `leadv2-gate1-prompt.sh` are modified, so you got substantially
into it. The original mission is `docs/missions/FORK-RUNS-FULL-SESSION-01.md`; re-read it,
nothing about it has changed. It is founder-ordered.

**The e2e gate failed on `plugins/leadv2/scripts/tests/run-core-offline.sh`.** That suite passes
clean on `main` (verified by the lead: 43/43, 20/20, 5/5), so the regression is yours — most
likely from the registry or gate1 changes. Run it, read the failure, fix it properly. Do not
weaken an assertion to make it green; you are touching the locking and gate machinery that keeps
two sessions from corrupting each other, and a test that stops checking that is worse than a
failing one.

Then finish. The three things the original mission says you must get right stand unchanged:
two sessions must not collide, Gate 1 must not silently auto-accept in a fork, and a dead fork
must be visible to its parent. That last one is not theoretical — the lead spent three hours
today reporting a dead lane as running.

## Hard constraints
- No phase may be skipped to make this work. A fork that runs Phase 0→8 runs all of it.
- Plugin repo only.

## Evidence required
`run-core-offline.sh` green, plus the transcript the original mission asks for: one real task
carried by a fork from intake to a written `phase8-passed.flag`, with the review gate's verdict
visible. Report to `docs/missions/FORK-RUNS-FULL-SESSION-01.report.md`. End with
DELIVERABLE_COMPLETE.
