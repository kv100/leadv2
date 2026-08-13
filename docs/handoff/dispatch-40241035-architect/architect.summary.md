verdict: APPROVE
next_action: continue

# architect.summary — DISPATCH-FG-GUARD-01

Design ready: fail-open PreToolUse:Bash hook denying non-backgrounded worker launches, plus
age/verdict/re-run-command enrichment of the `lane_is_live` refusal.

- HEAD `dec6592`. Hook models `leadv2-block-fg-agent.sh`; override `# fg-dispatch: allow`.
- Write-set fix: hook test belongs in `plugins/leadv2/scripts/tests/` + `run-core-offline.sh`, not root `tests/` — else it never runs.
- `age_s` only reachable via `leadv2-lane-liveness.sh --json`.

Full: architect.full.md
