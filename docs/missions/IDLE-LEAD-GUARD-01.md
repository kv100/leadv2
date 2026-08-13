# IDLE-LEAD-GUARD-01 — build (plugin repo ~/Projects/leadv2)

## Outcome
The lead cannot end a turn while work is queued and no lane is live. Autonomy stops depending on
the founder remembering to type `/goal`.

## Problem (verified 2026-08-05)
Emitting chat text ends the turn; an interactive session has no continuation loop, so every status
report is simultaneously a full stop. `hooks.json` registers six Stop hooks (force-reflect,
auto-clear-after-close, lead-prose-guard, bg-stop-warn, supervise-sentinel-cleanup, promise-guard)
and **none** refuses a turn end while work remains. Two standing memories already state the rule
(`feedback-never-end-turn-on-a-promise`, `feedback-turn-ends-only-when-queue-is-refilled`) and it
has no enforcer — the same rule-without-a-reader defect fixed earlier today in the fg-dispatch guard.

`/goal` (https://code.claude.com/docs/en/goal) is real and is the same mechanism, but it is
session-scoped and human-typed. This hook is the plugin-owned equivalent that needs nobody to
remember anything.

## Repo / base
`~/Projects/leadv2`. First action: `git fetch origin` then `git rebase origin/main` (NOT
`--ff-only merge` — it fails once the lane has its own commits). Record the SHA.

## Write set (allowed paths ONLY)
- `plugins/leadv2/hooks/leadv2-idle-lead-guard.sh` (new)
- `plugins/leadv2/hooks/hooks.json` (register the Stop hook)
- `plugins/leadv2/scripts/tests/test-idle-lead-guard.sh` (new)
- `plugins/leadv2/scripts/tests/run-core-offline.sh` (register the test)

## Hook contract — confirmed against official docs, use exactly this
- exit 0 + stdout `{"decision":"block","reason":"<next action>"}` → forces another turn, reason is
  fed back as guidance.
- exit 2 → also blocks; stderr becomes the reason.
- `{"continue":false,"stopReason":"..."}` → hard stop regardless.
The "8 consecutive blocks" cap and a `stop_hook_active` field could **NOT** be confirmed in
Anthropic's own docs — only in third-party blogs. **Do not rely on them.** This hook MUST carry its
own iteration cap.

## Requirements

**R1 — block condition.** Block the stop when ALL hold:
(a) there is queued/ready work — a `status: queued|ready` row in the project's task store, or a
lane worktree with uncommitted changes and a dead liveness probe;
(b) zero lanes are live — use `leadv2-lane-liveness.sh`, the authoritative probe. **Never** infer
liveness from file mtime or directory existence; both lied today and caused a false ALIVE report;
(c) no founder question is pending (check the control-plane questions path via
`leadv2-state-path.sh questions`).

**R2 — the reason must name the next action**, not scold. e.g.
`2 queued rows, 0 live lanes. Next: dispatch a2079527a14e (comment topic gate).` A vague reason
produces a vague next turn.

**R3 — own iteration cap.** Count consecutive blocks in a per-session state file. Default cap 8,
override `LEADV2_IDLE_GUARD_MAX_BLOCKS`. At the cap, stop blocking and emit a one-line warning so
the lead can hand back to the founder. Reset the counter whenever a stop is allowed.

**R4 — fail open, always.** Any error, unparseable input, missing task store, or missing probe →
exit 0 with no output. A hook that wedges the lead into an infinite loop is far worse than one
that misses a stop.

**R5 — kill switch.** `LEADV2_IDLE_GUARD=0` disables it entirely.

**R6 — do not fire outside leadv2 work.** If the project has no leadv2 task store / no
`docs/leadv2/`, exit 0 silently.

## Non-goals
Do not touch `/goal`, the other six Stop hooks, the dispatcher, or routing. Do not add a heartbeat
or cron — out of scope.

## Acceptance (each a fixture test, no live lane needed)
- queued work + zero live lanes + no pending question → BLOCKS, reason names a specific task id.
- queued work + one live lane → allows the stop.
- zero queued work → allows the stop.
- pending founder question → allows the stop.
- 8 consecutive blocks → 9th allows the stop and warns.
- `LEADV2_IDLE_GUARD=0` → allows the stop.
- malformed stdin / missing task store / probe binary absent → exit 0, no output.
- a repo with no `docs/leadv2/` → exit 0, no output.
- Each new test must FAIL with the hook unregistered and pass with it registered — state this in
  your report and show the failing run. A test that passes both ways proves nothing.
- The core offline suite is green from the rebased base, EXCEPT the pre-existing failure in
  `supervisor reconciliation` (test-supervise-v2.sh Test 1a) which already fails on untouched main.

## Rollback
`LEADV2_IDLE_GUARD=0`, or remove the entry from `hooks.json`. Name it in your report.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw test output.
