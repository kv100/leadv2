# B4-EMPTY-DIFF report

## Finding and scheduling evidence

The immediate cause was an unhandled arm and handle shape, not an expired timer.
`spawn_product_close` in `leadv2-dispatch-code.sh` launches the close process after
spawn confirmation, passing the selected arm and the original handle. That is
intentional: `pc_await_worker_exit` is responsible for waiting before diff scoping.
At the merge base, `pc_worker_alive` recognizes only `sonnet` with a bare numeric
PID in its Claude branch. `fable` falls through to `proceed_legacy`; a Sonnet full
`PID=... LABEL=... SESSION_ID=... STREAM=...` receipt falls through too.

Live artifact read: `~/.claude/leadv2-state/leadv2/tasks/dispatch-1f5e5544/journal.md`:

```text
- 2026-09-08T12:07:57Z [decision] product_close task=1f5e5544 status=spawned author=fable
```

Live artifact read: `~/.claude/leadv2-state/persona-engine/tasks/dispatch-1f5e5544/journal.md`:

```text
- 2026-09-08T12:07:57Z [decision] product_close task=1f5e5544 worker_liveness=unknown author=fable handle=PID=51773 LABEL=developer-dispatch-1f5e5544-1788869224 SESSION_ID=8c64cbf9-27ed-4a9d-b05e-7f976b0e2b89 STREAM=/Users/kostiantyn.vlasenko/Projects/leadv2/docs/handoff/dispatch-1f5e5544/attempts/1788869225-49695/developer.stream.jsonl action=proceed_legacy
- 2026-09-08T12:08:01Z [decision] review_gate task=1f5e5544 status=blocked reason=no_work terminal=no_work cause=empty_diff
- 2026-09-08T12:08:02Z [decision] dispatch_terminal task=1f5e5544 terminal=no_work cause=empty_diff worker_reason="{type:system,subtype:thinking_tokens,estimated_tokens:800,estimated_tokens_delta:150,session_id:8c64cbf9-27ed-4a9d-b05e-"
```

The two journals split dispatch and close events across repo state roots. Their
recorded timestamps establish that the waiter bypass occurred in the launch
second, four seconds before the empty-diff verdict. No speculative scheduling
explanation is needed.

## Liveness evidence available to the gate

| Signal | Reachability and use |
| --- | --- |
| Worker PID | The launch receipt contains `PID=51773`; the close process already receives that complete receipt as `HANDLE`. Normalize it only for process operations, preserving the receipt and arm identity. |
| Finalizer PID | `_pc_sonnet_run_dir_for_handle` resolves the launcher run by exact PID, verifies the shared pointer against its pid file, and reads `finalizer_pid`. The same launcher/run convention serves sonnet, haiku, opus, and fable. Live process evidence wins even if `.finalized` already exists. |
| Stream heartbeats | The receipt contains the attempt-specific `STREAM` path. Its recorded `tool_progress` events include `elapsed_time_seconds=30`, `60`, and `300`; these are progress, not completion. The implementation does not interpret elapsed tool time as a finish signal. |
| Stream mtime | `_pc_stat_mtime` is already in this script. When neither process is observable and no exact-run `.finalized` exists, a fresh stream keeps the wait alive. Use the attempt receipt rather than a potentially moved shared pointer. |

A live PID or finalizer remains live regardless of stream age. Without process
proof, stream writes renew a 120-second inactivity window
(`LEADV2_PC_CLAUDE_STREAM_STALE_S`, positive integer, capped at 3600). An exact-run
`.finalized` after process exit permits immediate gating; otherwise a missing or
stale stream permits gating. The existing 4200-second hard worker ceiling and
its deliberate reap/`dead:timeout` path are unchanged. This fix does not raise a
timeout or use elapsed thinking time to produce `no_work`.

Heartbeat artifact read with Python JSON parsing from
`docs/handoff/dispatch-1f5e5544/attempts/1788869225-49695/developer.stream.jsonl`
in the main checkout (line 345):

