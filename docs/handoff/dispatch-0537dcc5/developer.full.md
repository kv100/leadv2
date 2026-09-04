verdict: APPROVE
next_action: review_round_2

# WORKER-MCP-ALL-ARMS-01 — fix-round 4 (developer, dispatch-0537dcc5)

## Starting state

Resumed the lane (worktree-WORKER-MCP-ALL-ARMS-01) from the committed wip
commit `55d3bcb5` ("R4 partial (nested subagent output; parent went silent
citing pulse mode)"). Merged `origin/main` first (clean, no conflicts, only
docs/handoff churn from other lanes) → new tip `4e2b8b54`. All 4 findings
from `docs/handoff/WORKER-MCP-ALL-ARMS-01/fix-round-4.md` were investigated
against the CURRENT tree before writing anything, per protocol §6.5
(unrecognized-entity rule) — I did not assume the wip commit's partial state
matched what the mission text described.

## Finding-by-finding

**1. `lib/leadv2-worker-mcp.sh:210` inverted fallback note.** Already fixed
on the wip commit: `worker_mcp_preamble_for_arm()` returns rc=3 with EMPTY
stdout on every fail-open branch (codex unwired=rc4, sonnet non-slim=rc3,
`LEADV2_WORKER_MCP=0`=rc3, unresolvable config=rc3, missing preamble
file=rc3) — no inverted "MCP unavailable" string survives anywhere. Verified
by reading the full function body and by the suite's own regression case
(`[TEST] PASS: preamble gate: fail-open branch stays silent`).

**2. `tests/test-worker-mcp-all-arms.sh:1163` grep-only assertion.** Already
fixed on the wip commit: `_run_spawn_worker_mission()` sources the REAL
`leadv2-dispatch-code.sh` (`LEADV2_DISPATCH_SOURCE_ONLY=1`), calls
`_spawn_worker_body` with a stub kimi launcher, captures the actual `bg`
argv, and asserts `CODE-INTEL ROUTING` is present in the mission text the
child receives — not just that the gate function is called. A negative
control mutates a scratch copy to delete the exact mission-fold line and
proves the structural (grep-only) check stays green while this behavioural
case goes red — the exact round-1 defect shape, now caught. Re-ran both
cases this round: both PASS.

**3. `report.md:253` `RUNALL_PLACEHOLDER`.** This was the one real gap.
Fixed this round:
- Found and cleared a stale `/tmp/leadv2-core-offline-*-WORKER-MCP-ALL-ARMS-01.lock`
  (holder pid 64695, confirmed dead via `kill -0`) that would have blocked
  the run.
- Attempted to reset `.git/worktrees/WORKER-MCP-ALL-ARMS-01/leadv2-run-all-last-checked-sha`
  per prior-round memory guidance ("range is consumed per run") — BLOCKED:
  this session's own permission layer refuses writes to any `.git`-internal
  path as "sensitive file" (tried both overwrite and `rm -f`, both refused).
  Documented in report.md rather than worked around; ran
  `tests/run-all.sh --scope changed` anyway, against whatever range the
  existing state file pinned.
- The command runs >10min (core-offline alone; confirmed by memory and by
  this run). The Bash tool's hard cap is 600s. Ran it DETACHED to a log file
  (`nohup ... &`, single-owner pid, no `Monitor`, no `isolation:"worktree"`)
  and foreground-polled the SAME turn across 3 waves of ~580s each
  (`kill -0 $pid` loop, never ending the turn while it ran) until it
  finished naturally — ~29 minutes wall clock, never left running past this
  message.
- Real output: `run-all: 3 passed, 1 failed, scope=changed`. The 1 failure
  is `run-core-offline.sh` (aggregates 83 suites, `passed=65 failed=20`).
  Audited all 20 against this round's 10-file diff:
  - `core-offline cross-run exclusive lock (SUITE-SPEED-01)`: its test file
    is untouched by this round; re-ran standalone (not inside the 4-shard
    concurrent run) → `pass=3 fail=0` clean. The full-run failure is lock
    contention from 4 concurrent shards + 5 other active leadv2 sessions on
    this machine, not a regression.
  - `dispatch arm vocabulary (kimi retirement)` and `dispatch refusal
    fallback chain`: both touch `leadv2-dispatch-code.sh`, which this round
    DOES modify — audited the actual diff hunks (source the shared MCP lib
    at top-of-file; the `worker_mcp_preamble_for_arm` call + mission-fold
    inside `_spawn_worker_body`). Both hunks are isolated to the code-intel
    preamble. The failing assertions are about arm-ladder fallback chains
    and quota-capped arbiter routing — a different subsystem this diff never
    touches. Pre-existing.
  - The remaining 17 touch none of this round's files and match the repo's
    documented pre-existing-red set.
  - `test-worker-mcp-all-arms.sh` itself is NOT registered in
    `run-core-offline.sh`'s suite list at all (confirmed via grep) — it is
    picked up separately by `--scope changed`'s stem mapping and ran green
    (see below), so it is not among either the 65 passed or 20 failed.
  Placeholder replaced with this real output + the audit, in
  `docs/handoff/WORKER-MCP-ALL-ARMS-01/report.md` §"Round 3 evidence §4" and
  a new "## R4 findings" section.

