# D6-REGISTRY-LANE-OWNERSHIP-01 — give a lane a real owner

The long background is in `context.md` beside this file. Read it only if a decision below is
unclear; everything you need to build is here.

## The defect, measured — not inferred

```
lead_session_id:  Counter({'direct': 16})   <- EVERY row, of ALL THREE live sessions
session_id:       15 distinct values        <- already carries the session pid
```

None of the three variables in this chain is ever set, so it collapses to its last resort in all
six places it appears (`leadv2-dispatch-code.sh:7083`, `leadv2-session-runner.sh:197`,
`leadv2-codex-session-runner.sh:101`, `leadv2-inbox.sh:123`, `leadv2-broad-status.sh:1396`, and the
test `test-lane-placement-pin.sh:194`):

```
${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-${CLAUDE_SESSION_ID:-direct}}}
```

So: **a lane cannot be attributed to the session that made it**, the per-session lane cap counts
every session's lanes in one bucket, and a reader forced to pick one row per task cannot pick the
right one. `leadv2-lanes-snapshot.sh:644` already says `# last-write-wins on dup task_id` — that is
not "duplicates are fine", it is recorded resignation. `lib/leadv2-lane-state.sh:88-91` names the
real repair and does not make it. You are finishing it.

## What to build

A resolver, `plugins/leadv2/scripts/lib/leadv2-lead-identity.sh`, exposing
`leadv2_lead_session_id()` that returns a stable identity of the form `lead-<durable_pid>-<birth_hash>`.
`_lv2_durable_pid()` and `_lv2_pid_birth()` already exist (`leadv2-active-registry.sh:809` and `:860`) —
use them, do not reinvent.

**Land everything OUTSIDE the dispatcher.** Do NOT edit `leadv2-dispatch-code.sh` — another session
owns it. Put the exact one-line replacement for `:7071` in your report, ready to paste, and say it
is not landed.

## Acceptance — the cap test, not a count of names

With cap=1: a dispatch must be REFUSED for a second lane of the SAME session and PERMITTED for a
lane of ANOTHER session. "Two distinct owners appear in a file" is not acceptance; the cap behaving
differently for self and other is.

Plus the live check: **≥2 distinct `lead_session_id` values in the registry while two sessions work.**
Reading the code proves nothing here — the chain looks functional, has six links, and fails into a
constant silently.

## Evidence required

- One negative control **per changed function**, mutation applied INSIDE the function body.
  Report observed `baseline_rc` / `mutated_rc` / `restored_rc`. Never a `diff_hash`, never a code
  inferred from a tool's verdict.
- **A control that reddens the suite with a bash syntax error does not count** — it proves the file
  stopped parsing, not that the consequence broke. If that is the only mutation you can find for a
  function, say so: it is a coverage hole and a finding, not something to omit. (A sibling lane hit
  this three times last night and flagged it honestly; do the same.)
- Falsification: remove the assertion on any message text and keep the assertion on state — the
  control must stay RED.
- **Ten consecutive runs**, all exit codes reported. A disagreement between runs IS the finding and
  outranks the rest — that rule caught a real product race last night that one run would have
  shown green ~85% of the time.

## Bounds

- Declared write set only: `lib/leadv2-lead-identity.sh` and its suite.
- Do NOT touch `tests/run-all.sh` — put the `EXTRA_SUITE_MAP` row in the report, ready to paste,
  and state plainly that CI does **not** select the suite yet.
- Do NOT touch `docs/leadv2/` (shared runtime state — nine such files had to be subtracted from a
  sibling lane's merge last night), `leadv2-active-registry.sh` (another lane owns it),
  `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`, `lib/leadv2-route-arbiter.sh`.
- Do not commit to `main`; do not add to `tests/known-red-suites.txt`; do not weaken an assertion.
- Green under bash AND zsh, failing on disagreement — unquoted `$var` does not word-split in zsh.
- Deletion check before you finish: `git diff --diff-filter=D --name-only main...HEAD` — THREE dots.
- A file counts as saved when it appears in `git ls-files`, checked by eye. `.gitignore` swallows
  handoff paths silently and `git add` exits 0 while doing nothing.
- Your report goes to the dispatch directory in the MAIN repo, not into this worktree. Say its path
  in your final message.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-33e16647" "<question>" \
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