# developer.full.md — dispatch-6fccc10d (CODE-INTEL-IS-INSTALLED-AND-UNUSED-01, round 2)

Full analysis lives in the lane's own deliverable,
`docs/handoff/CODE-INTEL-IS-INSTALLED-AND-UNUSED-01/report.md` (committed in
the worktree at `.claude/worktrees/CODE-INTEL-IS-INSTALLED-AND-UNUSED-01`,
commit `232bb9ee`). This file is the condensed version for the review gate.

## What was delivered, in mission order

**Item 1 (widen census).** The brief's 5/5 fail_open was one session's logs.
Scanned every `journal.md` in the main leadv2 checkout's
`docs/leadv2/tasks/` (this worktree's own 290 journals predate the feature,
zero hits there) and every leadv2 worktree, persona-engine, respiro-ios.
Result: `15 codex arm_unwired`, `8 sonnet fail_open`, `5 glm-flash attached`.
**Attached does happen** — changes the diagnosis from "never resolves" to
"resolves for one arm, in one repo, and even then goes unused" (item 4).

**Item 2 (file:line root cause per arm).** `worker_mcp_preamble_for_arm()`
(`plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh:189-232`) collapses two
different causes into the same journal line:
- `sonnet` (8/8): `leadv2-worker-mcp.sh:199-206` returns `3` unconditionally
  unless `LEADV2_SUBSESSION_SLIM_MCP=1` (default `0`) — never calls the
  resolver at all; the child instead inherits the full unscoped MCP set.
- `glm/kimi/freepool`: `leadv2-worker-mcp.sh:207-215` calls
  `resolve_role_mcp_config()`, whose inline python
  (`leadv2-worker-mcp.sh:60-92`) returns `12` ("nothing resolved") when the
  project has no `.mcp.json`/`.claude/settings.json`/`~/.claude/settings.json`
  entry for the allow-listed server name — confirmed true for `m3`.
- `codex`: hard-coded `rc=4`, correct and intentional.

**Item 3 (fix the resolution, not the guard).** `resolve_role_mcp_config()`
is correct — proven by the 5 real `glm-flash attached` dispatches, each with
a `mcp-role-developer.resolved.json` on disk. The actual gap is per-repo MCP
wiring (item 11). Guard untouched, as required.

**Item 4 (prove a worker actually calls the tools) — the headline finding.**
Traced all 4 recoverable `glm-flash attached` dispatches to their
`~/.claude/cache/glm-runs/<handle>/journal.jsonl`. Every one has a resolved
config on disk (config really attached). **Every one has zero
`mcp__repowise__*`/`mcp__codebase-memory-mcp__*` tool_use blocks** — the
single `mcp__` string match in each file is the tool-name allowlist in the
session-init line, not a call. 0/4, not "unverified" — checked directly
against `"type": "tool_use"` blocks in the raw journal. This is the same
lying-green pattern the brief warned about, now confirmed as the current
state, not a hypothetical.

**Item 10 (real A/B or withdraw the claim).** Attempted a live
`mcp__repowise__get_answer` call from this very session for a "who calls X"
question — refused: `Claude requested permissions to use
mcp__repowise__get_answer, but you haven't granted it yet.` Could not run
the paired single-task A/B the brief required. Explicitly withdrawing that
specific claim; kept only the brief's pre-existing aggregate number
(persona-engine `measure-tool-cost.py`, 2026-08-25: 200K code-intel tokens
ever vs 8.19M Bash + 2.89M Read), clearly labeled as aggregate-not-paired.

**Items 6/11 (reachability + freshness).** Confirmed live via
`codebase-memory-mcp cli list_projects`: `m3` has a real 27010-node/
34831-edge index and no `.mcp.json`. Confirmed `m3`'s local `.repowise/`
directory is *not* actually built (only an empty `lancedb/` folder, no
`wiki.db`/`knowledge-graph.json`) — so only `codebase-memory-mcp` was worth
wiring, not `repowise`. **The write was attempted and refused**:
`Claude requested permissions to edit
/Users/kostiantyn.vlasenko/MythicalGames/m3/.mcp.json which is a sensitive
file` (outside the worktree; the WORKTREE PIN also argues against forcing
it). Exact JSON is in report.md.
LEAD_ACTION: apply it by hand at `/Users/kostiantyn.vlasenko/MythicalGames/m3/.mcp.json`,
never commit inside that repo. Same gap (no `.mcp.json`, index confirmed
present on the graph server) applies to `m3-trait`, `mondia-portal`,
`respiro-ios` — not attempted, listed for completeness only.
Freshness: no cron entry, no LaunchAgent references either tool.
persona-engine's index is 69 commits behind its own `last_sync_commit`
(verified via `git log <sha>..HEAD | wc -l` = 69) — nothing keeps it fresh
automatically today.

**Items 7-9.** No new production script changed this round, so no new
suite/EXTRA_SUITE_MAP row. `test-leadv2-code-intel-rate.sh` (round 1) proven
selected under `--scope changed` by the self-select filename convention
(`LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed`
lists it). Negative controls both directions are already covered by the
pre-existing `test-worker-mcp-all-arms.sh` (resolver-fails → fail-open case;
structural-check-passes-but-child-lacks-tools → behavioural case catches
it). Both suites green, exit 0, on macOS and in a `python:3.12-slim` Linux
container (mounted the main checkout's `.git` alongside the worktree so the
`gitdir:` pointer resolved) — raw output pasted in report.md.

**Lane hygiene.** `git diff --stat main..HEAD` showed 5 files this lane
would have deleted purely because it branched before `main` gained them
(4 handoff docs + `docs/leadv2/PLAN.md`) — restored verbatim from `main` in
two separate commits (`fae21d4b`, `51230ff6`), unrelated to this task's own
change. Final `git diff --stat main..HEAD` shows only the 3 files this task
actually adds (report.md + round-1's rate script/suite, both already
existing).

## Falsification set (paste, per the round-2 mission)

```
$ bash -n plugins/leadv2/scripts/leadv2-code-intel-rate.sh; echo $?
0
$ bash -n plugins/leadv2/scripts/tests/test-leadv2-code-intel-rate.sh; echo $?
0
$ bash plugins/leadv2/scripts/tests/test-leadv2-code-intel-rate.sh
[TEST] SUMMARY: 10 passed, 0 failed  (rc=0)
$ bash plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
[TEST] TOTAL: PASS=49 FAIL=0  (rc=0)
```
No python files changed this round. No production script changed this round
either (the item 3/11 fix is an out-of-repo config that could not be
applied) — so there is no code-level red-then-green pair for a change that
didn't happen; the falsifiable red-then-green evidence is the existing
mutation-control cases inside `test-worker-mcp-all-arms.sh` itself (all 49
passing, including every negative control).

## What is still open (not buried)

- `m3` (and `m3-trait`/`mondia-portal`/`respiro-ios`) MCP wiring: content
  ready, write blocked by permission — needs LEAD_ACTION.
- Paired single-task A/B for item 10: explicitly not done.
- `sonnet` arm's `LEADV2_SUBSESSION_SLIM_MCP` default: named, not changed —
  out of the brief's stated scope for this round.
- Index freshness (persona-engine 69 commits stale): documented, no
  reindex-on-commit mechanism designed or built — out of scope.

DELIVERABLE_COMPLETE
