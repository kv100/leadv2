Round 1's code is ALREADY COMMITTED in this lane as 09f7d8da: ref/leadv2-main-model.yaml flipped to opus, MAIN_MODEL_DEFAULT introduced in leadv2-repo-install.sh so LEADV2_MAIN_MODEL no longer derives from the think resolver, +63 lines in test-fable-think-tier.sh, +11 in run-all.sh. The worker died before proving any of it and the lead committed it verbatim as a rescue, so treat it as UNPROVEN, not correct. Do NOT redo or rewrite it. Read docs/handoff/LEAD-IS-OPUS-THINK-IS-FABLE-01/brief.md and deliver only what is still missing: item 2's argument about the sonnet fallback in leadv2-main-model-check.sh for a freshly adopted repo with no skills yet, item 3 the backfill of the repos already stamped fable (environment-platform, m3, mondia-portal, mp-frontend, mythical-aii, pf3-backend, pf3-local-dev, pf3-smart-contracts, plus getmany-followup-bot and m3-market if they carry it) where in m3 the env lives in .claude/settings.local.json because settings.json is git-tracked and must stay untouched, item 4 the written answer on whether Fable should also be a worker arm for hard tasks, and item 6 negative controls in BOTH directions so neither axis can be re-collapsed. Then green on macOS AND in a Linux container with exit codes pasted, and prove --scope changed selects the suite on a change to leadv2-repo-install.sh and to ref/leadv2-main-model.yaml. Never commit inside a MythicalGames repo. Also check git diff main..HEAD for files this lane would DELETE because it branched early and restore them from main. Commit in this lane.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-c717fd8a" "<question>" \
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