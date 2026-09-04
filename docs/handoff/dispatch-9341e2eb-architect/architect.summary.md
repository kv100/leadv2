verdict: REVISE
next_action: continue

Mechanism-closed design delivered; two mission premises are wrong and the design overrides them.

- repowise is per-repo (persona-engine `.repowise/` vs user-level pinned to leadv2) — a baked `mcp-role-*.json` would point workers at the wrong index. Files hold role→server-*names*; definitions resolve at spawn.
- F3 has a settings key: `autoCompactWindow` (100k–1M) — no launch wrapper needed.
- `~/.claude/scripts/claude-subsession.sh` is a stale independent copy on a live dispatch path.

Full: architect.full.md
