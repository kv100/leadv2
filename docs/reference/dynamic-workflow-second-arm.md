# Dynamic workflows — second arm

**Verdict: disagree with the lead's split.** The founder's instruction was that both workflows and nested agents are done *before WAVES*; “design before the gate, implementation after WAVES” changes that instruction rather than sequencing it. The safe interpretation is narrower than a full dynamic rollout: before WAVES, implement and prove one fixed-shape, receipt-bearing workflow step through the existing dispatch spine; defer adaptive shape selection until its measurements exist. The reason to avoid transport-plus-graph-policy in one rollout is sound, but it supports this two-stage pre-WAVES implementation, not an after-WAVES implementation delay.

## Scope and evidence method

This is a document-only audit. The first arm's working-tree file is absent here, so I read its immutable committed version with:

```text
git show 881cc487:docs/handoff/SMART-ARBITER-DESIGN-20260907/dynamic-workflow-report.md
```

`881cc487` is the sole commit touching that path in `git log --all -- <path>`. Current-code claims below refer to this lane's files and can be checked with the listed commands.

## 1. `runStep(request)` is the right seam only as a thin facade over dispatch

The first arm is right that a step needs one deterministic identity and a durable receipt. It is wrong to leave the impression that this should become a second execution pipeline. The existing dispatch path already contains the critical sequence:

1. `leadv2-dispatch-code.sh:8842-8893` constructs a descriptor and calls `route_arbiter worker`.
2. `leadv2-dispatch-code.sh:4777-4912` owns reserve → spawn → confirm/abort for a dispatch attempt.
3. `leadv2-dispatch-code.sh:6191-` owns the provider switch and adapters; the GLM branch, for example, starts at `:6320` and the Codex/Claude branches are in the same function.

So `runStep(request)` is a good *workflow-facing boundary* if it adds `workflow_run_id`, `step_id`, `attempt`, input digest, exact decision, and terminal receipt, then delegates to one extracted dispatch primitive. It is not a good replacement launcher. A fresh runner that independently calls the arbiter, reserves another budget, and invokes adapters would duplicate the live reserve/spawn/confirm semantics and make duplicate suppression and terminal attribution ambiguous.

