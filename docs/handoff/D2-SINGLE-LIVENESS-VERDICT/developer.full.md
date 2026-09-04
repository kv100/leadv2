# D2-E4-RESOLVES-THE-WRONG-DIR-01 — fix round 2 report

Rung E4 searched `docs/handoff/<tid>/` for the deliverable, but a lane named by its
founder task id keeps the deliverable under `docs/handoff/dispatch-<sig8>/` — the
directory the registry row's own `log_path` field points into. E4 was green in
fixtures and inert on the live path. Fixed by resolving a closed candidate set.

## What changed

`plugins/leadv2/scripts/leadv2-lane-liveness.sh` (commit 7de54f50):

- `deliverable_dirs(tid, session)` (new): candidate set = the tid-named dir (always;
  exact for dispatch-<sig8>-shaped ids) + the parent of the registry row's own
  `log_path` when it is a DIRECT child of `docs/handoff/`. Exact attribution from
  this lane's own row — never a glob across `docs/handoff/` (a glob could credit
  another lane's report → false `finished_unlanded`, the mirror mistake).
- A candidate dir that exists but cannot be READ (EACCES etc.) →
  `unknown:deliverable_dir_unreadable`: a check that could not look is never coerced
  to dead. ENOENT races are treated as absence, not unreadability.
- `deliverable_age_s(lane_dirs)`: newest non-empty `*.full.md`/`*.summary.md` across
  the whole candidate set; `resolve()`'s E4 rung passes the resolved set.
- No verdict literal renamed; no consumer edited; `dead:no_handoff_dir` /
  `dead:no_log_artifact` bottom labels unchanged (FUNNEL-GONE, NO-PID-NO-ARTIFACT,
  SHAPE4/5/6 pins verified green).

`plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh` (commit d072d785):
Tests 10-12, founder-shaped ids with the production `log_path` pointer.

## Ten consecutive suite runs

    run  1: rc=0 [TEST] RESULTS: 16 passed, 0 failed
    run  2: rc=0 [TEST] RESULTS: 16 passed, 0 failed
    run  3: rc=0 [TEST] RESULTS: 16 passed, 0 failed
    run  4: rc=0 [TEST] RESULTS: 16 passed, 0 failed
    run  5: rc=0 [TEST] RESULTS: 16 passed, 0 failed
    run  6: rc=0 [TEST] RESULTS: 16 passed, 0 failed
    run  7: rc=0 [TEST] RESULTS: 16 passed, 0 failed
    run  8: rc=0 [TEST] RESULTS: 16 passed, 0 failed
    run  9: rc=0 [TEST] RESULTS: 16 passed, 0 failed
    run 10: rc=0 [TEST] RESULTS: 16 passed, 0 failed

## Live-lane check (not a fixture)

Lane with a running worker at probe time — `LANE-SALVAGE-TOOL-01`, glm worker
pids 2772/3143/3627 (~2 min old at probe, run 260904-024348-LANE-SALVAGE-TOOL-01-603a),
registry row `log_path: docs/handoff/dispatch-15a3abee/developer.stream.jsonl`:

    $ bash plugins/leadv2/scripts/leadv2-lane-liveness.sh \
        --project-root ~/Projects/leadv2 --lane LANE-SALVAGE-TOOL-01 --no-codex --json
    {"lane":"LANE-SALVAGE-TOOL-01","verdict":"starting:224",...,"reason":"registered_no_stream",...}

`starting:224` — not `dead:*`. The mission's three measured lanes re-run now:
D2-UNBLIND-AND-THIRD-STATE-M0M1-01 → `finished:503s` (landed commit 8 min prior);
D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01 and D1-HARDEN-THE-WRITER-M1M3-01 →
`dead:no_log_artifact` — their reports are hours past the 1800s finished window, so
dead is the correct verdict there; E4 rescues fresh deliverables only, by design.

## Mutation controls (leadv2-mutation-control.sh; artifacts committed alongside)

| # | mutated body | control rc | baseline_rc | mutated_rc | red line |
|---|--------------|-----------|-------------|------------|----------|
| 1 | deliverable_dirs — revert resolution to docs/handoff/<tid> only | 0 | 0 | 1 | FAIL: Test 10: verdict=dead:no_log_artifact (must be finished_unlanded:<age>s — E4 resolved the wrong dir) |
| 2 | deliverable_age_s — scan only first candidate dir (lane_dirs[:1]) | 0 | 0 | 1 | FAIL: Test 10: verdict=dead:no_log_artifact (must be finished_unlanded:<age>s — E4 resolved the wrong dir) |
| 3 | resolve E4 rung — swallow unreadable dir | 0 | 0 | 1 | FAIL: Test 12: verdict=dead:no_log_artifact (must be unknown:* — an unreadable deliverable dir is never evidence of death) |

Control 1 is the mandated one: reverting the directory resolution turns the
founder-shaped case red at the exact regression this round existed to stop.
Artifacts: `mutation-control/20260903T234309Z-12008.txt`, `20260903T234408Z-74308.txt`,
`20260903T234510Z-36812.txt`.

## Falsification set

- `bash -n` on both changed shell files: OK.
- `python3 -m py_compile` on the extracted embedded Python (lines 85-1208): OK.
- `tests/run-all.sh --scope changed` (fresh lane range, no prior state file):
  see the run-all section below.
- `test-lane-liveness-authoritative.sh`: D6 FAILS IDENTICALLY ON THE UNMODIFIED BASE
  tree (git-archive extraction, byte-same failure line, only the age token differs) —
  pre-existing host-width red, not a regression of this change; every other assert green.

## New fixtures

- Test 10: founder-shaped id, deliverable under `docs/handoff/dispatch-<sig8>/`
  (tid dir holds planning artifacts only — the measured production shape) →
  `finished_unlanded:0s`.
- Test 11: founder-shaped id, dispatch dir present, no report anywhere →
  `dead:no_log_artifact` (death detection intact).
- Test 12: founder-shaped id, dispatch dir chmod-000 → `unknown:deliverable_dir_unreadable`;
  the fixture fails loudly if the platform does not enforce 000.

## Commits

- 7de54f50 fix(D2-E4-RESOLVES-THE-WRONG-DIR-01): E4 resolves the lane's real handoff dir
- d072d785 test(D2-E4-RESOLVES-THE-WRONG-DIR-01): founder-shaped fixtures

## run-all --scope changed

Result: rc=0, all selected suites green (three-states 16/0 among them); log tail
appended in the chat report.
