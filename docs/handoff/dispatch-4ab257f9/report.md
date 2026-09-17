# Report — test mission for task-class flag (dispatch-4ab257f9)

Date: 2026-09-17T09:25Z · model: glm-5.3-flash · worktree pinned: /Users/kostiantyn.vlasenko/Projects/leadv2 (branch main)

## Mission
`test mission for task-class flag` — smoke-dispatch verifying that a task-class
flag survives the whole dispatch path and reaches the worker.

## Verdict: PASS — flag propagates end-to-end

Evidence chain (all probed live in this lane session):

1. **Admission receipt** — `docs/handoff/dispatch-4ab257f9/admission-receipt.yaml`:
   `task_class: Heavy`, `source: flag`, `route: phases`, recorded 2026-08-28T13:17:40Z.
2. **Worker env** (this session, `env | grep` probe):
   `DC_TASK_CLASS=Heavy` — matches the receipt byte-for-byte (case aside; the
   dispatcher lowercases before use, see below).
3. **Dispatcher wiring** — `plugins/leadv2/scripts/leadv2-dispatch-code.sh`:
   - `:2554` `local _kind="${DC_KIND:-code}" _size_raw="${DC_TASK_CLASS:-standard}"`
   - `:2836-2837` `local _size_class="${DC_TASK_CLASS:-standard}"; _size_class="${_size_class,,}"`
     (default `standard` when the flag is absent)
   - `:2855` router emits `arm_excluded … reason=arm_not_capable_for_size task_class=${_size_class}`
     — the class is enforced against candidate arms, not merely recorded.

## Non-findings checked and excluded
- `docs/handoff/4ab82abf8512/task-class.yaml` says `task_class: Standard` —
  a **different task** (recorded 2026-09-15, `source: flag` there too, brain
  `class_source: floor_held`). Not part of this dispatch; no contradiction.
- `docs/handoff/4ab257f9/` holds only `cost-estimate.yaml` + `not-landing.reason`
  (an earlier landed/not-landed artifact for the short id).

## Lane self-check
- No `.sh`/`.py` files changed by this lane → `bash -n` / `py_compile` n/a.
- Changed-scope runner (`bash tests/run-all.sh --scope changed`, exit 0, budget mode):

```
test-resume-lane-arg-shapes: 39 passed, 1 failed
[TEST] FAIL: A8: dispatch exited 8 (expected 0)
shadow-control-plane: PASS=17 FAIL=0
  Failures (blocking):
    - plugins/leadv2/scripts/tests/run-core-offline.sh
    - plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh
run-all: 6 passed, 2 failed, 0 known-red, 28 known-red-skipped, scope=changed
```

  Both reds are **not this lane's diff** (lane changed zero `.sh`/`.py` files):
  - `test-resume-lane-arg-shapes.sh` was already modified in the worktree
    before this lane started (`git status: M`) — case A8 expectation is part of
    that foreign edit.
  - `run-core-offline.sh` flips NOT-KNOWN-RED under concurrent runners; a
    foreign lane was live during the run (`ps`: `test-status-surface-bash32.sh`
    in `.claude/worktrees/fe674d7918f3`).
