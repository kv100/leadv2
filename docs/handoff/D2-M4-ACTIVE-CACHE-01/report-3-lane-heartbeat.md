# D2-M4 (3/14) — leadv2-lane-heartbeat.sh

## Change

`pid_confirmed_dead()` used to collapse `ProcessLookupError` (ESRCH,
genuinely gone) and `PermissionError` (EPERM, pid exists, owned by another
user — e.g. reparented to ppid=1) into the same `except (...): return True`
branch (D2 brief #9/#14). This function feeds `resolve_verdict()`'s `dead`
state directly — the ONLY path to `dead` in the whole file — so a stale
heartbeat plus a live-but-foreign-owned pid could resolve to `dead` even
though the process is provably still running.

Split into `except ProcessLookupError: return True` (confirmed dead) and
`except PermissionError: return False` (never confirmed dead — falls back
to the honest `running_stale`, the file's own pre-existing "I don't know"
state for exactly this situation). `TypeError`/`ValueError` (malformed pid
data) unchanged.

This file needed no `--all --json` call to `leadv2-lane-liveness.sh` — it
is itself one of the `status`/`status --all --json` consumers other M4
files call into (`leadv2-pulse-beat.sh`'s `_lv2_current_live_count`
delegates here), and the fix is a single self-contained except-clause
split, matching the file's own stated design ("the ONLY place a pid is
consulted").

## New test

`test-leadv2-lane-heartbeat.sh` Test 10: stale heartbeat (60m old) + pid=1
(guaranteed EPERM for a non-root caller, guaranteed to exist) → asserts
`status == "running_stale"`, not `dead`. 10/10 pass (9 pre-existing + 1
new).

## Mandatory negative control (mutation-control-proven)

Mutated line 176 (`except PermissionError: return False` → `return True`,
reverting to the pre-fix collapse). Suite goes RED exactly on Test 10
(`expected running_stale, got 'dead'`). GREEN on the committed code.

## Commit

`6aa6d087`.

## Also found while auditing (out of scope, reported to Leadmain, not fixed here)

- `leadv2-active-registry.sh`: the same `except (..., ProcessLookupError,
  PermissionError): return False` pattern appears in FOUR independent
  `python3` subprocess blocks (`_leadv2_yaml_py_lock` :322,
  `leadv2_active_list` :1576, `leadv2_active_check_limits` :1664,
  `leadv2_fanout_register_session` :1827) — each a live, separately-executed
  copy, not module-level shadowing. Measured: EPERM reproduces on this
  machine (`os.kill(1,0)` → `PermissionError`), but is very likely latent on
  the live path — active-registry.sh's `_pid_alive` never compares birth
  time, so the only way it fires is a genuine EPERM, which does not occur
  for same-uid lane workers (only for foreign/system pids). Real defect,
  probably never triggered in prod. Sequencing left to Leadmain.
- `hooks/leadv2-stale-pid-sweep.sh`, `hooks/leadv2-orphan-monitor-sweep.sh`,
  `leadv2-fanout-lane-launcher.sh`, `leadv2-helpers.sh` (4 sites) — all
  reclassified OWN / out-of-scope / dead-code (see prior reports and
  Leadmain thread). `leadv2-helpers.sh:1707`
  (`_leadv2_settings_py_lock`/hook-install refcount liveness) carries the
  identical bug in a DIFFERENT registry (not `active.yaml`) — flagged, not
  fixed, out of D2's scope.

## Remaining M4 (real list, 14 → after this: check next)

`leadv2-lane-pulse-watch.sh`, `leadv2-lane-status-line.sh`,
`leadv2-merge-queue.sh`, `leadv2-provider-canary.sh`,
`leadv2-status-collector.sh`, `lib/leadv2-worktree-protected.sh`,
`codex-guard.sh`, `leadv2-codex-lead.sh` (last two: brief itself flags as
possibly provider-child self-probes — confirm before converting),
`hooks/leadv2-task-anchor.sh` (1066 lines, deferred to its own pass),
`leadv2-fanout.sh` (deferred separately — mixed file, one genuine but
differently-shaped site, see prior thread).
