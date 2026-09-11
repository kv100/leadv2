# F4 Composition Review

## 1. Registration, declaration, and the smallest fix

### Where an undeclared lane is registered

The concrete accidental registration path is `leadv2-session-runner.sh:203-205` calling `lane_adopt_pid`, which calls `lane_register` at `lib/leadv2-lane-state.sh:415-417`; when no non-dead same-task row exists, `lib/leadv2-lane-state.sh:146-183` appends a minimal row without a `writes` or `writes_reason` field.

Failure scenario: the dispatch row for `518b42814626` is no longer considered reusable, the live session runner adopts the task, and its new live row has an undeclared write set even though the earlier dispatch row carried the task's scope.

There is also an intentional, earlier prepass registration: `leadv2-dispatch-code.sh:8874-8899` passes an empty `lane_writes` with `prepass_pending`, and `leadv2-active-registry.sh:1204-1255` accepts and records that state; `leadv2-active-registry.sh:523-535` normalizes the empty value to `None` and deliberately leaves the empty candidate unjudged.

Failure scenario: a concurrent lane arrives while the first dispatch is still in prepass, so the first row is visible to collision checking before its eventual declaration exists.

### Why the declaration does not land on the blocking row

The declaration is persisted only by the dispatch path's later refresh at `leadv2-dispatch-code.sh:9125-9166` or by a caller that supplies the optional writes arguments to the shared registry writer at `leadv2-active-registry.sh:1891-1912`; `lane_adopt_pid` has no writes argument and the lane-state append at `lib/leadv2-lane-state.sh:178-183` writes only identity/liveness fields, so it cannot copy a declaration into a newly-created same-task row.

Failure scenario: row A receives the one-file declaration, row A becomes dead or is replaced, row B is created by adoption without that field, and the collision checker sees row B—not row A—as the live owner.

On the fanout path there is a second propagation gap: `leadv2-fanout.sh:980-982` registers the headless lane without writes, while the later `leadv2-fanout.sh:1313-1319` stamp reads only the optional `tasks.yaml` contract produced by `leadv2-fanout.sh:1351-1387` and suppresses `set_writes` failure with `|| true`.

Failure scenario: a one-file declaration exists in a handoff mission/brief but no matching `tasks.yaml` row supplies it, so the fanout row remains write-less and no diagnostic makes the launch refuse.

### Smallest safe change

For the observed duplicate-row defect, make the lane-state registration refuse before append at `lib/leadv2-lane-state.sh:178-183` when there is no reusable same-task row and no write set available, and stop swallowing that refusal at `leadv2-session-runner.sh:203-205`; this prevents the undeclared row from becoming a live 900-second blocker.

Failure scenario: a runner starts after its original row was removed and receives a non-zero adoption refusal instead of creating a new unknown-scope row, so an unrelated lane is admitted or is blocked only by a real declared intersection.

Do not blanket-change `leadv2-active-registry.sh:534-535` to reject every empty registration: the current dispatcher explicitly needs the prepass-pending state at `leadv2-dispatch-code.sh:8874-8899`, and report lanes can be legitimately write-less when they use the report-deliverable contract. If the policy must forbid every visible unknown row, the larger change is to delay active registration until after prepass (`leadv2-dispatch-code.sh:9125-9166`) or introduce a reservation state that the collision checker does not treat as an undeclared live owner.

## 2. Priority question: one correct-but-wrong composition

The following sequence explains the reported `writeset_pending` refusal without treating the registry as blind; the source and a read-only active-state probe show that the failure is row provenance/composition.

1. `leadv2-dispatch-code.sh:8874-8899` registers task `518b42814626` before prepass has resolved its scope, with `writes_reason=prepass_pending`; `leadv2-active-registry.sh:529-563` correctly records the row and defers candidate-path comparison because there is no candidate set yet.

   Failure scenario: the task is visible in `active.yaml` during the prepass interval even though its real scope has not yet been attached to that row.

2. The prepass correctly recognizes a one-file declaration as sufficient at `leadv2-dispatch-code.sh:5824-5838`, and the resolved declaration is correctly copied into `lane_writes` at `leadv2-dispatch-code.sh:9060-9091` and persisted by the second register call at `leadv2-dispatch-code.sh:9125-9166`.

   Failure scenario: row A now has the correct declared scope, but that correctness is local to row A and is not an invariant carried by every same-task registration path.

