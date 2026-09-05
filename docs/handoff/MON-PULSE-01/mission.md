# MON-PULSE-01 — dispatcher-owned lane watch + pulse beat default-on in single-lead (P1, Standard)

Repo: canonical leadv2 plugin. Context: docs/leadv2/freepool-backlog.md §MON-PULSE-01.
Founder order 2026-08-28 (3rd occurrence of PULSE-IN-SINGLE-LEAD-01): tracking and founder
updates must work IN THE PLUGIN always — never as session-improvised lead Monitors.

Live evidence today: two lead Monitors armed with `tail -n 0` missed dispatch_terminal
written 25s post-spawn; the founder saw nothing until he asked. Meanwhile the pulse
machinery exists (leadv2-pulse.sh, leadv2-pulse-write.sh, leadv2-pulse-beat.sh,
leadv2-broad-status.sh) but its beat historically fired only from the retired supervise loop.

Build, two parts:
1. DISPATCHER-OWNED LANE WATCH: at worker_spawned, leadv2-dispatch-code.sh itself starts a
   detached lightweight watcher (nohup bash, not a Claude Monitor) for that lane:
   - replay-safe: reads the journal from line 1 (tail -n +1), matches ALL terminal states
     (dispatch_terminal|dispatch_refused|worker_died|review_gate) for ITS task sig only;
   - on each transition appends one line to the lane pulse file via the existing
     leadv2-pulse.sh (task_id, phase, <=80 bytes) — reuse, do not reimplement;
   - exits after the terminal line or FREEPOOL/GLM timeout; never two watchers per lane
     (pidfile guard keyed by sig).
2. SINGLE-LEAD BEAT DEFAULT-ON: the BROAD_STATUS beat (leadv2-pulse-beat.sh /
   leadv2-broad-status.sh writer) must arm in single-lead mode by default whenever at least
   one lane is live in active.yaml — every 5 min, stopping when no lanes remain. Wire the
   arming into dispatch (first worker_spawned arms it once; pidfile guard) instead of the
   retired supervise loop. Env kill-switch LEADV2_PULSE_MODE=0 keeps working.

Tests (plugins/leadv2/scripts/tests/, hermetic):
(a) fake journal where the terminal line exists BEFORE the watcher starts -> watcher still
    reports it (replay-safety — the exact bug from today);
(b) watcher writes pulse lines on transitions and exits at terminal; second arm attempt for
    the same sig is a no-op (pidfile);
(c) beat armed on first spawn, not armed twice, stops when active.yaml has no live lanes;
(d) NEGATIVE CONTROL declared in header and RUN red: revert replay-safety (tail -n 0) ->
    test (a) must fail.
Add EXTRA_SUITE_MAP rows in tests/run-all.sh. bash -n all touched scripts.

Commit: feat(leadv2): MON-PULSE-01 — dispatcher-owned lane watch + single-lead pulse beat default-on.
Report: docs/handoff/MON-PULSE-01/report.md (max 250 words, raw suite tails), end DELIVERABLE_COMPLETE.
