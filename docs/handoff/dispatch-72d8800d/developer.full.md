# CODEX-DETACH-01 round 2 — developer full report

## Scope
LANE_WRITES: plugins/leadv2/scripts/codex-task.sh, codex-guard.sh,
plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh, tests/run-all.sh,
docs/handoff/CODEX-DETACH-01/. Only `test-codex-broker-staleness.sh` ended up
changed — codex-task.sh/codex-guard.sh were mutated for the RED controls and
reverted (git diff confirms no residual change); EXTRA_SUITE_MAP rows for
codex-task.sh/codex-guard.sh already existed in tests/run-all.sh (lines
122-123), nothing to add there.

## What was wrong (round 1 finding)
Case 1 paired a **dead pid** with a **swept sessionDir**. Since the pid check
alone decides "attach or self-heal" whenever it fires first, the sessionDir
half of `_codex_validate_broker` was never the deciding factor for any
assertion — dropping `-d "$_session_dir"` (leaving only `-n "$_session_dir"`)
left the suite green (pass=3 fail=0).

## Fix: Case 1b — the reused-pid scenario
Added a new fixture in test-codex-broker-staleness.sh: a **live** pid (a real
`sleep 60 &` process the test spawns and controls, standing in for the OS
having reused a dead broker's pid for an unrelated live process) paired with
a **swept** sessionDir. Asserts the broker still gets moved aside and the
companion self-heals to completion.

The spawned process is reaped on every exit path: registered in a
`cleanup_pids` array consumed by the existing `trap cleanup EXIT`, in addition
to an explicit `kill`/`wait` right after the assertion.

### RED control (mutation inside `_codex_validate_broker` in codex-task.sh)
Removed the `-d "$_session_dir"` test:
```
-  if [[ -n "$_session_dir" && -d "$_session_dir" ]]; then
+  if [[ -n "$_session_dir" ]]; then
```
Result:
```
[CODEX-BROKER-STALENESS] case 1b: live (reused) pid + swept sessionDir -> self-heals to completion
[CODEX-BROKER-STALENESS]   FAIL: expected self-heal completion for reused-pid case, got result='died:attached_to_existing_broker' stale_count=0
[CODEX-BROKER-STALENESS] pass=4 fail=1
RED control rc=1
```
Only case 1b failed (case 1 also still exercises the dead-pid path and stayed
green because its pid half independently triggers move-aside). Reverted;
confirmed byte-identical to pre-mutation via `git diff` (clean).

### Second control — pid-liveness check is load-bearing for case 2
Mutated the pid branch to always report dead (`if false; then ... else
_dead=1; fi`), which would evict a genuinely alive broker.
```
[CODEX-BROKER-STALENESS] case 2: alive pid + present sessionDir -> left untouched
[CODEX-BROKER-STALENESS]   FAIL: alive broker.json was evicted
[CODEX-BROKER-STALENESS] pass=4 fail=1
RED control rc=1
```
Reverted; confirmed clean via `git diff`.

## Fix: Case 4 — death-report enrichment assertion
The brief (context.yaml D4) required the reaper's failure record to carry the
worker log's last line and the broker's age/sessionDir-presence at reap time.
That enrichment (`deathDiagnostics`) already existed in codex-guard.sh's
`mark_job_failed` (lines 298-350, git-blamed to the same commit series) but
**nothing asserted it** — round 1 left it unverified.

Added case 4: extracts `stat_mtime`, `acquire_job_lock`, `release_job_lock`,
`mark_job_failed` from codex-guard.sh into a harness script, builds a fixture
job JSON (`status: running`, dead pid, `logFile` pointing at a 3-line log
whose last line is a unique marker, `startedAt` far in the past so grace
passes) plus a sibling `broker.json` with a swept `sessionDir`, calls
`mark_job_failed`, and asserts on the **persisted record** (not source text):
`status == "failed"`, `deathDiagnostics.lastLogLine == marker`,
`brokerAgeSec` is a non-negative int, `brokerSessionDirPresent === false`.

### Extraction pitfall found and fixed
The naive `sed -n '/^fn()/,/^}$/p'` pattern used for `_codex_validate_broker`
does NOT work for `mark_job_failed`: its embedded python heredoc contains an
**unindented dict-literal close brace** (`data["deathDiagnostics"] = {` ...
`}` at column 1, source line 350) that matches `^}$` before the function's
real end (line 389) — the sed range truncates mid-heredoc and the extracted
harness fails with "here-document ... delimited by end-of-file". Wrote
`extract_fn()`, a small brace-depth-aware Python extractor that tracks `{`/`}`
balance per line but skips over heredoc bodies entirely (detected via a
`<<-?\s*['"]?DELIM` regex, consuming lines verbatim until the literal
delimiter line). Used only for the codex-guard.sh extraction; the existing
sed-based extraction for codex-task.sh's two helpers is untouched (it already
works — no unindented braces in that function).

