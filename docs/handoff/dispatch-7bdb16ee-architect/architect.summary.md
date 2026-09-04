verdict: APPROVE
next_action: continue

Scope collapses to one code path: only `build_thread_anchor()` in leadv2-task-anchor.sh re-injects ungated.

- No sibling open-threads/scheduled-decisions injectors exist; single-lead-beat already hash-dedups BROAD_STATUS — do not touch it.
- Task-mode anchor already session-gated; only thread mode is open.
- New hole: nothing clears the gate on /compact → post-compact silence. PreCompact clear mandatory.

Full: architect.full.md