What retires in the first migrated workflow is its per-workflow executor shim (the first arm names audit's `glmBuild()` boundary). What does **not** retire is `leadv2-dispatch-code.sh`'s adapter path. The implementation cut should extract or expose its already-owned primitive; it must not reproduce it in `leadv2-workflow-step.py`.

The current registry is not yet that primitive. Dispatch uses it only to form a launchability set at `leadv2-dispatch-code.sh:2595-2620`; that implementation still grants GLM/GLM-flash/freepool through a shell-side `legacy` set at `:2603-2607`. It does not pass a registry descriptor into the actual spawn switch. Therefore an exact decision-to-argv validation remains required before a workflow may claim the boundary is closed.

Re-run:

```text
nl -ba plugins/leadv2/scripts/leadv2-dispatch-code.sh | sed -n '2592,2621p;4777,4912p;8842,8914p'
```

## 2. The registry/arbiter conflict is partly overtaken, but still blocking

Two 2026-09-09 changes materially improve the first arm's stale snapshot:

- `c2be0fac` adds `adapter_scope=external` and `external_adapter` for GLM/freepool registry refusals (`leadv2-launch-registry.py:411-429`). That distinguishes “this registry has no argv” from “the dispatcher has no launch path.”
- `1801fd14` replaces three `gpt-6-astra` Codex matrix rows with Luna/volume, Terra/standard, and Sol/top (`leadv2-routing.yaml:213-236`). It fixes the all-Astra model collapse.

For code work where the registry's task-class-to-size reduction equals the dispatcher descriptor, model/tier now agree. Raw local probe:

```text
$ python3 plugins/leadv2/scripts/lib/leadv2-launch-registry.py --kind code --role developer --arm codex --task-class standard --json
{"ok": true, "kind": "code", "role": "developer", "arm": "codex", "task_class": "standard", "model": "gpt-5.6-luna", "tier": "volume", "size": "standard", "size_fallback": false, "effort_requested": "low", "effort_applied": "low", "effort_supported": true, "pool_default": true, "argv": ["--tier", "volume", "--model", "gpt-5.6-luna", "--effort", "low"]}
$ timeout 15 bash plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh worker '{"work_kind":"code","size":"standard","complexity":"standard","task":"second-arm-standard","allowed_arms":["codex"]}'
arm=codex kind=code model=gpt-5.6-luna tier=volume effort=medium reason=cheapest_capable ...
$ python3 plugins/leadv2/scripts/lib/leadv2-launch-registry.py --kind code --role developer --arm codex --task-class heavy --json
{"ok": true, "kind": "code", "role": "developer", "arm": "codex", "task_class": "heavy", "model": "gpt-5.6-terra", "tier": "standard", "size": "heavy", "size_fallback": false, "effort_requested": "high", "effort_applied": "high", "effort_supported": true, "pool_default": true, "argv": ["--tier", "standard", "--model", "gpt-5.6-terra", "--effort", "high"]}
$ timeout 15 bash plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh worker '{"work_kind":"code","size":"heavy","complexity":"complex","task":"second-arm-heavy","allowed_arms":["codex"]}'
arm=codex kind=code model=gpt-5.6-terra tier=standard effort=high reason=cheapest_capable ...
```

The ellipses only omit volatile quota tokens after the stable identity fields; the command prints them in full. The standard-code probe is also the counterexample: the arbiter emitted `effort=medium`, while the registry would launch `effort=low`. So the quoted obstacle no longer holds as a model/tier-collapse claim, but it **still holds as an exact-decision claim**. The registry independently chooses the cheapest row for an arm (`leadv2-launch-registry.py:394-407`) and independently computes effort (`:438-455`); the arbiter computes effort from `router_v2.effort_matrix` (`leadv2-route-arbiter.sh:1025-1062`). They are different policy functions.

There is a second unreconciled path: for a heavy Codex plan, registry output says `effort_supported: false` and has only `--tier standard`, while it requests high effort:

```text
$ python3 plugins/leadv2/scripts/lib/leadv2-launch-registry.py --kind plan --role architect --arm codex --task-class heavy --json
{"ok": true, "kind": "plan", "role": "architect", "arm": "codex", "task_class": "heavy", "model": "gpt-5.6-terra", "tier": "standard", "size": "heavy", "size_fallback": false, "effort_requested": "high", "effort_applied": null, "effort_supported": false, "pool_default": true, "argv": ["--tier", "standard"]}
```

That is blocking for adaptive workflows because a receipt cannot honestly say the selected effort was applied. The pre-WAVES fixed-shape slice must accept a complete arbiter decision as input and validate equality of `(arm, model, tier, effort)` without re-ranking. Refuse when the adapter declares effort unsupported; do not silently substitute the registry's result.

Re-run:

```text
nl -ba plugins/leadv2/scripts/lib/leadv2-launch-registry.py | sed -n '376,456p'
nl -ba plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | sed -n '1025,1062p;1164,1186p'
nl -ba plugins/leadv2/config/leadv2-routing.yaml | sed -n '213,290p'
```

## 3. The first honest workflow measurement does not yet exist

No currently retained record joins a workflow's admitted shape to its actual step outcomes. `leadv2-scorecard-write.sh:236-319` records `nested_spawns`, optional escalation count, route-phase count, and close-level verification outcome. Its schema confirms those fields at `contracts/leadv2-scorecard.schema.json:115-145`. The arbiter's local JSONL record contains arm/model/tier and task but no workflow run, step, round, or result (`leadv2-route-arbiter.sh:741-761`). Consequently no existing number can distinguish “the policy selected W=1 and the workflow actually did one successful step” from “the policy selected W=4 but only one worker ran.” Calling either behavior measured would be false precision.

The first honest number after the fixed-shape receipt exists is **shape-realization rate**:

```text
shape_realization_rate = completed_receipts_with(actual_steps == admitted_W and actual_rounds == admitted_R)
                         / terminal_workflow_receipts
```

Report it separately by `(workflow_definition_rev, evidence_bucket, W, R)`, and keep `blocked_control_plane`, `unknown_completion`, and budget-exhausted terminal receipts in the denominator. A policy that always emits W=4 but launches one step scores below 1; a policy that launches extra work also scores below 1. This tests the policy/executor contract before trying to infer quality from task closure.

The first post-realization quality comparison is then the guarded pair: `verify_pass` and `bandit_reward_composite` already exist at close, but only compare W buckets after a fixed workflow definition and adequate counts. They are not a first measurement today because neither carries admitted W/R or per-step linkage. `route-decisions.yaml` likewise only exposes phase count (`scorecard-write.sh:274-307`), not workflow shape.

Re-run:

```text
nl -ba plugins/leadv2/scripts/leadv2-scorecard-write.sh | sed -n '236,319p'
nl -ba plugins/leadv2/contracts/leadv2-scorecard.schema.json | sed -n '115,145p'
nl -ba plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | sed -n '741,761p'
```

## 4. The cheapest safe wait is a frozen, replayable design snapshot

If implementation is deliberately delayed, record a single append-only design snapshot now, before any more routing edits: first-arm commit `881cc487`; current `HEAD`; `arb_rev` and `matrix_rev` from an arbiter decision; SHA-256 of `leadv2-routing.yaml`, `leadv2-launch-registry.py`, and `leadv2-dispatch-code.sh`; the effective Codex rows; the exact unsupported-effort cases; and the required receipt fields for a future fixed-shape step. This document contains the first four categories and reproducible commands; the implementation owner should make the snapshot machine-readable in its own allowed handoff location.

The acceptance rule is simple: before implementation begins, rerun the three local registry/arbiter probes above. If any selected tuple or unsupported-effort outcome differs, reopen the design decision instead of implementing against this report. That is much cheaper than preserving prose while the two policy owners continue to change.

This does not make an after-WAVES delay compliant with the founder instruction. It only makes a bounded pause recoverable if the lead obtains an explicit revised authorization.

## What the first arm got wrong or left unverified

I checked hardest: (1) the committed first-arm report at `881cc487`, (2) the current registry after `c2be0fac`, and (3) the current routing matrix/arbiter after `1801fd14`.

1. Its sequencing recommendation conflicts with the founder's plain “workflows ... before WAVES” instruction. The anti-attribution rationale is valid, but it does not authorize postponing all implementation until after WAVES.
2. Its registry/arbiter warning used a pre-2026-09-09 snapshot. The all-Astra model-collapse portion is stale: the matrix now contains Luna/Terra/Sol and standard/heavy code probes agree on model/tier. The conclusion needs narrowing, not deletion: effort is still divergent and some adapters cannot apply it.
3. It proposed `runStep` without identifying the existing dispatch reserve/spawn/confirm spine that must be reused. A new independent reservation/adapter loop would be a real duplicate path.
4. It left the Workflow-host bridge explicitly `UNVERIFIED`, correctly. That remains an implementation blocker; no source-only JS comment proves a host binding.
5. It did not establish a current measurement capable of validating adaptive shape. Existing scorecards measure close-level outcomes and counts, not admitted W/R against realized steps.
6. It did not have the later `adapter_scope=external` distinction, so its description of external-provider registry refusals is obsolete. This corrects scope reporting, not exact launch-decision validation.

## Self-check and changed-scope verification

No production code is changed in this audit, so there is no fabricated red-to-green product-fix story. The meaningful red result is intentionally still red: the standard-Codex probe in §2 shows registry `effort_requested=low` versus arbiter `effort=medium`; this report records it rather than pretending a documentation edit fixed it.

Raw document check (rc=0):

```text
report_exists=True
heading=# Dynamic workflows — second arm
required_markers_missing=[]
PASS: report document structure and required evidence anchors
```

Raw mechanical checks (rc=0):

```text
$ git diff --check
<no output>
bash -n: N/A (0 changed shell files)
python3 -m py_compile: N/A (0 changed Python files)
```

Raw changed-scope command and result (rc=0):

```text
$ timeout --kill-after=15 900 bash tests/run-all.sh --scope changed
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] scope=changed running 0 of 95 suites (base=main@81fbacc25a, 0 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=0 total=95 base=main@81fbacc25a changed=0 unmapped=0 verdict=nothing_to_run reason=no_relevant_changed_files
[CORE-OFFLINE] suites passed=0 failed=0 missing=0 verdict=nothing_to_run reason=no_relevant_changed_files repo=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/G-WORKFLOWS-ARM3
[PASS] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] .../tests/test-status-surface-bash32.sh
test-status-surface-bash32: 16 passed, 0 failed, 0 skipped
[PASS] .../tests/test-status-surface-bash32.sh
[RUN] .../tests/test-status-surface-single-lead.sh
test-status-surface-single-lead: 24 passed, 0 failed
[PASS] .../tests/test-status-surface-single-lead.sh
[RUN] .../tests/test-status-surface-fast-names.sh
test-status-surface-fast-names: 12 passed, 0 failed
[PASS] .../tests/test-status-surface-fast-names.sh
run-all: 4 passed, 0 failed, scope=changed
```

The full process was foregrounded under the displayed timeout and returned before this report was committed. The core selected no source suites because the then-untracked documentation file was not part of the Git range; the three serial gate suites still ran and passed. The document is staged and committed immediately after the final diff check below.
