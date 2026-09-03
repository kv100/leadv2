# FREEPOOL-MUST-ACTUALLY-GET-WORK-01 report

Round 3. All evidence below was produced fresh in this round (2026-09-03) from the
committed lane state (`8dc52ff4` + `109f2f02`), not carried over from round 2's
uncommitted draft.

## Cause status

| Cause | Status | Mechanism |
| --- | --- | --- |
| (a) silent classifier override (addendum 4) | Fixed in `109f2f02`, verified this round | `leadv2-dispatch-code.sh:3960` emits `task_class_override by=admission ... requested=<hint> resolved=<class> reason=<deciding evidence>`; `usage()` at `:6376` documents `--task-class` as a classifier-overridable hint, so the flag is no longer a lie in the interface. |
| (b) `--protected` with no write-set connection (brief cause 1 / fix A) | Fixed in `8dc52ff4`, verified this round | `_lane_writes_class` (`leadv2-dispatch-code.sh:6588`) classifies the declared LANE_WRITES; `:7244` journals `protection_derived` with the deciding write-set. Effective protection = write-set verdict OR manual flag (flag is additive only). tests/ + `plugins/leadv2/scripts/tests/` + `docs/handoff/`-only sets are never protected; empty/unknown fails closed to protected. |
| (2) turn cap kills with uncommitted work (brief cause 2 / fix B) | Fixed in `8dc52ff4`, verified this round | `freepool-coder.sh:1836`: when the reaped child's bound is `turn_count`, the supervisor runs `leadv2_worker_commit_epilogue` with a `wip(<run_id>): turn-cap checkpoint` message before outcome classification. Default on; `FREEPOOL_TURNCAP_CHECKPOINT=0` is the dedicated negative-control seam. No limit bump involved. |
| floor vs test-only lanes (brief fix C) | Floor preserved, exemption proven by live line | `lib/leadv2-route-arbiter.sh:143`: the FP-08 `bulk_only` floor keeps applying to standard/heavy/strategic code EXCEPT when the dispatcher proves `test_only` from the write-set classification (descriptor default false = exactly the old behaviour). The `full` knob is untouched. Live floor behaviour shown in the acceptance line: `floor_mode=bulk_only ... test_only=1` with no `arm_floor_applied`. |

## Acceptance dispatch journal

A hermetic dispatch through the production dispatcher and arbiter (no sibling-copy
mutation), write-set only `tests/` + `docs/handoff/`, `--task-class standard`, **no
`--protected`**, glm pinned at util 99 so the choice is real and not quota-forced:

```text
[leadv2-dispatch-code] protection_derived by=router task=feb927ef writes=tests/freepool-probe.sh,docs/handoff/FREEPOOL/report.md write_class=tests_docs writes_protected=0 manual_protected=0 effective_protected=0
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=freepool model=freepool-default tier=standard effort=medium task=feb927ef reason=cheapest_capable arbiter_pick=freepool util_glm=99 util_codex=20 util_claude=20 util_freepool=0 floor_mode=bulk_only floor_mode_source=yaml test_only=1 complexity=unknown duration_class=unknown
```

The required line is the `route_resolved ... arm=freepool` one; `protection_derived`
above it is the write-set derivation that admitted it.

## leadv2-mutation-control.sh

Fresh run this round (`bash docs/handoff/FREEPOOL-MUST-ACTUALLY-GET-WORK-01/leadv2-mutation-control.sh <artifact>`); each mutation below is applied to a sibling throwaway copy, shown RED, reverted, and the production path re-proven GREEN:

