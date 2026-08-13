# DISPATCH-FG-GUARD-01 (plugin repo ~/Projects/leadv2)

## Outcome
A long-running leadv2 worker launch can no longer be silently killed by the Bash tool's
foreground timeout, and a lane refused as live tells the caller how to proceed.

## Incident this fixes (2026-08-05, do not re-derive)
The lead ran `leadv2-dispatch-code.sh` in a foreground Bash call. The 2-minute tool timeout
SIGTERMed the process group mid architect-prepass. The lead then judged liveness from
`ls -la` mtime — 2 minutes old, because a dying process writes on its way out — and reported the
lane as working. It was dead for 38 minutes. Full causes:
`~/Projects/persona-engine/docs/handoff/DISPATCH-KILLED-BY-FG-TIMEOUT-01/causes.md`.

## Repo / base
Work in `~/Projects/leadv2`. Record `git rev-parse HEAD` there in your first line.

## Write set (allowed paths ONLY)
- `plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh` (new)
- `plugins/leadv2/hooks/hooks.json` (register the new PreToolUse Bash hook)
- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (C3 — message only, no behaviour change)
- `tests/` (the repo's existing hook test location)

## C1 — block the foreground launch
New PreToolUse hook on `Bash`, modelled on the existing `leadv2-block-fg-agent.sh`: same input
parsing, same fail-open `trap ... exit 0` discipline, same exit-code convention.

Deny a Bash command that invokes a long-running worker launcher when the call is NOT
backgrounded. Match by basename so path and alias variants are covered:
`leadv2-dispatch-code.sh`, `leadv2-codex-session-runner.sh`, `leadv2-fanout.sh`, `glm-coder.sh`,
`omp-task.sh`.

"Backgrounded" = the command ends in `&`, or uses `nohup ... &`, or `setsid`, or the tool call set
`run_in_background`. If the hook input exposes `run_in_background`, honour it; otherwise fall back
to the textual `&` / `nohup` / `setsid` test.

Exempt, so the guard never blocks legitimate quick calls: `--no-spawn`,
`LEADV2_DISPATCH_SPAWN=0`, the `status` and `record-review` subcommands, `--help`.

The deny message must state why (the 2-minute tool timeout SIGTERMs the process group) and the
exact corrected command to run instead. Override escape hatch: a trailing `# fg-dispatch: allow`
comment, matching the convention `leadv2-block-bash-heredoc.sh` already uses.

**Fail open.** A hook that errors must exit 0 — never wedge the lead out of dispatching.

## C3 — make the live-lane refusal actionable
In `leadv2-dispatch-code.sh`, the exit-5 `lane_is_live` refusal (around lines 582-595) prints the
reason and path only. Add the liveness verdict, its age in seconds, and the literal command to
re-run once it clears. Message only — no behaviour change.

## Non-goals
Do NOT touch the phase/pipeline structure — that is cause C4, a separate founder decision,
explicitly out of scope. Do not change routing, quota gates, or arm resolution.

## Acceptance
- A foreground `bash .../leadv2-dispatch-code.sh @mission.md` is DENIED, message contains the
  corrected command.
- The same command with a trailing `&` is ALLOWED.
- `status`, `--help`, `--no-spawn` are ALLOWED.
- `# fg-dispatch: allow` overrides the deny.
- Malformed/empty stdin exits 0 (fail-open).
- The repo's existing hook test suite passes from a clean base.

## Rollback
Remove the hook's entry from `hooks.json`. Name it explicitly in your report.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw test output. Do not edit boards or plans.
