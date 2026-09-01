# WORKER-MCP-ALL-ARMS-01 — every arm gets the two code-intel MCPs and is told to use them instead of grep

Umbrella: TOKEN-ECONOMY-01 (founder 2026-09-01: "верное использование граф-MCP и repowise всеми
агентами, всеми провайдерами — для экономии токенов").
LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKER-MCP-ALL-ARMS-01`
LANE_WRITES: plugins/leadv2/scripts/freepool-coder.sh,plugins/leadv2/scripts/kimi-coder.sh,plugins/leadv2/scripts/codex-task.sh,plugins/leadv2/scripts/leadv2-codex-planner.sh,plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh,plugins/leadv2/config/mcp-role-default.json,plugins/leadv2/config/codex-mcp-servers.toml,plugins/leadv2/prompts/worker-code-intel-preamble.md,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh,tests/run-all.sh,docs/handoff/WORKER-MCP-ALL-ARMS-01/
Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Measured 2026-09-01 (audit over main)
| Arm | graph MCP (codebase-memory) | repowise MCP | told to use them |
|---|---|---|---|
| glm-coder.sh | yes — `lib/leadv2-worker-mcp.sh` (T14), `LEADV2_WORKER_MCP=1` default | yes | yes (subagent protocol §1b) |
| claude-subsession.sh | yes | yes | yes |
| **freepool-coder.sh** | **no** — zero `WORKER_MCP` references | **no** | **no** |
| **kimi-coder.sh** | **no** | **no** | **no** |
| **codex-task.sh / leadv2-codex-planner.sh** | partial — `~/.codex/config.toml` has `[mcp_servers.codebase-memory-mcp]` (user-level, not plugin-owned) | **no** | **no** |

Three of five arms rediscover callers, impact and mechanism by grep + cat on every run. Today three of
four live lanes ran on freepool. That is the tax the founder is paying.

## Do
1. `freepool-coder.sh` and `kimi-coder.sh`: call the SAME `lib/leadv2-worker-mcp.sh` resolver
   glm-coder.sh uses (never a copy), gated by the same `LEADV2_WORKER_MCP` (default 1), so the spawn
   line carries `--mcp-config` with the role-scoped servers.
2. Codex: a plugin-owned `config/codex-mcp-servers.toml` declaring BOTH servers (`codebase-memory-mcp`
   and `repowise`, same commands the `.mcp.json` of the consuming repo uses); `codex-task.sh` and the
   planner pass it per invocation (`-c` overrides or `--config`), never by editing `~/.codex/config.toml`.
   Verify the codex CLI flag shape against `codex --help` on this machine and paste it in report.md.
3. One preamble, `prompts/worker-code-intel-preamble.md` (≤25 lines), injected into EVERY arm's mission
   by `leadv2-dispatch-code.sh` (one injection point, not per-launcher): the routing table from
   persona-engine's CLAUDE.md — "who calls / trace / impact → graph (`search_graph`, `query_graph`,
   `trace_path`); how / where / why → repowise (`get_answer`, `get_context`, `get_symbol`); noisy
   commands (tests, git log, diff) → `repowise distill <cmd>`; a confident empty answer is not the end
   of an investigation (bare-name `trace_path` false-zero trap)". No arm gets a different text.
4. Suite `test-worker-mcp-all-arms.sh`: for each of the five launchers, a dry-run/`--print-spawn`
   (add one if missing, no network) shows `--mcp-config` (Claude-CLI arms) or the codex config path
   (codex arms) AND the preamble marker in the mission. Mutation negative control, RUN and paste red:
   `LEADV2_WORKER_MCP=1` but the resolver call removed from freepool → freepool row red.
   Register in `tests/run-all.sh`.
5. Live proof in report.md: one real short run per arm that is reachable right now (freepool at
   least; codex if not in cooldown) whose stream shows an `mcp__codebase-memory-mcp__*` or
   `mcp__repowise__*` tool call. Paste the line.

## Do NOT
- Edit `~/.codex/config.toml`, `~/.claude/settings.json` or any consuming repo's `.mcp.json`.
- Add a new MCP server or change what the role allowlists (`mcp-role-*.json`) permit.
- Touch quota, routing, or caching code — that is CACHE-TRUTH-01.
