# CONTINUATION-GUARD-01 — silence in chat must never mean "done"

Founder-reported defect (2026-08-12): during an active /leadv2 task the lead answers a
founder question, then goes silent — no continuation, no notification. The founder reads
silence as "everything finished". Nothing in the plugin prevents this today (audit
defect 3 confirms: no hook blocks ending a turn while a close-gate / task is in flight).

Build a plugin-default **Stop hook** `plugins/leadv2/hooks/leadv2-continuation-guard.sh`
(register in hooks.json next to leadv2-loop-detect / leadv2-compact-warn):

1. Fires on Stop. Cheap checks only (<100ms, offline): an active task exists
   (active.yaml sessions non-empty for this session's task, or LEADV2_TASK_ID env with
   no phase8-passed.flag) AND the ending turn made zero state-changing tool calls.
2. If both true → BLOCK with a short message: name the active task + its phase and
   demand either (a) a state-changing call / dispatched worker / armed watcher this
   turn, or (b) an explicit final line "работа продолжается: <что ждём>" /
   "задача закрыта: <артефакт>". Model persona-engine's promise-guard stop hook —
   read ~/Projects/persona-engine/.claude/hooks/ for its implementation as reference,
   but write plugin-generic (no PE paths).
3. Kill switch: LEADV2_CONTINUATION_GUARD=0. Loop safety: never block twice in a row
   for the same turn-id (track a sentinel under the task's handoff dir), so a hook
   fight cannot deadlock the session.
4. Tests: plugins/leadv2/scripts/tests/test-continuation-guard.sh — hermetic (all state
   under mktemp sandbox; NO reads of ~/.claude or real repo state): blocks on
   silent-stop-with-active-task; allows when watcher armed / worker dispatched / task
   closed / kill switch; never double-blocks.

Off-limits: leadv2-dispatch-code.sh, leadv2-dispatch-product-close.sh, test files owned
by E2E-GATE-RESIDUE-01 (its lane is running — do not touch its writes).

Deliverable: hook + hooks.json registration + test suite green (rc=0, output attached),
summary in docs/handoff/CONTINUATION-GUARD-01/summary.md, DELIVERABLE_COMPLETE.
