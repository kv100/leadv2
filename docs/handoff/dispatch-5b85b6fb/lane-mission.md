# COMBO2-FIX2 — close 3 codex HIGHs (~/Projects/leadv2, lane 04789baf)

Lane is 57/0 green; codex review found 3 HIGHs — READ THE REPORT FIRST (exact anchors + fix
directions + required tests are in it):
.claude/worktrees/04789baf/docs/handoff/dispatch-04789baf-review/codex.r1.md

1. HIGH: _codex_worker_liveness_deadline_check (dispatch-code.sh:~3855) declares dead on ANY
   codex-status failure. Require a positively-parsed missing-row result («No job found»)
   before arm_dead; other failures = unknown/fail-open + journal, reservation intact. Test:
   status exits nonzero with transient error → no strike/spill.
2. HIGH: _codex_newest_rollout_since (:~3625) falls back to newest-of-anyone when own
   session_meta.cwd is absent/mismatched — a sibling's turn_aborted can kill this dispatch.
   No terminal decision without an exact expected-worktree candidate; journal ambiguity and
   continue. Test: concurrent sibling + absent own cwd → no terminal verdict.
3. HIGH: review-run.sh:~838 round-0 consumes selfcheck.md verdict RED without diff-hash
   binding — stale RED rejects a healthy new diff. Write diff_hash into selfcheck.md at
   build, consume round-0 only on hash match; absent/malformed/mismatch → journal + normal
   LLM review. Test: stale-RED/current-diff-mismatch.

FOREGROUND everything, suites strictly SOLO, COMMIT before ending (uncommitted exit =
incident; the stop-gate will checkpoint you but that is the incident path, not the plan).

## Acceptance
3 new red-first legs green · affected suites green · full run-core-offline FOREGROUND SOLO
green · bash -n + shellcheck -S warning · COMMIT.

## Off_limits
leadv2-dispatch-product-close.sh; lib/leadv2-builder-selfcheck.sh (combo-1 lane owns them —
EXCEPT writing diff_hash into selfcheck.md if that requires a selfcheck writer change: in
that case coordinate by writing ONLY the minimal hash-stamp line and note it in the artifact);
routing; supervise*.

## Terminal artifact
Commit shas + per-HIGH red/green raw output + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-5b85b6fb" "<question>" \
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