**4. `config/codex-mcp-servers.toml:283` evidence-free codex claim.** Already
fixed on the wip commit (the finding's line 283 doesn't exist — the file is
47 lines total; the pre-fix version was presumably longer). Independently
re-ran both probes this round rather than trusting the file's own claim:
- `LEADV2_ALLOW_DIRECT_CODEX=1 codex exec --help` → confirmed: only
  `-c/--config key=value` generic override exists, no dedicated MCP-server
  flag.
- `grep -c mcp ~/.claude/plugins/cache/openai-codex/codex/{1.0.3,1.0.4}/scripts/codex-companion.mjs`
  → `0` for both cached versions.
- `grep -n 'spawn(' <same files>` → line 643 in both, byte-identical:
  `spawn(process.execPath, [scriptPath, "task-worker", "--cwd", cwd,
  "--job-id", jobId], ...)` — the companion never shells out to `codex exec`
  on this path, so none of the `codex exec --help` flags (including `-c`)
  ever reach a codex process from here.
- `codex-task.sh:50`'s `find ~/.claude/plugins/cache/openai-codex -name
  codex-companion.mjs -path "*/scripts/*" | sort -V | tail -1` independently
  confirmed to resolve 1.0.4 over 1.0.3 (both installed).
The decision (no MCP wiring for codex this round, filed as follow-up) holds
on freshly-gathered evidence, not just the prior round's claim.

## Self-check (falsification set)

```
$ for f in $(git diff --name-only 258d018e..HEAD -- '*.sh'); do bash -n "$f"; done
codex-task.sh OK / freepool-coder.sh OK / kimi-coder.sh OK /
leadv2-dispatch-code.sh OK / lib/leadv2-worker-mcp.sh OK /
tests/test-worker-mcp-all-arms.sh OK / tests/run-all.sh OK
(no *.py files changed this round — py_compile n/a)

$ bash plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
[TEST] TOTAL: PASS=49 FAIL=0   (rc=0)

$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh \
    plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=234
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

## What I deliberately left alone

- The 20 pre-existing `run-core-offline.sh` failures (audited, none caused by
  this round's diff — see finding 3 above). Not this lane's scope to fix.
- `docs/leadv2/`, `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-*/phases.d/*.yaml`,
  `docs/leadv2/.bus*`, `docs/leadv2/active.yaml*`, `docs/leadv2/merge-queue.jsonl`,
  `docs/leadv2/tasks/*/journal.md` — all show as modified in `git status`
  (side effects of running the live orchestrator's shared bus/lock/registry
  machinery via `tests/run-all.sh`, and/or concurrent writes from the 5 other
  active leadv2 sessions on this machine). Left uncommitted per the mission's
  explicit constraint ("Never commit docs/leadv2/, LEAD_V2_STATE.md,
  phases.d/, plugins/leadv2/scripts/docs/") and per the general rule against
  touching shared state that may belong to concurrent sessions.
- Could not reset `.git/worktrees/.../leadv2-run-all-last-checked-sha`
  (permission-guarded as a sensitive file); documented instead of worked
  around.

## Commits this round

- `2a4fc7d7` — `docs(WORKER-MCP-ALL-ARMS-01): R4 findings table + real
  run-all --scope changed evidence` (report.md only; all code fixes were
  already on the wip commit `55d3bcb5`).
- Merge commit `4e2b8b54` — `origin/main` merged first, per mission.

Lane state: tree clean for all LANE_WRITES-scope paths, `main` merged,
`test-worker-mcp-all-arms.sh` PASS=49 FAIL=0, falsifiable, no placeholder
tokens remain in `report.md`.

DELIVERABLE_COMPLETE
