# CODE-INTEL-IS-INSTALLED-AND-UNUSED-01

The founder asked on 2026-09-03 whether we actually use repowise and the code graph, how often, and
whether it saves anything. The honest answer turned out to be measurable, and it is worse than
"we use them badly": **workers are never handed them at all.**

## Measured, 2026-09-03

Every dispatch emits one `code_intel_preamble` decision line
(`plugins/leadv2/scripts/leadv2-dispatch-code.sh:5280-5282`): `mode=attached` on rc=0,
`mode=skipped reason=fail_open` on rc=3, `mode=none reason=arm_unwired` on anything else.

Across every dispatch log reachable on this machine today:

    5  mode=skipped reason=fail_open
    0  mode=attached
    0  mode=none reason=arm_unwired

Five of five. **Not one worker in this sample was given the code-intel preamble.** The sample is
small — it is the logs this session had, not the full history — so the first job below is to widen
it, not to trust this number.

The fail-open is deliberate, and its reasoning is sound: `worker_mcp_preamble_for_arm()`
(`plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh:167-215`) refuses to inject a preamble that tells
a worker to call `mcp__*` tools unless that spawn will actually carry the role-scoped MCP config —
round 2 of `WORKER-MCP-ALL-ARMS-01` had injected it unconditionally, so codex (no MCP wiring) got
missions promising tools that provably did not exist. So the guard is right. **The question this
task must answer is why the config never resolves, not whether to remove the guard.**

## The cost side, for scale

Measured 2026-08-25 in persona-engine (`scripts/measure-tool-cost.py`): **Bash 8.19M tokens + Read
2.89M, against 200K for every code-intel MCP call ever made.** The tool that exists to make reading
cheap accounts for ~2% of what reading by hand cost. The heaviest single entries in both tools are
review diffs — one at 14,319 tokens, one file read twice at 7,383 each.

## Where it is even possible today

| repo | repowise index | MCP configured |
|---|---|---|
| persona-engine | yes | repowise + graph |
| leadv2 | yes | repowise only |
| pf3-backend | yes | repowise only |
| m3 | yes | **none** |
| getmany-followup-bot, respiro-ios, m3-market | no | none |

## What this task must deliver

1. **Widen the measurement before diagnosing.** Count `code_intel_preamble` outcomes across every
   journal and dispatch log on disk, not just this session's five, split by arm. If some arm does
   get `attached`, that changes the whole diagnosis — say so.
2. **Name why rc=3 is returned**, at a file:line, for each arm that fails. `resolve_role_mcp_config()`
   is the predicate; say what it is looking for and what is actually absent.
3. **Fix the resolution, not the guard.** The guard prevents lying to workers and must stay. A
   worker that is handed the preamble must genuinely have the tools.
4. **Prove a worker actually calls them.** A dispatch whose journal shows `mode=attached` AND whose
   stream contains at least one `mcp__repowise__*` or `mcp__codebase-memory-mcp__*` tool call. An
   attached preamble that no worker acts on is the same lying-green as no preamble.
5. **Make the rate visible.** The attach rate and the per-arm breakdown belong on a surface someone
   reads, so this cannot silently regress to 0/5 again.
6. **Wire `m3`'s MCP** — it has a repowise index and no MCP config, so its index is unreachable.
   Do not commit inside any MythicalGames repo; that config is local-only.
7. **A negative control per claim**: force the resolver to fail, show the suite red (a worker gets no
   preamble); revert, show green. And the reverse — force it to succeed with the tools absent, and
   show the guard still refuses.
8. Green on macOS and in a Linux container, exit codes pasted. Register any new suite in
   `tests/run-all.sh` and prove `--scope changed` selects it.
9. Commit in this lane before you finish.

Related: `SKILL-USAGE-IS-UNMEASURED-01` (same shape — a capability nobody can prove is used).

Off limits: `main`, `tests/known-red-suites.txt`, weakening assertions, removing the fail-open guard,
and injecting the preamble for an arm that has no MCP wiring.

## Added 2026-09-03 after the founder asked whether the savings are proven

They are not, and the brief above did not say so plainly enough. Two more deliverables:

10. **An A/B on one real task, or the savings claim is withdrawn.** Nobody has ever run the same
    task with and without code-intel and compared token cost. Until that exists, "these tools save
    tokens" is the tools' *purpose*, not a measured fact, and must not be stated as one. Pick a task
    of the shape they should help most — "who calls X", "where does this mechanism live", "what
    breaks if I change this" — run it both ways, and report both numbers even if the answer is that
    they cost more. A negative result here is a real finding and must not be buried.
11. **Reachability, per repo, made true.** The graph server holds 19 indexed projects, including
    `m3`, `m3-trait`, `pf3-backend`, `environment-platform`, `mondia-portal`, `respiro-ios`,
    `getmany-followup-bot` and `leadv2` — but a repo whose `.mcp.json` does not wire the server
    cannot reach its own index. Wire every repo that has an index. Separately, repowise in this
    workspace resolves only `persona-engine`, and that index is from **2026-08-31, commit
    `b9f5d20a`** — days behind. Say what keeps an index fresh and whether anything does it
    automatically today; a stale index that answers confidently is worse than no index.
    Local-only config in the MythicalGames repos — never commit inside them.
