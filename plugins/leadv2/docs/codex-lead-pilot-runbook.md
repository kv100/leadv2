# Codex lead pilot runbook

## Premise

This is a one-working-block experiment in which a Codex CLI lead uses the existing
leadv2 dispatcher to launch Claude/GLM workers. The legal composition question is
already settled by the cited research: the clients remain separate; the open question
is whether hook-free orchestration improves outcomes per unit of measured cost.
Do not judge the experiment from a drop in Claude burn alone.

## Install and launch

Do not overwrite `~/Projects/persona-engine/AGENTS.md`: it contains the existing
product guardrails. Install this additive pilot brief instead:

```bash
cp plugins/leadv2/docs/codex-lead-AGENTS-pilot.md \
  ~/Projects/persona-engine/.claude/ref/90-codex-lead-pilot.md
# Append exactly this one line to ~/Projects/persona-engine/AGENTS.md:
@import .claude/ref/90-codex-lead-pilot.md
```

`UNVERIFIED:` import resolution has not been demonstrated in persona-engine; the
existing import is written as `@import ref/01-orchestrator.md` although its file is
at `.claude/ref/01-orchestrator.md`. In minute one, ask the new session to quote a
line from this brief before it can dispatch.

Open exactly one session from persona-engine:

```bash
cd ~/Projects/persona-engine
command codex -m gpt-5.6-sol -c model_reasoning_effort=xhigh -s workspace-write
```

`command` bypasses a shell alias. Verify the effective binary/options locally before
launch; do not use an alias that adds a sandbox-bypass flag. The model and effort
flags are belt-and-braces for the configured pilot defaults. Work for one block only:
two to four named tasks, no marathon; reset the session rather than compacting it.

## Task menu

Select two to four Standard-class tasks from `docs/tasks.yaml` by criteria, not ID:

- one subsystem and at most two write paths;
- acceptance demonstrable by a file artifact or a live probe the founder can repeat;
- reversible: no publish path, payment, or migration;
- premise re-provable at dispatch time; and
- not parked in `docs/leadv2/burn-deferred.*`.

Exclude every item on the Codex-FULL not-for list. Keep WIP at one: a review or fix
round is still the active task.

## Dispatch door

Use the existing dispatcher once per lane and record its returned handle and status
in the ledger. Its invocation is task-specific; do not hand-write a `claude -p`
command.

| rc | Meaning | Required lead action |
| --- | --- | --- |
| 0 | lane launched or resolve-only success | Record the handle and wait for its evidence. |
| 1 | usage or internal failure | Correct the invocation; never retry it verbatim. |
| 2 | duplicate task signature | Do not relaunch: the work is already in flight. |
| 3 | lock unavailable or architect prepass parked | Surface the decision; this call is terminal until answered. |
| 4 | all arms refused/unavailable | Terminal for today; do not poll or retry until a real premise changes. |
| 5 | lane worktree placement refused | Create the named worktree or choose a valid ref, then retry. |
| 6 | burn cap parked the task | Correct stop: record the park and stop dispatching; never raise the cap. |

## Review door

Review every completed lane before merge:

```bash
bash plugins/leadv2/scripts/leadv2-review-run.sh \
  --task <task-id> --root <lane-worktree> --handoff <handoff-dir> \
  --diff <diff-file> --author <author> [--fanout <n>]
```

| rc | Meaning | Required lead action |
| --- | --- | --- |
| 0 | passed | Only now may the accepted diff proceed. |
| 2 | missing/bad flags | Fix the call; no merge. |
| 6 | blocked: lost or empty review body | Retry once with a different arm; a second block parks. |
| 7 | review failed | One bounded fix round against named findings, then review again. `do_not_merge=1` is absolute. |
| 8 | round or spawn cap | Escalate or park; never loop. |
| 9 | unreviewed: no arm available | Not a pass; park or escalate. |

**A `review-gate.md` file is not a verdict. Read `status:`: only rc=0 and `status: pass`
permit progress.**

## Measurement protocol

Before and after the working block, preserve separate snapshots and run the digest:

```bash
for f in ~/.claude/state/leadv2/quota-cache/anthropic.json \
         ~/.claude/state/leadv2/quota-cache/glm.json \
         ~/.claude/state/leadv2/quota-cache/codex.json; do
  printf '%s\n' "=== $f"; cat "$f"
done
bash plugins/leadv2/scripts/leadv2-quota-status.sh
```

Pre-flight passes only when the digest reports a non-zero `burn24h`; `no_telemetry`
or zero disables the burn gate and makes the pilot inconclusive. Preserve the raw
before/after output in the pilot log, together with the Codex TUI rate-limit reading.

| Measure | Before / after source | Interpretation |
| --- | --- | --- |
| Claude-Max and GLM | `anthropic.json`, `glm.json`, plus quota-status output | Compare cost to accepted outcomes, never alone. |
| Codex | `codex.json` plus manually pasted Codex TUI rate-limit reading | Required counterweight to Claude burn. |
| Delivery | ledger rows | Count landed, stalled, and parked from the ledger, not handoff directories. |
| Founder load | tally marks | One mark whenever the founder corrects or unblocks the lead. |

The quota script states that its burn database has no Codex rows; it must never be
read as Codex zero usage. See [quota-status source](../scripts/leadv2-quota-status.sh).

## Transcript checklist

The lead has no Claude hooks. The reviewer checks the transcript for each observable:

| Would-have-been gate | Observable |
| --- | --- |
| shared/canonical edit guard | No edits under `~/.claude/leadv2-shared/` or canonical `plugins/leadv2/**` scripts. |
| worktree enforcement | Every write is under the active lane worktree. |
| lead-edit/no-Opus-code rule | Lead delegated application-code changes rather than making them. |
| heredoc guard | No Bash heredoc used. |
| close ritual | Ledger, evidence, review verdict, and close state are all recorded. |
| memory/state discipline | State is in the documented ledger/journal locations, with append-only journals. |
| task-output discipline | No hidden task-output shortcut replaces evidence. |
| monitor cap | No uncontrolled polling or concurrent WIP. |
| deny floor | No destructive `git reset`, `git clean`, or `rm -rf` in a shared tree. |
| foreground dispatch | Each started verification/dispatch result is waited for and recorded. |

`block-codex`, `codex-direct-exec-guard`, and `codex-first-nudge` do not transfer:
they stop a Claude lead from invoking Codex, while this pilot's lead is Codex.

## Pre-registered decision

Confirm these thresholds before launch; do not revise them from the outcome.

- PASS: at least 2 lanes reach an accepted reviewed diff (review rc=0 and `status: pass`), founder interventions are at most 3, there are zero checklist violations that would have been blocked, Claude 24-hour burn is no higher than a comparable Claude-lead day, and Codex consumption is recorded.
- FAIL: any merge on review rc=9, review rc=6, or `do_not_merge=1`; any shared-tree/canonical-plugin edit; more than 5 founder interventions; or zero landed lanes.
- INCONCLUSIVE: burn telemetry is absent/zero, or the Codex-side number is missing.

## Rollback

Delete the one `@import .claude/ref/90-codex-lead-pilot.md` line and close the Codex
session. Lane commits remain ordinary commits, kept or reverted on their own merit.

## Deliberately excluded from the brief

The ≤150-line brief omits the full 33-guard list, supervisor/fanout mode,
Codex-FULL/session-runner recursion, Kimi and ladder-spill behavior, detailed retry clauses,
MCP tooling, model-pinning workflow, and measurement instructions. Those are not active
mechanisms for this single-lead pilot.