```json
{"type":"tool_progress","tool_use_id":"toolu_01G4hvn387oFoeq5hzBTijqN-heartbeat-9","tool_name":"Bash","parent_tool_use_id":"toolu_01G4hvn387oFoeq5hzBTijqN","elapsed_time_seconds":300,"heartbeat":true,"session_id":"8c64cbf9-27ed-4a9d-b05e-7f976b0e2b89","uuid":"c40aecd4-f1a8-4f4d-be36-3ca4e3442dad"}
```

## Scope and ownership evidence

All tracked edits are in the pinned B4 worktree. Before editing, the live
`~/.claude/leadv2-state/leadv2/active.yaml` had only this lane plus an older
`75cef0fbfd23` row declaring the close script. That older row was stale and had
`dead_at: 2026-09-08T12:36:22Z`; its recovered row was also dead at 15:15:58Z.
Its worktree's `git status --short` showed only an unrelated architect-prepass
file, and its latest commit was `90c87b9d test(review): commit three lane-bound
mutation controls`. No live competing owner was identified. `ps` was denied by
the sandbox, so this is registry/worktree evidence, not independent PID proof.

The production diff changes liveness receipt parsing, Claude arm routing,
process/finalizer checks, and matching reap/rollback paths. It does not edit
`pc_scope_diff` or the `asked_into_void`, `unscoped_lane_work`,
`cross_repo_elsewhere`, or `declared_no_bytes` classification branches.
No merge or push was performed. Reports and mutation artifacts accompany the
two authorized code/test paths; no tracked runtime-state path is changed.

## Test design and evidence limits

The new suite starts a real worker subprocess and invokes the whole close
script with the launcher's full receipt. The worker emits heartbeats and writes
its first deliverable bytes after six seconds, beyond the historical immediate
liveness evaluation. Time is scaled; this is not a literal multi-minute replay.
A review stub checks that `review.diff` contains those late bytes. A terminal
ledger stub captures the actual `write-terminal` argument, and assertions check
that value (`landed` or `no_work`), not a journal substring. No paid model or
external API is used. Other cases cover full Sonnet receipts, numeric Sonnet
compatibility, exited haiku/opus, heartbeat-only progress, stale heartbeats, and
a live finalizer after the model PID exits.

The first test invocation failed to create a sandbox temporary directory. That
is not counted as a negative control. The valid pre-fix run below reproduced
`no_work` on both live workers; the expanded post-fix suite passed 32 assertions.
GNU mktemp was exposed through `/tmp/b4-tools` for existing harnesses whose BSD
mktemp default directory is not writable in this sandbox. This is test-process
setup only, not a repository change.

## bash -n and python3 -m py_compile evidence

See the commands and exit codes below.

```text
$ timeout 10 bash -n plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
rc=0
$ timeout 10 bash -n plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh
rc=0
python3 -m py_compile: not applicable; no Python files changed
```

## test-empty-diff-waits-for-a-live-worker.sh RED evidence

timeout 100 bash plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh (before production edits; rc=1)

```text
FAIL fable_late terminal value: got=no_work expected=landed
FAIL fable_late late bytes reached review: got=absent expected=reviewed
FAIL fable_late close rc: got=5 expected=0
PASS fable_exited terminal value: no_work
PASS fable_exited cause: empty_diff
PASS fable_exited close rc: 5
PASS fable_exited exited promptly (1s): prompt
FAIL sonnet_raw_handle terminal value: got=no_work expected=landed
FAIL sonnet_raw_handle late bytes reached review: got=absent expected=reviewed
FAIL sonnet_raw_handle close rc: got=5 expected=0
PASS haiku_exited terminal value: no_work
PASS haiku_exited cause: empty_diff
PASS haiku_exited close rc: 5
PASS haiku_exited exited promptly (1s): prompt
PASS opus_exited terminal value: no_work
PASS opus_exited cause: empty_diff
PASS opus_exited close rc: 5
PASS opus_exited exited promptly (1s): prompt
PASS sonnet_numeric_compat terminal value: no_work
PASS sonnet_numeric_compat cause: empty_diff
PASS sonnet_numeric_compat close rc: 5
PASS sonnet_numeric_compat exited promptly (1s): prompt
RESULT pass=16 fail=6
```

