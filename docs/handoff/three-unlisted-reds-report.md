# Three unlisted reds: scope-blocked investigation

Date: 2026-09-08. Dispatch: dispatch-2dfefcdd. Lane: a49cbf1665d4.
Baseline commit: d694075d01dda39d5862c49ce67b375aa233937d.

## Outcome and write-set stop

BLOCKED: the sentinel production repair requires `plugins/leadv2/scripts/claude-subsession.sh`, which is outside LANE_WRITES. The brief explicitly says to stop and report rather than widen the write set. This lane therefore commits evidence only. No suite has been repaired, skipped, deleted, or allowlisted. No restored-green or accepted mutation-control result is claimed.

The lane has no `.claude/scripts/` directory. Its tracked equivalents are `plugins/leadv2/scripts/tests/test-claude-subsession-sentinel.sh` and `plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh`, neither of which is in the literal write set. The permitted `plugins/leadv2/scripts/lib/leadv2-lane-liveness.sh` also does not exist; the actual reader is `plugins/leadv2/scripts/leadv2-lane-liveness.sh`.

A read-only parity check further found that main's `.claude/scripts/` is an ordinary directory with different bytes from the tracked plugin tree, not a symlink to that tree. Consequently the measured paths and the tracked lane counterparts cannot be silently substituted. The exact measured scripts were copied into a disposable directory and rerun as well. No main-checkout edit, merge, or push was made. The report alone is the intended lane diff.

## Execution and evidence provenance

Initial `pwd`, `git status --short`, and `git diff --stat` confirmed the pinned lane and a clean baseline. Shell-file reads used the explicit shell-script discovery exception in the supplied AGENTS instructions.

Tracked baseline snapshot:

```sh
TASK_EVIDENCE=$(mktemp -d /tmp/three-unlisted-reds.XXXXXX)
mkdir "$TASK_EVIDENCE/repo"
git archive HEAD | tar -xf - -C "$TASK_EVIDENCE/repo"
# Actual TASK_EVIDENCE: /tmp/three-unlisted-reds.GjAMnE
```

Each of these commands ran in that snapshot, with stdout and stderr captured separately and an outer 240-second bound:

```sh
timeout --kill-after=10s 240s bash plugins/leadv2/scripts/tests/test-claude-subsession-sentinel.sh
timeout --kill-after=10s 240s bash plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh
timeout --kill-after=10s 240s bash plugins/leadv2/scripts/tests/test-lane-finished-state.sh
```

All three returned 1, not a timeout. The finished-state suite rewrites liveness/snapshot scripts during its own existing Test 5 controls; the disposable snapshot contained those writes. The other two suites copy scripts into their own separate fixtures before probing them.

Exact measured `.claude/scripts` copy:

```sh
mkdir -p /tmp/three-unlisted-reds.GjAMnE/measured-plugin
cp -R /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/scripts /tmp/three-unlisted-reds.GjAMnE/measured-plugin/scripts
timeout --kill-after=10s 120s bash /tmp/three-unlisted-reds.GjAMnE/measured-plugin/scripts/tests/test-claude-subsession-sentinel.sh
timeout --kill-after=10s 120s bash /tmp/three-unlisted-reds.GjAMnE/measured-plugin/scripts/tests/test-lane-liveness-authoritative.sh
```

Both returned 1. These are local fake-worker/fixture runs, not provider/API verification; quoted profile/quota lines are raw harness output, not independently verified external-system claims.

## test-claude-subsession-sentinel.sh

**Classification: live defect.** Evidence: both source trees stamp `.finalized` while the worker PID is alive and write `exit_code=127` instead of the fake child's eventual 4. The exact measured-tree run reports `PASS=11 FAIL=5`; the tracked-tree run reports `PASS=10 FAIL=6` (the tracked reader's verdict cache also masks the changed C5 fixture).

The launcher starts the worker in one background child, then calls `wait "$PID"` inside a different background subshell. That subshell cannot reap its sibling; it receives 127 and immediately starts post-run bookkeeping and finalization. This can happen as soon as the sibling waiter runs, before the worker's four-second sleep completes. A separate bounded shell reproduction below confirms `sibling_wait_rc=127 worker_kill0_rc=0`; the real parent can still reap the worker successfully.

The live source copies both contain this pattern (tracked launcher lines 1340 and 1388-1414; measured copy lines 1263-1283 contain the waiter/finalizer). It is not a test-only mutation. The finalizer can also call the commit epilogue before the worker finishes in the tracked implementation. Its effect on real work was not exercised.

**False-dead conclusion:** premature finalization is reproduced, but `dead:sentinel_finalized` for a still-running recorded Claude PID is NOT reproduced. The measured E3 result is `alive`; C1 also passes with an aged sentinel and a live PID. The reader's `sentinel_check()` requires an aged sentinel (default 60 seconds) AND `os.kill(cpid, 0)` raising `ProcessLookupError`; a live recorded Claude PID vetoes the sentinel verdict. Thus the finding does not establish that the reported recent-commit STALL incident has this cause. Descendant-only work after the recorded PID exits and other consumers of `.finalized` were not exhaustively audited because this lane reached the write-set stop.

E2 additionally contains an obsolete expectation: it checks `outcome=4`. Commit `f672f0a9a815a8b9218cb450c7837fcbab36ead4` changed the contract to `outcome=died-clean` plus `exit_code=4`. That stale assertion does not excuse the observed 127 or early stamp. E3 assumes seeing `.finalized` means the child was reaped; the production bug invalidates that synchronization.

