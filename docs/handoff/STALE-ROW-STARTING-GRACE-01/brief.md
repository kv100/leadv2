# STALE-ROW-STARTING-GRACE-01 — a registry row with a dead pid must never refuse its own re-dispatch

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-liveness.sh,plugins/leadv2/scripts/leadv2-active-registry.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-stale-row-starting-grace.sh,tests/run-all.sh,docs/handoff/STALE-ROW-STARTING-GRACE-01/
Run suites with `LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST. Never commit `docs/leadv2/`,
`docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*`. Commit by LANE_WRITES pathspecs; an uncommitted exit
is a failed round. Review-facing text in ENGLISH.

## Measured (lead, 2026-09-02)
RESUME-LANE-ACCEPTS-PATH-01 R5 was refused 3× with `lane_is_live` while its registered pid 2036 was
dead and no stream existed. `leadv2-lane-liveness.sh` (~:758-765) gives a registered row a
`starting:` grace whose age falls back to `dispatch.json` mtime when `started_at` is missing — and
every refused dispatch REWRITES `dispatch.json`, so the refusal refreshes the grace it is refusing on:
a stale row refuses itself forever. Fixed by hand with `leadv2-active-registry.sh unregister`; the row
also survived the first unregister (grace re-derived from the fresh mtime) until the 300 s window
expired.

## Do
1. Age for the `starting:` rung comes from `started_at` ONLY. If `started_at` is missing, the row gets
   NO grace — it is `unknown`, and a dead pid makes it `dead` regardless of any file mtime. Delete the
   `dispatch.json` mtime fallback; never derive liveness from a file the dispatcher itself writes.
2. A row whose pid is dead AND has no live stream (mtime older than `LANE_STALL_MIN`) is `dead` even
   inside the grace window: the dispatcher's `lane_is_live` check must treat `dead` as free and
   overwrite the row (journal `stale_row_reclaimed task=… pid=… age=…`), not refuse.
3. `unregister` must remove the row in one call and the next liveness read must not resurrect it from
   `dispatch.json` or any sidecar.
4. Suite `test-stale-row-starting-grace.sh` (fixtures, no live spawn): (a) row with dead pid, no
   started_at, fresh dispatch.json → `dead`, dispatch proceeds; (b) row with live pid inside grace →
   `starting`, dispatch refused; (c) row with started_at 10 min ago, dead pid, no stream → `dead`;
   (d) unregister → row gone on the next read. Mutation negative controls, RUN and paste red: restore
   the mtime fallback → (a) red; remove the dead-pid override → (c) red. Revert. Register in
   `tests/run-all.sh` (`leadv2-lane-liveness` stem); paste `--scope changed` line + FALSIFIABLE.
5. `report.md`: before/after liveness output for the RESUME-LANE shape reproduced from fixtures.

## Do NOT
- Do not change the stall thresholds, the pulse, or the watcher kill logic (ONE-LANE-WATCH-01 owns them).

## Scope addition — 2026-09-02 09:10Z (BRAIN-CLASS-LIVE-01 refused 6 dispatches)
A `session_id: recovered` row written by the compact/recovery hook pinned `pid: 26252`, which was
`leadv2-lane-watch-v2.sh --loop <other-session>` running from the lane worktree. The liveness probe
returned `starting:N reason=registered_no_stream pid_source=legacy` and the dispatcher refused
`lane_is_live` — six times, across two lead sessions. Earlier the same lane was held "live" by an
orphan `leadv2-single-lead-beat-loop.sh` (ppid 1). Required: (1) a recovered row must never take a
watcher/beat-loop/lane-watch pid as worker evidence — pid must be a worker arm process or none;
(2) `starting:` from a `recovered` row with no stream must expire (grace ≤ 5 min) instead of refusing
forever; (3) `leadv2_active_unregister` printed rows=0 while the row survived — make unregister
verify-and-fail-loud. Evidence: `dispatch-BRAIN-CLASS-LIVE-01-r4{a..f}.log` in the 09-02 scratchpad,
journal lines 08:55Z/09:10Z in persona-engine `docs/leadv2/open-threads.md`.
