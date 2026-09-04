verdict: APPROVE
next_action: continue

Opt-in multi-profile Claude dispatch: user-level TSV registry + a fail-open selector scoring each profile's live quota, exporting only the winner's CLAUDE_CONFIG_DIR to the child.

- Reuses `read_anthropic()` — already reads every account independently.
- One integration point: `claude-subsession.sh` (both launch sites).
- Label-only evidence; paths/tokens never journalled.

Full: full.md
