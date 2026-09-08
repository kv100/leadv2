# The gate declares an empty diff while the worker is still writing

**Priority 0.** This destroys finished work. It killed a lane 14 minutes before its worker
completed a 463-line design report, and the report survived only because I went into the worktree
by hand and committed it myself. Row B4 of `PRE-WAVES-PLAN.md`, which the founder has started.

REPO: `~/Projects/leadv2`. Its `main` IS the live path — symlink deploy, so a fix not committed to
main is not delivered. **Dispatch and work from `~/Projects/leadv2`.**

---

## The observation, with its evidence

Lane `1f5e5544` (founder row `1PLUGIN-FABLE-2`), 2026-09-08:

    12:08:01Z review_gate task=1f5e5544 status=blocked reason=no_work terminal=no_work cause=empty_diff
    12:08:02Z dispatch_terminal task=1f5e5544 terminal=no_work cause=empty_diff
               worker_reason="{type:system,subtype:thinking_tokens,estimated_tokens:800,...}"

At that instant the worker was **alive**. Its own stream,
`docs/handoff/dispatch-1f5e5544/attempts/1788869225-49695/developer.stream.jsonl`, carries
`tool_progress` heartbeats on a running Bash call out to `elapsed_time_seconds=300`. It had not yet
written its file. It went on to finish a complete 463-line report at 12:22 — fourteen minutes after
the lane was declared dead — and could no longer commit it, because the lane was already terminal.
I recovered the file by hand from `.claude/worktrees/1PLUGIN-FABLE-2/docs/audits/`; it is now in
main as `c646cb7c`.

Note the shape of the failure: `terminal=no_work` is nominally retryable, but the worker is reaped
at terminal, so the fourteen minutes of thinking it had already done are gone. A retry does not
recover them. This is not a false alarm that costs a log line; it costs the whole lane.

The branch is `leadv2-dispatch-product-close.sh:2915`:

    _pc_terminal="no_work"; _pc_cause="empty_diff"; _pc_rg_reason="no_work"

It is the `else` of a dirty/undeclared classification. Nothing in that chain asks whether the
worker has finished.

---

## What to establish first, before changing anything

The diff check itself is not wrong — an empty diff really is an empty diff. The defect is **when**
it is allowed to be terminal. So the first question is not "how do I fix the check" but:

**Why did the gate evaluate at 12:08 at all?** Find what scheduled that evaluation. It may be a
timeout whose window is shorter than a long think, a poll that treats "no commit yet" as "done", a
worker-liveness check that returned the wrong answer, or a completion signal that fired early. The
answer determines whether the fix belongs at the scheduler, at the liveness check, or at the
terminal branch. Do not assume it is the last one just because that is where the log line is
printed.

Second, establish **what liveness evidence is available at that moment.** At least these exist and
you should say which are reachable from the gate: the worker pid, the `developer.stream.jsonl`
heartbeats (`tool_progress` with `elapsed_time_seconds`), and the stream file's mtime. There is a
neighbouring precedent worth reading — the `worker_timeout` path at `:1699-1700` already reaps a
live worker deliberately, so the codebase already has a notion of "the worker is still there".

---

## What the fix has to achieve

**An empty diff must not be terminal while the worker is demonstrably alive.** That is the
acceptance criterion.

What it must not do:

- It must not simply raise a timeout. A worker that thinks for longer than any constant will hit
  the same wall; the point is to stop deciding on a clock.
- It must not make a genuinely dead lane wait forever. A worker that has exited, or whose
  heartbeats have stopped for a stated interval, must still reach `no_work` promptly — an empty
  lane that hangs is a different failure and it is also expensive.
- It must not swallow `asked_into_void` or the `refused` branches above it (`unscoped_lane_work`,
  `cross_repo_elsewhere`, `declared_no_bytes`). Those are about declared scope, not liveness, and
  they stay as they are.

---

## Negative controls (E2E-KILLRATE-01, non-negotiable — two, both run, red then green)

1. **The exact failure.** A worker that writes its file at minute N, where N is longer than the
   gate's current evaluation window, must reach review rather than `no_work`. Before your fix this
   must FAIL. Assert the terminal **value**, not a log string.
2. **The guard.** A worker that has actually exited with an empty diff must still reach `no_work`
   promptly. Break your own liveness rule deliberately (treat every worker as alive) and show the
   suite goes red — otherwise the fix is just an infinite wait wearing a hat.

Insert every mutation **inside the function body**, never at top level: a top-level insert reddens
everything for the wrong reason and reads as a pass. That mistake has already invalidated one
measurement in this repo.

Register your suite with a `# run-all-triggers: leadv2-dispatch-product-close` header. **Then prove
selection correctly** — this knob lies in three ways and has produced two wrong conclusions today:
it counts from `$GIT_DIR/leadv2-run-all-last-checked-sha` when that file exists (`:294-310`), and
with no checkpoint and no resolvable base ref it degrades to `HEAD~1..HEAD`, the last commit only
(`:308-317`). Pin the range to the merge base for the proof (write the merge-base sha into the
checkpoint file, run, remove it) and state in the report which range you measured from.

---

## Constraints

- Do not merge. Report, and the lead verifies and merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`. Never
  `git add -A` — enumerate paths.
- Report `main...HEAD` (three dots), never `main..HEAD` — two dots renders every commit that landed
  on main after your branch point as a deletion, which has produced two false alarms today.
- A concurrent lane may hold `leadv2-dispatch-product-close.sh` at the same time. Check before you
  start; if it is taken, say so and stop rather than racing — two lanes writing that file is how a
  fix gets silently reverted.

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-1401655b" "<question>" \
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