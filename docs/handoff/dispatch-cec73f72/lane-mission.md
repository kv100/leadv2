EMPTY-LANE-SELECTS-ALL-95-SUITES-01. A lane with nothing to prove runs the biggest possible
proof, and therefore can never pass its own close gate.

REPO: ~/Projects/leadv2. Measured by the lead 2026-09-08T09:1x-09:2xZ on lane `5fcc9823fa3b`.

## The measurement

    $ LEADV2_CORE_OFFLINE_SCOPE_DUMP=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh --scope changed
    SCOPE_RESULT selected=95 total=95 base=main@affe74c702 changed=0 unmapped=0
      reason=no_relevant_changed_files (base=main@affe74c702; everything else is .md/docs housekeeping)

and the consequence, from that lane's own journal:

    e2e_gate task=e9eee486 status=ran verdict=timeout rc=124 timeout_s=900
    dispatch_terminal task=e9eee486 terminal=parked cause=e2e_timeout

`changed=0 unmapped=0` is the *healthiest* possible input: nothing relevant changed, and nothing
went unmapped. The selector answers it with the *maximum* run. So a lane that produced no code —
or produced only docs — is guaranteed to time out and park. This is not the artifact bug
(`0424a451`, nested housekeeping counted as unmapped) and not the budget question
(a legitimately large 25-suite selection genuinely needing >900s, filed separately). It is a third
thing: the empty case falls into the same "cannot prove coverage" branch as the unknown case.

## The distinction to encode

There are two different zeros and the selector currently conflates them:

- **`unmapped>0`** — changed files exist and we cannot prove a suite covers them. Running
  everything is CORRECT. Do not touch this; it is the safety net and it has already saved us.
- **`changed=0`** — there is nothing to cover. Running everything proves nothing that running
  nothing would not prove, and costs the whole budget. This case should resolve fast and honestly.

Decide what `changed=0` should select and justify it in the commit body — an empty selection that
reports a clean, explicit "nothing to run" verdict, or a small fixed smoke set. Either is
defensible; what is not defensible is the full set. Whatever you pick, the gate must be able to
tell "nothing to prove" apart from "proved everything" in its log line: a close gate that reads
`verdict=pass` must not be ambiguous about which of those happened.

Note the honest tension, and say which side you came down on: a lane that commits NOTHING is
usually a broken lane, and making its gate pass quietly could hide that. It is filed separately
(`REVIEW-AND-SELFCHECK-GREEN-ON-AN-EMPTY-LANE-01`) precisely so that this fix does not have to
solve it — but do not make that defect harder to see. Surfacing "this lane changed nothing" loudly
in the gate line is welcome; using a 900-second timeout as the way to surface it is not.

## Acceptance
acceptance:
  surface: command_output
  observable: in a worktree whose only difference from main is docs/anchor commits,
    `LEADV2_CORE_OFFLINE_SCOPE_DUMP=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh --scope changed`
    no longer prints `selected=95 total=95`, and the run finishes in seconds rather than hitting
    the 900s ceiling. Paste the SCOPE_RESULT line and the wall time. Then, in the SAME worktree,
    add one genuine unmapped source file and show `selected=95 … reason=unmapped_files` still
    happens — the safety net must be untouched. Both pasted; the second is what proves you fixed
    the empty case and not the net.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the body of the function you changed, route `changed=0` back into the full-set branch.
   The suite must go red on `selected=` / the reason code — the values under test — not on a log
   string.
2. Inside the same body, make `unmapped>0` take your new fast path too. The suite must go red on
   the genuine-unmapped case: that mutation deletes the coverage proof, which is far worse than
   the bug you are fixing.
Insert each mutation INSIDE the function body, never at top level. Self-register with
`# run-all-triggers: run-core-offline` and verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`.

## Constraints
- Touch `plugins/leadv2/scripts/tests/run-core-offline.sh` and your new suite. Nothing else.
- Do NOT touch `leadv2-dispatch-code.sh` or `lib/leadv2-route-arbiter.sh` — a sibling lane (P1b,
  task `da195ecf5abc`) owns both right now.
- Do NOT weaken the `unmapped_files` fallback policy. You are changing what happens when there is
  nothing to cover, not what happens when coverage is unproven.
- Bash 3.2 only: no associative arrays in new code, no `${x^^}`, no `readarray`/`mapfile`.
- Never `git add -A`. `git commit -- <path>` commits the WORKING TREE, not the index: stage
  explicitly, check `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact. Say "unverified" out loud; never "should work".

LANE_WRITES: plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/test-scope-empty-lane-is-not-a-full-run.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-cec73f72" "<question>" \
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