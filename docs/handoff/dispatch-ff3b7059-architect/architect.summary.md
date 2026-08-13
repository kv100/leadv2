verdict: APPROVE
next_action: continue

Design scoped to `render_single_lead()` + two fixture suites. Root causes found, not guessed.

- Hash names & missed terminal cross-ref: reservations store the human name in `lane_label`; `task_id` is always `""`.
- Lead-as-lane: `codex_census()` counts `leadv2-codex-lead.sh`'s own `.session-runner.pid`.
- Terminal rows must drop the lane, not linger as `closing`.

Full: architect.full.md