## test-empty-diff-waits-for-a-live-worker.sh GREEN evidence

timeout 150 bash plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh (after fix and expanded coverage; rc=0)

```text
PASS fable_late terminal value: landed
PASS fable_late late bytes reached review: reviewed
PASS fable_late close rc: 0
PASS fable_exited terminal value: no_work
PASS fable_exited cause: empty_diff
PASS fable_exited close rc: 5
PASS fable_exited exited promptly (3s): prompt
PASS fable_heartbeat_only terminal value: landed
PASS fable_heartbeat_only late bytes reached review: reviewed
PASS fable_heartbeat_only close rc: 0
PASS fable_stale_heartbeat terminal value: no_work
PASS fable_stale_heartbeat cause: empty_diff
PASS fable_stale_heartbeat close rc: 5
PASS fable_stale_heartbeat exited promptly (2s): prompt
PASS fable_finalizer terminal value: landed
PASS fable_finalizer late bytes reached review: reviewed
PASS fable_finalizer close rc: 0
PASS sonnet_raw_handle terminal value: landed
PASS sonnet_raw_handle late bytes reached review: reviewed
PASS sonnet_raw_handle close rc: 0
PASS haiku_exited terminal value: no_work
PASS haiku_exited cause: empty_diff
PASS haiku_exited close rc: 5
PASS haiku_exited exited promptly (1s): prompt
PASS opus_exited terminal value: no_work
PASS opus_exited cause: empty_diff
PASS opus_exited close rc: 5
PASS opus_exited exited promptly (1s): prompt
PASS sonnet_numeric_compat terminal value: no_work
PASS sonnet_numeric_compat cause: empty_diff
PASS sonnet_numeric_compat close rc: 5
PASS sonnet_numeric_compat exited promptly (1s): prompt
RESULT pass=32 fail=0
```

## leadv2-mutation-control.sh evidence

Both mutations insert a return INSIDE pc_worker_alive, immediately after its opening line. return 1 recreates the skipped wait; return 0 breaks the dead-worker guard. Each tool run first requires a green baseline. Final lane-bound artifacts are refreshed after this report is committed.

```text
CONTROL forced_pc_worker_alive_rc=1
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=0
MUTATION-CONTROL ok suite=plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh red_line=FAIL fable_late terminal value: got=no_work expected=landed diff_hash=a03fa1431af6a5ced8a960dd6abc1c7c5e3d2e796eab382d7e390a35c7683bc2 lane_diff_hash=dbcb23a8dbb1d050933703026099b3fe6836050ef85a5a19abd6d3ff95444cd1
control_tool_rc=0
CONTROL forced_pc_worker_alive_rc=0
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=0
MUTATION-CONTROL ok suite=plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh red_line=FAIL fable_exited terminal value: got=dead expected=no_work diff_hash=3e4b4a2bcacde24278249fde2393d167e9a0f19cdd2b1e2b952711e0c7a26c02 lane_diff_hash=b8cdc1aca3615dc56e9b67c255a8f5ec2fa12c35e420f788f0d796f9c7a2696c
control_tool_rc=0
```

## test-e2e-foreign-failure.sh merge-base comparison evidence

git archive fe491bffb6df9f3a4ac17e14ac6a2f7ea43c2982 plugins/leadv2 | tar -xf - -C /tmp/b4-baseline; PATH=/tmp/b4-tools:$PATH TMPDIR=/tmp LEADV2_TEST_CONTEXT=1 timeout -k 10 150 bash /tmp/b4-baseline/plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh; rc=1

