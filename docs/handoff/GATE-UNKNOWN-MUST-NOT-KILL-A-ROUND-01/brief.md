# GATE-UNKNOWN-MUST-NOT-KILL-A-ROUND-01 — a gate that timed out said "I don't know", not "no"

## The defect

Five lanes were lost to the closing e2e gate in a single day. In every one of the five the worker had
finished and committed; what was missing was a verdict:

```text
status: unknown
reason: e2e_timeout
rc: 124
timeout_s: 900
```

`unknown` is not a failure. The gate did not judge the work — it ran out of time. Yet the round ends
there: the lane is left with no verdict, no resumption, and a human has to notice that the tree still
holds finished work. That happened five times today, and finished-but-abandoned work was found in a
worktree on five separate occasions, four of them from exactly this.

**This lane is not about making the gate faster.** Load fluctuates and always will. The defect is a
decision in the code: an inconclusive gate terminates a round. That decision can be changed.

## What to build

A round whose gate returns `unknown` must remain **resumable**, and the state must say so in a way a
later reader — human or script — can act on without re-deriving anything:

1. **The verdict is preserved as inconclusive, not as an end.** `unknown` must be distinguishable
   from `fail` at every consumer that reads the gate's output. Find those consumers before you change
   the writer: a fix that only edits `e2e-gate.md` while a reader still treats "not pass" as "fail"
   changes nothing.
2. **The round records what it would need to resume** — the commit under test, the gate that did not
   answer, and the reason. Enough that resuming does not mean re-running the whole round.
3. **The lane must not be left looking dead.** Whatever the pulse and lane-state derive from the gate
   has to show "gate inconclusive, work committed", never silence.

Do not build a retry loop that re-runs the gate immediately on the same loaded host — that is how the
five lanes were lost in the first place, and it turns one timeout into two.

## Where to look

- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` — writes
  `leadv2-dispatch-product-close: e2e suite TIMED OUT after 900s` and the `e2e-gate.md` verdict.
- The consumers of that verdict: whatever reads `e2e-gate.md` / `e2e-gate.log`, and whatever decides
  a round is over. Enumerate them and say which ones conflate `unknown` with `fail`.
- `docs/handoff/dispatch-*/e2e-gate.md` on this machine carries five real examples from today. Use
  them as fixtures instead of inventing a shape.

## Acceptance

- **The behavioural proof:** drive a round whose gate returns `unknown` (a fixture gate that exits
  124 is fine — do not burn 900 s), and show from the state on disk that the round is resumable and
  the lane does not read as dead. Paste before and after.
- **A negative control per changed function**, mutation applied INSIDE the function body, reported as
  the observed `baseline_rc` / `mutated_rc` / `restored_rc` triple. Never a `diff_hash`, never a code
  inferred from a tool's verdict.
- Assert each mutant **differs from the original byte for byte** before running it: a mutation whose
  anchor stopped matching writes nothing and reads as a control that passed.
- **Under each mutation the red assertions must share no cause but the named one.** If a mutation
  reddens three cases that all trace back to one branch, that is one witness, not three — say so, or
  separate the cases.
- A control that reddens the suite by crashing it or breaking the parse does not count.
- Falsification: remove the assertion on any message text, keep the assertion on state — the control
  must stay RED.
- **Ten consecutive runs**, all exit codes reported, **under bash AND zsh**. Two suites shipped today
  were blind under zsh: one aborted at line 41 with rc=127 before its first assertion, the other ran
  and reported every known defect as absent. A suite that did not execute must never resemble one
  that found nothing — if yours is bash-only by mechanism, re-exec under bash or refuse loudly with a
  named reason, never skip quietly.

## Bounds

- Do NOT edit `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`,
  `lib/leadv2-route-arbiter.sh`, `tests/run-all.sh`, `tests/known-red-suites.txt`.
- Do NOT touch `docs/leadv2/` — shared runtime state, read by a live pulse while you work.
- Do not commit to `main`. Do not weaken an assertion. Never `reset --hard`, `clean`, `stash`, or
  `worktree prune` — live lanes stand next to yours in a shared tree, and one of them
  (`E2E-GATE-BROKE-TODAY-01`) is running right now on neighbouring gate work.
- `${BASH_SOURCE[0]}` does not exist under zsh, and `declare -F` there answers "defined" for a
  function that does not exist. Do not build a guard on either.
- Deletion check: `git diff --diff-filter=D --name-only main...HEAD` — THREE dots.
- A file counts as saved when it appears in `git ls-files`, checked by eye.
- **Commit your work before you reach any gate.** Five lanes today finished and were found only
  because someone looked in the worktree; the branch said nothing.
- Your report lands in the dispatch directory of the MAIN repo. State its full path in your final
  message.
- If any instruction here rests on a false premise, stop and say so with the measurement. That is a
  complete and welcome answer; papering over it is not.
