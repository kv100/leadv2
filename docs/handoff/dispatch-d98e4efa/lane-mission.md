# SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01 — a suite must register itself, not queue for one file

## The defect

`tests/run-all.sh` selects suites two ways: by stem match, and by `EXTRA_SUITE_MAP` — one string
of `"<changed-stem>:<suite-path>"` rows, defined at `:134` and consumed at `:482`.

Every lane that adds a suite must therefore edit **the same block in the same file**. With three
sessions working, that block is a queue: lanes wait for it, and a lane that declares it honestly in
its write set collides with every other lane that does the same.

**Do not "fix" this by making the map bigger or by adding a second map.** The task is to remove the
shared file from the registration path.

## What is NOT the defect — measured, do not chase it

Sibling sessions measured this and it is worth your time to know before you start:

- 211 mission files on disk declare `tests/run-all.sh` in `LANE_WRITES`. A declaration in a mission
  lives forever; closing a round does not retract it.
- **None of that affects the conflict decision.** The check reads the live REGISTRY, not the disk:
  `leadv2-active-registry.sh:311` takes a registry row, `:372` and `:500` iterate `sessions` from
  the yaml. Lanes were yielding to dead lanes the check never reads.

So the queue is real but the blocking was phantom. Your job is the queue, not the phantom. And note
the caveat: **an empty registry is today's anomaly, not the norm.** Once the registry migration
lands and rows return, genuine conflicts come back — so the fix must remove the need to edit the
shared file at all, not rely on the file being uncontended.

## What to build

A registration mechanism where **a suite declares its own selection triggers next to itself**, and
`run-all.sh` discovers them by walking the tests directory. Shape is yours to choose; a first-line
marker inside each suite file (the pattern the artifact pane already uses elsewhere in this repo)
and a sidecar file are both acceptable. Requirements on the design:

- Adding a suite touches **only that suite's own file(s)** — never `tests/run-all.sh`.
- Existing `EXTRA_SUITE_MAP` rows keep working. Migrate them in the same change or leave them as a
  supported fallback; do not silently drop a row — a dropped row is a suite CI stops running, and
  nothing goes red to tell you.
- Discovery must be deterministic and must fail loudly on a malformed declaration. A suite whose
  trigger cannot be parsed is an error, never silently unselected.

## Acceptance — behavioural, run it

1. **The serialisation is gone:** add two new suites in two separate worktrees, each declaring only
   its own files, and dispatch both. Neither is refused, and neither edits `tests/run-all.sh`.
2. **Selection still works:** `--scope changed` against a tree where the mapped source is modified
   selects the suite. Paste the line that shows it selected.
3. **No row lost:** every stem currently in `EXTRA_SUITE_MAP` still selects the same suite after the
   change. Prove it by enumeration, not by inspection — a script that walks the old rows and asserts
   each still resolves.

## Evidence required

- One negative control **per changed function**, mutation applied INSIDE the function body.
  Report observed `baseline_rc` / `mutated_rc` / `restored_rc`. Never a `diff_hash`, never a code
  inferred from a tool's verdict.
- **A control that reddens the suite via a bash syntax error does not count** — it proves the file
  stopped parsing, not that the consequence broke. If that is the only mutation available for a
  function, say so: that is a coverage hole and a finding, not something to omit.
- Falsification: remove the assertion on any message text, keep the assertion on state — the control
  must stay RED.
- **Ten consecutive runs**, all exit codes reported. A disagreement between runs IS the finding and
  outranks the rest; that rule caught a real product race last night that one run would have shown
  green ~85% of the time.

## Bounds

- **Never register a selection trigger for a suite file that does not exist yet.** That is CI green
  proving nothing — the exact disease this fleet is removing.
- Do NOT touch `docs/leadv2/` (shared runtime state), `leadv2-dispatch-code.sh`,
  `leadv2-claude-profile-select.sh`, `lib/leadv2-route-arbiter.sh`, `leadv2-active-registry.sh`.
- Do not commit to `main`; do not add to `tests/known-red-suites.txt`; do not weaken an assertion.
- Green under bash AND zsh, failing on disagreement — unquoted `$var` does not word-split in zsh.
- Deletion check before you finish: `git diff --diff-filter=D --name-only main...HEAD` — THREE dots.
  Two dots compare against main's current tip and report files main gained as if you deleted them.
- A file counts as saved when it appears in `git ls-files`, checked by eye. `.gitignore` swallows
  handoff paths silently and `git add` exits 0 while doing nothing.
- Your report lands in the dispatch directory of the MAIN repo, not in this worktree. State its
  full path in your final message.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-d98e4efa" "<question>" \
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