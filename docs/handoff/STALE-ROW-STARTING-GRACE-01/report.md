# STALE-ROW-STARTING-GRACE-01 — report

## Measured question: do stale rows block anything, or only pollute `list`?

**Answer (measured 2026-09-06, pre-fix): they DID block — `check_limits` refused.**
With the 7 dead-pid tombstones present (plus other non-stale rows, 10 counted
total), `leadv2_active_check_limits <any class>` exited rc=1 with
`[registry] hard limit reached: 10/5 active sessions` on EVERY class, while the
real dispatch admission path (register's writeset scan, the only check the
dispatch path consults) returned rc=0. So the tombstones were eating a limit
that nothing on the dispatch path even consults — a real defect, not cosmetic.
The refusing check, named: the hard-limit counter inside
`leadv2_active_check_limits` in `plugins/leadv2/scripts/leadv2-active-registry.sh`
(previously counted `sessions` unfiltered, never asked liveness).

Note the lead's EPERM/`kill(1,0)` hypothesis was already refuted before the
fix: `_pid_alive` (:301, duplicated in the list/check_limits embeds) catches
`PermissionError` and returns False — pid=1 is DEAD, not immortal. The
immortality was in the *counters*, which never consulted liveness at all.

Secondary defect (measured, same predicate): the `Active sessions (N / 5 max)`
header counted the same tombstones into N.

## What was done (commit bb4af7a2)

1. `check_limits` and the `Active sessions (N / max)` header now exclude rows
   with a recorded, provably-dead pid (same predicate as `_lv2_ws_dead`).
   **Fail-closed**: rows with pid=None/absent stay counted — an unknown-pid row
   is never silently treated as dead. Dead rows render with a `DEAD` marker.
2. `leadv2_active_unregister <task_id>` gained attempt discriminators that do
   NOT break existing callers: `--dead` (only provably-dead-pid rows; never
   removes a pid=None row), `--session-id <sid>`, `--pid <pid>`. Bare
   `unregister <task_id>` keeps the legacy remove-all behaviour, so every
   existing caller is unaffected.

## Controls (verbatim output)

1. **Positive** — dead tombstones must not trip the hard limit: suite A1 PASS.
2. **Paired negative** — live row of the same task_id survives the cleanup:
   - `PASS: C1 --dead removed exactly the 2 dead rows (4 -> 2)`
   - `PASS: C2 paired negative: LIVE row of same task_id survived`
   - `PASS: C3 other task_id untouched`
3. **Real live pid still counts and still blocks**: `PASS: A3 pid=None row
   still counts (fail-closed, rc=1)` plus the mutation leg below — reverting
   `_row_dead()` to False re-reddens A1/B1/B2, i.e. the filter is live; with
   it, live/pid-less rows still trip the limit (A2/A3).
4. **Declared suite negative control**: mutation = body-level
   `_row_dead() -> return False  # MUTATION` inside the function body (never
   top-level), applied to a TEMP COPY of the registry script, run with
   `STALE_ROW_GRACE_MUTATION=1`:

```
MUTATION KILLED: suite is red under _row_dead()->False (3 fail(s))
```

   Full suite unmutated: **ALL GREEN** (13/13, incl.
   `PASS: C6 --dead never removes a pid=None row (fail-closed)` and
   `PASS: C7 legacy bare unregister still removes ALL rows of the task_id`).

## Live verification (2026-09-06, post-fix, shared registry)

```
$ leadv2_active_check_limits standard
[registry] hard limit reached: 28/3 active sessions
$ leadv2_active_list | head -4
Active sessions (28 / 3 max):
session_id                     task_id              phase        class      pid      daemon  writes               peer         stale
...
```

Genuinely-live rows (dispatch-c4c38811 intake pid=10746, this lane's own row)
show no DEAD marker; the old dead-pid tombstones render with DEAD and no longer
drive the count that matters for their class.

Honest caveat: the live shared registry still refuses `check_limits` — but on a
different row class than this lane was dispatched against: ~20
`phase=recovered_unowned` rows with **pid=null** left by the recovery sweep.
Those are fail-closed by design (unknown pid is never assumed dead) and belong
to foreign/other-session work — per the brief they were not touched.

## Falsification set

- `bash -n plugins/leadv2/scripts/leadv2-active-registry.sh` — clean.
- `bash plugins/leadv2/scripts/tests/test-stale-row-starting-grace.sh` — ALL GREEN.
- Mutation leg (above) — red as required.
- `bash tests/run-all.sh --scope changed` (state file reset to 3debb685 so
  bb4af7a2 is re-verified) — result appended below.

## RUN-ALL --scope changed

(pending — appended when the runner completes)
