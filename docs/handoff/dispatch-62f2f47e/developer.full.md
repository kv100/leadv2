# dispatch-62f2f47e — developer (fable arm) — nested-agents design report

## What was delivered

One file, as the mission's `LANE_WRITES` names it:
`docs/handoff/SMART-ARBITER-DESIGN-20260907/nested-agents-report-fable.md` (report only; no
workflow, script or config modified). Plus this protocol deliverable pair under
`docs/handoff/dispatch-62f2f47e/`, following the committed precedent of
`docs/handoff/dispatch-0672c002/developer.full.md` (cited at `leadv2-dispatch-code.sh:3223`).

## Decisions, one line each

1. **Depth 1: keep.** No task shape in this repo needs a grandchild; a "sub-orchestrator inside a
   lane" is a second lead with no registry, journal or LANE_WRITES. Depth 1 has never even been
   exercised.
2. **read_only: keep** for what the yaml governs (Agent-tool subagents spawning). It does not
   reach lane workers at all — the guard's nested path fires only on `agent_type`, which headless
   lane sessions do not present (inferred, tagged UNVERIFIED in the report). LANE_WRITES is
   agent-blind at close, so a worker's write-capable child is already consistent with the
   contract.
3. **Arbiter picks: yes, and it already must** (spawn-arbiter-gate, founder order 2026-09-04).
   The static allowlist stacked on top is what makes both entries unreachable. Same seam as
   `10ee163f7a3e` (arbiter decides `freepool-default` for recon/Explore; Agent tool cannot run it).
   Not ready to ship from this report.
4. **Codex/GLM: a second question**, different executor (Bash-launched `codex exec`/`mcp-server`)
   and different hooks. Not answered here.

## Measured facts that drove the decisions (artifacts in the report §0)

- `nested-spawns.log` whole history: 2 lines, one 2026-08-04 event, `verdict=deny
  reason=route.subrun.write_role_denied`; zero `verdict=allow` ever; zero `escalation-budget.yaml`
  ever written. Scorecard `nested_spawns` has therefore always read 0.
- Arbiter journal (359 rows): all 4 `recon`/`Explore` decisions → `freepool`/`freepool-default`.
  With inherit-guard (Explore needs explicit model), arbiter-gate (pinned model must equal decided
  model, `:96`) and routing-guard allowlist (haiku|sonnet only), no spawn form passes.
- `LEADV2_TASK_ID` is exported by codex/kimi runners only; `leadv2-dispatch-code.sh` has 0 hits, so
  the per-task count cap takes the "never cap" branch for every Claude lane.
- `direct-spawn-gate.jsonl`: 94 rows, deny 45 / sanctioned_bypass 39 / allow_with_reason 10, gate
  mode default `warn` — write-capable children are being spawned, unattributed to lanes.
- `codex --help` (0.153.4): `agents exec mcp-server app-server` exist; `exec-server`, `cloud` do not.

## Measurement seams named per recommendation

| Q | Value | Today | Emitted at | Negative control |
|---|---|---|---|---|
| 1 | `depth_exceeded` deny count | 0 | routing-guard.sh:166 | max_depth 2 in scratch override + spawn from explore caller |
| 2 | per-lane Agent-spawn count | does not exist | would be routing-guard.sh:86-103 once LEADV2_TASK_ID is exported | launch lane without export → no per-task log |
| 3 | `verdict=allow` count; recon/Explore→freepool rows | 0 for life; 4/4 | routing-guard.sh:237,270; arbiter journal | admit freepool in executor filter → allow stays 0 |

## Deliberately left alone

- No edit to `nested-spawn-policy.yaml`, `leadv2-routing-guard.sh`, `NESTED-SPAWNS.md`, the lane
  prompt, or any hook — mission is report-only.
- Did not re-diagnose `10ee163f7a3e` beyond confirming the unreachability with journal rows.
- Did not read or wait for the second arm's report.
- No founder question opened; the three undecidable items are listed in the report's "Open at my
  level" with what would settle each.

## Self-check (raw output)

No shell or Python file changed → `bash -n` / `py_compile`: nothing to check.

Changed-scope runner, foreground, timeout 300s:

```
$ timeout 300 bash plugins/leadv2/scripts/tests/run-core-offline.sh --scope=changed
[CORE-OFFLINE] scope=changed running 0 of 95 suites (base=main@34e9fefa05, 0 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=0 total=95 base=main@34e9fefa05 changed=0 unmapped=0 verdict=nothing_to_run reason=no_relevant_changed_files
[CORE-OFFLINE] suites passed=0 failed=0 missing=0 verdict=nothing_to_run reason=no_relevant_changed_files repo=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/40c0337e885f
```

Docs-only diff: the runner correctly selects nothing (the behaviour landed in base commit
34e9fefa). No red-then-green cycle exists for a report.

## Tool-call budget

14 tool calls before writing; 3 writes; 1 commit. Under the 30-call cap.

DELIVERABLE_COMPLETE
