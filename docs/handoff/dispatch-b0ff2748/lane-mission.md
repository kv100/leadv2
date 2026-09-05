# FALS-FIX2 — close 3 codex findings on TEST-FALSIFICATION-GATE (~/Projects/leadv2, lane a73c9b8f)

Lane 57/0 green; codex FAIL with 3 findings — READ THE FULL REPORT FIRST (anchors + repro):
docs/handoff/dispatch-a73c9b8f-review/codex.r1.md

1. HIGH: the gate greps for the RED-then-GREEN marker but (a) any echo/comment in the test
   satisfies it (forgeable) and (b) the test's own rc is ignored — a FAILING test with the
   marker passes the gate. Require BOTH: rc==0 AND the marker coming from the harness's own
   structured output (e.g. require the marker line format the run_case harness emits —
   `RED-then-GREEN: <name> (pre_rc=1 -> post_rc=0)` with the literal pre_rc=1 -> post_rc=0
   tail), and journal a distinct reason for rc!=0 vs marker-missing.
2. MEDIUM: coverage only catches directly-resolved */tests/test-*.sh — new test files in new
   dirs or renamed suites escape. Widen the classifier: any path whose basename matches
   test-*.sh|*_test.sh under any dir, plus renames (R-side).
3. MEDIUM: the C4 kill-switch byte-restore claim is untested — add the leg (C4 off →
   selfcheck.md byte-identical modulo generated_at/diff_hash to pre-C4 pinned lib, same idiom
   as the C0 case).

FOREGROUND, suites strictly SOLO, COMMIT before ending.

## Acceptance
Red legs shown · builder-selfcheck suite green · full run-core-offline FOREGROUND SOLO green ·
bash -n + shellcheck -S warning · COMMIT.

## Off_limits
leadv2-dispatch-code.sh; leadv2-review-run.sh; routing; supervise*.

## Terminal artifact
Commit sha + per-finding red/green raw output + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b0ff2748" "<question>" \
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