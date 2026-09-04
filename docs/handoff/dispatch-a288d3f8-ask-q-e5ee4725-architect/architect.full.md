# Ask-timeout decision — FORK-STORM-KILLS-HOOKS-01: convert real poll loops now?

## Decision

DECISION_OPTION: a
RATIONALE: Helper + fixture-proven pattern ship this lane; converting three high-churn watchers outside LANE_WRITES needs per-loop fixtures and review surface a mid-build scope expansion cannot safely carry.

## Verified facts (probe artifacts)

- Helper and its proof exist in this worktree: `plugins/leadv2/scripts/lib/leadv2-sleep.sh` (3314 bytes, executable), `plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh` (5525 bytes), plus `plugins/leadv2/hooks/leadv2-hook-fork-budget.sh` — all present on disk, 2026-09-01T13:24Z.
- All three conversion targets exist: `plugins/leadv2/scripts/codex-task.sh`, `plugins/leadv2/scripts/leadv2-lane-watch.sh`, `plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh` (ls hit on all three).
- Sleep surface per file (`grep -c 'sleep'`): codex-task.sh = 8, leadv2-lane-watch.sh = 2, leadv2-single-lead-beat-loop.sh = 1.
- `codex-task.sh` is NOT a hook (`grep codestask plugins/leadv2/hooks/hooks.json` → no hits for codex-task), so no plugin-cache propagation step blocks conversion — the blocker is risk, not mechanics.
- `__quota-watch` (`_codex_quota_watch`, codex-task.sh:480) is quota-gate logic with explicit in-file warnings about duplicate-lockout and reason-scoped dedupe traps (comments codex-task.sh:405-:410, :476-:479). Its poll loop is bound to a bounded-lifetime + lock-dir idempotence design, with deliberately non-collapsing timers (10min refuse vs 45min declare-dead, codex-task.sh:86-87).

## Why a, not b

1. **A fixture problem, not a mechanics problem.** Each real loop has its own trap/lifetime semantics (macOS bash 3.2: trapped TERM defers behind a foreground child; EXIT trap never fires on an untrapped signal). The helper's fixture proves the *pattern*; it does not prove each watcher's conversion. A wrong sleep-swap in quota-watch is an active regression in the quota gate, not a hygiene slip — the exact class of defect the founder's earlier ask-timeout ruling (dispatch-6280f73a: "option (b) … is an active regression") warns about.
2. **LANE_WRITES expansion mid-build.** Three files, 11 sleep sites total, none in the approved write set. Converting now multiplies the review surface of an already fixture-proven deliverable and re-opens scope at the worst point in the lane.
3. **The orphan is pre-existing behavior, not a regression this lane introduces.** Deferring one lane keeps no new defect live; shipping an unproven conversion could create one.

## Follow-up lane requirements (for lead to schedule)

- Scope: exactly the 3 named files; expand LANE_WRITES in that lane's context.yaml.
- Acceptance: extend `test-no-orphan-sleep.sh` with a per-watcher assertion — after SIGTERM to the watcher, no `sleep` child outlives it — run per converted loop, not only for the fixture.
- Constraint: quota-watch conversion must preserve lock-dir idempotence and the 10min/45min timer separation; fixture must include a queued-stall case.

## Out of scope

- No code changes by this role; decision only. No edits to LANE_WRITES or active.yaml from here (LEAD_ACTION: schedule the follow-up conversion lane with the acceptance above).

DELIVERABLE_COMPLETE
