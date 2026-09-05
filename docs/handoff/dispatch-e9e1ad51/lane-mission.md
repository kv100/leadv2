# FP-07 — review engine codex arm chokes (P1)

Repo: canonical leadv2 plugin (this repo). Context: docs/leadv2/freepool-backlog.md §FP-07.

Bug (observed twice, deterministic, 2026-08-28, task PHASE-DISCIPLINE-01): the codex
reviewer arm launched by plugins/leadv2/scripts/leadv2-review-run.sh dies on its FIRST
command when `rg` exits 1 (rg exit 1 = "no matches", not an error). The thread ends with
a 288-byte body -> gate `status: blocked reason=review_body_lost`. Evidence:
docs/handoff/PHASE-DISCIPLINE-01/review-codex.md (both attempts identical).

Fix, two layers:
1. The codex reviewer invocation: find where the review mission/prompt or the codex glue
   makes rg exit-1 fatal (the runner treats nonzero as command failure and codex gives up).
   Make the review prompt/glue instruct or wrap searches so no-match is not fatal
   (`rg ... || true` pattern in the mission text, or the glue's error classification).
2. leadv2-review-run.sh: on reason=review_body_lost, retry ONCE on a DIFFERENT arm from
   the pool (author-exclusion still binding); journal `review_arm_retry from=<a> to=<b>`.
   Never retry the same arm twice; if no distinct arm remains, keep status=blocked.

Tests (plugins/leadv2/scripts/tests/): stub arm that writes a <200-byte body -> engine
retries on a different stub arm and passes; both-arms-lost -> blocked; negative control
declared in header and RUN red (mutation: retry on the SAME arm — must be caught).
Run the suite + bash -n; raw output in report.
Commit: fix(leadv2): FP-07 review arm no-match choke + body-lost retry on distinct arm.
Report: docs/handoff/FP-07/report.md (max 250 words), end DELIVERABLE_COMPLETE.

(re-dispatch 2026-08-28: class=Standard; first attempt 27434c7a misclassified Light via fallback, freepool arm produced empty diff)

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-e9e1ad51" "<question>" \
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