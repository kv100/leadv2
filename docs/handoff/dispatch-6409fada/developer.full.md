verdict: APPROVE
next_action: deploy

# PPC-G3: fix the integration test harness signal (worktree BEAT-LOOP-ORPHANS-01)

Note: this handoff dir already contained a `developer.full.md` from a prior run referencing
commit `d9ec634` (promise-guard journal sandbox-control fix) — that commit does not exist in
this worktree's history (`git log` here tops out at `6eb6d56` pre-fix / `d3d8781` post-fix), so
it was done against a different worktree under the same dispatch id. Per the WORKTREE PIN
instruction, this report covers only the work actually done in
`.claude/worktrees/BEAT-LOOP-ORPHANS-01`, superseding that stale content.

## Root cause

This worktree's real integration suite is `plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh`
(BEAT-LOOP-ORPHANS-01's own harness, per `docs/handoff/BEAT-LOOP-ORPHANS-01/fix-round-3.md`,
which calls for running exactly this suite plus `run-all.sh --scope changed`). Running it fresh:

```
[TEST] 19 passed, 11 failed
```

Failures: A5, A6, D0b, E7, E8, E9, E10(x4), NC3 — all cases asserting "no env evidence -> unknown"
came back "worker" instead. Traced to `env | grep LEADV2` in this very process:

```
$ env | grep -E "LEADV2_SUBSESSION_ROLE|LEADV2_WORKER_ARM|LEADV2_SESSION_KIND|CLAUDE_CODE_ENTRYPOINT"
LEADV2_SUBSESSION_ROLE=worker
CLAUDE_CODE_ENTRYPOINT=sdk-cli
```

This subagent IS a worker session (dispatched via `claude -p` / sdk-cli), so its own launcher
exports `LEADV2_SUBSESSION_ROLE=worker`. The suite's E-block unit table (`kind_of()`/`kind_reason()`
helpers, `plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh:344-356`) spawns `bash -c "..."`
subshells to exercise `leadv2_hook_session_kind()` in isolation, but `bash -c` inherits the
*exported* environment of the invoking shell — so the ambient `LEADV2_SUBSESSION_ROLE=worker`
leaked into every subshell, including cases that deliberately pass no per-call env override
(E7/E8/E9) and expect the predicate to fall through to "unknown". Same leak hit the full-hook
cases (A5/A6/D0b) via `run_hook()`. The suite's own header claims "Hermetic: ... no real
control-plane state" — untrue for the invoking process's own session-kind env vars, which is
exactly the harness signal defect matching the mission ("fix the integration test harness
signal": the suite was giving a false-red verdict about a correct predicate, purely as an
artifact of who ran it).

## Fix (commit d3d8781)

`plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh`, right after `set -uo pipefail`:

```bash
unset LEADV2_SUBSESSION_ROLE LEADV2_WORKER_ARM LEADV2_SESSION_KIND \
      LEADV2_SESSION_KIND_OUT LEADV2_SESSION_KIND_REASON 2>/dev/null || true
```

This makes the suite hermetic regardless of whether it's invoked by a lead session, a worker
session, or a bare CI shell — each test case's own explicit env prefix (e.g.
`LEADV2_WORKER_ARM=1 kind_of ...`) is unaffected since those still set the var for that one
subshell; only the *ambient* leak from the outer process is removed.

## Verification — foreground, HEAD=d3d8781

```
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh
...
[TEST] 30 passed, 0 failed

$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=29

$ LEADV2_SUITE_LOCK_DISABLE=1 timeout 300 bash tests/run-all.sh --scope changed
...
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] running 83 suites across 4 shards
[exited with code 0]
```

`bash -n` implicitly exercised by running the suite itself (no syntax errors). `git diff` /
`git show d3d8781` confirms only the one `unset` block added to
`test-beat-loop-orphans.sh` — no product code (session-kind lib, beat hook, loop script) changed.

## Tree state post-commit

`git diff -- plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh` is empty (committed). The
worktree still carries a large unrelated staged set (~150 files: other tasks' `docs/handoff/*`
entries, `tests/run-all.sh` diff, `docs/LEAD_V2_STATE.md`) that predates this session and is
outside this mission's `LANE_WRITES` — left untouched and unstaged/uncommitted by this commit
(pathspec-scoped `git add` was used, per the lane-salvage-commit-hazard memory). That set looks
like the round-3 merge-with-main state described in `docs/handoff/BEAT-LOOP-ORPHANS-01/fix-round-3.md`;
resolving/committing it is a separate, larger decision (which side wins each of the 2 conflicting
files) that this mission did not ask for and I did not attempt.

## Left alone

- Did not perform the `git merge main` from fix-round-3.md — out of scope for "fix the
  integration test harness signal"; the merge is a bigger, separate decision over ~150 unrelated
  staged files already sitting in this worktree's index.
- Did not touch the session-kind predicate itself (`leadv2-hook-session-kind.sh`) — it was already
  logically correct; only the test harness's environment isolation was broken.

DELIVERABLE_COMPLETE