3. During runner adoption, `leadv2-session-runner.sh:191-205` calls `lane_adopt_pid`; `lib/leadv2-lane-state.sh:146-183` finds no reusable non-dead row and appends row B without `writes`, while `lib/leadv2-lane-state.sh:415-417` then transitions that new row.

   Failure scenario: the live worker/spawning process is represented by row B with `writes=None`, although the earlier row A and the task's actual work both have a concrete scope.

4. An unrelated lane with a single `docs/handoff/` file reaches the registry; `leadv2-active-registry.sh:545-563` sees row B's missing scope, `_lv2_ws_pending` measures its first-registration age at `leadv2-active-registry.sh:464-483`, and `_lv2_ws_live_worker` fails closed for a live non-interactive worker at `leadv2-active-registry.sh:425-462`.

   Failure scenario: the checker correctly refuses to compare an unknown incumbent against the candidate because a live worker might write anywhere, even though the actual declared files are disjoint.

5. The dispatcher correctly translates that registry refusal at `leadv2-dispatch-code.sh:4257-4312` into `dispatch_refused reason=writeset_pending`, names `blocked_by=518b42814626`, carries `blocked_writes_reason=undeclared`, and reports the configured 900-second window, matching the observed `task=89e8edf3` line.

   Failure scenario: each of four innocent one-file read-only lanes is refused for the full `window_s=900` interval, producing the reported four refusals despite no real write collision.

   Observed output shape: `dispatch_refused reason=writeset_pending task=89e8edf3 blocked_by=518b42814626 blocked_writes_owner=518b42814626 blocked_writes_reason=undeclared writes_reason=undeclared age_s=125 window_s=900`.

The composed outcome is wrong, but each component behaved as implemented: registration created the row it was asked to create, declaration persisted on its original row, collision checking refused unknown live scope, and the bounded fail-closed window applied. The defect is that the system permits two same-task row shapes with different write-set truth.

## 3. SOUND findings

### SOUND — undiffable write-set refusal and named remedy

Mechanism: `leadv2-dispatch-code.sh:4488-4502` and `:4532-4587` reject an all-`docs/handoff/` or all-`docs/leadv2/` write set before spawn, while admitting a validated report deliverable and naming `--lane-deliverable 'report:docs/handoff/<task>/report.md'` as the remedy.

Failure scenario: a build lane that declares only handoff files and has no reviewable artifact is refused as `undiffable_write_set` before reservation or model spend, with a concrete path to make an audit/design lane certifiable.

### SOUND — empty speakable pool refusal names every exclusion

Mechanism: `lib/leadv2-route-arbiter.sh:1335-1360` emits `pool_empty_all_excluded` with the exclusion rendering and exits refusal, while `hooks/leadv2-spawn-arbiter-gate.sh:54-61` forbids substituting an un-speakable fallback model.

Failure scenario: a bare Agent spawn whose filtered pool contains no speakable model is denied with the complete exclusion list, as asserted by `tests/test-spawn-speakable-pool.sh:96-106`, rather than being silently routed to an unsupported model.

## 4. Other findings

### Gate 1 can create the same unsafe row after a registry error

Mechanism: `leadv2-gate1-prompt.sh:61-70` falls back when registry registration fails, and its direct-write branch at `:108-121` creates a minimal row without `writes` while the registration/logging path is treated as best-effort.

Failure scenario: a source, lock, or state-path error causes Gate 1 to report success with a live-looking write-less row, and a later worker makes that row a pending blocker instead of failing admission at the point of registration.

### Fanout finalization can preserve a missing declaration

Mechanism: `leadv2-fanout-lane-launcher.sh:180-187` and `:270-282` re-register without forwarding `LANE_WRITES`, while the shared registry only preserves prior writes during recreation at `leadv2-active-registry.sh:649-710` when the prior row is actually found.

Failure scenario: if the prior reservation row is absent or not found under the same state root, launcher handoff/finalization creates a live row with the default no-write reason even though the parent fanout had a declaration available.

## 5. Confidence boundary

Confident: the registration/declaration chain, the lane-state append without writes, the collision-checker pending/live-worker logic, the 900-second refusal formatting, both SOUND behaviors, and the current read-only registry/state shape were verified against source and runtime state. Not fully verified: the exact process-timing event that caused row B for `518b42814626` and an independent replay of all four historical refusals; those causal details remain evidence-backed by the corrected S6/live artifacts rather than reconstructed from a fresh dispatch.
