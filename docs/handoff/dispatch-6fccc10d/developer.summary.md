verdict: APPROVE
next_action: review_round_2

Widened the census (5 glm-flash `attached` found, not 0), traced all 4 real dispatches behind it, and found 0/4 made an actual `mcp__*` call despite the config resolving — "attached" is not "used".

- m3's MCP fix (`.mcp.json`) is written up but blocked by a write-permission refusal outside the worktree; exact content in report.md. LEAD_ACTION: apply it by hand at `/Users/kostiantyn.vlasenko/MythicalGames/m3/.mcp.json`, do not commit inside that repo.
- Live single-task A/B (item 10) blocked by the same permission gap; withdrew the paired-savings claim, kept only the brief's existing aggregate number.
- Both suites green on macOS + Linux container, `--scope changed` selection proven, negative controls already covered by the pre-existing `test-worker-mcp-all-arms.sh`.

Full: full.md
