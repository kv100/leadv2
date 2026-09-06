# D2-M3-M6-REMAINDER-01 — M3 report

Scope: D2-SINGLE-LIVENESS-VERDICT brief.md migration step M3 only
(`finished*)` consumer arms in `leadv2-dispatch-ledger.sh`). M4/M5/M6 not
started — see "Remaining" below.

## Change

`plugins/leadv2/scripts/leadv2-dispatch-ledger.sh`:

- **`_dl_derive_lane_state`**: added `finished:*)` and `finished_unlanded:*)`
  case arms (additive, every existing arm untouched).
  - `finished:*` → `landed` with a real commit sha, fetched via an UNSCOPED
    `git log` lookup (liveness's E3 already corroborated a commit exists
    somewhere in the worktree — our own path-scoped lookup above found
    nothing, or this function would already have returned `landed` earlier).
    The lookup follows the same `DERIVE-COERCES-GIT-FAILURE-TO-NO-COMMIT-01`
    rc-checked discipline as the two existing probes: a failed git (fork
    failure under load, held index.lock) degrades to `unknown`, never a
    fabricated placeholder sha. (Found live during test-writing: an initial
    version swallowed the rc and stamped a placeholder — caught by a real,
    reproducible ~1-in-4 flake under this machine's load, fixed to match
    the established pattern before committing.)
  - `finished_unlanded:*` → the new `finished_unlanded` literal, verbatim.
- **`dispatch_ledger_write_terminal`**: added `finished_unlanded` to the
  terminal-state enum whitelist (additive only).
- **`cmd_reconcile`'s own `case "${term}" in`**: added a `finished_unlanded)`
  arm that stamps the terminal directly (no rescue-commit step — this
  verdict is already evidence the work is done, nothing to rescue).
- **`_dl_reap_one_lane`**: widened both the pre-lock check and the
  post-lock re-check from `dead:*` alone to
  `dead:*|finished:*|finished_unlanded:*` — all three are not-alive,
  evidence-based verdicts with equal standing for "safe to proceed and
  inspect the worktree"; the inspection below still decides the precise
  terminal (`no_work` on a clean tree, `dead_with_unlanded_work` on a dirty
  one). Before this widening, a `finished:*`/`finished_unlanded:*` lane fell
  to the `*)` catch-all and reap returned "indeterminate, writing nothing"
  — silently skipping the lane forever. This is the exact gap the brief's
  M3 acceptance criterion names.

## Regression check

- `test-reap-funnel-death-proof.sh` (the brief's own designated acceptance
  suite): 23/23 before, 29/29 after (6 new assertions added). 4 consecutive
  clean runs to rule out the flake found and fixed above.
- Six other suites touching `_dl_derive_lane_state`/
  `dispatch_ledger_write_terminal`/`_dl_reap_one_lane` (found via
  `grep -rl`): `test-dirty-lane-never-lands.sh`,
  `test-dispatch-outcome-terminal-retry.sh`,
  `test-empty-writes-dirty-probe.sh`, `test-lead-worker-channel.sh`,
  `test-ledger-reopen-contract.sh`, `test-worker-wrote-outside-lane.sh` —
  all green, no regression.

## New tests

`test-reap-funnel-death-proof.sh`, four new cases:

- **C10** (reap-level): `finished:5s` verdict, clean tree → reap writes a
  real `no_work` terminal row (previously: none).
- **C11** (reap-level): `finished_unlanded:9s` verdict, clean tree → same.
- **C12a** (direct `_dl_derive_lane_state` unit coverage): `finished:*` with
  a real unscoped commit present (deliberately outside the derive
  pathspec) → `landed` with that exact sha.
- **C12b**: `finished_unlanded:*` → the literal, verbatim.

## Mandatory negative controls (mutation-control-proven)

Via `leadv2-mutation-control.sh` against the committed baseline
(`233cc029`, parent `e99f8bd4`):

- **C4**: deleted both new case labels in `_dl_derive_lane_state`
  (`finished:*)`/`finished_unlanded:*)` → non-matching labels) — suite goes
  RED (`baseline_rc=0`, `mutated_rc=1`). Artifact:
  `mutation-control/20260906T142555Z-51558.txt`.
- **C5**: reverted `_dl_reap_one_lane`'s widened pre-lock case back to
  `dead:*` alone — RED. Artifact:
  `mutation-control/20260906T142642Z-99119.txt`.

Both required `git add -f` (`docs/handoff/*/*` gitignore rule).

## CI selection

`test-reap-funnel-death-proof.sh` already carries
`# run-all-triggers: leadv2-dispatch-ledger.sh leadv2-lane-liveness.sh`
(pre-existing, unchanged by this lane) — the file I modified is already a
named trigger.

**Could not run the live selection proof.** `LEADV2_RUN_ALL_SELECT_ONLY=1
bash tests/run-all.sh --scope changed` currently exits FATAL on every
invocation, repo-wide, for a reason unrelated to this lane:
`test-dod-gate-suite-registration.sh:3`'s own
`# run-all-triggers: lib/leadv2-dod-gate.sh leadv2-dod-gate.sh` declaration
contains a `/` in its first token, which the trigger-name charset
(`[A-Za-z0-9._-]`) rejects — `run-all: FATAL bad_trigger_decl`. That file is
committed on main (not another session's uncommitted work), so this is a
live, repo-wide blocker as of this writing, reported to Leadmain
(not this lane's file, not fixed here).

## Commits

- `233cc029` — the fix + new tests.
- report + mutation-control artifacts (this commit).

## Remaining (D2-M3-M6-REMAINDER-01, not started)

- **M4**: convert the 18 lane-registry PID readers with no liveness call to
  adopt `leadv2-lane-liveness.sh` instead of their own `kill -0`/`ps` probe
  (brief §5 census), in batches of ≤4, `leadv2-pulse-beat.sh` first. Known
  branchers needing their own new `finished*)` arm once converted:
  `leadv2-lanes-snapshot.sh`, `leadv2-status-surface.sh`,
  `leadv2-backlog-pump.sh`.
- **M5**: E0 contradiction guard (`unknown:contradictory_rows`) — ordering
  dependency on D1 M1, which landed with D1's merge (`1b02faf9`), so M5 is
  now unblocked.
- **M6**: dedupe `leadv2-lanes-snapshot.sh`'s own duplicate `_commit_age_s()`
  (the `LANE-LIVENESS-THREE-STATES-02` copy at `:545/:586/:862` per the
  brief) — call the shared function instead.

DELIVERABLE_COMPLETE (M3 only)