### RED control (mutation inside `mark_job_failed` in codex-guard.sh)
```
-data["deathDiagnostics"] = {
-    "lastLogLine": last_log_line,
-    "brokerAgeSec": broker_age_sec,
-    "brokerSessionDirPresent": broker_session_dir_present,
-}
+data["deathDiagnostics"] = {}
```
Result:
```
[CODEX-BROKER-STALENESS] case 4: death report enriched with last log line + broker age + sessionDir presence
[CODEX-BROKER-STALENESS]   FAIL: death report enrichment missing/wrong (FAIL:lastLogLine=None)
record: {..., "deathDiagnostics": {}, ...}
[CODEX-BROKER-STALENESS] pass=4 fail=1
RED control rc=1
```
Reverted; confirmed clean via `git diff`.

## Full green run (post-revert, final state)
```
[CODEX-BROKER-STALENESS] case 1: dead pid + swept sessionDir -> self-heals to completion
[CODEX-BROKER-STALENESS]   stale broker moved aside, task self-healed to completion ✓
[CODEX-BROKER-STALENESS] case 1b: live (reused) pid + swept sessionDir -> self-heals to completion
[CODEX-BROKER-STALENESS]   live-pid+swept-sessionDir broker moved aside, task self-healed ✓
[CODEX-BROKER-STALENESS] case 2: alive pid + present sessionDir -> left untouched
[CODEX-BROKER-STALENESS]   alive broker preserved ✓
[CODEX-BROKER-STALENESS] case 3: no broker.json yet -> silent no-op
[CODEX-BROKER-STALENESS]   no-op, nothing created ✓
[CODEX-BROKER-STALENESS] case 4: death report enriched with last log line + broker age + sessionDir presence
[CODEX-BROKER-STALENESS]   death record carries lastLogLine + brokerAgeSec + brokerSessionDirPresent ✓
[CODEX-BROKER-STALENESS] pass=5 fail=0
GREEN rc=0
```

## Falsification set
```
$ bash -n plugins/leadv2/scripts/codex-task.sh && echo OK
bash -n codex-task.sh OK
$ bash -n plugins/leadv2/scripts/codex-guard.sh && echo OK
bash -n codex-guard.sh OK
$ bash -n plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh && echo OK
bash -n test OK
```
No .py files touched.

`git diff --stat` (post-revert, pre-commit): only
`plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh | 161 ++++` —
codex-task.sh and codex-guard.sh show zero diff (mutations fully reverted).

## Changed-scope runner — environmental block, not from this diff
`tests/run-all.sh --scope changed` was launched and waited on in the
foreground for 33+ minutes (multiple blocking TaskOutput calls + a 570s
direct wait). It never completed. Root-caused live (not guessed): its child
`run-core-offline.sh` blocks on `flock 9` against
`/private/tmp/leadv2-core-offline.lock`, a lock shared process-wide across
this machine's `~/.claude` install. At the time of the wait, `lsof` on that
lock file showed 60-67 concurrent waiters/holders, one bash process per
currently-active lane (11 lanes were listed as live in this session's
`[LEADV2_ACTIVE_OTHER_SESSIONS]` context — PULSE-BEATS-IN-IDLE-REPOS-01,
ARMS-ADMISSION-01, ANTI-SILENCE-ONE-MECHANISM-01, etc. each have their own
`tests/run-all.sh --scope changed` queued on the same lock). The lock file's
mtime advanced during the wait (queue is moving, not deadlocked), but at that
depth full drain was not observed inside the wait budget.

Given the queue is a system-wide serialization point untouched by this diff
(neither `run-core-offline.sh` nor the lock mechanism itself is in
LANE_WRITES), and the suite that actually exercises this change
(`test-codex-broker-staleness.sh`, the one row in EXTRA_SUITE_MAP mapped to
both codex-task.sh and codex-guard.sh) was run directly with full RED/GREEN
mutation proof above, I did not fabricate an aggregate-runner result. This is
reported as an open item, not silently dropped.

## Left alone
- `_codex_validate_broker`'s shape (pid-then-sessionDir check, move-aside via
  `mv ... .stale-<ts>`) — brief said it "is the right shape and stays."
- The `deathDiagnostics` enrichment logic itself in codex-guard.sh — already
  correct, only the missing test coverage was the gap.
- EXTRA_SUITE_MAP in tests/run-all.sh — rows for codex-task.sh/codex-guard.sh
  already present from round 1, verified via grep, no edit needed.

DELIVERABLE_COMPLETE
