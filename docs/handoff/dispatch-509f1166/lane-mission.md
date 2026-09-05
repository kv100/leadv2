# NATIVE-CODEX-OPS-PROFILE-01-R2-TARGETED

Targeted continuation on worktree `4986ec86` at `2e453ca`. Fix the installed
artifacts, not only their source documentation.

1. `codex-lead-AGENTS-pilot.md` is copied by install.sh and still mandates WIP=1.
   Replace it with the same dynamic capacity contract: native slots, provider
   health, dependencies and write-set collisions; independent reads may overlap.
2. `prompts/leadv2-status.md` is the installed fallback status prompt. Make it
   merge native `list_agents` + current plan with external registry/quota facts and
   render only `IN PROGRESS` / `NEXT`, without invented numbers.
3. Keep pulse wording truthful: chat emits a state-change or maximum-60-second
   compact update while active; lifecycle hooks provide start/stop evidence and
   `list_agents` supplies live state. Do not claim a 60-second machine timer that
   is not shipped.
4. Restore the core boundary contract expected by
   `test-codex-child-session-boundary.sh`: a headless single-task lead must never
   recursively launch another full lead session. Preserve the phrase/semantic
   test while keeping Codex as the lead under an optional parent of any type, not
   specifically Claude/Opus.
5. Tests must scan the actual installed brief and fallback prompt, and run the
   core child-session boundary suite. Preserve Terra/high and all prior checks.

Do not touch dispatcher, review engine or hooks. Commit only authorized files
and leave clean.

acceptance:
  surface: file_artifact
  observable: The files actually copied/used at install enforce dynamic WIP, compact native status and truthful pulse, while the headless lead retains its no-recursive-lead boundary.
  authored_at: 2026-08-24T21:55:00Z

LANE_WRITES: plugins/leadv2/docs/codex-lead-AGENTS-pilot.md,plugins/leadv2/codex-lead/prompts/leadv2-status.md,plugins/leadv2/codex-lead/marketplace/plugins/leadv2/skills/leadv2-status/SKILL.md,plugins/leadv2/codex-skills/source-command-leadv2/SKILL.md,plugins/leadv2/codex-lead/tests/test-codex-install.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-509f1166" "<question>" \
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