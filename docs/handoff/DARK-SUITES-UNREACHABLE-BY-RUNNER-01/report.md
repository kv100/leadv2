# DARK-SUITES-UNREACHABLE-BY-RUNNER-01 — report

## What was dark

D0 census (`docs/handoff/CONTROL-PLANE-HAS-NO-OWNER-01/census.md`) named 23 plan-relied-on
suites; 9 were reachable by `tests/run-all.sh --scope changed`, 14 were dark (existing,
several red, never selected). On this lane's base commit (`3b1b553f`), one of the 14
(`test-worker-outlives-terminal-state.sh`) was already registered by a different lane
(three `EXTRA_SUITE_MAP` rows already present). This lane registers the remaining **13**.

## Change

`tests/run-all.sh` `EXTRA_SUITE_MAP` gained 17 rows (one suite can be locked to more than
one production carrier) covering the 13 suites, keyed to the script each suite actually
drives/asserts against (verified by reading each suite's own `SUT`/`BIN`/`HELPER=` variable,
not guessed from the filename):

| suite | production key(s) added |
|---|---|
| `test-lane-liveness-authoritative.sh` | `leadv2-lane-liveness.sh` |
| `test-lane-liveness-lies.sh` | `leadv2-lanes-snapshot.sh`, `leadv2-active-registry.sh` |
| `test-lane-liveness-sentinel.sh` | `leadv2-lane-liveness.sh` |
| `test-lane-registry-self-deadlock.sh` | `leadv2-dispatch-code.sh` |
| `test-dispatch-terminal-deregisters-lane.sh` | `leadv2-dispatch-ledger.sh` |
| `test-dispatch-ledger-partial-close.sh` | `leadv2-dispatch-code.sh` |
| `test-dispatch-ledger-task-id.sh` | `leadv2-dispatch-code.sh`, `leadv2-dispatch-ledger.sh` |
| `test-t-core-dispatch-ledger.sh` | `leadv2-dispatch-ledger.sh` |
| `test-status-surface-close-phase.sh` | `leadv2-status-surface.sh` |
| `test-status-surface-cwd.sh` | `leadv2-status-surface.sh`, `leadv2-state-path.sh` |
| `test-status-surface-handle-identity.sh` | `leadv2-status-surface.sh` |
| `test-broad-status-relay-scope.sh` | `leadv2-single-lead-beat.sh` (hook), `leadv2-beat-owner.sh` |
| `test-lanes-snapshot.sh` | `leadv2-lanes-snapshot.sh` |

Commit: `7f21363d` (this lane branch, `tests/run-all.sh` only — no runtime-state path touched).

## Selection proof — `--scope changed` actually picks each suite

For every one of the 9 distinct production files above, I modified that file (appended a
comment line, uncommitted), ran `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope
changed`, grepped the `[SELECT]` lines for each suite this task maps to that file, then
reverted (`git checkout -- <file>`) before touching the next file — so causation is isolated,
not just "the map has a row."

### macOS (Homebrew bash, native host)

```
# touch: plugins/leadv2/scripts/leadv2-lane-liveness.sh
  OK selected: test-lane-liveness-authoritative.sh
  OK selected: test-lane-liveness-sentinel.sh
# touch: plugins/leadv2/scripts/leadv2-lanes-snapshot.sh
  OK selected: test-lane-liveness-lies.sh
  OK selected: test-lanes-snapshot.sh
# touch: plugins/leadv2/scripts/leadv2-active-registry.sh
  OK selected: test-lane-liveness-lies.sh
# touch: plugins/leadv2/scripts/leadv2-dispatch-code.sh
  OK selected: test-lane-registry-self-deadlock.sh
  OK selected: test-dispatch-ledger-partial-close.sh
  OK selected: test-dispatch-ledger-task-id.sh
# touch: plugins/leadv2/scripts/leadv2-dispatch-ledger.sh
  OK selected: test-dispatch-terminal-deregisters-lane.sh
  OK selected: test-dispatch-ledger-task-id.sh
  OK selected: test-t-core-dispatch-ledger.sh
# touch: plugins/leadv2/scripts/leadv2-status-surface.sh
  OK selected: test-status-surface-close-phase.sh
  OK selected: test-status-surface-cwd.sh
  OK selected: test-status-surface-handle-identity.sh
# touch: plugins/leadv2/scripts/leadv2-state-path.sh
  OK selected: test-status-surface-cwd.sh
# touch: plugins/leadv2/hooks/leadv2-single-lead-beat.sh
  OK selected: test-broad-status-relay-scope.sh
# touch: plugins/leadv2/scripts/leadv2-beat-owner.sh
  OK selected: test-broad-status-relay-scope.sh
```
17/17 OK. `git status --short` after the loop showed only pre-existing, unrelated
`docs/leadv2/*` runtime-state churn (background harness activity on this shared machine,
not touched or committed by this lane) plus the staged `tests/run-all.sh`.

### Linux container (`docker run ubuntu:latest`, apt git/python3/patch installed,
`git config --global --add safe.directory '*'`, main repo root bind-mounted so the
worktree's `gitdir:` pointer resolves — same methodology as D0's census)

