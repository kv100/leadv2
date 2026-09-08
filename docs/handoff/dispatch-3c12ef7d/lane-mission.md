# A handoff-only write set is refused AFTER the work is paid for

**Row B5 of `PRE-WAVES-PLAN.md`.** This has already killed two design lanes in one day.

REPO: `~/Projects/leadv2`. Its `main` IS the live path — symlink deploy, so a fix not
committed to main is not delivered. **Dispatch and work from `~/Projects/leadv2`.**

---

## The symptom, as the lead observed it

A mission whose declared `--writes` paths are **all** under `docs/handoff/` spawns a worker
normally, the worker runs, and roughly **25 seconds after spawn** the lane dies with
`undiffable_write_set`. The refusal is correct in substance — a lane that can only write
into a handoff directory produces no diff, so the review gate has nothing to certify — but
it arrives **after** the arm was selected, the reservation taken, and the model turn paid
for. Nothing at dispatch time warns you, and the reason string is not guessable from the
outside: nobody reading `--writes docs/handoff/x/report.md` expects `undiffable_write_set`.

## What to establish first, before designing anything

Do not trust the paragraph above as a mechanism description — it is a lead's observation of
an outcome. Establish, from the code:

1. **Where the refusal is raised**, exactly, and what predicate decides "undiffable". Is it
   "every path is under `docs/handoff/`", or "no path is under a reviewable tree", or
   something else? Quote the line.
2. **When it is raised** relative to arm selection, reservation, and worker spawn. The
   ~25s delay is the interesting part: it says the check runs at a stage that already
   costs money. Name the stage.
3. **Whether a legitimate recon/design lane can ever satisfy the rule.** Our own recon
   missions genuinely produce only a report. If the rule refuses them by construction, the
   rule is wrong for that lane *kind*, not just badly timed — say so if that is what you
   find.

## What the fix has to achieve

**The refusal moves to dispatch time, before an arm is selected, and says what to do.**
Concretely: a mission that cannot produce a reviewable diff is refused *before* any model
turn is paid for, with a reason a human can act on — naming the offending write set and the
remedy, not just a class name.

Then the second half, and it is the more important one: **decide what a report-only lane
should do instead.** Options to weigh (this is your call to argue, not mine to dictate):
`--kind recon` bypassing the diff requirement; a declared `report_only` flag; or requiring
one reviewable path alongside the handoff paths. Whatever you choose, a recon lane must be
able to run and be closed honestly — today the lead works around this by adding a token
non-handoff path, which is a lie the gate cannot detect.

Do not silently widen the rule so that every handoff-only lane passes review. A lane with
no diff still has nothing for the review gate to certify; the fix is to route it to the
right terminal state, not to let it through the wrong one.

## Negative controls (E2E-KILLRATE-01, non-negotiable — two, both run, red then green)

1. **The symptom.** A handoff-only write set is refused **at dispatch time**, and the
   assertion is on the *stage* and the *reason value*, not on a log substring. Prove the
   refusal happens before an arm is selected — an assertion that no arm reservation exists
   is the honest form of that.
2. **The guard.** A write set that DOES contain a reviewable path is **not** refused.
   Break your own predicate deliberately (refuse everything) and show the suite goes red —
   otherwise the fix is a gate that refuses all lanes.

Insert every mutation **inside the function body**, never at top level: a top-level insert
reddens everything for the wrong reason and reads as a pass. That mistake has already
invalidated one measurement in this repo.

Register your suite with a `# run-all-triggers: <stem>` header and **prove selection**:
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh` must print your
`<stem>:<suite path>` row, and the stem must be a file your change actually touches. Do not
prove selection with `--scope changed` — it is stateful and lies three ways (row B6); the
trigger-map print is the honest instrument.

## Constraints

- Do not merge. Report, and the lead verifies and merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`.
  Never `git add -A` — enumerate paths.
- Report `main...HEAD` (three dots), never `main..HEAD`.
- If you conclude the rule itself is wrong rather than mistimed, say that plainly and argue
  it. A well-argued contradiction of this mission is worth more than a compliant fix.

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/tests/test-handoff-only-write-set-is-refused-early.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-3c12ef7d" "<question>" \
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