# CODEX-DIES-MID-TEST-01 — the codex arm produces nothing on lanes whose work needs a long test run

Lane: `worktree-CODEX-DIES-MID-TEST-01` (anchor `264e50f`). All timestamps 2026-09-01 UTC.

## Critical 1 — what kills the worker (measured, not theorised)

**Killer: the openai-codex Claude plugin's own SessionEnd hook.** On every Claude Code
session end in a workspace, `session-lifecycle-hook.mjs SessionEnd` runs
`sendBrokerShutdown(brokerEndpoint)` and `teardownBrokerSession(... killProcess:
terminateProcessTree)`, killing the shared `codex app-server` for that workspace state
dir. Every in-flight `codex-companion.mjs task-worker` on that broker dies mid-command,
its job record stays `status=running`, and its log simply stops.

Neither candidate from the brief is the cause — it is not an idle/no-output cap and not
a total-runtime cap. It is a session-lifecycle side effect that strikes when ANY Claude
session whose cwd resolves to the job's workspace state dir ends (the dispatching lead
session, or a sibling). The incident deaths cluster ~hourly (13:33, 14:33, 15:31) —
the lead-session churn cadence.

### The kill chain, from the runtime

Plugin code (live on this machine, `~/.claude/plugins/cache/openai-codex/codex/1.0.4/`):

- `hooks/hooks.json` — SessionEnd → `node session-lifecycle-hook.mjs SessionEnd`
- `scripts/session-lifecycle-hook.mjs:98-109` — `sendBrokerShutdown(brokerEndpoint)` then
  `teardownBrokerSession({ ..., killProcess: terminateProcessTree })`
- `scripts/lib/broker-lifecycle.mjs:76` — broker session resolved per-cwd from
  `<stateDir>/broker.json`; the broker IS the `codex app-server` process tree
- `scripts/session-lifecycle-hook.mjs:64` — the same hook ALSO `terminateProcessTree(job.pid)`s
  every still-running job whose `sessionId` matches the ending session (that path also
  deletes the jobs from state — the incident jobs were NOT deleted, so the incident
  signature is the broker-teardown path, not the own-session path)

### Live reproduction (both directions), 2026-09-01

Mission-mandated repro: dispatch a codex job whose child runs a 4-minute test, then fire
the exact hook the harness fires.

**RED (committed script `264e50f`, pre-fix) — job `task-mtiv30mx-0nxhk6`:**

```
16:08:29  [log] Running command: ... timeout 300 bash -c 'sleep 240; echo LONGTEST-DONE'
16:10:07  [log] Still running; no output has been produced yet.   <- LAST LINE EVER
16:10:48  printf '{"session_id":"1111...","cwd":"<this worktree>"}' | node session-lifecycle-hook.mjs SessionEnd   (rc=0)
16:10:56  ps -p 58129 58905 58934  -> ALL GONE (worker, app-server x2)
          job json: pid=58129 status=running      <- stale forever
          state.json: job still listed running; broker.json deleted
          `codex-task.sh status task-mtiv30mx-0nxhk6` -> "Progress:" frozen at 16:10:07, looks alive
```

No TERMINAL line, no error, no exit status — exactly the four-lane incident signature.
(Later marked failed `worker_process_died` by codex-guard, still with no terminal line in
the log.)

**GREEN (fixed script) — job `task-mtiv7hqp-xymzuv`:**

```
16:11:56  [log] Running command: ... sleep 240 ...
          dispatch stderr: "[codex-task] armed deathwatch for task-mtiv7hqp-xymzuv"   <- absent in RED
16:12:09  SessionEnd hook fired (rc=0)
16:12:14  worker 77441 + app-server dead; deathwatch pid 77738 SURVIVES (nohup+disown)
16:13:58  job status=failed err=reaped: transport_gone_app_server_absent
          [log] [codex-task] TERMINAL: job=task-mtiv7hqp-xymzuv cause=transport_gone_app_server_absent
                worker_pid=77441 reaped_at=2026-09-01T16:13:58.000Z note=...
```

The 109s delay from kill to TERMINAL is the reaper's deliberate log-mtime grace
(`CODEX_REAP_LOG_GRACE_S`, default 120s — a growing log outranks every pid-shaped guess;
CODEX-REAP-LOG-MTIME-LIVENESS-01). "Within seconds" would mean reaping on a pid probe
alone, which this codebase already learned not to do.

Incident corroboration on disk (pre-fix corpses, unchanged by this lane):

```
TESTS-POLLUTE-REAL-JOURNAL-01/jobs/task-mtio1i6q-*.json  errorMessage: reaped: transport_gone_app_server_absent
MAIN-CORE-SUITE-RED-01/jobs/task-mtitpx11-*.json          errorMessage: worker_process_died  (log stops 15:31:41)
PHASE-GATE-IS-INVERTED-01/jobs/task-mtirobio-*.log        last line 14:33:53 "Running command: ... timeout 120 bash test-..." <log ends>
```

All seven incident jobs share sessionId `fa00a41c-…` (the lead session) and none were
deleted from their state.json — the broker-teardown signature, not the own-session-kill
signature.

