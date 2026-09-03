# CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01

Founder, 2026-09-03: «арбитр должен ещё отталкиваться от квоты доступной и даты когда сбросится
квота недельная».

## The gap

The arbiter picks an arm from task class and from per-provider ceilings (`glm 80/90`, `codex 90/95`,
`claude 95`). Those ceilings are **percentages of a window**. The arbiter never sees:

1. how much is actually left in the current window, and
2. **when that window resets** — the weekly window and the 5-hour window reset on different clocks.

So it treats these two situations identically, and they call for opposite decisions:

| situation | right move |
|---|---|
| 85% burned, window resets in 20 min | wait, or take one cheap round on the same arm |
| 85% burned, window resets in 4 days | switch arms now — otherwise the week stalls |

## What this task must deliver

1. **A source of truth for remaining budget and reset time, per arm** (glm / codex / claude / kimi).
   Name the file:line it is read from. Say what happens when a provider does not publish a reset
   time — a missing value must degrade to a named, defensible default, never to a silent zero.
2. **The arbiter reads both and explains itself in the journal**, e.g.
   `route_resolved arm=X remaining=Y reset_in=Z reason=…`. A decision that cannot be read back
   from the journal did not happen.
3. **A wait rule versus a switch rule.** Near reset ⇒ wait or use a cheap arm; far reset ⇒ switch.
   The threshold must be argued from the measured shape of the windows, not picked.
4. **A negative control per claim**: forge a remaining value and a reset date, show the suite goes
   red, revert, show green.
5. Green on macOS and in a Linux container, exit codes pasted. Register any new suite in
   `tests/run-all.sh` and prove `--scope changed` selects it.
6. Commit in this lane before you finish.

Related: `CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01` (same arbiter, the safety axis) and
`LEAD-DOES-MACHINE-WORK-01` (today the lead does this arithmetic in its head).

Off limits: hardcoding an arm out of routing (see `feedback_never_hardcode_arm_exclusion`),
`tests/known-red-suites.txt`, weakening assertions.
