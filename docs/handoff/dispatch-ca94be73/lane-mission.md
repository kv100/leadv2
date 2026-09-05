# LIVE-LANE-IS-ABSENT-FROM-THE-REGISTRY-01 — a registration that missed and reported success

## The defect, from the one line that survived

Across forty lane journals exactly **one** registration line exists:

```text
active_register_miss task=07401216 rc=0
```

A miss that returned `0`. Everything downstream believes it: the pulse says `линий нет` while a lane
is demonstrably running (measured 2026-09-04 — a live glm arm writing into its worktree while every
status surface reported an empty board). The registry is not wrong about a row it holds; it is
silent about a row it never wrote.

**Your task is not to make the pulse prettier.** It is to find the path on which registration does
not happen, and make that path say so out loud.

## Where to look, and what not to assume

- `plugins/leadv2/scripts/lib/leadv2-active-registry.sh` — the registry itself, and the call site in
  the dispatcher that reaches it. The dispatcher file `leadv2-dispatch-code.sh` is owned by another
  session: **read it, do not edit it.** If the fix belongs there, put the exact replacement text in
  your report and say plainly that it is not landed.
- Two registries have already been observed diverging, and `docs/leadv2/active.yaml` is git-tracked,
  so every worktree carries a frozen copy. `~/.claude/leadv2-state/leadv2/active.yaml` is the live
  one. State which store you measured, in the sentence, every time.
- `BASH_SOURCE[0]` is unset under `bash -c`, which moves the resolved path of a sourced library.
  That is a known way for this code to write somewhere nobody reads. A sibling defect was exactly
  this shape: `leadv2-phase-record.sh` resolves its store from an inherited `LEADV2_PROJECT_ROOT`
  and wrote 25 directories of phase records into the wrong repository, rc=0, no output.
- `rc=0` from a helper proves the helper returned, not that it wrote. Check for the row, by path.

## What to build

1. **A reproduction**: the narrowest command that registers a lane and leaves no row, with the
   store's path named. If the miss is conditional, name the condition.
2. **The path speaks**: on the failing path the code must report the miss in a way a reader cannot
   confuse with success — a non-zero return a caller can act on, or a journal line whose text says
   the row was not written. `active_register_miss … rc=0` is precisely the shape being removed; do
   not reproduce it under a new name.
3. **Its own suite** — `plugins/leadv2/scripts/tests/test-active-register-miss.sh`, carrying a
   `# run-all-triggers:` declaration so CI selects it (self-registration has landed; do NOT edit
   `tests/run-all.sh`).

## Acceptance

- The reproduction, run before and after: before, a row is missing and the caller sees `0`; after,
  the caller sees the failure. Paste both.
- **A negative control per changed function**, mutation applied INSIDE the function body, reported as
  the observed `baseline_rc` / `mutated_rc` / `restored_rc` triple. Never a `diff_hash`, never a code
  inferred from a tool's verdict.
- **Under each mutation exactly ONE assertion may go red, and it must be the named one.** A mutation
  that reddens several cases means the cases share a cause and are not independent evidence. A
  control that reddens the suite by crashing it or breaking the parse does not count — that proves
  the file stopped running, not that the consequence broke.
- Before running a mutant, assert it **differs from the original byte for byte**: a mutation whose
  anchor stopped matching writes nothing and reads as a control that passed.
- Falsification: remove the assertion on any message text, keep the assertion on state — the control
  must stay RED.
- **Ten consecutive runs**, all exit codes reported. A disagreement between runs IS the finding and
  outranks the rest.

## Bounds

- Do NOT edit `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`,
  `lib/leadv2-route-arbiter.sh`, `tests/run-all.sh`, `tests/known-red-suites.txt`.
- Do NOT touch `docs/leadv2/` — shared runtime state; nine such files had to be subtracted from a
  sibling lane's merge, and a live pulse reads them while you work.
- Do not commit to `main`. Do not weaken an assertion. Never `reset --hard`, `clean`, `stash`, or
  `worktree prune` — live lanes stand next to yours in a shared tree.
- Green under bash AND zsh, failing on disagreement. Note that `declare -F` answers "defined" under
  zsh for a function that does not exist; do not build a guard on it.
- Deletion check before you finish: `git diff --diff-filter=D --name-only main...HEAD` — THREE dots.
- A file counts as saved when it appears in `git ls-files`, checked by eye: `.gitignore` swallows
  handoff paths silently and `git add` exits 0 while doing nothing.
- Your report lands in the dispatch directory of the MAIN repo, not in this worktree. State its full
  path in your final message.
- If any instruction here rests on a false premise, stop and say so with the measurement. That is a
  complete and welcome answer; papering over it is not.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-ca94be73" "<question>" \
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