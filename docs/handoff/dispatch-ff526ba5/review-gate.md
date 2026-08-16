arms: glm,opus,sonnet
verified: 0/0
status: pass
reviewer: glm
diff: 7282419f
findings_source: finding_lines
findings:
- [Medium] plugins/leadv2/scripts/leadv2-fork-session.sh:747 — postflight reaps the worktree but never calls leadv2_active_unregister — the active.yaml row preflight wrote survives until the lead's claude PID dies and stale-pid-sweep collect…
omitted: low=5
report: docs/handoff/dispatch-dispatch-ff526ba5/review-glm.md
