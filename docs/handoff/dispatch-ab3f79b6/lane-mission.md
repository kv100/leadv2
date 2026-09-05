# NATIVE-CODEX-CONTROL-PLANE-01-R3-TARGETED

One targeted High fix on worktree `a2d18758` at `1721008`.

The isolated apply_patch allow path must not trust a lexical
`.claude/worktrees/<id>` substring or `abspath`. Resolve `cwd` and targets through
realpath, require the cwd to be a genuine linked Git worktree (git-dir distinct
from common-dir and under the common repo's worktrees registry), require its real
toplevel to equal the allowed lane root, and require every existing or future
patch target to resolve inside that real toplevel. Main worktree, ordinary fake
directories, symlinked fake worktrees, absolute escapes and `..` escapes deny.

Add executable fixtures for a real temporary linked worktree and the symlink
bypass. Preserve all 18 focused and 43 manifest/72 guard cases. Commit only the
hook and focused test, leave clean.

acceptance:
  surface: file_artifact
  observable: apply_patch is allowed in a genuine isolated linked worktree and denied for main, fake, symlinked or escaping paths.
  authored_at: 2026-08-24T21:51:00Z

LANE_WRITES: plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh,plugins/leadv2/codex-lead/tests/test-codex-hooks.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-ab3f79b6" "<question>" \
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