verdict: APPROVE
next_action: review_round_2

Implemented WORKER-CONTEXT-DIET-01 per architect's mechanism-closed design (no census corrections needed).

- `resolve_role_mcp_config()` (fail-open, 5 rc paths) + two flag appends in `claude-subsession.sh`; `mcp-role-{developer,critic,architect,default}.json` allowlists; per-repo definitions resolved at spawn.
- Fixed `leadv2-claude-subsession.sh:50` to prefer canonical over the stale `~/.claude/scripts/` copy (confirmed real, drifted, not a symlink).
- Probe script + doc + `PER_TASK_BOILERPLATE` cwd/SHA line + `--agent`/`--bare` TODO.

10/10 new tests pass (incl. under HOME-scrubbed core-offline isolation). Full core-offline: 59/61 pass; 2 pre-existing unrelated failures (GLM ladder, fanout shared-tree symlink) confirmed present on unmodified HEAD too.

Live probe (4 billed spawns) NOT run this session — see full.md §Not done.

Full: full.md
