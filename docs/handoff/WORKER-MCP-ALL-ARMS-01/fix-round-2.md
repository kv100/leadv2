# WORKER-MCP-ALL-ARMS-01 — fix round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKER-MCP-ALL-ARMS-01`
LANE_WRITES: plugins/leadv2/scripts/freepool-coder.sh,plugins/leadv2/scripts/kimi-coder.sh,plugins/leadv2/scripts/codex-task.sh,plugins/leadv2/scripts/leadv2-codex-planner.sh,plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh,plugins/leadv2/config/mcp-role-default.json,plugins/leadv2/config/codex-mcp-servers.toml,plugins/leadv2/prompts/worker-code-intel-preamble.md,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh,tests/run-all.sh,docs/handoff/WORKER-MCP-ALL-ARMS-01/
Continue from the existing commits on this branch (`git log main..HEAD`); run with
`LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST (`git merge main`). Never commit anything under
`docs/leadv2/` (`git checkout -- docs/leadv2` before each commit; commit by explicit pathspecs). Round 1 had
no `report.md` — write one under `docs/handoff/WORKER-MCP-ALL-ARMS-01/` and `git add -f` it. An
uncommitted exit is a failed round.

## Review verdict on round 1 (reviewer glm) — FAIL, high=1
`test-worker-mcp-all-arms.sh:6` claims coverage of "both their `run` (v1) and `bg`/child spawn paths" but
never invokes the bg / `cmd_run_child` path. The reviewer proved it: deleting the whole cmd_run_child MCP
wiring (`freepool-coder.sh:1261-1293`, `kimi-coder.sh:1119-1135`) leaves the suite green. The `bg` path
is the ONLY path the dispatcher uses — so the shipped wiring is unproven exactly where it runs.

## Do
1. Exercise the real `bg` → `cmd_run_child` path for freepool and kimi with the transport faked one level
   lower (a fake `claude` / kimi binary on PATH that dumps its argv + env to a file, and a fake
   provider endpoint if needed): assert the child argv/env carries the MCP config (`--mcp-config` or
   the equivalent the lane wired) and the role-resolved server list; assert the code-intel preamble is in
   the prompt the child receives. Same for codex (`codex-task.sh` → the `-c mcp_servers…` / toml path).
2. Mutation negative control, RUN and paste red: remove the cmd_run_child MCP wiring in freepool
   (the reviewer's exact mutation) → the new case red; same for kimi. Revert both.
3. Fix the suite header to say exactly what is covered (no claim without a case).
4. `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh`
   → paste FALSIFIABLE; `tests/run-all.sh --scope changed` → paste the selected-suite line.
5. `report.md`: "## Round 2 evidence" with the fake-transport artifacts (argv dump excerpts), red/green
   outputs, and one line per arm: "arm X: MCP servers reach the child via <mechanism>, proved by <case>".