```text
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] FAIL: R1 pre-fix-equivalent: expected exit 8 + e2e_regression, got rc=5 md=<>
[TEST] FAIL: R1 post-fix: expected non-8 rc + fail_foreign + foreign_files naming B.txt, got rc=5 md=<> flag=<>
[TEST] FAIL: R2: own regression must kill under BOTH settings (this is a permissiveness guard, not new-red evidence) -- pre-fix-dead=0 post-fix rc=5 md=<>
[TEST] FAIL: R3: mixed own+foreign must still kill (own wins, no laundering) -- pre-fix-dead=0 post-fix rc=5 md=<>
[TEST] FAIL: R4: expected dead+e2e_regression+whole_tree_fallback marker, pre-fix-dead=0 post-fix rc=5 md=<>
[TEST] FAIL: R5: expected pass with scope: lane_writes, got rc=5 flag=<>
[TEST] FAIL: loudness (1/4): missing/mismatched e2e_gate decision line -- append dispatch-r6sig001 decision product_close task=r6sig001 worker_liveness=unknown author=codex handle=- action=proceed_legacy
append dispatch-r6sig001 decision review_gate task=r6sig001 status=blocked reason=no_work terminal=no_work cause=empty_diff
[TEST] FAIL: loudness (2/4): missing per-suite foreign_failure line -- append dispatch-r6sig001 decision product_close task=r6sig001 worker_liveness=unknown author=codex handle=- action=proceed_legacy
append dispatch-r6sig001 decision review_gate task=r6sig001 status=blocked reason=no_work terminal=no_work cause=empty_diff
[TEST] FAIL: loudness (3/4): e2e-gate.md missing status: fail_foreign -- 
[TEST] FAIL: loudness (4/4): sentinel missing for a foreign_failure

[TEST] 1 passed, 10 failed, 0 not run
FAIL: R1 pre-fix-equivalent: expected exit 8 + e2e_regression, got rc=5 md=<>
FAIL: R1 post-fix: expected non-8 rc + fail_foreign + foreign_files naming B.txt, got rc=5 md=<> flag=<>
FAIL: R2: own regression must kill under BOTH settings (this is a permissiveness guard, not new-red evidence) -- pre-fix-dead=0 post-fix rc=5 md=<>
FAIL: R3: mixed own+foreign must still kill (own wins, no laundering) -- pre-fix-dead=0 post-fix rc=5 md=<>
FAIL: R4: expected dead+e2e_regression+whole_tree_fallback marker, pre-fix-dead=0 post-fix rc=5 md=<>
FAIL: R5: expected pass with scope: lane_writes, got rc=5 flag=<>
FAIL: loudness (1/4): missing/mismatched e2e_gate decision line -- append dispatch-r6sig001 decision product_close task=r6sig001 worker_liveness=unknown author=codex handle=- action=proceed_legacy
append dispatch-r6sig001 decision review_gate task=r6sig001 status=blocked reason=no_work terminal=no_work cause=empty_diff
FAIL: loudness (2/4): missing per-suite foreign_failure line -- append dispatch-r6sig001 decision product_close task=r6sig001 worker_liveness=unknown author=codex handle=- action=proceed_legacy
append dispatch-r6sig001 decision review_gate task=r6sig001 status=blocked reason=no_work terminal=no_work cause=empty_diff
FAIL: loudness (3/4): e2e-gate.md missing status: fail_foreign -- 
FAIL: loudness (4/4): sentinel missing for a foreign_failure
baseline_rc=1
```

## tests/run-all.sh selection and changed-scope evidence

