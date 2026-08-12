# CONTINUATION-GUARD-01 — Summary

## Defect

During an active `/leadv2` task the lead answers a founder question, then goes
silent — no continuation, no notification. The founder reads silence as
"everything finished". Nothing in the plugin prevented this (audit defect 3).

## Solution

New Stop hook `leadv2-continuation-guard.sh` that blocks when:
1. An active task exists (`active.yaml` sessions non-empty, or `LEADV2_TASK_ID`
   env set without `phase8-passed.flag`), AND
2. The ending turn made zero state-changing tool calls.

The block message names the active task + its phase and demands either:
- (a) a state-changing call / dispatched worker / armed watcher, or
- (b) an explicit final line: "работа продолжается: \<что ждём\>" /
  "задача закрыта: \<артефакт\>".

### State-changing tools recognised

Edit, MultiEdit, Write, NotebookEdit, Agent, Workflow, SendMessage, Monitor,
Task*, Bash with git-commit/dispatch/install/sed -i/etc.

### Kill switch

`LEADV2_CONTINUATION_GUARD=0` disables the hook entirely.

### Loop safety

Three layers prevent deadlock:
1. `stop_hook_active` canonical field (honoured → exit 0 on retry).
2. Per-session sentinel file — blocks at most once per session turn; the
   sentinel is auto-cleared on the next invocation.
3. ERR trap exits 0 (fail-open: a crashed hook never wedges the session).

## Files changed

| File | Change |
|---|---|
| `plugins/leadv2/hooks/leadv2-continuation-guard.sh` | **NEW** — Stop hook |
| `plugins/leadv2/hooks/hooks.json` | Register hook in Stop section |
| `plugins/leadv2/scripts/tests/test-continuation-guard.sh` | **NEW** — 13-case hermetic test suite |

## Test results

```
13 passed, 0 failed (rc=0)
```

Cases: silent-stop-with-active-task (block), Edit/Bash-commit/Agent/Monitor
(allow), continuation/close phrases (allow), closed task (allow), no active
task (allow), kill switch (allow), stop_hook_active (allow), double-block
sentinel (allow on retry), LEADV2_TASK_ID env (block).

## Pattern lineage

Modelled on `leadv2-promise-guard.sh` (same Stop-hook sentinel/anti-loop
approach, same transcript reconstruction logic) but addresses a different
defect: promise-guard catches *forward-tense commitments with no action*;
continuation-guard catches *any silent stop during an active task*. The two
hooks are complementary — continuation-guard fires even without a commitment
shape, which is exactly the gap the defect described.