## Critical 2 — a killed job must say so

`_codex_reap` (the first component that can PROVE the death) now appends to the job's own
log, best-effort:

```
[codex-task] TERMINAL: job=<id> cause=<cause> worker_pid=<pid> reaped_at=<iso> note=worker process died without recording a terminal state; named by the leadv2 reaper (CODEX-DIES-MID-TEST-01)
```

and the per-job **deathwatch** (`codex-task.sh __deathwatch <jobId>`), armed by the
`--background` dispatch path right after codex-guard.sh (same nohup+disown pattern),
emits a durable dispatch-journal row so lane liveness sees it:

```
~/.claude/cache/leadv2-events/CODEX-DIES-MID-TEST-01.jsonl
{"seq":1,"ts":"2026-09-01T16:13:58Z","repo":"CODEX-DIES-MID-TEST-01","arm":"codex",
 "handle":"task-mtiv7hqp-xymzuv","kind":"codex_worker_died",
 "detail":"cause=transport_gone_app_server_absent log=/Users/.../task-mtiv7hqp-xymzuv.log"}
```

Division of labour: codex-guard watches JOB STATUS; the deathwatch watches the WORKER
PID. The autoreap sweep stays a pure state mutation BY DESIGN — recording inside
`_codex_reap` made hermetic reap suites append real cooldown rows to the LIVE arm ladder
(measured this lane: the first test iteration leaked 9 fixture `codex_worker_died` rows
into the real `project.jsonl`; surgically removed, see §Hygiene). The deathwatch only
exists on real dispatches, so it owns the announcement — including when the sweep beat it
to the corpse (job already `failed` with `errorMessage: reaped:*` on first poll).

## Critical 3 — degrade, don't vanish

The deathwatch records an arm failure through the standard bounded ladder:

```
~/.claude/cache/arm-cooldown/codex.state
2026-09-01T16:13:58Z ARM_COOLDOWN arm=codex reason=transport_gone_app_server_absent
                     reprobe_at=2026-09-01T16:28:58Z cooldown_s=900 ... job=task-mtiv7hqp-xymzuv
```

No arm is excluded by name anywhere in the diff; `grep -n 'glm'` over the changed hunks
returns nothing but the cross-arm-spill guard in the test. The router's next resolve sees
a real failure record and cools codex for one bounded window — quota, task shape and
outcomes keep deciding the arm.

## Not fixed here (deliberately)

The killer itself — the plugin's SessionEnd broker teardown — is upstream plugin
behaviour shared by all repos; working around it inside leadv2 (e.g. a private
app-server) is a policy decision, not a mid-build fix. This lane makes the death loud,
attributed, and router-visible instead, which is what the acceptance asked for. If the
founder wants the dispatching session to keep its broker across session churn, that is a
separate task (candidate: `codex-task.sh` spawning the app-server itself rather than
inheriting the plugin's session-scoped one).

## Tests

`plugins/leadv2/scripts/tests/test-codex-longrun.sh` (hermetic:
`CODEX_GUARD_STATE_ROOT`/`LEADV2_EVENT_LOG_DIR`/`LEADV2_ARM_COOLDOWN_DIR` all redirected
into a mktemp fixture; no real job store, no dispatch, no network):

- T1  plain `reap` on a dead worker ⇒ TERMINAL line in the job's own log + status=failed
- T4a `__deathwatch` reaps a dead worker within its poll interval (incl. the
  sweep-got-there-first path) and announces
- T2  journal row `kind=codex_worker_died arm=codex` in the redirected journal
- T3  arm-cooldown record with the reap cause; T3b NO `glm.state` (cross-arm spill guard)
- T4b ALIVE worker (long test running) ⇒ untouched, no kill record, exits on MAX_S

RED→GREEN proof was done on the real call path (live dispatches above), which is
stronger than a synthetic mutation: the committed script `264e50f` is the RED (silent
death, frozen status), the working tree is the GREEN (TERMINAL + journal + cooldown).
The suite's own RED was observed during development: T2/T3 failed while the deathwatch
exited quietly on sweep-reaped jobs; fixed, all pass.

`EXTRA_SUITE_MAP` row added (`codex-task.sh:plugins/leadv2/scripts/tests/test-codex-longrun.sh`);
selection proven with `tests/run-all.sh --scope changed` (output in the lane transcript).

## Hygiene

- 9 fixture `codex_worker_died` rows this lane's first test iteration leaked into the
  REAL `~/.claude/cache/leadv2-events/project.jsonl` (15:56:22–15:56:33, handles
  `task-norunpid`, `task-queued-dead`, `task-worker-died`, `task-repair`, `task-repair2`,
  `task-repair-fallback`, `task-truly-dead`) were surgically removed; `project.jsonl`
  contained nothing else. Verified: no `fixdead*`/`fixlive*` fixture handles in any real
  journal after the green suite run.
- The two repro corpses (`task-mtiv30mx-0nxhk6`, `task-mtiv7hqp-xymzuv`) are real
  dispatches that really died; their records, TERMINAL line, journal row and cooldown row
  are left in place as the live evidence.
