# CODEX-LEAD-ALL-TOOLS-GUARD-01

Close the Codex plugin enforcement hole outside shell commands.

Premise:
- The current `PreToolUse` matcher is broad, but `lv2guard-pretooluse.sh` extracts only `tool_input.command` and therefore silently allows non-command tool inputs.
- Current Codex hooks send `tool_name` plus tool-specific arguments. `apply_patch` is hook-visible, MCP and local function tools are generally hook-visible, and specialized/hosted tools can opt out.
- The root-lead rule is that application-code writes are delegated and scoped; current worktree/review/close enforcement is mostly prose-only.

Required behavior:
1. Parse `tool_name` and the real input shape without weakening the existing Bash deny floor or fail-closed behavior for unreadable deny configuration.
2. In an activated leadv2 root session, mechanically deny direct application-code edits through `apply_patch`/Edit/Write and obvious write-capable MCP/local tools unless the target is an allowed lead-owned state/evidence/mission path.
3. Do not block read-only graph/search/status tools, leadv2 dispatcher/reviewer/close commands, or unrelated non-leadv2 sessions.
4. Treat unknown/uninspectable write-capable inputs conservatively and observably. Do not pretend hosted tools are covered when Codex docs say they may bypass local tool hooks.
5. Keep path decisions worktree-aware and repo-relative; prevent writes to another lane or canonical shared application tree.
6. Add behavioral tests using real Codex hook payload shapes for Bash, apply_patch, MCP read, MCP write, local function read/write, malformed JSON, inactive session, and allowed lead-owned evidence writes.

Non-goals:
- Do not change lifecycle pulse behavior, router scoring, or root model selection.
- Do not broaden destructive command allowlists.

acceptance:
  surface: rendered_line
  observable: In an activated root-lead session, a direct application-code apply_patch or write-capable MCP call is refused with a specific reason, while graph reads and dispatcher commands continue to work.
  authored_at: 2026-08-24T18:25:00Z

LANE_WRITES: plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh,plugins/leadv2/codex-lead/tests/test-lv2guard-pretooluse-all-tools.sh