**Fix:** not applied. Repair child ownership/waiting in the launcher and synchronize the suite on actual child/finalizer completion; assert the current outcome schema. The required launcher and tracked test paths are outside the literal write set.

**Control output:** no repaired baseline exists, so the required reintroduced-defect mutation and restored green were not run. A future control must reintroduce sibling waiting inside the production function body and fail on sentinel existence while the worker is alive and on the captured exit-code value. Do not count the existing C-case passes as repair proof.

### sibling-wait.log

Command (8-second bound):

```sh
timeout --kill-after=2s 8s bash -c '
reproduce_sibling_wait() {
  sleep 2 &
  worker=$!
  ( wait "$worker" 2>/dev/null; rc=$?; kill -0 "$worker" 2>/dev/null; alive_rc=$?; printf "sibling_wait_rc=%s worker_kill0_rc=%s\n" "$rc" "$alive_rc" ) &
  waiter=$!
  wait "$waiter"
  wait "$worker"
  printf "parent_reap_rc=%s\n" "$?"
}
reproduce_sibling_wait
'
```

```text
sibling_wait_rc=127 worker_kill0_rc=0
parent_reap_rc=0
```

### test-claude-subsession-sentinel.sh — measured-path red output

```text
=== E1/E2: real bg spawn, worker alive at t+2s ===
[claude-subsession] WARN: subagent-protocol SKILL.md not resolvable (tried /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.zbqiFf/repo/.claude/skills/leadv2-subagent-protocol/SKILL.md, /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.zbqiFf/plugin/skills/leadv2-subagent-protocol/SKILL.md) — prefix will omit the protocol reference
[claude-subsession] stable prefix file reused for developer (server cache status comes from usage telemetry)
[claude-subsession] prefix path: /tmp/leadv2-cache/prefix-developer.0951e375891852eafc82e091a9d87437.md
[claude-profile] selected=work score=30 source=live candidates=2 cred_kind=keychain identity=team/kostiantyn.vlasenko@mythical.games
[claude-subsession] cost recorded: developer/sonnet in=0 out=0 usd=0.000000 cache_hit=null
[TEST] PASS: run dir created
[TEST] PASS: meta.yaml carries task_id
[TEST] PASS: pid file matches printed PID (name=pid, not pgid)
[TEST] FAIL: .finalized stamped while worker alive (false-dead)
[TEST] PASS: worker pid alive at t+2s
[TEST] PASS: .finalized stamped after child reaped
[TEST] FAIL: E2: .outcome carries real child exit code (4)
  got: outcome=died-clean
exit_code=127
at=2026-09-08T11:03:09Z
=== E3: liveness → dead:sentinel_finalized on claude arm ===

[TEST] FAIL: E3: verdict is dead:sentinel_finalized
  got: {"lane":"SENT-CL","verdict":"alive","age_s":581,"source":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.zbqiFf/repo/docs/handoff/SENT-CL/developer.stream.jsonl","log_path":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.zbqiFf/repo/docs/handoff/SENT-CL/developer.stream.jsonl","raw_log_path":"docs/handoff/SENT-CL/developer.stream.jsonl","pid":null,"pid_alive":false,"reason":"log_fresh","attempt":null,"child_of":null,"pid_source":"legacy","pid_identity":"unverified"}
[TEST] FAIL: E3: sentinel_arm is claude
  got: {"lane":"SENT-CL","verdict":"alive","age_s":581,"source":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.zbqiFf/repo/docs/handoff/SENT-CL/developer.stream.jsonl","log_path":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.zbqiFf/repo/docs/handoff/SENT-CL/developer.stream.jsonl","raw_log_path":"docs/handoff/SENT-CL/developer.stream.jsonl","pid":null,"pid_alive":false,"reason":"log_fresh","attempt":null,"child_of":null,"pid_source":"legacy","pid_identity":"unverified"}
[TEST] FAIL: E3: lane_outcome surfaced
  got: {"lane":"SENT-CL","verdict":"alive","age_s":581,"source":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.zbqiFf/repo/docs/handoff/SENT-CL/developer.stream.jsonl","log_path":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.zbqiFf/repo/docs/handoff/SENT-CL/developer.stream.jsonl","raw_log_path":"docs/handoff/SENT-CL/developer.stream.jsonl","pid":null,"pid_alive":false,"reason":"log_fresh","attempt":null,"child_of":null,"pid_source":"legacy","pid_identity":"unverified"}
=== C1: live pid + aged sentinel → NOT sentinel dead ===
[TEST] PASS: C1 live pid → no sentinel dead
=== C2: missing pid file + aged sentinel → NOT sentinel dead ===
[TEST] PASS: C2 missing pid file → no sentinel dead
=== C3: LEADV2_LANE_SENTINEL_CLAUDE=0 rollback → NOT sentinel dead ===
[TEST] PASS: C3 claude kill switch off → no sentinel dead
=== C4: .finalized inside settle window → NOT sentinel dead ===
[TEST] PASS: C4 fresh .finalized → no sentinel dead
=== C5/H3: newest pointer mtime wins across arms (glm newer → arm=glm) ===
[TEST] PASS: C5: newest pointer wins → arm=glm (not first-match claude)
=== C6/H3-tie: same-second pointers, claude finalized vs glm fresh → must NOT resolve the finalized arm ===
[TEST] PASS: C6 same-second tie → non-finalized arm wins
[TEST] Results: PASS=11 FAIL=5
```

## test-lane-liveness-authoritative.sh