```text
$ .../leadv2-mutation-control.sh protection-and-floor
PASS: bash syntax: dispatcher + arbiter
PASS: green: Standard tests/docs-only lane resolves arm=freepool without --protected
EVIDENCE: [leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=freepool model=freepool-default tier=standard effort=medium task=feb927ef reason=cheapest_capable arbiter_pick=freepool util_glm=99 util_codex=20 util_claude=20 util_freepool=0 floor_mode=bulk_only floor_mode_source=yaml test_only=1 complexity=unknown duration_class=unknown
PASS: green: journal carries deciding test/docs write-set derivation
PASS: green: Standard tests/docs-only lane is below the preserved capability floor
PASS: RED: negative control A always-protected mutation blocks freepool for the tests/docs lane
PASS: RED: negative control C forced-floor mutation demotes freepool for the tests/docs lane
PASS: green: classifier escalation journals requested class, resolved class, and reason
PASS: RED: negative control D suppressing override journal removes the required trace
PASS: green: production dispatcher remains freepool-admitting after mutation controls
SUMMARY: pass=9 fail=0
ARTIFACT=protection-and-floor EXIT=0

$ .../leadv2-mutation-control.sh turn-cap-checkpoint
PASS: bash syntax: freepool checkpoint path
PASS: green: turn-capped freepool round leaves an in-scope checkpoint commit
PASS: RED: negative control B checkpoint-disabled turn-capped round has no commit and remains dirty
SUMMARY: pass=3 fail=0
ARTIFACT=turn-cap-checkpoint EXIT=0
```

Mutation → assertion mapping (one negative control per claimed cause):

- Cause (b): mutation A — `_writes_class` forced to always `protected` → freepool admission goes RED (`arm_excluded ... reason=protected_path`), reverted → green.
- Cause (2): mutation B — checkpoint seam disabled (`FREEPOOL_TURNCAP_CHECKPOINT=0`) → the "capped round leaves a commit" assertion goes RED (repo dirty, no checkpoint commit), seam on → green.
- Cause C exemption: mutation C — arbiter floor branch forced to apply despite `test_only` → freepool demoted with `arm_floor_applied ... reason=standard/code`, reverted → green.
- Cause (a): mutation D — the `task_class_override` emit removed → the override-trace assertion goes RED, reverted → green.

## Changed-scope suite selection

`--scope changed` over the lane range (state file reset to lane anchor `4fb63b42`, select-only seam so the prohibited 83-suite core runner is not started on this shared machine):

```text
[SELECT] .../plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-freepool-gets-work.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-freepool-model-selector.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-freepool-turncap-checkpoint.sh
run-all: 37 selected, scope=changed, select_only=1
EXIT_SELECT=0
```

Both new suites are registered twice over: by `EXTRA_SUITE_MAP` rows in `tests/run-all.sh` (`leadv2-dispatch-code`/`leadv2-route-arbiter`/`freepool-coder`/`leadv2-worker-epilogue`/`freepool-arm.yaml` → the new suites) and by the `test-<stem>.sh` self-select path convention.

## Individual suite runs (this round)

```text
bash plugins/leadv2/scripts/tests/test-freepool-gets-work.sh           === 9 passed, 0 failed ===  EXIT=0
bash plugins/leadv2/scripts/tests/test-freepool-turncap-checkpoint.sh  === 3 passed, 0 failed ===  EXIT=0
bash plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh    === 31 passed, 0 failed === EXIT=0
bash plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh      === 7 passed, 0 failed ===  EXIT=0
bash plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh       8 passed, 0 failed        EXIT=0
```

`test-worker-commit-epilogue.sh` is included because the lane modified
`lib/leadv2-worker-epilogue.sh` (trailing-slash normalization in `_lv2_epilogue_lane_writes`).

## Falsification and syntax

```text
bash -n OK: freepool-coder.sh, leadv2-dispatch-code.sh, lib/leadv2-route-arbiter.sh,
lib/leadv2-worker-epilogue.sh, test-freepool-capability-floor.sh, test-freepool-gets-work.sh,
test-freepool-model-liveness.sh, test-freepool-turncap-checkpoint.sh, tests/run-all.sh,
leadv2-mutation-control.sh   (all EXIT=0)
```

No standalone `.py` file was changed by this lane (`git diff --name-only 4fb63b42..HEAD -- '*.py'` is empty), so there is nothing to `py_compile`; the arbiter's changed logic is embedded Python and is executed green by every suite run above.

## Honest boundaries

- The checkpoint covers every death the supervisor itself observes (turn cap and all other bounds — the non-`turn_count` branch already ran the commit epilogue since WORKERS-MUST-COMMIT-01). It cannot cover the supervisor process itself being SIGKILLed/stale-reaped — that class is what killed rounds 1 of this lane and of CI-SUITES-ARE-MACOS-ONLY-01; an in-process checkpoint is structurally powerless there. Nothing in this lane claims otherwise.
- Whether `heavy` was the right verdict for this task's shape is out of scope per addendum 4; the classifier was not tuned.
