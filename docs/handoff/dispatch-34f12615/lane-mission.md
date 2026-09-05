# ONE-LANE-WATCH-01 — fix round 4

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ONE-LANE-WATCH-01-R2`
LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-watch-v2.sh,plugins/leadv2/scripts/tests/test-lane-watch-v2.sh,docs/handoff/ONE-LANE-WATCH-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `d783ffb`); run with `LEADV2_SUITE_LOCK_DISABLE=1`.
Do NOT touch `plugins/leadv2/scripts/tests/test-phase-precondition.sh` — the commit `3d4b969` on this
branch is foreign and the lead drops it at landing.

## Review verdict on round 3 (reviewer glm, `review-findings.json`)
status=fail high=1:
- **[High] `leadv2-lane-watch-v2.sh:237` `_lw_provider_output_age_min`** — every top-level file in the
  run dir except `broker.json`/`state.json` counts as WORKER output. But `progress.log`,
  `meta.yaml`, `exit_code`, `supervisor.log` are written by the RUNNER (glm-coder / freepool-coder /
  kimi-coder heartbeat, status flips, supervisor polls), so a hung or killed worker keeps reading
  "provider-fresh" and LANE-STALL is suppressed. Measured: 53 min of silence on
  `260901-184335-PHASE-GATE-IS-INVERTED-01-7ddb` never reported.

## Do
1. Invert the rule: worker output is an ALLOW-list, not "everything but two names". Enumerate per
   runner what the MODEL's own tool calls produce (`developer.stream.jsonl` / `*.stream.jsonl`,
   `jobs/*`, the lane worktree mtime that `lane_dirs` already covers) and count only those. Runner
   bookkeeping (`progress.log`, `meta.yaml`, `exit_code`, `supervisor.log`, `broker.json`,
   `state.json`, anything the runner touches on a timer) never counts. If a runner has NO model-
   written file in the run dir, the worktree mtime is the only signal — say so in a comment.
2. Add the measured case to `test-lane-watch-v2.sh`: fixture run dir whose `progress.log` and
   `meta.yaml` are touched "now" while the stream file and worktree are 60 min old → age ≥ 60 →
   LANE-STALL fires. And the positive: a fresh stream file → no stall.
3. Mutation negative control, RUN and paste red: put `progress.log` back into the counted set →
   the new stall case red. Revert.
4. Append "## Round 4 evidence" (suite time, green run, control red) to report.md; commit in the
   lane. An uncommitted exit is a failed round.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-34f12615" "<question>" \
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