**Classification of the brief's measured `.claude/scripts` suite: live defect.** Evidence: D6 emits `lanes 3/3 | 1·?·3s +`, losing the numeric part of `+2`. The suite correctly rejects that value. The original no-drop hypothesis is not the sentinel bug: this is statusline rendering/truncation, not worker finalization.

The tracked plugin counterpart has a different failure: with the standard runner's `LEADV2_TEST_CONTEXT=1` it renders the full `lanes 3/3 1·?·2s +2 | Test in ...` segment. Its D6 regex captures everything through end-of-line, then requires the last token to be `+2`, so it rejects the following model/quota segment. This counterpart is test rot under commit `74a04a114d113b3765612ad122a8cdd1ccf9dfba`: `git blame -L 1117,1125` attributes the switch to lanes-first, base/quota-after to that commit. Treating this counterpart as the same measured file would incorrectly classify the original deployed-copy failure as only rot.

A direct tracked-suite run without test context fails earlier: the newly added ten-second liveness cache replays the earlier empty `--all` fixture after the log-only lane is created. With test context (which `tests/run-all.sh` exports), that assertion passes and D6 fails as above. Two bounded tracked runs, with inherited LEADV2_LANE_CAP=4 and with 3, both reached the same D6 parser failure; a cap override did not fix it.

**Fix:** not applied. Establish which script tree is intended to execute, repair/synchronize the deployed renderer if needed, and repair the tracked test to parse only the lane segment while retaining exact total/drop-counter checks. The renderer `leadv2-lane-status-line-tail.sh` and tracked test path are outside LANE_WRITES; writing ignored `.claude/scripts` paths into this lane would not repair the tracked plugin.

**Control output:** no green repair or mutation-control success claimed. A future function-body mutation must break `try_drop_to_k`'s numeric hidden-lane count and make a numeric value assertion fail, then restore green. It must not merely change a diagnostic log string.

### test-lane-liveness-authoritative.sh — measured-path red output

```text
[lane-liveness] WARN: task_id=dispatch-test0010 has no parseable started_at (None) -- age_s is indeterminate, not 0
[lane-liveness] WARN: task_id=dispatch-test0010 has no parseable started_at (None) -- age_s is indeterminate, not 0
[TEST] PASS: running job is not classified dead without codex-guard
[TEST] PASS: cancelled job is reported as cancelled, not dead
[TEST] PASS: failed job surfaces errorMessage when no older reason field exists
[TEST] PASS: supervise enumerates Codex app-server job
[TEST] PASS: supervise preserves authoritative Phase
[TEST] PASS: fresh session.log is alive without active.yaml row
[TEST] PASS: session.log path is recorded as liveness source
[TEST] PASS: supervise emits log-only lane while registry is empty
[TEST] PASS: silence threshold controls log-only lane verdict
[TEST] PASS: pid-alive silent lane remains silent
[TEST] PASS: pid-alive silent lane is absent from stuck
[TEST] PASS: self-reported provider running + stale log -> silent, not alive
[TEST] PASS: LEADV2_LANE_LIVENESS_V2=0 reproduces exact prior (self-report trusted) behavior
[TEST] PASS: fresh log + no PID + provider cancelled -> alive, terminal status never overrides a fresh log
[TEST] PASS: fresh-cancelled row carries a real age_s
[TEST] PASS: funnel lane with recorded log_path is alive, not dead:no_handoff_dir
[TEST] PASS: funnel lane liveness source is the recorded log_path, not a directory scan
[TEST] PASS: no docs/handoff/FUNNEL-TASK/ directory created for a funnel-dispatched lane
[lane-liveness] WARN: task_id=FUNNEL-GONE has no parseable started_at (None) -- age_s is indeterminate, not 0
[lane-liveness] WARN: task_id=FUNNEL-GONE has no parseable started_at (None) -- age_s is indeterminate, not 0
[TEST] PASS: funnel lane with a missing log_path target falls through to the directory scan unchanged
[TEST] PASS: C2: live PID with no artifact floors to silent, not dead
[TEST] PASS: C2 negative: no PID + no artifact stays dead:no_handoff_dir
[TEST] PASS: C1 shape 2: pre-first-write funnel lane resolves starting: via registration grace (dirname scan removed by S1/D3)
[TEST] PASS: C1 shape 4: fanout-lane- sibling dir alone is not lane evidence under the S1 closed ladder
[TEST] PASS: C1 shape 5: docs/leadv2/tasks/<tid>/pulse.md alone is not lane evidence under the S1 closed ladder
[lane-liveness] WARN: task_id=SHAPE6-TASK has no parseable started_at (None) -- age_s is indeterminate, not 0
[lane-liveness] WARN: task_id=SHAPE6-TASK has no parseable started_at (None) -- age_s is indeterminate, not 0
[TEST] PASS: C1 shape 6: sessions.map binding alone is not lane evidence under the S1 closed ladder
[TEST] PASS: D3: 1000s-old stream is silent under --lane
[TEST] PASS: D3 -- --all agrees with --lane for the same 1000s-old lane (no flicker)
[TEST] PASS: D1: pid-less lane past abandon_max ages out to dead, never stays silent forever
[TEST] PASS: D1 -- count_live excludes the abandoned pid-less lane
[TEST] PASS: D1 boundary: ~3570s (< abandon_max 3600) is still silent
[TEST] PASS: D1 boundary: ~3630s (> abandon_max 3600) is dead
[TEST] PASS: D2: fresh started_at + pid null + no artifact resolves starting, not dead
[TEST] PASS: D2 negative: old started_at + no artifact still resolves dead, never starting
[TEST] PASS: SELF-DEADLOCK: fresh prepass child stream is NOT a live signal by default (parent resolves dead)
[TEST] PASS: SELF-DEADLOCK rollback: LEADV2_LANE_PREPASS_LIVE=1 restores the composed-prepass signal
Traceback (most recent call last):
  File "<string>", line 10, in <module>
    assert tokens and tokens[-1] == "+2", ("expected 1 lane token + +2 drop counter, got", tokens, stripped)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AssertionError: ('expected 1 lane token + +2 drop counter, got', ['1·?·3s', '+'], 'Test in ~/.claude/plugins/data/codex-openai-codex/tmp/lane-liveness.CLvaAG/ladder-repo | cc* 20x 46%·7d/3d11h · cc 5x 71%·7d/7h58m · cx 88%·wk/6d18h · glm 20%·wk/10h55m | lanes 3/3 | 1·?·3s +')
[TEST] FAIL: D6 -- degradation ladder dropped a lane
[36mTest[0m in [32m~/.claude/plugins/data/codex-openai-codex/tmp/lane-liveness.CLvaAG/ladder-repo[0m | cc* 20x 46%·7d/3d11h · cc 5x 71%·7d/7h58m · cx 88%·wk/6d18h · [33mglm 20%·wk/10h55m[0m [34m| lanes 3/3 | 1·?·3s +[0m
[TEST-SAFETY] tripwire OK: /tmp/three-unlisted-reds.GjAMnE/measured-plugin/scripts/leadv2-lane-liveness.sh unchanged (md5 0ae43b866a25393a5716cdc15fad465e before and after)
```