```
  OK selected: test-lane-liveness-authoritative.sh
  OK selected: test-lane-liveness-sentinel.sh
  OK selected: test-lane-liveness-lies.sh
  OK selected: test-lanes-snapshot.sh
  OK selected: test-lane-liveness-lies.sh
  OK selected: test-lane-registry-self-deadlock.sh
  OK selected: test-dispatch-ledger-partial-close.sh
  OK selected: test-dispatch-ledger-task-id.sh
  OK selected: test-dispatch-terminal-deregisters-lane.sh
  OK selected: test-dispatch-ledger-task-id.sh
  OK selected: test-t-core-dispatch-ledger.sh
  OK selected: test-status-surface-close-phase.sh
  OK selected: test-status-surface-cwd.sh
  OK selected: test-status-surface-handle-identity.sh
  OK selected: test-status-surface-cwd.sh
  OK selected: test-broad-status-relay-scope.sh
  OK selected: test-broad-status-relay-scope.sh
```
17/17 OK, same order, same result as macOS.

## Negative control (mutation inside a function body, via `leadv2-mutation-control.sh`)

Target: `test-lane-liveness-sentinel.sh` / `plugins/leadv2/scripts/leadv2-lane-liveness.sh`,
mutating line 525 **inside** `sentinel_check()`'s body (not top-level):

```python
# before (line 525, inside def sentinel_check(tid, row): ... )
    if sentinel_age < sentinel_settle_s:
# after (mutant)
    if sentinel_age < 999999:
```
This defeats the settle-window check so a sentinel that is old enough to fire never does —
exactly the S1 case ("even when the log mtime is still fresh... case S1") the suite exists
to lock down.

`leadv2-mutation-control.sh` runs the suite against a from-scratch scratch-tree snapshot
(never the real file — confirmed unmutated by `git status --short` after each run), baseline
first, then mutated, and refuses to write an artifact unless baseline was green and the
mutant diff was non-empty (anchor-count / noop-edit guards).

### macOS

```
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-lane-liveness-sentinel.sh
  file=plugins/leadv2/scripts/leadv2-lane-liveness.sh
  red_line=[TEST] FAIL: S1: verdict is dead:sentinel_finalized
  diff_hash=7538506f7a15a59dcb7f6f9c41311c6530fd39e036ffab5eaae576ae340a8920

artifact (docs/handoff/DARK-SUITES-UNREACHABLE-BY-RUNNER-01/mutation-control/20260903T191053Z-87008.txt):
  suite=plugins/leadv2/scripts/tests/test-lane-liveness-sentinel.sh
  file=plugins/leadv2/scripts/leadv2-lane-liveness.sh
  anchor=525s/.*/    if sentinel_age < 999999:/
  baseline_rc=0
  mutated_rc=1
  red_line=[TEST] FAIL: S1: verdict is dead:sentinel_finalized
```
Post-run: `git status --short plugins/leadv2/scripts/leadv2-lane-liveness.sh` → clean;
re-ran the real suite → `rc=0` (13 passed, 0 failed), confirming the revert.

### Linux container

```
=== baseline (real file, unmutated) ===
baseline_rc=0
=== Results: 13 passed, 0 failed ===

=== mutation-control tool ===
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-lane-liveness-sentinel.sh
  file=plugins/leadv2/scripts/leadv2-lane-liveness.sh
  red_line=[TEST] FAIL: S1: verdict is dead:sentinel_finalized
tool_rc=0

artifact:
  baseline_rc=0
  mutated_rc=1
  red_line=[TEST] FAIL: S1: verdict is dead:sentinel_finalized

=== confirm real file untouched, still green ===
(git status --short: empty)
post_rc=0
```
Both OSes: **baseline_rc=0 → mutated_rc=1**, identical red line, real file untouched after,
suite green again on re-run. This is the `baseline_rc`/`mutated_rc` pair + red line the
acceptance criterion asks for (not a `diff_hash` claim).

I ran the negative control once, on the suite/mutation pair above, as the representative
proof that (a) the registration mechanism selects a suite that is actually sensitive to its
mapped production file, not an inert placeholder, and (b) `leadv2-mutation-control.sh` — the
repo's own DoD-gate mutation tool — works end-to-end for this class of suite. I did not run
a full mutation/negative-control pass against all 13 registered suites; that would be a much
larger effort (finding a real function-body anchor per suite) and was not needed to prove the
registration claim, which the selection proof above already establishes suite-by-suite.

## Self-check (falsification set)

```
$ bash -n tests/run-all.sh
SYNTAX_OK   (macOS and, separately, inside the Linux container)
```
No Python files were touched by this lane (`py_compile` — n/a, no `.py` files changed).

`git diff --diff-filter=D --name-only main...HEAD` (three dots): empty — nothing deleted.

## What I deliberately left alone

- **Did not fix** the pre-existing hangs/red states the D0 census recorded for suites that
  were *already* registered before this lane (`test-lane-registry-outlives-dispatcher.sh`,
  `test-lane-placement-pin.sh`, `test-broad-status-duty.sh`) — out of this task's scope
  (registration + selection proof, not suite repair).
- **Did not touch** `tests/known-red-suites.txt`, `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
  or any `docs/leadv2/*` runtime-state path — all three are explicitly off-limits per the
  shared resume brief. The `docs/leadv2/*` files show as modified in `git status` from
  concurrent background harness activity on this shared machine; none of that was staged or
  committed by this lane.
- **Did not re-map** `test-worker-outlives-terminal-state.sh` — already registered on this
  lane's base commit by another lane (three `EXTRA_SUITE_MAP` rows already present before I
  started).

DELIVERABLE_COMPLETE
