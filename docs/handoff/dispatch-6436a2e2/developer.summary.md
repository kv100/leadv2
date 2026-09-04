verdict: APPROVE
next_action: deploy

LEAD_V2_STATE.md writes moved out of lane worktrees to ~/.claude/leadv2-state/<slug>/, fixing the 6/6 dod_fail runtime_state_in_diff verdict.

- Writer fixed: leadv2-active-registry.sh `_leadv2_state_md()` routes through leadv2-state-path.sh
- Single seam fixed: leadv2-helpers.sh `LEADV2_LEAD_STATE_PATH`/`LEADV2_STATE` default
- 13 more readers/writers updated to consume that seam; gate itself untouched (negative control passed)

Full: full.md