### test-lane-liveness-authoritative.sh — tracked counterpart, runner test context

```sh
LEADV2_TEST_CONTEXT=1 LEADV2_LANES_ALL_REPOS=0 timeout --kill-after=10s 120s bash plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh
# rc=1
```

```text
[lane-liveness] WARN: task_id=dispatch-test0010 has no parseable started_at (None) -- age_s is indeterminate, not 0
[lane-liveness] WARN: task_id=dispatch-test0010 has no parseable started_at (None) -- age_s is indeterminate, not 0
[TEST] PASS: running job is not classified dead without codex-guard
[TEST] PASS: cancelled job is reported as cancelled, not dead
[TEST] PASS: failed job surfaces errorMessage when no older reason field exists
[TEST] PASS: supervise enumerates Codex app-server job
[TEST] PASS: supervise preserves authoritative Phase
[TEST] PASS: fresh session.log is alive without active.yaml row
[TEST] PASS: session.log path is recorded as liveness source
[TEST] PASS: supervise emits log-only lane while registry is empty
[TEST] PASS: silence threshold controls log-only lane verdict
[TEST] PASS: pid-alive silent lane remains silent
[TEST] PASS: pid-alive silent lane is absent from stuck
[TEST] PASS: self-reported provider running + stale log -> silent, not alive
[TEST] PASS: LEADV2_LANE_LIVENESS_V2=0 reproduces exact prior (self-report trusted) behavior
[TEST] PASS: fresh log + no PID + provider cancelled -> alive, terminal status never overrides a fresh log
[TEST] PASS: fresh-cancelled row carries a real age_s
[TEST] PASS: funnel lane with recorded log_path is alive, not dead:no_handoff_dir
[TEST] PASS: funnel lane liveness source is the recorded log_path, not a directory scan
[TEST] PASS: no docs/handoff/FUNNEL-TASK/ directory created for a funnel-dispatched lane
[lane-liveness] WARN: task_id=FUNNEL-GONE has no parseable started_at (None) -- age_s is indeterminate, not 0
[lane-liveness] WARN: task_id=FUNNEL-GONE has no parseable started_at (None) -- age_s is indeterminate, not 0
[TEST] PASS: funnel lane with a missing log_path target falls through to the directory scan unchanged
[TEST] PASS: C2: live PID with no artifact floors to silent, not dead
[TEST] PASS: C2 negative: no PID + no artifact stays dead:no_handoff_dir
[TEST] PASS: C1 shape 2: pre-first-write funnel lane resolves starting: via registration grace (dirname scan removed by S1/D3)
[TEST] PASS: C1 shape 4: fanout-lane- sibling dir alone is not lane evidence under the S1 closed ladder
[TEST] PASS: C1 shape 5: docs/leadv2/tasks/<tid>/pulse.md alone is not lane evidence under the S1 closed ladder
[lane-liveness] WARN: task_id=SHAPE6-TASK has no parseable started_at (None) -- age_s is indeterminate, not 0
[lane-liveness] WARN: task_id=SHAPE6-TASK has no parseable started_at (None) -- age_s is indeterminate, not 0
[TEST] PASS: C1 shape 6: sessions.map binding alone is not lane evidence under the S1 closed ladder
[TEST] PASS: D3: 1000s-old stream is silent under --lane
[TEST] PASS: D3 -- --all agrees with --lane for the same 1000s-old lane (no flicker)
[TEST] PASS: D1: pid-less lane past abandon_max ages out to dead, never stays silent forever
[TEST] PASS: D1 -- count_live excludes the abandoned pid-less lane
[TEST] PASS: D1 boundary: ~3570s (< abandon_max 3600) is still silent
[TEST] PASS: D1 boundary: ~3630s (> abandon_max 3600) is dead
[TEST] PASS: D2: fresh started_at + pid null + no artifact resolves starting, not dead
[TEST] PASS: D2 negative: old started_at + no artifact still resolves dead, never starting
[TEST] PASS: SELF-DEADLOCK: fresh prepass child stream is NOT a live signal by default (parent resolves dead)
[TEST] PASS: SELF-DEADLOCK rollback: LEADV2_LANE_PREPASS_LIVE=1 restores the composed-prepass signal
Traceback (most recent call last):
  File "<string>", line 10, in <module>
    assert tokens and tokens[-1] == "+2", ("expected 1 lane token + +2 drop counter, got", tokens, stripped)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AssertionError: ('expected 1 lane token + +2 drop counter, got', ['1·?·2s', '+2', '|', 'Test', 'in', '~/.claude/plugins/data/codex-openai-codex/tmp/lane-liveness.a7XhWI/ladder-repo', '|', 'cc*', '20x', '46%·7d/3d11h', '·', 'cc', '5x', '71%·7d/7h58m', '·', 'cx', '88%·wk/6d18h', '·', 'glm', '20%·wk/10h55m'], 'lanes 3/3 1·?·2s +2 | Test in ~/.claude/plugins/data/codex-openai-codex/tmp/lane-liveness.a7XhWI/ladder-repo | cc* 20x 46%·7d/3d11h · cc 5x 71%·7d/7h58m · cx 88%·wk/6d18h · glm 20%·wk/10h55m')
[TEST] FAIL: D6 -- degradation ladder dropped a lane
[34mlanes 3/3 1·?·2s +2[0m | [36mTest[0m in [32m~/.claude/plugins/data/codex-openai-codex/tmp/lane-liveness.a7XhWI/ladder-repo[0m | cc* 20x 46%·7d/3d11h · cc 5x 71%·7d/7h58m · cx 88%·wk/6d18h · [33mglm 20%·wk/10h55m[0m
[TEST-SAFETY] tripwire OK: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/plugins/leadv2/scripts/leadv2-lane-liveness.sh unchanged (md5 acb0ac43e7e6b38bcbca8671cdb0e9c8 before and after)
```

