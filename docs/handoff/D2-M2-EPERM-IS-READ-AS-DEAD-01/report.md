# D2-M2-EPERM-IS-READ-AS-DEAD-01 — report

Scope: D2-SINGLE-LIVENESS-VERDICT brief.md, migration step M2 only
(process-kind match + EPERM/ESRCH split in `pid_state`/`pid_alive`).
M3-M6 are queued separately as D2-M3-M6-REMAINDER-01, not touched here.

## Change

`plugins/leadv2/scripts/leadv2-lane-liveness.sh`, `pid_state()`:
- Split the combined `except (TypeError, ValueError, ProcessLookupError, PermissionError)`.
  `ProcessLookupError` (ESRCH, brief #9's true negative) stays `("dead", "unverified")`.
  `PermissionError` (EPERM — the pid exists, owned by someone else) now returns
  `("alive_unverified", "unverified")`, never dead.
- After a successful birth-time match, added `_proc_kind(pid)` (duplicated from
  `leadv2-active-registry.sh::_proc_kind`, same discriminator built for
  PHASE-REFUSAL-LEAVES-A-LANE-REGISTERED-01): `kill(0)==0` + birth match alone no
  longer promotes to `alive_verified` (brief #14 — an interactive `claude`
  session, no `-p`/`--print`, recycled onto a recorded worker pid, was read as
  alive for hours). `worker` kind -> `alive_verified`; `unknown` (ps wedged) ->
  `alive_unverified`; anything else -> `dead:mismatch`.
- `pid_alive()` (unreferenced inside this heredoc today) got the same EPERM fold
  for consistency, per the brief naming both functions for C3.

## Regression check

- `test-lane-liveness-lies.sh`: 4/4 pass
- `test-lane-liveness-authoritative.sh`: pass, tripwire OK (production file
  untouched by the suite's own scratch-copy run)
- `test-liveness-tristate-01.sh`: 14/14 pass
- `test-lane-liveness-sentinel.sh`: 16/16 pass
- `test-lane-finished-state.sh`: 9/10 pass. The one failure (Test 5a, a
  RED/GREEN mutation gate on the `finished:` check) was confirmed **pre-existing
  on clean main** — reproduced byte-identically by swapping in
  `git show HEAD:plugins/leadv2/scripts/leadv2-lane-liveness.sh` in place of the
  edited file and re-running: same failure, same output. Unrelated to this
  change, not fixed here (out of M2 scope).

## Mandatory negative controls (mutation-control-proven)

New suite: `plugins/leadv2/scripts/tests/test-lane-verdict-pid-is-a-worker.sh`,
against the real `leadv2-lane-liveness.sh --project-root --lane --json` CLI
(no helper called in isolation).

- **C1** (mandatory, brief #14): fixture is a real background process invoked
  as `<scratch>/claude 600` (symlink to `sleep`, same trick as
  `test-lanes-snapshot.sh` Test 3b — `ps -o args=` shows the invoked path,
  containing "claude", no `-p`/`--print`) with its real `ps -o lstart=` as
  `pid_birth`, so `pid_state` reaches the kind check instead of degrading on a
  missing birth. Asserts `pid_alive == False`.
  Mutation: `leadv2-lane-liveness.sh:402` (`kind = _proc_kind(pid)` ->
  unconditional `return ("alive_verified", "verified")`) — suite goes RED
  (`pid_alive=True`), reverts GREEN. Artifact:
  `mutation-control/20260906T130232Z-86168.txt`.
- **C3**: fixture is pid 1 (EPERM for a non-root caller, same convention as
  `leadv2-orphan-reaper.sh`'s `_pid_alive` comment and
  `test-stale-sweeper-wiring.sh`). Asserts `pid_alive == True`, never dead.
  Mutation: `leadv2-lane-liveness.sh:388` (the `except PermissionError:`
  return -> `("dead", "unverified")`) — suite goes RED (`pid_alive=False`),
  reverts GREEN. Artifact: `mutation-control/20260906T130405Z-1429.txt`.

Both artifacts required `git add -f` (`docs/handoff/*/*` gitignore rule).

## CI selection proof

`test-lane-verdict-pid-is-a-worker.sh` carries
`# run-all-triggers: leadv2-lane-liveness.sh`. Proved with a real edit (a
trailing comment line, appended and saved — `touch` does not register with
git) to `leadv2-lane-liveness.sh`, then reverted:

```
LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../test-lane-liveness-authoritative.sh
[SELECT] .../test-lane-liveness-sentinel.sh
[SELECT] .../test-lane-verdict-pid-is-a-worker.sh
```

## Commit

`fac2653d` — `leadv2-lane-liveness.sh` + the new suite.

## Out of scope (D2-M3-M6-REMAINDER-01, not started here)

- M3: `finished*)` arms in `leadv2-dispatch-ledger.sh`'s
  `_dl_derive_lane_state`/`_dl_reap_one_lane`
- M4: converting the 18 `finished:`-unaware call sites
- M5: E0 contradiction guard (`unknown:contradictory_rows`) — ordering
  dependency on D1 M1
- M6: dedupe `leadv2-lanes-snapshot.sh`'s own `_commit_age_s()`

DELIVERABLE_COMPLETE
