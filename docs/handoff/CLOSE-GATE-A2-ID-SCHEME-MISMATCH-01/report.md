# CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01 — report

Lane: CLOSE-GATE-A2-ID-RESOLVE-02 (worktree), task CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01
Date: 2026-08-31

## The defect (as briefed, confirmed live)

A2 in `leadv2-phase8-assert.sh` compared `row.id == task_id` where `task_id`
is a human milestone name (`V5-M0-SKELETON-01`) while backlog rows are
fingerprint-keyed; the name lives only in `intent` before the first colon.
The comparison could never match → A2 always exited 2 → close gate blocked.
The comment promised a lane-yaml fallback that no code on that path performs,
and the printed remedy `leadv2_tasks_release V5-M0-SKELETON-01 --outcome
success` failed with the same mismatch one layer down.

## The fix

1. **Shared resolver** — `row_matches(it, task_id)` added to
   `plugins/leadv2/scripts/leadv2_tasks_yaml_common.py` (the single-source
   module every tasks.yaml reader is required to route through). Matches when
   row `id == task_id` OR the FULL segment before the first colon of
   `intent == task_id`. Anchored on the whole pre-colon segment, never a
   substring: `V5-M1` does not match `V5-M10:`. Empty `task_id` never matches.

2. **Call sites resolved (count: 8, across 3 files):**
   - `leadv2-phase8-assert.sh` A2 tasks.yaml lookup (the reported defect)
   - `leadv2-phase8-assert.sh` A2 lane-yamls fallback path (same scheme
     mismatch, would have bitten identically on the absent-tasks.yaml path)
   - `leadv2-tasks-lib.sh` dispatcher ops: `release` (this is
     `leadv2_tasks_release` — the printed remedy is now executable), `claim`,
     `unclaim`, `by_id`, `update`
   All are additive: an id match still wins; a fingerprint caller sees
   identical behaviour. The dispatcher now receives the scripts dir as argv
   so it imports `row_matches` from the shared module — no second copy of the
   resolution rule exists.

3. **The lying comment removed.** The A2 heredoc now says plainly: the
   lane-yamls branch runs ONLY when tasks.yaml is absent; on this path there
   is NO fallback. The rc=2 failure message names what was searched ("by row
   id and by intent pre-colon segment; only tasks.yaml was consulted") and
   the remedy now names the exact command: `leadv2_tasks_release ${TASK_ID}
   --outcome success`.

4. **Found, same class, NOT changed (out of lane scope, listed for triage):**
   `leadv2-collision-check.sh:109`, `leadv2-self-spawn.sh:38`,
   `leadv2-daemon.sh:692` compare raw ids against items whose ids may be
   fingerprints. These were not touched: collision-check's registered ids and
   daemon's claim registry are populated from the same ids they later compare,
   so today they are self-consistent; widening them needs its own acceptance
   probe. `codex-task.sh`, `leadv2-decide.sh`, `leadv2-queue-sweep.sh`,
   `leadv2-tasks-clobber-guard.sh` hits are different data domains (option
   ids, output rows), not this scheme mismatch.

## Test suite

`plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh` — fixtures only
(mktemp), never a real backlog. Covers all 5 acceptance cases plus an
extraction sanity test and a full-gate E2E of the real-repo shape
(claimed_done + release receipt + phase8-passed.flag). The negative-control
anchor is the fingerprint fixture itself.

EXTRA_SUITE_MAP rows added for both changed producers
(`leadv2-phase8-assert.sh`, `leadv2-tasks-lib.sh`) in `tests/run-all.sh`.

## Mutation control

Mutation inside the production A2 body on the real call path (restoring the
id-only comparison), run against the fingerprint fixture. RED evidence, then
revert, then GREEN — see the transcript section below (paste in final message).

## Honest caveats

- LANE_WRITES listed only `leadv2-phase8-assert.sh`, the test, `run-all.sh`,
  and this handoff dir; the mission's Critical section explicitly required
  fixing `leadv2_tasks_release` too, so `leadv2-tasks-lib.sh` was edited under
  that explicit instruction. Flagging the scope tension for the reviewer.
- The changed-scope runner has known pre-existing reds (foreign-failure
  fixture, LANE-PLACEMENT-01, C5-registered-arm-silent) per project memory;
  any red from this run is attributed only if it maps to this lane's files.