## test-lane-finished-state.sh

**Classification: test rot.** Evidence: nine failures return `unknown:contradictory_rows`, including Test 5a's prerequisite. Fixtures explicitly write `worktree: <fixture repo>` and pass that same fixture repo as `--project-root`. Commit `4742d502296fafdce124a09abffec3f7bba59dce` added the E0 guard, whose explicit second trigger is `worktree == PROJECT_ROOT`; it precedes all finished/dead rungs. Source evidence: `resolve()` lines 965-999 checks the real paths and returns `reason=worktree_is_project_root`. This is unrelated to the sentinel writer defect.

**Fix:** not applied after the scope stop. The allowed suite could be repaired in a follow-up by using a distinct scratch lane checkout for worktree evidence, directing commits and process cwd there, and isolating every existing mutation in a scratch script tree. Do not disable the E0 guard or weaken finished/dead assertions.

**Control output:** the suite's existing Test 5a never reached its mutation because the baseline was already wrong. Test 5b printed a pass, but that is not a `leadv2-mutation-control.sh` artifact and is not offered as this lane's negative-control proof. A follow-up must run the required tool after a green suite baseline, mutate the production finished-check inside `resolve()`, assert a changed verdict value, and restore green. No suite is claimed fixed here.

### test-lane-finished-state.sh — red output

```text
[TEST] Test 1: live pid + fresh stream -> alive; not an escalation candidate
[TEST] FAIL: Test 1: verdict=unknown:contradictory_rows escalated=False still_present=True
[TEST] Test 2: dead pid + recent commit -> finished, no escalation, placement not refused
[TEST] FAIL: Test 2: verdict=unknown:contradictory_rows escalated=False still_present=True
[TEST] Test 3: dead pid, unborn-HEAD worktree, no deliverable -> dead, escalation raised
[TEST] FAIL: Test 3: verdict=unknown:contradictory_rows removed=True (real death detection must not be disabled by this fix)
[TEST] Test 4: dead pid + recent commit + fresh stream mtime -> still finished, never alive
[TEST] FAIL: Test 4: verdict=unknown:contradictory_rows (must be finished:*, never alive) escalated=False still_present=True
[TEST] Test 6: single OLD commit (older than LEADV2_LANE_FINISHED_WINDOW_S) + no live pid -> dead:*, never finished:*
[TEST] FAIL: Test 6: verdict=unknown:contradictory_rows (must be dead:*, never finished:* or alive/starting)
[TEST] Test 7: registration older than LEADV2_LANE_STARTING_MAX_S (300s default), no pid, no stream -> dead:*, never starting:*
[TEST] FAIL: Test 7: verdict=unknown:contradictory_rows (must be dead:*, never starting:* -- the stuck-starting incident)
[TEST] Test 8: live pid whose cwd is the lane worktree + STALE (but < ABANDON_MAX) stream mtime -> must never read dead or finished
[TEST] FAIL: Test 8: verdict=unknown:contradictory_rows (expected silent:* -- a live worker's lane must never read dead or finished)
[TEST] Test 9: pid alive but recorded birth mismatches observed lstart (pid reuse / an orphan sharing the pid number) -> dead:*, never alive
[TEST] FAIL: Test 9: verdict=unknown:contradictory_rows (must be dead:* -- an alive-but-mismatched pid must never read alive)
[TEST] Test 5a: mutating leadv2-lane-liveness.sh's finished-check must turn verdict non-finished (RED), revert restores it (GREEN)
[TEST] FAIL: Test 5a: pre-mutation baseline must be finished:* (got unknown:contradictory_rows) -- fixture broken, mutation gate aborted
[TEST] Test 5b: mutating leadv2-lanes-snapshot.sh's finished-veto must let escalation fire again (RED), revert restores no-escalation (GREEN)
[TEST] PASS: Test 5b: mutation re-enabled escalation on a finished lane (row pruned, RED); revert restores no-escalation (row kept, GREEN)

[TEST] ===================================================================
[TEST] RESULTS: 1 passed, 9 failed
[TEST] FAIL: Test 1: verdict=unknown:contradictory_rows escalated=False still_present=True
[TEST] FAIL: Test 2: verdict=unknown:contradictory_rows escalated=False still_present=True
[TEST] FAIL: Test 3: verdict=unknown:contradictory_rows removed=True (real death detection must not be disabled by this fix)
[TEST] FAIL: Test 4: verdict=unknown:contradictory_rows (must be finished:*, never alive) escalated=False still_present=True
[TEST] FAIL: Test 6: verdict=unknown:contradictory_rows (must be dead:*, never finished:* or alive/starting)
[TEST] FAIL: Test 7: verdict=unknown:contradictory_rows (must be dead:*, never starting:* -- the stuck-starting incident)
[TEST] FAIL: Test 8: verdict=unknown:contradictory_rows (expected silent:* -- a live worker's lane must never read dead or finished)
[TEST] FAIL: Test 9: verdict=unknown:contradictory_rows (must be dead:* -- an alive-but-mismatched pid must never read alive)
[TEST] FAIL: Test 5a: pre-mutation baseline must be finished:* (got unknown:contradictory_rows) -- fixture broken, mutation gate aborted
```

