E2E-GATE-RUNS-ALL-94-SUITES-BECAUSE-THE-ENTRYPOINT-IGNORES-SCOPE-CHANGED-01 — the phase-8 close gate
in the leadv2 repo asks for a narrowed run and gets the full set. This is parking real, finished work
right now: three lanes are queued behind it.

REPO: ~/Projects/leadv2. This is a NEW defect found 2026-09-07T20:40Z, not one of the six
GATE-EVIDENCE rows. It blocks all of them by blocking every close.

## Measured, 2026-09-07T20:27–20:45Z

`leadv2-phase8-e2e-gate.sh:242` resolves the entrypoint via `leadv2-e2e-entrypoint.sh` and `:255` runs

    ( cd "$root" && _lv2_selfcheck_timeout_run 900 ... -- bash -c "${e2e_cmd} --scope changed" )

In **persona-engine** the entrypoint resolves to `tests/run-all.sh`, which honours `--scope changed`.
In **leadv2** it resolves to `plugins/leadv2/scripts/tests/run-core-offline.sh`, and that script has
**no top-level argument parsing whatsoever** — no `while [[ $# ]]`, no `case "$1"` for flags; `$1`/`$@`
appear only inside helper functions (`:85, :233, :241, :246, :270`). The flag is silently discarded.

Live confirmation, run by the lead with the flag attached:

    $ bash plugins/leadv2/scripts/tests/run-core-offline.sh --scope changed
    [CORE-OFFLINE] running 94 suites across 4 shards      <- 94, i.e. everything

Consequence, measured on lane `d2823c51e670` (a 4-file diff: two new scripts, two new tests):

    20:19:09  selfcheck task=fb9df7f1 status=green checks=6 skipped=2
    20:34:11  e2e_gate  task=fb9df7f1 status=ran verdict=timeout rc=124 timeout_s=900
    20:34:16  dispatch_terminal task=fb9df7f1 terminal=parked cause=e2e_timeout

Finished, committed, self-checked work (`f4484166`) parked — because a 4-file change was made to run
94 suites on a laptop already carrying three lanes. Two more lanes (`f33ff575078f` commit `aa18b583`,
`cd486551a5cb` commit `fe55a781`) are walking into the same wall as this is written.

**Ruled out, do not re-investigate:** the suite lock is NOT the cause. `run-core-offline.sh:89` keys
`LEADV2_SUITE_LOCK_FILE` by the repo root slug, so each lane worktree gets its OWN lock file
(verified: `/tmp/leadv2-core-offline-*-worktrees-d2823c51e670.lock` etc. are distinct). Lanes do not
serialize against each other on it. The gate did not wait for a lock; it genuinely ran all 94 suites.

## What to build

Teach `run-core-offline.sh` the `--scope changed` contract that `tests/run-all.sh` already implements,
and **reuse that repo's existing mechanism rather than inventing a third one.** Read how `run-all.sh`
resolves changed files → suites (the `# run-all-triggers: <stem>` self-registration convention plus
`EXTRA_SUITE_MAP`) and make the core-offline runner honour the same contract, so a suite registers its
triggers in exactly one place no matter which runner executes it.

Non-negotiable properties, in priority order:

1. **Fail OPEN, never closed.** If the changed set cannot be determined — no base ref, a detached
   HEAD, a git failure, an unmapped file — run **everything** and say so on stdout. A scope bug that
   selects zero suites and exits 0 is the lying-green disease in its purest form, and it would be
   invisible: the gate would go green faster and nobody would ask why.
2. **Say what it narrowed to, and why.** The current line is `[CORE-OFFLINE] running 94 suites across
   4 shards`. Under a narrowed scope it must name the count AND the reason, e.g.
   `running 6 of 94 suites (scope=changed, base=<sha>, 4 changed files, 2 unmapped -> full-set fallback)`.
   A gate whose only output in 900 s is one line is undiagnosable; that is why this defect survived.
3. **An unknown flag must not be silently swallowed.** Whatever the outcome for `--scope`, an
   unrecognised argument should be a loud error, not a no-op. Silent arg-dropping is what let the gate
   claim a narrowed run for weeks.
4. **Do not change the 900 s budget.** Raising a timeout so a gate goes green is the move this repo
   keeps getting burned by. If, after narrowing, a typical lane still cannot finish in 900 s, report
   that with the measured numbers and stop — the budget is a separate decision for the lead.

## Acceptance
acceptance:
  surface: log_line
  observable: In a worktree whose diff touches only files mapped to a small set of suites,
    `run-core-offline.sh --scope changed` prints a suite count strictly less than 94, names the base
    ref and the changed-file count, and exits 0 having actually executed those suites. With no
    resolvable base it prints the fallback reason and runs all 94. Show both runs' output.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the scope-resolution function body, make an unresolvable base return an EMPTY suite set
   instead of the full set. The suite must go red **on the executed suite count being 0** — not on a
   log string. This is the control that matters: it is the exact shape of a gate that passes forever.
2. Inside the same function, ignore the changed-file list and always return all 94. The suite must go
   red on the count for a narrow diff. Without this control, a runner that "supports" `--scope` by
   parsing the flag and then running everything anyway would still pass — which is today's bug wearing
   a new flag.
Insert each mutation INSIDE the function body, never at top level — a top-level insert makes every
suite red for the wrong reason and reads as a pass. Self-register your new suite with
`# run-all-triggers: run-core-offline` and verify with `LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`;
do NOT edit `tests/run-all.sh` (held by a live lane).

## Constraints
- Do NOT touch: `leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`, `lib/leadv2-glm-policy-resolve.py`,
  `config/leadv2-routing.yaml`, `tests/run-all.sh`, `codex-task.sh`. Read them freely. If the fix needs
  one, STOP and report which line and why.
- Do NOT delete or disable any suite to make the set smaller. The 12 pre-existing red suites
  (`MAIN-CORE-SUITE-RED-01`) stay exactly as they are; narrowing scope is not a licence to drop them.
- Never `git add -A`. **Trap verified by experiment today: `git commit -- <path>` commits the WORKING
  TREE for that path, not the index** — in a dirty repo it silently sweeps in other people's
  uncommitted edits to the same file. Stage explicitly, check `git diff --cached --stat`, then commit
  WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact: a suite count, a base ref, a run output. Say "unverified" out
  loud; never say "should work".

LANE_WRITES: plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/test-core-offline-scope-changed.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-31b4e0e4" "<question>" \
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