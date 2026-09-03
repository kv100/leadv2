# D2 — pre-brief evidence: the liveness verdict needs a pinned pattern, not a habit

Measured twice, independently, by two lead sessions on 2026-09-03. Carry this into the D2 brief as
a **named acceptance criterion**, not as background.

## The finding

"Liveness is decided by `ps`, not by mtime" is not yet a rule — it is half a rule. `ps` with the
wrong pattern returns a confident zero for a lane that is writing at that same second.

Session `fb`, six wave-3 lanes:

| pattern | result |
|---|---|
| `ps aux \| grep -F "worktrees/<name>"` | **0 for all six** — including a lane whose stream mtime was 1 second old |
| `ps aux \| grep -F "<name>"` | 4 and 2 processes on two of them |

Session `c2`, three of its own lanes, run back to back:

| lane | narrow `worktrees/<name>` | free `<name>` |
|---|---|---|
| LANE-MERGE-SILENTLY-REVERTS-MAIN-01 | 0 | **4** |
| TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01 | 0 | 1 |
| CODE-INTEL-IS-INSTALLED-AND-UNUSED-01 | 2 | 3 |

Cause: a lane's processes do not all carry the lane name adjacent to `worktrees/` on their command
line. The narrow pattern matches only some of them, and matches none for some lanes.

Consequence, already paid: `c2` declared seven lanes dead using the narrow pattern. The verdict
happened to be right — no commits were moving and the deaths coincided with an editor process
exiting — but the method was unsound. **A right answer from an unsound method is not evidence**, and
next time it will be a wrong answer.

## What this makes D2 responsible for

Not "a function that returns liveness". Specifically: **one pinned pattern, chosen once, in one
function**, so no lead reinvents it and gets its own zero. If every lead writes their own `ps`
invocation, D2 has not been delivered no matter how good the function is.

## Acceptance criterion for D2's suite — write it exactly this way

The suite must **catch the false zero of the narrow pattern**, not merely check that the function
returns something.

Concretely: stand up a fixture lane whose worker process carries the lane name WITHOUT an adjacent
`worktrees/` on its command line — that is the real shape that produced every zero above — then
assert that the liveness function reports it ALIVE. A suite that only asserts "alive lane reports
alive" using a conveniently-named fixture passes today and would have passed all through the
incident; it proves nothing.

Add the mirror case: a genuinely dead lane must report dead, so the fix cannot be "always return
alive".

Negative control: the mutation goes INSIDE the liveness function's body — revert it to the narrow
pattern — and the suite must go red. Proof is the `baseline_rc` / `mutated_rc` pair plus the literal
red suite line. Register the suite in `EXTRA_SUITE_MAP` in `tests/run-all.sh` and prove
`--scope changed` selects it; of the 23 suites the plan assumed, the runner can currently reach 9,
and an unregistered suite rots silently.