## Path-parity probe

Read-only Python probe: for each path below, `Path.resolve()` and `hashlib.sha256(Path.read_bytes()).hexdigest()` were printed. The tracked main and lane bytes match for these files; the ordinary `.claude/scripts` copy differs.

```text
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/scripts/tests/test-claude-subsession-sentinel.sh
  realpath=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/scripts/tests/test-claude-subsession-sentinel.sh sha256=01273d3ccd9e9c09e15e2255c3345771a3990748a1c8a4c23241e6b61664335f
/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-claude-subsession-sentinel.sh
  realpath=/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-claude-subsession-sentinel.sh sha256=b12f97739888cc22e570149bf2ddc1771e60ba2d49ae69c7e5bc6fc0f083f4df
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/plugins/leadv2/scripts/tests/test-claude-subsession-sentinel.sh
  realpath=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/plugins/leadv2/scripts/tests/test-claude-subsession-sentinel.sh sha256=b12f97739888cc22e570149bf2ddc1771e60ba2d49ae69c7e5bc6fc0f083f4df
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/scripts/tests/test-lane-liveness-authoritative.sh
  realpath=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/scripts/tests/test-lane-liveness-authoritative.sh sha256=e0bb4cec6f711979109963e32f336958c3e69a99c4d68610bf260da1c6c66df7
/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh
  realpath=/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh sha256=0832a4807033a99b93fea1a56899ce884a73fe01ed21cbe1b47d58b3406b6adf
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh
  realpath=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh sha256=0832a4807033a99b93fea1a56899ce884a73fe01ed21cbe1b47d58b3406b6adf
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/scripts/claude-subsession.sh
  realpath=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/scripts/claude-subsession.sh sha256=0bed03c646de367862bdce069b3c52e69819b914f49c318f1612ab0a9c337712
/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/claude-subsession.sh
  realpath=/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/claude-subsession.sh sha256=97622fd16d2109b4fcab0c565a33c684c6caadd6c5230dae3da0042a9617bfc3
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/plugins/leadv2/scripts/claude-subsession.sh
  realpath=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/plugins/leadv2/scripts/claude-subsession.sh sha256=97622fd16d2109b4fcab0c565a33c684c6caadd6c5230dae3da0042a9617bfc3
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/scripts/leadv2-lane-liveness.sh
  realpath=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/scripts/leadv2-lane-liveness.sh sha256=b0cbecdc78803c4f649dd26f1add2e8e0052159eed00f323962662439ac74fb2
/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/leadv2-lane-liveness.sh
  realpath=/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/leadv2-lane-liveness.sh sha256=e14738fa696efdc3f6dfb0712b7aff3aa75180fc2e8d22d4d33c16a9d36a4a9e
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/plugins/leadv2/scripts/leadv2-lane-liveness.sh
  realpath=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/plugins/leadv2/scripts/leadv2-lane-liveness.sh sha256=e14738fa696efdc3f6dfb0712b7aff3aa75180fc2e8d22d4d33c16a9d36a4a9e
```

## Falsification and closure

No shell or Python source is changed by this report-only lane. The required changed-file syntax census, `git diff --check`, and changed-scope runner output are appended below after execution. Passing a docs-only selection does not establish that any of the three red suites is green.

### leadv2-mutation-control.sh

NOT RUN: no suite was repaired or turned green, and production repair is scope-blocked. There is no mutation-control artifact or restored-green claim. The mission's complete repair/negative-control acceptance criteria remain unmet.

### bash -n / python3 -m py_compile / git diff --check — raw changed-file census

```text
$ changed-file syntax census: git diff --name-only HEAD
docs/handoff/three-unlisted-reds-report.md
bash -n: NOT APPLICABLE (0 changed .sh files)
python3 -m py_compile: NOT APPLICABLE (0 changed .py files)
$ git diff --check HEAD


rc=0
```

