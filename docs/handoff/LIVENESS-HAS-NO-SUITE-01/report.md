# LIVENESS-HAS-NO-SUITE-01 -- census + new suite

## Census -- who answers "is this lane alive" in this repo

| # | File | Rule it implements | Verdict shape |
|---|------|--------------------|----------------|
| 1 | lib/leadv2-lane-state.sh -- alive(row)/lane_alive | (pid, start-time) pair: os.kill(pid,0) AND recorded pid_start_time == observed `ps -o lstart=` | Binary only (rc 0/1). Finding F1: "no record" and "dead" both exit 1 -- not distinguished at the return-value level. |
| 2 | leadv2-lane-heartbeat.sh -- resolve_verdict() + status not-found branch | Heartbeat-age tri-state: running / running_stale (unknown, never guessed into dead) / dead (only if local pid confirmed gone) / terminal states; absent-record handled separately with its own exit code | Genuinely tri-state at rc level: verdict rows exit 0, no-record exits 4. Finding F2: pid_confirmed_dead() is bare kill(pid,0), no start-time corroboration (vulnerable to case 5, unlike #1). |
| 3 | leadv2-lane-liveness.sh | Third, independent (pid,lstart) corroboration path + sentinel/log-freshness logic, 1065-line python-in-bash-heredoc | Not exercised by this suite -- no safe function-level mutation seam within this lane's budget; flagged as follow-up. |
| 4 | lib/leadv2-watch-lifecycle.sh -- wl_cmdline_match/wl_pidfile_live | kill -0 plus per-pid `ps -p <pid> -o command=` substring match against a caller-supplied needle; never scans the whole process table | Binary. Verified clean of process-name-table-scan and post-filter-pipe $? by this suite's T3/T4. |
| 5 | leadv2-status-surface.sh -- _pid_alive() (R4) | err="$(kill -0 "$pid" 2>&1)"; EPERM treated as alive (case 6 fix); rc captured directly from the command substitution (case 7/8 avoided) | Binary; good reference, out of scan scope (3353-line file, whole-file scan would be noisy). |
| 6 | leadv2-dispatch-product-close.sh | Explicit "NEVER uses pgrep -f" comment -- documents/avoids case 1/3 by design | n/a |

Real violators found, OUT of this suite's scan scope, off-limits to fix in this lane
(plugins/leadv2/scripts/*.sh edits forbidden per lane-mission.md -- reported as findings only):
- leadv2-fanout.sh:1244 -- `pgrep -f "/leadv2 ${tid}"` (case 1/3 pattern).
- leadv2-spawn-rate.sh:119 -- `ps -Ao comm=,etimes= | grep -E 'leadv2-(...)'` (case 11 pattern).

Summary: 6 authoritative liveness-answering locations characterized; 2 real process-name-pattern
violators found outside scan scope; 2 findings (F1, F2) about pre-existing gaps in the two
reference implementations themselves.

## New suite

plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh -- 9 checks (T0 syntax + T1..T4, each
with its own mutation-tested negative control: T1NC/T2NC/T3NC/T4NC).

- T1: lane_alive() on a pid whose OBSERVED start time mismatches the RECORDED one (case 5,
  pid reuse) answers dead (rc 1), while naive kill -0 on the same still-genuinely-alive pid
  answers alive (rc 0).
- T2: leadv2-lane-heartbeat.sh status on an unregistered task_id returns rc 4, distinct from
  BOTH a live answer (rc 0, status=running) and a dead answer (rc 0, status=dead) -- cases 4, 12.
- T3: static scan -- neither lib/leadv2-lane-state.sh nor lib/leadv2-watch-lifecycle.sh contains
  a pgrep -f or ps ... | grep liveness check (cases 1, 2, 3, 11).
- T4: static scan -- neither file reads $? after a value-losing pipe stage (head/tail/wc/sort/
  uniq/column) instead of from the command itself (cases 7, 8).

Every mutation is inserted INSIDE a real function body on a SCRATCH copy (.nc-* files, removed
by an EXIT trap) -- never the tracked file, never a top-level/whole-file change.

Full raw run output (all 9 baseline_rc/mutated_rc pairs + red lines), the EXTRA_SUITE_MAP diff,
and the --scope changed selection proof are in this task's developer.full.md deliverable
(docs/handoff/dispatch-271bdd7d/developer.full.md).

## What was deliberately left alone

- leadv2-lane-liveness.sh (biggest decider, no safe function-level mutation seam found within
  budget) -- documented, not tested by a mutation control in this suite.
- The two real process-name-pattern violators (leadv2-fanout.sh:1244, leadv2-spawn-rate.sh:119)
  -- reported, not fixed (off-limits: plugins/leadv2/scripts/*.sh may not be edited in this lane).
- Finding F1 (lane_alive() collapses "no record" into "dead"'s rc) -- reported, not fixed
  (same off-limits boundary); this is why T2 targets leadv2-lane-heartbeat.sh, which does NOT
  have this gap, instead of lib/leadv2-lane-state.sh, which does.
- docs/leadv2/* runtime-state churn from concurrent lanes sharing this worktree -- untouched,
  not staged, not committed by this lane.
