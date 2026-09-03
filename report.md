# PHASE-BOOTSTRAP-DEADLOCK-01

## Reproduction

Before changing the tree, I created detached scratch worktree
`/private/tmp/phase-bootstrap-repro.26ht1Y` from `HEAD` and ran a brand-new
Standard task with isolated cache/state, `--no-spawn`, and one declared write:

```text
$ bash plugins/leadv2/codex-lead/lv2guard.sh -c 'cd /private/tmp/phase-bootstrap-repro.26ht1Y && timeout 120 env -u CLAUDE_PROJECT_ROOT PROJECT_ROOT=/private/tmp/phase-bootstrap-repro.26ht1Y LEADV2_PROJECT_ROOT=/private/tmp/phase-bootstrap-repro.26ht1Y LEADV2_DISPATCH_CACHE_DIR=/private/tmp/phase-bootstrap-repro.26ht1Y/.cache3 LEADV2_STATE_BASE=/private/tmp/phase-bootstrap-repro.26ht1Y/.state3 LEADV2_DISPATCH_TERMINAL_LEDGER=0 LEADV2_BURN_GOVERNOR=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_LANE_SHAPE=off LEADV2_DISPATCH_SPAWN=0 bash plugins/leadv2/scripts/leadv2-dispatch-code.sh "PBDEADLOCK first time shell line 20260902" --kind code --task-class standard --subsystems 1 --task-id PBDEADLOCK-REPRO-20260902-C --no-spawn --writes plugins/leadv2/scripts/leadv2-dispatch-code.sh'
[leadv2-dispatch-code] lane_plan_missing task=502450be reason=source_absent source=/private/tmp/phase-bootstrap-repro.26ht1Y/docs/handoff/PBDEADLOCK-REPRO-20260902-C/context.yaml
[leadv2-dispatch-code] dispatch_task_bound task=502450be founder_task=PBDEADLOCK-REPRO-20260902-C
[leadv2-dispatch-code] task_class=Standard route=phases source=flag task=502450be
[leadv2-dispatch-code] class_floor_held task=502450be declared=Standard computed=Light
[leadv2-dispatch-code] brain_decision task=502450be class=Standard class_source=floor_held phases=classify,plan,gate1,build,test,review,deploy,live_verify,close reason=declared_floor
[leadv2-dispatch-code] dispatch_classified task=502450be class=product reason=conservative_default kind=code
[leadv2-dispatch-code] phase_precondition_refused task=502450be class=Standard missing=plan,gate1 mode=1
[leadv2-dispatch-code] ERROR: dispatch refused: missing mandatory phases: plan,gate1
[leadv2-dispatch-code] ERROR:   remedy: /private/tmp/phase-bootstrap-repro.26ht1Y/plugins/leadv2/scripts/leadv2-phase-record.sh record 502450be plan --artifact docs/handoff/<task-id>/brief.md   (or docs/handoff/<task-id>/fix-round-N.md, or a context.yaml with decisions:, or a non-empty architect-prepass.md)
[leadv2-dispatch-code] ERROR:   remedy: /private/tmp/phase-bootstrap-repro.26ht1Y/plugins/leadv2/scripts/leadv2-phase-record.sh record 502450be gate1 --reason "<founder gate-1 decision>"   (or --artifact <path-to-.gate1-passed> if run through leadv2-gate1-prompt.sh)
[leadv2-dispatch-code] active_lane_released task=502450be id=PBDEADLOCK-REPRO-20260902-C where=exit_trap
$ echo $?
3
```

The refusal is caused by the dispatcher recording `classify` before the guard
checks whether the lane has zero phase records. The exact pre-change sites were
`leadv2-dispatch-code.sh:6931` (classify record) and `:6939` (phase guard).

## Fix

Pending.

## Verification

Pending.