### Tracked snapshot baseline supplements

These outputs distinguish the tracked counterpart from the exact measured-path copy. Both commands returned 1.

#### claude-subsession-sentinel.baseline.log

```text
=== E1/E2: real bg spawn, worker alive at t+2s ===
[claude-subsession] WARN: subagent-protocol SKILL.md not resolvable (tried /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.isbv5c/repo/.claude/skills/leadv2-subagent-protocol/SKILL.md, /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.isbv5c/plugin/skills/leadv2-subagent-protocol/SKILL.md) — prefix will omit the protocol reference
[claude-subsession] stable prefix materialised for developer → /tmp/leadv2-cache/prefix-developer.0951e375891852eafc82e091a9d87437.md
[claude-subsession] prefix path: /tmp/leadv2-cache/prefix-developer.0951e375891852eafc82e091a9d87437.md
[claude-profile] selected=work score=30 source=live candidates=2 cred_kind=keychain identity=team/kostiantyn.vlasenko@mythical.games
[claude-subsession] cost recorded: developer/sonnet in=0 out=0 usd=0.000000 cache_hit=null
[TEST] PASS: run dir created
[TEST] PASS: meta.yaml carries task_id
[TEST] PASS: pid file matches printed PID (name=pid, not pgid)
[TEST] FAIL: .finalized stamped while worker alive (false-dead)
[TEST] PASS: worker pid alive at t+2s
[TEST] PASS: .finalized stamped after child reaped
[TEST] FAIL: E2: .outcome carries real child exit code (4)
  got: outcome=died-clean
exit_code=127
at=2026-09-08T11:00:15Z
=== E3: liveness → dead:sentinel_finalized on claude arm ===

[TEST] FAIL: E3: verdict is dead:sentinel_finalized
  got: {"lane":"SENT-CL","verdict":"alive","age_s":582,"source":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.isbv5c/repo/docs/handoff/SENT-CL/developer.stream.jsonl","log_path":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.isbv5c/repo/docs/handoff/SENT-CL/developer.stream.jsonl","raw_log_path":"docs/handoff/SENT-CL/developer.stream.jsonl","pid":null,"pid_alive":false,"reason":"log_fresh","attempt":null,"child_of":null,"pid_source":"legacy","pid_identity":"unverified","stream_end":"empty"}
[TEST] FAIL: E3: sentinel_arm is claude
  got: {"lane":"SENT-CL","verdict":"alive","age_s":582,"source":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.isbv5c/repo/docs/handoff/SENT-CL/developer.stream.jsonl","log_path":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.isbv5c/repo/docs/handoff/SENT-CL/developer.stream.jsonl","raw_log_path":"docs/handoff/SENT-CL/developer.stream.jsonl","pid":null,"pid_alive":false,"reason":"log_fresh","attempt":null,"child_of":null,"pid_source":"legacy","pid_identity":"unverified","stream_end":"empty"}
[TEST] FAIL: E3: lane_outcome surfaced
  got: {"lane":"SENT-CL","verdict":"alive","age_s":582,"source":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.isbv5c/repo/docs/handoff/SENT-CL/developer.stream.jsonl","log_path":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.isbv5c/repo/docs/handoff/SENT-CL/developer.stream.jsonl","raw_log_path":"docs/handoff/SENT-CL/developer.stream.jsonl","pid":null,"pid_alive":false,"reason":"log_fresh","attempt":null,"child_of":null,"pid_source":"legacy","pid_identity":"unverified","stream_end":"empty"}
=== C1: live pid + aged sentinel → NOT sentinel dead ===
[TEST] PASS: C1 live pid → no sentinel dead
=== C2: missing pid file + aged sentinel → NOT sentinel dead ===
[TEST] PASS: C2 missing pid file → no sentinel dead
=== C3: LEADV2_LANE_SENTINEL_CLAUDE=0 rollback → NOT sentinel dead ===
[TEST] PASS: C3 claude kill switch off → no sentinel dead
=== C4: .finalized inside settle window → NOT sentinel dead ===
[TEST] PASS: C4 fresh .finalized → no sentinel dead
=== C5/H3: newest pointer mtime wins across arms (glm newer → arm=glm) ===
[TEST] FAIL: C5: newest pointer wins → arm=glm (not first-match claude)
  got: {"lane":"SENT-CL","verdict":"alive","age_s":582,"source":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.isbv5c/repo/docs/handoff/SENT-CL/developer.stream.jsonl","log_path":"/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/claude-subsession-sentinel.isbv5c/repo/docs/handoff/SENT-CL/developer.stream.jsonl","raw_log_path":"docs/handoff/SENT-CL/developer.stream.jsonl","pid":null,"pid_alive":false,"reason":"log_fresh","attempt":null,"child_of":null,"pid_source":"legacy","pid_identity":"unverified","stream_end":"empty"}
=== C6/H3-tie: same-second pointers, claude finalized vs glm fresh → must NOT resolve the finalized arm ===
[TEST] PASS: C6 same-second tie → non-finalized arm wins
[TEST] Results: PASS=10 FAIL=6
```

#### lane-liveness-authoritative.baseline.log

