verdict: REVISE
next_action: continue

Round 2: attempted D1 (tier 1) incrementally per plan. Completed steps 1, 2, 5, 7; steps 3, 4, 6 (census move into `_ss_lanes_py`, `render_single_lead` awk-projection rewrite, and the parity test that depends on it) not attempted — confirmed by reading both ~600-line subsystems in full that a safe, verified merge does not fit this round's budget.

- Step 2: added additive `cls=queued` branch to `_ss_lanes_py`'s classify chain (ledger-only `kind=="worker"` row, `ledger_state` in pending/queued/reserved, no pid/exit-code evidence). Threaded `QUEUED_N` through both single- and multi-project bash consumer paths.
- Step 5: `emit_lanes_table` header appends `, N queued` only when `QUEUED_N>0`; verified byte-identical when 0.
- Verified with a live before/after fixture diff (not just tests): non-queued rows unchanged; a `state:"pending"` reservation now renders `STATE=queued`, excluded from live/dead counts.
- Step 7: fixed `test-status-surface-fast-names.sh` T3's stale space-delimited fixture to the real `·`-delimited format (independent of D1, was flagged broken since round 1's tier-2 fix); now 12/0 (was 11/1).
- Steps 3/4/6 (census move, `render_single_lead` rewrite, 10-case parity test) left undone — `render_single_lead` remains a fully independent ~570-line heredoc with its own census/reservation/terminal indices; merging it correctly into `_ss_lanes_py`'s already 4-round-hardened classify chain needs a dedicated follow-up session, not faked here.

All required gate tests green: `bash -n` (both files, both interpreters) clean; single-lead 23/0; bash32 15/0; fast-names 12/0. `test-status-surface-parity.sh` not created (depends on step 4). No commit made.

Full: full.md
