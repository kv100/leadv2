# WORKER-MCP-ALL-ARMS-01 — fix round 3

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKER-MCP-ALL-ARMS-01`
LANE_WRITES: plugins/leadv2/scripts/freepool-coder.sh,plugins/leadv2/scripts/kimi-coder.sh,plugins/leadv2/scripts/codex-task.sh,plugins/leadv2/scripts/leadv2-codex-planner.sh,plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh,plugins/leadv2/config/mcp-role-default.json,plugins/leadv2/config/codex-mcp-servers.toml,plugins/leadv2/prompts/worker-code-intel-preamble.md,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh,tests/run-all.sh,docs/handoff/WORKER-MCP-ALL-ARMS-01/
Continue from the existing commits on this branch; run with `LEADV2_SUITE_LOCK_DISABLE=1`. Merge main
FIRST. Never commit `docs/leadv2/`, `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*`; commit by
LANE_WRITES pathspecs. English review-facing text. An uncommitted exit is a failed round.

## Review verdict on round 2 (reviewer opus) — FAIL, high=2
1. `kimi-coder.sh:1120/1135` — the journal target is `journal.jsonl` but the `tee` at :1135 has no `-a`,
   so it TRUNCATES the file and destroys every `worker_mcp_attached` / `worker_mcp_skipped` record on
   the only path the dispatcher uses.
2. `leadv2-dispatch-code.sh:5089` — the code-intel preamble is injected unconditionally for ALL arms,
   including codex (documented as unwired by this same diff) and every MCP fail-open path, so workers
   are told to call `mcp__*` tools that provably do not exist in their session.

## Do
1. `tee -a` (and audit every other `tee`/`>` onto a journal in the files under LANE_WRITES — list them in
   the report). Suite case: two consecutive journal writes → both records present.
2. Inject the preamble ONLY when the arm's MCP attach succeeded (`worker_mcp_attached` for that spawn);
   on skip/fail-open inject nothing (or a one-line "code-intel MCP unavailable in this session — use
   grep/Read" note). Suite cases: attached → preamble present; skipped → absent; codex → absent while
   codex stays unwired.
3. Mutation negative controls via the runner if `leadv2-mutation-control.sh` exists on main, else by
   hand in a scratch copy — RUN and paste red: drop `-a` → case 1 red; make the injection unconditional
   → case 2 red. Revert.
4. `leadv2-suite-falsifiable.sh` on the suite → FALSIFIABLE; `tests/run-all.sh --scope changed` line.
5. "## Round 3 evidence" in report.md; commit (pathspecs only).
