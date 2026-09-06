# D2-M4 (6th real conversion) — leadv2-codex-lead.sh

Brief-flagged borderline file (possible provider-child self-probe) —
confirmed mixed, not purely OWN.

## Change

`leadv2-codex-lead.sh` has TWO independent duplicate-claim guards. The
`active.yaml`-based one (Python, around line 345) already handled EPERM
correctly (`except (TypeError, ValueError, ProcessLookupError): live=False`
/ `except PermissionError: live=True`) — no bug there.

The SECOND guard (`.session-runner.pid` file, bash, line ~367) used bare
`kill -0 "$_runner_pid" 2>/dev/null` — bash cannot distinguish ESRCH from
EPERM by exit code alone (both nonzero), so an EPERM runner pid (exists,
owned by another user) would fail to refuse a duplicate dispatch of the
same task, letting two runners claim it (D2 brief #9/#14).

Fix: capture `kill -0`'s stderr and check for a permission-denied message,
same pattern as `leadv2-stale-sweeper.sh`'s `_ssw_pid_alive`. Refuses on
either signal (rc=0 alive, or stderr matches "not permitted").

## Bug caught during test-writing, not code review

The first fix attempt (`_runner_err="$(kill -0 "$_runner_pid" 2>&1)"` as a
bare assignment, `_runner_rc=$?` on the next line) made the WHOLE SCRIPT
exit silently under `set -euo pipefail`: a failing command substitution
used as a plain assignment's value is itself a failing simple command, and
`set -e` aborts on it — before `_runner_rc=$?` ever ran. The refuse message
never printed; the wrapper simply exited 1 with only the advisory line.
Caught by running the real test (not by code review) — the first test run
showed `rc=1` with `already owns task` MISSING from the output, which
looked like a red herring until traced to `set -e`. Fixed with
`... && _runner_rc=0 || _runner_rc=$?` (a list, not a simple command,
so `set -e` does not fire on the failing branch).

## New test

`test-codex-lead-intake.sh`: EPERM runner pid (1) in
`docs/handoff/TASK-EXPLICIT/.session-runner.pid` still refuses the
explicit-task-id claim (no runner launch, `already owns task` in output).
11/11 pass (10 pre-existing + 1 new).

## Mandatory negative control (mutation-control-proven)

First attempt (deleting the case-arm lines) broke bash syntax — the mutation
tool correctly reported a syntax error rather than a false pass. Retried
neutering the match string instead (`not permitted` → `xxnomatchxx` on the
case pattern line). Suite goes RED exactly on the new test:
`FAIL: EPERM runner pid did not refuse: rc=0` — confirming the mutated code
now launches instead of refusing. GREEN on the committed code.

## Commit

`e5074b11`.

## Running tally

Real conversions (6): `leadv2-active-cache.sh`, `hooks/leadv2-worktree-enforce.sh`,
`leadv2-lane-heartbeat.sh`, `leadv2-merge-queue.sh`,
`lib/leadv2-worktree-protected.sh` (latent), `leadv2-codex-lead.sh`.
Misclassified (8): `leadv2-pulse-beat.sh`, `hooks/leadv2-orphan-monitor-sweep.sh`,
`hooks/leadv2-stale-pid-sweep.sh`, `leadv2-fanout-lane-launcher.sh`,
`leadv2-helpers.sh` (4 sites), `leadv2-lane-pulse-watch.sh`,
`leadv2-lane-status-line.sh`, `leadv2-provider-canary.sh`.
Already-compliant (2): `leadv2-orphan-reaper.sh`, `leadv2-status-collector.sh`.
Confirmed OWN + protected downstream (1): `codex-guard.sh`.
Deferred to Leadmain / separate rows: `leadv2-fanout.sh` (mixed),
`leadv2-lane-state.sh` (Leadmain's own row), `leadv2-active-registry.sh`
(×4 sites, latent, sequencing TBD).
Remaining: `hooks/leadv2-task-anchor.sh` (1066 lines, own pass).
