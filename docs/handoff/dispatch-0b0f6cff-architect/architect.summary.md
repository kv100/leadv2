verdict: APPROVE
next_action: continue

Root cause of all 11 failures is one defect: `classify()` is the lanes path's process-liveness
chain, so a reservation-only lane (`state:confirmed`, no process) can never reach `live`.

- Add dispatch-reservation branches to `leadv2-lane-class.py`; lanes path stays inert.
- Split the renderer's silent drop into terminal / queued / dead / unknown-renders-anyway.
- 3 expectations deliberately move; parity suite is new.

Full: architect.full.md
