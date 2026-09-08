STATUS-SURFACE-SUITE-RED-ON-MAIN-01. A suite on `main` is red, and because the close gate runs
`tests/run-all.sh`, it hands `verdict=fail` to lanes that never touched it. One lane has already
been failed by it tonight.

REPO: ~/Projects/leadv2. Measured by the lead 2026-09-08T08:0x-08:4xZ, on `main`.

## The measurement

    $ bash tests/test-status-surface-single-lead.sh
    FAIL - (a) expected '🛠 deadbeef sonnet ...', got '🛠 dispatch-deadbeefm7 sonnet now'
    test-status-surface-single-lead: 22 passed, 1 failed

And the consequence, from a real gate run on a lane whose diff is nowhere near this file:

    e2e_gate task=a0b9aa86 status=ran verdict=fail rc=1 scope=whole_tree_fallback
      elapsed_s=169 budget_s=900

The rendered line the suite got back is live production state, not its fixture: it contains
`mode=single-lead active 1`, real `limits` rows and `urgent: 0 (4h)`. `dispatch-deadbeefm7` is a
TEST FIXTURE that is sitting in the live registry
(`~/.claude/leadv2-state/persona-engine/active.yaml`) as a task row, and the status surface reads
that registry. So the suite is asserting against whatever the machine happens to be doing.

That is the defect. It is not "the expected string drifted".

## What to build

**The suite must not read live state.** Point it at an isolated registry — a temp `active.yaml`
seeded with exactly the rows the assertion is about, via whatever env seam the status-surface
script already honours (find it; do not invent a new one if one exists). After the fix the suite
must give the same answer on a busy machine and an idle one.

Two things you must NOT do:
1. **Do not update the expected string to match today's live output.** That makes the suite green
   and permanently wrong — it would then assert that a fixture named `dispatch-deadbeefm7` is
   present in production.
2. **Do not fix it by deleting the row from the live `active.yaml`.** The lead can do that in ten
   seconds; it comes back the next time a fixture runs. A suite that passes only because someone
   tidied the machine first is not a passing suite.

If the status-surface script genuinely has no seam for an alternate registry path, adding a
narrow one (an env var read in exactly one place, defaulting to today's path) is in scope — say so
in the commit message and keep it to that.

## Acceptance
acceptance:
  surface: command_output
  observable: `bash tests/test-status-surface-single-lead.sh` reports 0 failures, AND it still
    reports 0 failures with a junk row deliberately added to the live
    `~/.claude/leadv2-state/persona-engine/active.yaml` (add it, show the suite green, remove it).
    Both runs pasted. The second run is the whole point: it proves the isolation, where the first
    only proves the machine is currently quiet.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the body of whatever you changed, point the suite back at the live registry. It must go
   red on the RENDERED LINE for the seeded fixture — the value under test — not on a log string.
2. Inside the same body, seed the isolated registry with a row carrying a DIFFERENT id than the
   assertion expects. The suite must go red: an isolated registry that ignores what it was seeded
   with is not isolation, it is a suite that stopped looking.
Insert each mutation INSIDE the function body, never at top level. Self-register with
`# run-all-triggers: status-surface` (match the real script's stem) and verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`.

## Constraints
- Touch ONLY `tests/test-status-surface-single-lead.sh` and, if the seam is genuinely missing, the
  status-surface script it exercises. Nothing else.
- Do NOT touch `tests/run-all.sh`, `plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh`,
  `run-core-offline.sh`, `leadv2-dispatch-code.sh` — several landed within the last few hours.
- Do NOT edit `~/.claude/leadv2-state/persona-engine/active.yaml` as part of the fix (adding and
  removing a junk row for the acceptance run is fine, and expected).
- Bash 3.2 only: no associative arrays in new code, no `${x^^}`, no `readarray`/`mapfile`.
- Never `git add -A`. `git commit -- <path>` commits the WORKING TREE, not the index: stage
  explicitly, check `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact. Say "unverified" out loud; never "should work".

LANE_WRITES: tests/test-status-surface-single-lead.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-e1836bd3" "<question>" \
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