```text
[lane-liveness] share slot had a provably dead in-flight holder (pid=?) — reclaiming
[lane-liveness] WARN: task_id=dispatch-test0010 has no parseable started_at (None) -- age_s is indeterminate, not 0
[lane-liveness] WARN: task_id=dispatch-test0010 has no parseable started_at (None) -- age_s is indeterminate, not 0
[TEST] PASS: running job is not classified dead without codex-guard
[lane-liveness] share slot had a provably dead in-flight holder (pid=?) — reclaiming
[TEST] PASS: cancelled job is reported as cancelled, not dead
[lane-liveness] share slot had a provably dead in-flight holder (pid=?) — reclaiming
[TEST] PASS: failed job surfaces errorMessage when no older reason field exists
[TEST] PASS: supervise enumerates Codex app-server job
[TEST] PASS: supervise preserves authoritative Phase
[TEST] PASS: fresh session.log is alive without active.yaml row
[TEST] PASS: session.log path is recorded as liveness source
[TEST] FAIL: supervise emits log-only lane while registry is empty
{
  "warnings": [],
  "delta_mode": false,
  "birth_norm_source": "shared",
  "table": [
    {
      "task_id": "codex:running-job",
      "phase": "verifying",
      "minutes_in_phase": 61140,
      "status": "running",
      "status_reason": "authoritative codex-task.sh status: status=running",
      "waiting": false,
      "where": "codex app-server",
      "protocol_version": "provider"
    }
  ],
  "requires_founder": [],
  "questions": [],
  "waiting": false,
  "stuck": [],
  "closed_since_last": [],
  "truth_probe": "no_probe_configured",
  "truth_probe_reason": null,
  "truth_breaches": [],
  "orphans": [],
  "adopted": [],
  "would_adopt": [],
  "would_prune": [],
  "dead": [],
  "degraded": [],
  "observe_only": true,
  "reconcile_cycle": 2,
  "resume": {
    "status": "degraded",
    "role_present": false,
    "lanes": [],
    "focus": null,
    "next_action": null,
    "recent": [],
    "tasks_top10": [],
    "degraded": [
      "open-threads.md unavailable (/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/lane-liveness.M0gVNu/repo/docs/leadv2/open-threads.md)",
      "tasks.yaml unavailable/malformed (/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/lane-liveness.M0gVNu/repo/docs/tasks.yaml)"
    ],
    "degraded_resume_instruction": "ROLE UNAVAILABLE: read docs/leadv2/open-threads.md head verbatim; do not hand-rank docs/tasks.yaml",
    "pointers": "Full: docs/leadv2/open-threads.md . docs/leadv2/active.yaml . docs/tasks.yaml",
    "block": "<supervisor-handoff>\nROLE (sacrosanct):\n  (unavailable -- see degraded)\n\nLIVE LANES (0):\n  (none live)\n\nFOCUS: (unavailable)\nNEXT-ACTION: (none captured -- see tail below)\n\nHANDOFF DEGRADED:\n  - open-threads.md unavailable (/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/lane-liveness.M0gVNu/repo/docs/leadv2/open-threads.md)\n  - tasks.yaml unavailable/malformed (/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/lane-liveness.M0gVNu/repo/docs/tasks.yaml)\n  - ROLE UNAVAILABLE: read docs/leadv2/open-threads.md head verbatim; do not hand-rank docs/tasks.yaml\n\nFull: docs/leadv2/open-threads.md . docs/leadv2/active.yaml . docs/tasks.yaml\n</supervisor-handoff>",
    "block_lines": 17,
    "block_bytes": 705
  },
  "hidden_lanes_summary": null
}
[TEST-SAFETY] tripwire OK: /private/tmp/three-unlisted-reds.GjAMnE/repo/plugins/leadv2/scripts/leadv2-lane-liveness.sh unchanged (md5 acb0ac43e7e6b38bcbca8671cdb0e9c8 before and after)
```

### tests/run-all.sh --scope changed — raw output

```sh
timeout --kill-after=10s 180s bash tests/run-all.sh --scope changed
# timeout returned 124; this is NOT a passing gate.
```

```text
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] scope=changed running 0 of 95 suites (base=main@34e9fefa05, 0 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=0 total=95 base=main@34e9fefa05 changed=0 unmapped=0 verdict=nothing_to_run reason=no_relevant_changed_files
[CORE-OFFLINE] suites passed=0 failed=0 missing=0 verdict=nothing_to_run reason=no_relevant_changed_files repo=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4
[PASS] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/tests/test-status-surface-bash32.sh
== T1: /bin/bash -n on the renderer ==
  ok   - renderer parses clean under bash 3.2
== T2: /bin/bash -n on the wrapper ==
  ok   - wrapper parses clean under bash 3.2
== T2b: /bin/bash -n on the broad-status composer ==
  ok   - broad-status composer parses clean under bash 3.2
== T3: env -i minimal PATH (the actual SwiftBar launch shape) renders lanes ==
changed_scope_rc=124
```

The core runner selected zero relevant suites, but the top-level runner also selected the always-run `tests/test-status-surface-bash32.sh`. Its three initial syntax checks passed; T3 (minimal-PATH live status rendering) did not finish within the 180-second outer bound. The invocation has terminated. No broad-green claim is made, and no additional verification process is pending.

### Final lane status

Evidence checkpoint commit: `6cbf80f3`. This final report update records the completed timeout result. The report is the only changed/committed file; the three suites and production remain unchanged. The lane is NOT ready for a repair approval or a green close. It needs a corrected write set covering the actual tracked suite/production paths and resolution of the divergent main `.claude/scripts` deployment copy. No merge or push was performed.

BLOCKED: required production/test paths are outside LANE_WRITES; the changed-scope gate also timed out at status-surface T3 (rc=124).
