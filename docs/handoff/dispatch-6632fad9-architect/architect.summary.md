---
verdict: APPROVE
next_action: continue
---

Scoped design for V3-ENV-GUARDS-01: three guards, 7 files, red-first suite.

- Item 1 root cause: pump's `git rev-parse --show-toplevel` fallback resolves to the lane worktree; pin CACHE_DIR to canonical root. Second writer in pump-caller hook also fixed.
- Item 2 dead shape probed live (rollout 05-22-53: `task_complete`, `last_agent_message:null`, 946ms); new check spills after the first-byte guard.
- Item 3 audit: set `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` (two hooks need Task tools); unset agent-teams.

Full: architect.full.md