Both selection and execution use the checkpoint pinned to the merge base
`fe491bffb6df9f3a4ac17e14ac6a2f7ea43c2982`, with HEAD initially
`2b49cc48438733eb62f79883c6de79e6f5fae154`. This measures the full lane range,
not a remembered last-checked commit or HEAD~1 fallback. A subsequent commit
only reordered the guard case first; production behavior and test assertions
are identical. The checkpoint did not exist before the run and is removed by
the wrapper's EXIT trap. Selection includes the explicit trigger mapping as
well as the test's self-selection convention.

Execution wrapper: `PATH=/tmp/b4-tools:$PATH TMPDIR=/tmp timeout -k 10 900 bash
tests/run-all.sh --scope changed`. No suite filter overrides the selected set.
The required changed-scope validation is not green. The following core output
already contains failures. The same foreign-failure assertions fail on the
merge-base archive above; this does not attribute every other runner failure.
The completed runner transcript, exit status, and core shard output are part
of this report's [changed-scope appendix](mutation-control/changed-scope.md).
Keeping that raw appendix and refreshed control receipts under mutation-control/
lets the evidence bind to a stable committed code/test/report diff.

```text
merge_base=fe491bffb6df9f3a4ac17e14ac6a2f7ea43c2982
head=2b49cc48438733eb62f79883c6de79e6f5fae154
measured_range=fe491bffb6df9f3a4ac17e14ac6a2f7ea43c2982...HEAD
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/tests/test-status-surface-bash32.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/tests/test-status-surface-single-lead.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/tests/test-status-surface-fast-names.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-arm-advance-real.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-asked-into-void.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-close-gate-nowork-abandoned.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-dispatch-product-close-exit-trap.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-dwr-resume.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-empty-writes-autocommit-loud-skip.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-leadv2-merge-safety-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-no-work-terminal.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-parked-worker-resume.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-reliability-02.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-review-arms.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-produced-nothing-cause.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-question-delivery-ownership-01.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-report-only-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-arm-no-verdict.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-body-persist.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-gate-scope-evidence.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-pool-empty-rootcause.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-pool-never-empty.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-silence-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-single-owner-census.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-verdict-recovery.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-silent-arm-index-and-cross-repo.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-stop-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worker-ended-on-wait.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-workflow-bypass-guard-lane.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/tests/test-review-arm-pool.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh
run-all: 53 selected, scope=changed, select_only=1
```

Raw core failure excerpt (the complete transcript is in the appendix):

```text
[CORE-OFFLINE] FAILED: product-close scopes a single-repo lane worktree
[CORE-OFFLINE] FAILED: plugin reliability (process liveness + role fallback + prepass/reorder signals)
[TEST] FAIL: R1 pre-fix-equivalent: expected exit 8 + e2e_regression, got rc=5 md=<>
[TEST] FAIL: R1 post-fix: expected non-8 rc + fail_foreign + foreign_files naming B.txt, got rc=5 md=<> flag=<>
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh (scope-selected ad-hoc)
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-review-single-owner-census.sh (scope-selected ad-hoc)
[CORE-OFFLINE] FAILED: plugins/leadv2/tests/test-review-arm-pool.sh (scope-selected ad-hoc)
```

## Closure evidence

Implementation and the dedicated regression suite are committed. Both liveness
mutations were killed; their tool-created receipts are in `mutation-control/`.
Refreshed receipts and the [final control output](mutation-control/final-controls.md)
bind to the final committed code/test/report diff. The report's first control
transcript records the earlier test-order checkpoint, so use the refreshed
receipts for final hash matching.

The new suite is registered by `# run-all-triggers: leadv2-dispatch-product-close`
and selected from the pinned merge-base range. Shell syntax checks passed;
Python compilation is inapplicable. `git diff --check` passed. The classification
branches named in the brief are unchanged. Scope review uses `git diff main...HEAD`.

The required broad validation is not green, so this lane is not presented as
review-ready or delivered to main. The lead retains merge ownership. No merge,
push, reset, stash, clean, or worktree-prune operation was performed.

BLOCKED: changed-scope validation has failures outside the B4 regression; see the completed runner appendix and merge-base comparison.
