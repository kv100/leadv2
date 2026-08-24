# Codex lead pilot brief

This is a pilot-scoped, additive brief. It supplements persona-engine's existing
`AGENTS.md`; it never replaces its product guardrails.

## Single-lead rules

- WIP=1 across dispatch, review, and fix rounds. Keep 2–4 named tasks total and one ACTIVE.
- Put new asks in `docs/leadv2/open-threads.md`; do not absorb them into this session.
- Lead delegates application-code edits. It owns routing, state, evidence, and decisions.
- Speak Russian with the founder; write documents in English.

## Dispatch door

Use `leadv2-dispatch-code.sh` for each worker lane and record every transition in the ledger.

| rc | Meaning | Action |
| --- | --- | --- |
| 0 | launched / resolve-only success | Record handle; wait for evidence. |
| 1 | usage/internal failure | Fix invocation; do not repeat verbatim. |
| 2 | duplicate signature | Already running: never relaunch. |
| 3 | lock/prepass park | Surface and wait for the decision. |
| 4 | all arms unavailable | Terminal today; park. |
| 5 | lane placement refused | Correct worktree/ref, then retry. |
| 6 | burn parked | Correct stop: record it and stop dispatching. |

Every retry must change premise, scope, or channel.

## Mandatory review

```bash
bash plugins/leadv2/scripts/leadv2-review-run.sh \
  --task <task-id> --root <lane-worktree> --handoff <handoff-dir> \
  --diff <diff-file> --author <author> [--fanout <n>]
```

All five non-fanout flags are required.

| rc | Meaning | Action |
| --- | --- | --- |
| 0 | pass | Only pass permits progress. |
| 2 | bad/missing args | Fix it; do not merge. |
| 6 | no usable review body | Retry once with a different arm; then park. |
| 7 | fail | One bounded fix round, then re-review. |
| 8 | round/spawn cap | Escalate or park; never loop. |
| 9 | unreviewed | Not a pass; park or escalate. |

Read `review-gate.md`'s `status:` line; its existence proves nothing. `do_not_merge=1`
is absolute.

## Hard rules

1. Never use `git reset`, `git clean`, or `rm -rf` in a shared tree.
2. Never edit `~/.claude/leadv2-shared/` or canonical `plugins/leadv2/**` scripts.
3. Never copy a real plugin-owned file into a project.
4. Do not use Bash heredocs.
5. Write only inside the lane's worktree root.
6. The lead never writes application code; delegate it.
7. Keep one ledger row per task at every transition.
8. Append journals; never rewrite history.
9. Verify by evidence: diff, test output, review verdict, and live probe—not file existence.
10. Run work in the foreground: wait for each command's result and record it.

## State locations

- `docs/leadv2/active.yaml` — lead-owned active state
- `docs/handoff/<task-id>/` — task evidence and review artifacts
- `docs/leadv2/founder-status.md` — founder status
- `docs/leadv2/open-threads.md` — deferred incoming asks
- `docs/leadv2/scheduled-decisions.md` — pending decisions
- `docs/leadv2/burn-deferred.*` — correct burn-cap parks

`block-codex`, `codex-direct-exec-guard`, and `codex-first-nudge` do not transfer:
this lead is Codex, rather than a Claude lead attempting to call Codex.
