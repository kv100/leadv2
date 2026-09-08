SCAN-ROOTS-MAP-MISSES-THE-PLUGIN-TEST-DIR-01. `tests/run-all.sh`'s own self-registration suite is
RED on main, and it is red about the thing that matters most in this repo: a directory full of
declared suites that the trigger scanner's root map does not cover.

REPO: ~/Projects/leadv2. Measured by the lead 2026-09-08T03:4xZ, on `main` at `3cb4c49f`.

## The measurement

    $ bash tests/test-run-all-self-registration.sh
    FAIL: scan roots: declaring root(s) missing from the map: plugins/leadv2/scripts/tests
          — scan_suite_triggers stopped walking a directory that holds declared suites
    test-run-all-self-registration: 11 passed, 1 failed

Red on `main` and red inside every lane worktree. Because run-all runs this suite as part of its
own set, **every close gate now ends `verdict=fail` for a reason that has nothing to do with the
lane being gated** — which is the same class of wrong verdict this repo has already produced three
times tonight, just from the other direction.

The confusing part, and the reason this needs looking at rather than guessing: the suites in that
directory ARE being listed today. `LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh` prints,
among others:

    leadv2-task-judge:plugins/leadv2/scripts/tests/test-judge-parses-its-own-answer.sh
    leadv2-phase8-e2e-gate:plugins/leadv2/scripts/tests/test-docs-only-detector-sees-commits.sh
    leadv2-codex-config-prune:plugins/leadv2/scripts/tests/test-codex-config-prune.sh

So the listing walks the directory while the suite says the root map does not declare it. Exactly
one of those two is right, and **which one is right decides the whole fix**:
- If the MAP is stale (the scanner really does cover the dir, the map just never learned about it),
  the fix is to declare the root.
- If the LISTING reaches those files by some other path (a glob, a second scan, a fallback) while
  `scan_suite_triggers` genuinely stops short, then suites in that directory are selected by luck
  and not by the scan — and the fix is in the scanner.

Find out which before changing anything, and say which one it was in the commit message. A guess
here produces a green suite over a scanner that still cannot see the directory, and that is the
lying-green disease in the one place we can least afford it: the mechanism that decides which tests
CI runs at all.

## What to build
1. Determine, with output, whether `scan_suite_triggers` walks `plugins/leadv2/scripts/tests` or
   not. Paste the evidence.
2. Fix the real side. Do not silence the assertion, do not relax it to "warn", do not add the
   directory to an ignore list.
3. After the fix, `bash tests/test-run-all-self-registration.sh` is 12/0 and the trigger listing
   still names all suites it named before — show both, and show that the count did not go DOWN.

## Acceptance
acceptance:
  surface: command_output
  observable: `bash tests/test-run-all-self-registration.sh` reports 0 failures on main, and
    `LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | wc -l` is >= its pre-fix value. Paste
    both, before and after.

## Negative control (E2E-KILLRATE-01) — run it and SHOW it red
Inside the body of whichever function you changed, revert the one decision that made the directory
reachable/declared. The suite must go red on the SET of declaring roots it reports — the value
under test — not on a log string. Insert INSIDE the function body, never at top level. Show it red,
restore, show it green.

## Constraints
- Touch ONLY `tests/run-all.sh` (and the self-registration suite if, and only if, the investigation
  proves the assertion itself is wrong — in which case say so loudly and explain).
- Do NOT touch `plugins/leadv2/scripts/tests/*` suites, `leadv2-phase8-e2e-gate.sh`,
  `run-core-offline.sh`, `leadv2-dispatch-code.sh`.
- `core_offline_scope_arg()` in `tests/run-all.sh` landed an hour ago (`3cb4c49f`) and is verified —
  leave it alone.
- Bash 3.2 only: no associative arrays in new code, no `${x^^}`, no `readarray`/`mapfile`.
- Never `git add -A`. `git commit -- <path>` commits the WORKING TREE, not the index: stage
  explicitly, check `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact. Say "unverified" out loud; never "should work".

LANE_WRITES: tests/run-all.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-46f80fcd" "<question>" \
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