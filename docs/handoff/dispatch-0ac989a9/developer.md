# developer.md — BOARD-BLIND-TO-DETACHED-WORKERS-01 (dispatch-0ac989a9)

## Root cause — mechanism VERIFIED, and it differs from the brief's hypothesis

The brief's hypothesis (exit trap deleting a lead_durable row because
`set_worker_pid` never promoted it) is wrong, and I can say so with lines:

1. On a CONFIRMED spawn the dispatcher DISARMS the exit-trap release slot
   before handing off (R5 §4 of leadv2-dispatch-code.sh); the runner in
   Test 4 exercises `cleanup_pending_dispatch` with the slot cleared and the
   row survives; with the slot armed on a `pid_role: worker` row the release
   refuses it (`reason=not_owner_row_intact`) — the :4012 guard works.
2. The observed `active_lane_released where=exit_trap` at 00:10:20Z belonged
   to an attempt that exited `phase_precondition_refused` BEFORE any spawn —
   a correct release, not the incident.
3. The real killer is the liveness ladder + snapshot prune:
   - glm/glm-flash/kimi/freepool/codex arms spawn DETACHED workers — no
     local pid the ladder can `kill -0`, only a handle. Only the sonnet arm
     calls `leadv2_active_set_worker_pid` (:4834-4838); the codex arm hands
     a HANDLE to codex-task.sh, the glm branch a handle to glm-coder.sh —
     so the row keeps `pid_role=lead_durable` with the dispatcher's pid.
   - `leadv2-lane-liveness.sh` correctly refuses to read a lead_durable pid
     as worker evidence (LANE-REGISTRY-SELF-DEADLOCK-01), but nothing
     replaced the missing worker leg: a running detached worker (artifacts
     in its run dir / worktree, NOT in `docs/handoff/<tid>/`) resolved
     `dead:no_log_artifact` / `dead:silent_no_process`.
   - `leadv2-lanes-snapshot.sh`'s corroborated prune then saw "pid dead"
     (the exited dispatcher's pid) and tombstoned + deleted the running
     row -> ДОСКА ПУСТА. Both arms (codex dispatch-ef95d34a, glm
     dispatch-ab0ec014) fail through the same hole.

Evidence legs, live-verified:
- handle record: `_dispatch_register_arm` writes `arm=<arm> handle=<handle>`
  to `docs/handoff/<tid>/arm-registered` — leadv2-dispatch-code.sh:704,724-732,
  called at :4678 for every CONFIRMED spawn.
- glm-family run dir: glm-coder.sh writes the worker pgid to
  `<RUNS_DIR>/<handle>/pgid` — glm-coder.sh:1515; RUNS_DIR default
  `~/.claude/cache/glm-runs`, GLM_RUNS_DIR env seam — :54-66.
- codex: codex-task.sh's `--all` job registry, parsed at
  lane-liveness.sh:292 (`provider_jobs`), keyed by job id == arm-registered
  handle; queued/running means live.

## The fix (narrowest: teach the liveness oracle the worker's own channel)

**plugins/leadv2/scripts/leadv2-lane-liveness.sh** (+109): new
`detached_worker_live(tid, row)` probe — reads the last `arm=… handle=…`
line of `docs/handoff/<tid>/arm-registered` and asks the WORKER's channel:
run-dir `pgid` group-alive via `kill(-pgid,0)` for glm/glm-flash/kimi/
freepool, jobs-registry `queued|running` for codex. Positive-only: absent
record, missing run dir, unparsable/dead pgid, terminal job -> not live, so
a finished worker keeps its dead verdict (no-leak direction). Wired at the
two points where the ladder previously fell through to dead labels with zero
worker evidence: the no-stream handoff path, and the stale-stream/pid path
(gated on `not is_fresh`).

**plugins/leadv2/scripts/leadv2-lanes-snapshot.sh** (+11): the prune veto
honors an authoritative `alive` verdict — "pid dead" (a dispatcher's pid,
dead the instant it exits) must not prune a lane the oracle says is running.
The compare-and-delete ownership checks are untouched; no new files; the
renderer is untouched.

## Tests — tests/test-board-blind-detached-workers-01.sh (new, 5 cases)

Red run (fix reverted to HEAD; command:
`bash plugins/leadv2/scripts/tests/test-board-blind-detached-workers-01.sh`):

```
[TEST] FAIL: Test 1: verdict=dead:no_log_artifact, expected alive (live pgid=12941 handle=260829-034420-cafe0001-aaaa)
[TEST] FAIL: Test 2: still_present=False table_status=dead (expected True/active)
[TEST] PASS: Test 3: finished worker -> dead verdict, row pruned from active.yaml
[TEST] PASS: Test 4: disarmed trap keeps the detached row; worker-role row refused (not_owner_row_intact)
[TEST] FAIL: Test 5: verdict=dead:no_log_artifact, expected alive
2 passed, 3 failed — EXIT=1
```

(Test 2 red is the exact incident shape: row deleted from active.yaml, the
table renders it dead/absent. Tests 3/4 are guardrails and pass both ways.)

Green run (same command, fix applied):

```
[TEST] PASS: Test 1: detached glm worker live -> verdict=alive (was dead:no_log_artifact)
[TEST] PASS: Test 2: row still in active.yaml after 2 polls; table status=active
[TEST] PASS: Test 3: finished worker -> dead verdict, row pruned from active.yaml
[TEST] PASS: Test 4: disarmed trap keeps the detached row; worker-role row refused (not_owner_row_intact)
[TEST] PASS: Test 5: detached codex job running -> verdict=alive
5 passed, 0 failed — EXIT=0
```

Both required directions live in the one file: a live detached row SURVIVES
the release/prune path and renders active (T1/T2/T5); a genuinely finished
worker is still released/pruned — no leak (T3). T4 pins the exit-trap
contract. Fixtures are scratch (`lv2_mktemp_dir`, isolated
LEADV2_STATE_ROOT, inert codex stub via the CODEX_TASK_SH env seam); the
live control-plane registry is never touched.

## Falsification set

- `bash -n` on every changed shell file: OK (lane-liveness, lanes-snapshot,
  the test file).
- No standalone Python files changed (the probe is embedded in
  lane-liveness's existing python heredoc; `bash -n` covers syntax, the
  green run covers runtime).
- Repo changed-scope runner, foreground:
  `bash tests/run-all.sh --scope changed` ->
  `run-all: 3 passed, 1 failed` — the failure is the `run-core-offline`
  aggregate (9 suites red). ALL 9 reds pre-exist this diff, proven by
  re-running each failing suite with my two files reverted to HEAD:
  8/9 rc=1 identical; `test-lane-truth-batch-01.sh` fails with the SAME
  single line (`FAIL: Row 1 mutation gate HEAD must resolve stamped stream
  alive`) with and without the fix; `test-fg-dispatch-guard.sh` is green
  (36/36) in isolation both ways (its aggregate red is shard contention);
  `test-routing-enforcement-p1.sh`'s red is the same freepool-chain
  expectation family as the arm-vocabulary reds, visible on HEAD before its
  own 110s timeout. Matches the recorded baseline reds (memory:
  run-all-changed-preexisting-reds, 2026-08-28).

## diff --stat (mission files)

```
 plugins/leadv2/scripts/leadv2-lane-liveness.sh   | 109 +++++++
 plugins/leadv2/scripts/leadv2-lanes-snapshot.sh  |  11 ++
 plugins/leadv2/scripts/tests/test-board-blind-detached-workers-01.sh | 396 ++++ (new)
```
