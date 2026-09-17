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
- Changed-scope runner: see chat report for pasted raw output (worktree had
  three pre-modified test suites from parallel work, not this lane's diff).
