# IDLE-LEAD-GUARD-01 — fix round 2 (plugin repo ~/Projects/leadv2)

Round 1 is commit `c4a6dda` in worktree `.claude/worktrees/02a2c572`. Reviewed and **BLOCKED**.
Continue from those edits — do not start over. Full review:
`~/Projects/persona-engine/docs/handoff/DISPATCH-KILLED-BY-FG-TIMEOUT-01/idle-guard-review.md`.

Both critical findings were reproduced live. Both fail in the direction that causes harm. The rule
for this whole file: **when in doubt, allow the stop.** A hook that wedges an interactive session
is far worse than one that misses a stop.

## F1 — BLOCKING. Unwritable state dir permanently defeats the iteration cap → infinite block loop.
`leadv2-idle-lead-guard.sh:198` swallows the counter write with `|| true`, so the counter file is
never created, every later run re-reads `count=0`, and the cap at :77 never fires. Reproduced:
`chmod 555` the state dir, run the hook 10× with a queued row and zero live lanes — every call
blocks, counter frozen at 1/8 forever. This is the exact infinite loop the cap exists to prevent,
and the cap is the ONLY protection, since Anthropic's docs confirm no built-in consecutive-block
limit.

Fix: if the counter cannot be persisted, ALLOW the stop. A cap that cannot count must not block.

## F2 — BLOCKING. The pending-question check silently no-ops in the wrong direction.
Lines 90-117: if `QDIR` resolves empty — e.g. `leadv2-state-path.sh` missing or broken — the whole
pending-founder-question guard is skipped and execution proceeds as if no question were pending.
Reproduced: a real `status: pending` question file present, QDIR resolution broken → the hook still
emitted a block whose reason said "no pending question". That blocks the lead precisely while it is
waiting for a human answer.

Fix: if QDIR cannot be resolved, ALLOW the stop. Unknown question state is not evidence that no
question is pending.

## F3 — the tests miss both, by construction.
Case 5 (the cap loop) uses a writable state dir throughout. Case 4 and every `7x` case set
`LEADV2_IDLE_GUARD_QUESTIONS_DIR` directly, so the `leadv2-state-path.sh` resolution path is never
executed by any test.

Add tests that FAIL against `c4a6dda` and pass after the fix:
- state dir unwritable (`chmod 555`) + queued work + 0 live lanes → ALLOWS the stop; assert the
  hook does not block on the 2nd, 5th and 10th consecutive call.
- `leadv2-state-path.sh` unresolvable/absent, with a real pending question present → ALLOWS the stop.
- QDIR resolvable and a pending question present → ALLOWS, reason mentions the pending question.
- the existing cap test, but with the state dir writable, still reaches the cap at 8.
Show both runs (against `c4a6dda` and after) in your report.

## F4 — Medium, fix while here
The `stop_hook_active` comment at :23 claims the field is read for telemetry; nothing reads it
anywhere. Either read it or delete the comment — a comment that describes behaviour the code does
not have is how today's whole incident started. Counter files never expire; add an age-based reset.

## F5 — NEW REQUIREMENT (founder ruling 2026-08-05, binding)
**The founder typing anything by hand is excluded as a mechanism.** `/goal` is therefore not an
acceptable answer; neither is a session cron. Two consequences for this hook:

1. **Drive to a RESULT, not to an empty queue.** The block condition today is "queued rows exist",
   so the loop terminates when rows run out — which also happens when rows are merely closed.
   Add an optional goal/done-state: a declared session outcome the hook checks, and terminate on
   the outcome. Where the outcome cannot be expressed, say so plainly in your report rather than
   faking a condition.
2. **The plugin must arm the loop itself at SessionStart**, so nothing depends on a human
   remembering. Add the SessionStart wiring in this round, or report BLOCKED explaining why it
   cannot be done from a hook — do not silently leave it to the founder.

## Write set
Same as round 1, plus the SessionStart hook file and its `hooks.json` entry if F5.2 needs one.

## Base
Stay in worktree `02a2c572`. Round 1 skipped the rebase: do `git fetch origin && git rebase
origin/main` first and record the SHA.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw output of both test runs.
