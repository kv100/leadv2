# CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01 — fix round 1

Your wait-vs-switch rule is accepted in substance and approved for merge by the second lead. Two
things in it were singled out as correct and must not be altered:

- `WAIT_FRACTION_OF_PERIOD=0.10` multiplied by the **window's own** period, with both live window
  shapes named in `WINDOW_PERIOD_HOURS` and both founder examples reproduced with arithmetic in the
  comment. A derived threshold, not a picked number.
- `window_reset()` returning `period, period, 'default_full_period'` when the reset is unreadable, so
  an unknown reset always reads as "far" and can never fabricate an imminent wait. And `reset_basis`
  travelling outward, so the basis of the verdict is observable rather than hidden.

Keep both. The closure note is committed at
`docs/handoff/CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01/brief-closure-note.md` — read it.

Two items close this lane. Nothing else is in scope.

## 1. An unknown window NAME degrades in the wrong direction

`window_period_hours()` falls back to `DEFAULT_PERIOD_HOURS=168.0` when the window name is not in
`WINDOW_PERIOD_HOURS`. The threshold then becomes 16.8h, and a window that is really short reports
`hours_to_reset` of, say, 0.5h — `0.5 <= 16.8` — so it **waits**.

That is the opposite direction from your unknown-**reset** handling, and the opposite is the harmful
one: we stay on an arm that is over its ceiling instead of leaving it. An unreadable reset honestly
sends us away; an unreadable window name holds a burnt provider in the chain.

Verified scope before you start, so you fix the real case and not a larger imagined one: the fallback
only bites when **all three** hold — the name is unknown, **and** `limit_window_seconds` is absent
from the window payload (line 111 already returns `lws/3600` when it is present, which covers the
common case), **and** a live `hours_to_reset` is present. When `hours_to_reset` is also absent,
`window_reset()` sets `h = period`, `168 <= 16.8` is false, and the code already switches correctly.

Required: an unknown window name must be **`unknown`**, not "assume weekly". On `unknown`, behave as
the code did before this change — switch away — because "I could not ask" must never become a
positive answer. Surface it in `reset_basis` with its own word so an operator can see that the
verdict rests on an unknown window rather than on a real measurement; do not reuse
`default_full_period`, which means something else.

Do not change `WAIT_FRACTION_OF_PERIOD`, `WINDOW_PERIOD_HOURS`, or the `default_full_period` path.

## 2. This lane has no negative control at all — that is the blocking item

You shipped `tests/test-quota-reset-arbiter.sh` and it is green. Green proves the suite runs; it does
not prove the suite **bites**. Three of five wave-3 lanes are in this state and not one of them will
be closed without a biting control.

Write negative controls in the shape that was accepted on `TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01`
today — read `plugins/leadv2/scripts/tests/nc-claude-account-collapse.sh` in that lane's worktree as
the model. Required properties, all of them:

- The mutation is applied **inside a function body**, never at file top level. A top-level insert
  makes every suite red for the wrong reason and reads as a pass.
- The mutated copy is written to a scratch file and the suite is run against **that copy** via an
  injection variable — never by editing the original in place.
- An `NC-SETUP-FAIL` guard: if the target line no longer matches, the control exits non-zero loudly
  instead of silently mutating nothing.
- The control **passes only when the suite goes red**.

Two controls, one per claim:
- **NC1** — inside the wait predicate `near_reset_wait()`, force it to always return false. The suite
  must go red on the "20 min left on a 5h window → wait" case.
- **NC2** — inside `window_reset()`, make the unreadable-reset path return `0.0` instead of the full
  period. The suite must go red, proving the assertion that an unknown reset cannot fabricate an
  imminent wait actually bites.

Add a third for item 1's new behaviour once you have written it.

Report for each: the `baseline_rc` / `mutated_rc` pair and the literal red suite line, then revert and
show green with both exit codes pasted. A `diff_hash` is not proof of a run.

## Constraints

- Do **not** touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — held by another session.
  `lib/leadv2-route-arbiter.sh` is yours; the earlier blanket warning about it was withdrawn.
- Nothing goes into `tests/known-red-suites.txt`, and no assertion is weakened to reach green.
- Your registration line in `tests/run-all.sh` shares that file with two other lanes. Do not
  reformat or move existing lines — append only, so the three-way merge stays trivial.
- Commit after each item. The machine is heavily loaded and workers have been dying of CPU
  starvation; uncommitted work on this lane has already been rescued by hand once.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-79a9c5b7" "<question>" \
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