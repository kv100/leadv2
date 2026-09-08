GATE-RUNS-EVERYTHING-BECAUSE-run-all-SWALLOWS-SCOPE-01. The close gate asks for a scoped run and
gets an unscoped one, so every close burns 900 s and times out. This is the LAST thing standing
between three verified lanes and their merge, and it is the fourth defect in the same gate.

REPO: ~/Projects/leadv2. Measured by the lead 2026-09-08T02:2x-02:4xZ.

## The measurement

Three lanes re-gated back to back, immediately after the docs-only fix landed (`5f4a4bf8`):

    e2e_gate task=fb9df7f1 status=ran verdict=timeout rc=124 timeout_s=900   sentinel: absent
    e2e_gate task=a0b9aa86 status=ran verdict=timeout rc=124 timeout_s=900   sentinel: absent
    e2e_gate task=157a7898 status=ran verdict=timeout rc=124 timeout_s=900   sentinel: absent

`status=ran` is the good news — the gate now SEES committed work instead of stamping a false pass.
It then runs the wrong thing.

The chain:
- `leadv2-phase8-e2e-gate.sh:276` runs `bash -c "${e2e_cmd} --scope changed"` — correct.
- `leadv2-e2e-entrypoint.sh` resolves `e2e_cmd` to `bash <root>/tests/run-all.sh` for a leadv2 lane
  worktree.
- `tests/run-all.sh` parses `--scope` for its OWN suite selection (`:39-56`) and then, at `:121-124`,
  does `add_suite "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh"` — **as a suite, with no
  arguments.** The core runner is 95 suites behind one entry in the list.
- Live `ps` during the third gate, the smoking gun — no `--scope` anywhere:

      bash .../cd486551a5cb/plugins/leadv2/scripts/tests/run-core-offline.sh
      flock -x -n -E 99 -o /tmp/leadv2-core-offline-….lock env _LV2_CORE_OFFLINE_LOCK_HELD=1 \
        bash .../cd486551a5cb/plugins/leadv2/scripts/tests/run-core-offline.sh

The scope machinery below it is FINE and must not be touched. In the same worktree, called directly:

    LEADV2_CORE_OFFLINE_SCOPE_DUMP=1 run-core-offline.sh --scope changed
    [CORE-OFFLINE] SCOPE_RESULT selected=3 total=95 base=main@5f4a4bf897 changed=4 unmapped=0 reason=-

and the two selected suites run in 0.22 s and 0.18 s. So the gate spends 900 s running 95 suites
after being told, in writing, to run 3. `338d6ad9` taught `run-core-offline.sh` to parse `--scope`;
this defect means nothing ever reaches it through the gate's own path.

## What to build

1. **Forward the scope.** When `tests/run-all.sh` delegates to `run-core-offline.sh`, pass the scope
   it was given. `--scope all` must stay `--scope all`; `--scope changed` must arrive as
   `--scope changed`. Whether that means `add_suite` learns per-suite args or the core runner is
   invoked outside the generic suite list is your call — pick the one that does not change how any
   other suite in the list is invoked.
2. **Make the delegation legible.** One line naming what was handed down, so the next investigation
   reads a log instead of `ps`.
3. **Do not touch the selection logic** in `run-core-offline.sh` (`:812-947`) — it is measured
   correct above. Do not touch the gate. Do not widen `EXTRA_SUITE_MAP`.

Out of scope, already filed, do NOT fix here: the gate's timeout kills its direct child but not the
process group, so a 900 s timeout leaves `run-core-offline.sh` and its `flock` child running
forever (observed on all three lanes tonight). Ledger row
`SD-THE-GATE-TIMEOUT-DOES-NOT-KILL-THE-SUITE-TREE-01`.

## Acceptance
acceptance:
  surface: command_output
  observable: in `~/Projects/leadv2/.claude/worktrees/d2823c51e670`,
    `bash plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh fb9df7f1` finishes well under
    `timeout_s=900` with a real `verdict=` (pass or fail — either is a valid outcome, `timeout` is
    not), and the run log carries a `[CORE-OFFLINE] … scope=changed running N of 95` line with N
    small. Paste the gate line, the wall-clock duration, and the CORE-OFFLINE line. Also show
    `--scope all` still running the full set, or the fix is half a fix.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the delegation you added, drop the forwarded scope again. The suite must go red on the
   SELECTED SUITE COUNT the core runner reports (95 vs 3) — the value that has never varied — not
   on a log string.
2. Inside the same place, forward a hardcoded `--scope changed` regardless of what run-all was
   given. The suite must go red for the `--scope all` case: a gate that can no longer be asked for
   a full run is a new lying-green surface, not a fix.
Insert each mutation INSIDE the function body, never at top level — a top-level insert makes every
suite red for the wrong reason and reads as a pass. Self-register with
`# run-all-triggers: run-all run-core-offline` and verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`; do NOT hand-edit the suite map.

## Constraints
- Touch ONLY `tests/run-all.sh` and your new suite. If the fix genuinely cannot live there, say why
  before touching `plugins/leadv2/scripts/tests/run-core-offline.sh`, and change nothing else.
- Do NOT touch `leadv2-phase8-e2e-gate.sh`, `leadv2-e2e-entrypoint.sh`, `leadv2-helpers.sh`,
  `leadv2-dispatch-code.sh`, `leadv2-task-judge.sh`.
- Bash 3.2 only: no associative arrays, no `${x^^}`, no `readarray`/`mapfile` in new code paths.
- Never `git add -A`. `git commit -- <path>` commits the WORKING TREE, not the index: stage
  explicitly, check `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact. Say "unverified" out loud; never "should work".

LANE_WRITES: tests/run-all.sh, plugins/leadv2/scripts/tests/test-run-all-forwards-scope.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-deb7e831" "<question>" \
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