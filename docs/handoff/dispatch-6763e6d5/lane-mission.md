GATE-BUDGET-TOO-SMALL-FOR-run-all-OWN-SUITES-01. The close gate has never once reached a verdict on
this machine. Every run ends `verdict=timeout rc=124 timeout_s=900`, and after tonight's fixes we
know exactly why — and it is no longer a bug in the scoping.

REPO: ~/Projects/leadv2. Measured by the lead 2026-09-08T03:3x-03:5xZ, main at `3cb4c49f`.

## The measurement

The scope forwarding works. From the real gate log of a real lane
(`docs/handoff/fb9df7f1/e2e-gate.log`, 510 lines):

    run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
    [CORE-OFFLINE] scope=changed running 3 of 95 suites (base=main@3cb4c49f50, 4 changed files, 0 unmapped)
    [CORE-OFFLINE] SCOPE_RESULT selected=3 total=95 … reason=-

Those three suites pass in seconds. Then `run-all.sh` carries on through **its own** suite set —
`test-dod-gate-suite-registration.sh`, `test-run-all-carrier-map.sh`,
`test-run-all-self-registration.sh` and everything before them — and the wall clock runs out:

    e2e_gate task=fb9df7f1 status=ran verdict=timeout rc=124 timeout_s=900
    elapsed_s=902     sentinel: absent

Same outcome on all three parked lanes, twice each, before and after the scope fix. So the core
runner obeys `--scope changed` while run-all's own list does not appear to narrow anywhere near as
much, and the 900 s ceiling is reached by the honest work of running suites — not by a hang.

`status=ran` is the good part: the gate now sees committed work instead of stamping a false pass
(`5f4a4bf8`). It just cannot finish.

## The question to answer before changing anything

**Is run-all's own list actually unscoped, or is it scoped and simply slow?** Measure it. For the
lane worktree `~/Projects/leadv2/.claude/worktrees/d2823c51e670` (4 changed files, all under
`plugins/leadv2/{scripts/lib,tests}/`), report how many of run-all's own suites `--scope changed`
selects and how long each takes. The answer decides the fix and the two are NOT interchangeable:
- **Unscoped** → the fix is selection: run-all's own list must honour `--scope changed` the way the
  core runner now does. Raising the ceiling would just hide it.
- **Scoped but slow** → the fix is the ceiling (`E2E_TIMEOUT_S`), sized from the measurement, plus
  a line in the gate log saying how much budget was consumed so the next person sees it coming.

Do not raise the timeout as a reflex. A gate that passes because it was given more time to run
suites nobody asked for is a slower version of the same defect.

## What to build
1. The measurement above, pasted in the report: selected count, per-suite wall clock, total.
2. Whichever fix the measurement points to — one of the two, not both.
3. If the answer is the ceiling: the gate must print the elapsed time and the budget on every run,
   pass or fail, so a future timeout is diagnosable from one line instead of a 510-line log.

## Acceptance
acceptance:
  surface: command_output
  observable: in `~/Projects/leadv2/.claude/worktrees/d2823c51e670`,
    `bash plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh fb9df7f1` reaches a real `verdict=`
    (pass or fail — `timeout` is not a verdict) and prints its elapsed time. Paste the gate line and
    the wall clock. Then show the same for a deliberately BROKEN lane fixture — the gate must still
    be able to say `fail`, or the fix has only taught it to say yes.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the body of whatever you changed, revert that one decision (drop the selection, or put
   the old ceiling back). The suite must go red on the SELECTED SUITE COUNT or the ELAPSED/VERDICT
   value — never on a log string.
2. Inside the same body, make the gate reach `pass` by skipping suites rather than by selecting
   them correctly. The suite must go red: a gate that passes by running less than it should is the
   defect we spent tonight removing three times.
Insert each mutation INSIDE the function body, never at top level. Self-register with
`# run-all-triggers: run-all leadv2-phase8-e2e-gate` and verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`.

## Constraints
- Touch ONLY `tests/run-all.sh` and/or `plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh`, plus your
  new suite. Nothing else.
- `core_offline_scope_arg()` in `tests/run-all.sh` (`3cb4c49f`) and `_p8_diff_is_docs_only` in the
  gate (`5f4a4bf8`) both landed tonight and are verified — do not touch either.
- `tests/test-run-all-self-registration.sh` was just fixed for a pipefail/SIGPIPE false red
  (`abf5dbae`) — leave it alone.
- Bash 3.2 only: no associative arrays in new code, no `${x^^}`, no `readarray`/`mapfile`.
- Never `git add -A`. `git commit -- <path>` commits the WORKING TREE, not the index: stage
  explicitly, check `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact. Say "unverified" out loud; never "should work".

---

## AMENDMENT, 2026-09-08T10:2xZ — per-suite numbers, which change the answer

The 03:3xZ analysis above stopped at "the honest work of running suites reaches 900s". I have since
timed every top-level suite individually (`timeout 400` each, lane worktree `cd486551a5cb`), and the
distribution matters more than the total:

       8s rc=0   test-acceptance-shape.sh            15s rc=1   test-lane-liveness-authoritative.sh
      16s rc=0   test-active-cache-liveness.sh        6s rc=0   test-lane-liveness-e0-contradiction.sh
       1s rc=0   test-arm-receipt-import-unjoined    13s rc=0   test-lane-liveness-sentinel.sh
      47s rc=0   test-board-blind-detached-01       355s rc=1   test-lane-truth-batch-01.sh
      12s rc=1   test-claude-subsession-sentinel    321s rc=0   test-status-surface-bash32.sh
     147s rc=0   test-dispatch-resume-sentinel        7s rc=0   test-status-surface-fast-names.sh
       4s rc=0   test-fork-storm-watcher-liveness    17s rc=0   test-status-surface-single-lead.sh
      80s rc=1   test-lane-finished-state.sh
      ------
      total_s=1049, BEFORE core-offline delegates its own 25-suite run

Three conclusions, in the order they should drive the work:

1. **Fifteen leaf suites alone are 1049s against a 900s budget.** So "raise the timeout" is not
   merely a fix at the wrong layer — it is an unwinnable race, because the sum grows with every
   suite added. Whatever you do must make the close budget stop containing work it does not need.

2. **Two suites are 676s, 64% of everything.** `test-lane-truth-batch-01.sh` is 355s AND is on
   `tests/known-red-suites.txt` — a suite we have already decided is allowed to fail is spending
   six minutes of a fifteen-minute budget in order to fail. Taking known-reds out of the close
   budget is the single cheapest change available and it is worth -355s on its own.
   `test-status-surface-bash32.sh` is 321s and GREEN, so it is not a correctness problem, but five
   minutes deserves an explanation before it is accepted as normal.

3. **Four suites are red and only one is allow-listed.** That is a separate lane, already dispatched
   (founder row `a49cbf1665d4`), and it owns `tests/known-red-suites.txt` plus the three suite
   files. **Do not touch those files.** If your fix needs the allowlist to change shape, say so in
   the report and stop, rather than editing across the boundary.

Correcting the earlier framing in this mission, which was mine: I previously said those suites were
"red on environment, not code". `test-lane-liveness-authoritative.sh` is red on main too (rc=1,
28s), not only in a worktree. Only the REASON string is worktree-specific.

LANE_WRITES: tests/run-all.sh, plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh, plugins/leadv2/scripts/tests/test-gate-reaches-a-verdict.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-6763e6d5" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.