# V3-DISPATCHER-ACCEPTANCE-FINISH-01 — close the critic blockers (~/Projects/leadv2)

Base: lane worktree, checkpoint 029ce01 carries the full 3-Fault implementation (Fault-1
absolute HANDOFF_DIR in claude-subsession.sh, Fault-2 foreign-root guard in
leadv2-dispatch-code.sh, Fault-3 `retry-dead` subcommand, 4 test files). Critic verdict FAIL —
READ THE REPORT FIRST, it names exact lines and repros:
~/Projects/leadv2/docs/handoff/dispatch-b4042501-review/critic.full.md
Original mission (context): the same dir's lane-mission.md.

Close the critic's «Required before this can pass» list, items 1–3 and 6–7 (item 4 junk-cleanup
and item 5 commit are done by the lead — tree is clean at 029ce01):

1. (blocker) Fix the `_LV2_CWD_GIT_ROOT` else-branch regression + add the subdir/no-env red-first
   test the critic describes.
2. (blocker) Make the Fault-2 foreign-root guard LIVE: default-on (or loud refusal on mismatch).
   Drop or invert its test Case 2, which currently asserts the defective (guard-off) behavior.
3. (blocker) Repair test-dispatch-retry-dead.sh so it actually reaches the `retry-dead` path
   (today it exits earlier and vacuously passes).
4. (item 6) Deliver Fault-1's secondary: a successful prepass must clear a park (or ship
   --clear-park), with test — or write 3 lines in your terminal artifact explaining why it is
   genuinely out of scope.
5. (item 7 nits) ask-lead.sh path absolute too; set JOURNAL_TASK in cmd_retry_dead so
   dispatch_retry_over_dead_attempt lands in the task journal (emit() no-ops without it).

## Acceptance
All 5 test files green with red legs shown for the new/changed ones · run-core-offline
FOREGROUND solo green in the lane (NEVER background-and-idle-wait) · bash -n + shellcheck
-S warning on both scripts · COMMIT on the lane branch — do not leave the tree dirty.

## Off_limits
leadv2-dispatch-product-close.sh; routing order/ceilings; supervise*.

## Terminal artifact
Commit sha + per-blocker red/green raw output + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-e2f1b64e" "<question>" \
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