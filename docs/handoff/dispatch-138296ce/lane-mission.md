# MISSION — extend `mktemp-guard.sh` to the bare suffixed template

**Repo: `~/Projects/leadv2` (the shared plugin repo). Exactly two files. Nothing else.**

Founder permission recorded 2026-09-06T20:05Z in `persona-engine/docs/leadv2/open-threads.md`
(commit `b67cea69c`, tag `[MKTEMP-GUARD-PERMISSION]`), verbatim option chosen: *«Разрешаю эту
правку — только этот объём: mktemp-guard.sh + три случая сюиты (включая молчание на R4).
Исполнитель — сессия, не лид. Откат одним git revert.»*
**If you find yourself needing to touch a third file, STOP and report — the scope is the sanction.**

## Files

- `plugins/leadv2/scripts/lib/mktemp-guard.sh` (36 lines today)
- `plugins/leadv2/scripts/tests/test-mktemp-guard.sh`

## What the guard is, so you do not mis-model it

It is **not** a repo-wide linter. `mktemp_guard()` inspects `${BASH_SOURCE[1]}` — the script that
sourced it — so a test script guards *itself*. Keep that shape.

Today it detects one thing (`:20`):

```
grep -E '\bmktemp\b([^#]*[[:space:]])?-t([[:space:]]|$)' "$script" | grep -vE '^[[:space:]]*#'
```

Every line it can ever see carries `-t`. That was built for `CI-SUITES-ARE-MACOS-ONLY-01`:
`mktemp -d -t name` with no X's at all makes GNU refuse, stdout empty, and every downstream path
resolve against `/`.

## The hole to close

The **bare** form — `mktemp /tmp/foo-XXXXXX.json`, no `-t` — is never examined. Measured on macOS:

```
mktemp /tmp/pf-a-XXXXXX.json   ->  rc=0  /tmp/pf-a-XXXXXX.json     <- returned LITERALLY
mktemp /tmp/pf-e-XXXXXX        ->  rc=0  /tmp/pf-e-cAnzhU          <- control: substituted
first  call: rc=0 path='/tmp/pf-col2-XXXXXX.json'
second call: rc=1 path=''      mktemp: mkstemp failed ...: File exists
```

The path is a fixed shared name, so the **second** caller gets `rc=1` and an **empty string**, and
`"$p/subdir/file"` becomes `/subdir/file`. On Linux this does not happen — GNU coreutils 9.4
substitutes such a template correctly (measured on the VPS). **So the defect is macOS-only, and the
guard must still fire on every platform**, because the code is written on macOS and every lane runs
there. Say the reason in the refusal text: *"BSD does not substitute; GNU does."*

## Add a second, independent detection

- Consider only lines that do **not** carry `-t` — that keeps this check and R4 disjoint.
- In such a line, find the `mktemp` template word and take the **LAST** run of three or more `X`.
  Flag it when any character follows that run inside the same shell word (`.json`, `.txt`, `.tmp`,
  `.py`, `.json.tmp`, …).
- **The trap that already cost a full re-count today:** `X{3,}[A-Za-z0-9._-]` matches the *fourth
  X* of `XXXXXX`, so it flags every correct template. Last run, then tail. Do not write a third
  regex from scratch — port the scan from
  `~/Projects/persona-engine/tests/unit/test-mktemp-suffixed-template.sh`, which is green on main.
- Skip full-line comments, as the existing detection already does.
- Keep `mktemp_guard()`'s contract: no `set -e` trip on the clean path (that is case R5, and it is
  a historic bug — read it before you touch control flow).

## R4 must keep passing — this is the boundary of the sanction

`test-mktemp-guard.sh:109` requires silence on `mktemp -t sp.XXXXXX.json`, and that verdict is
CORRECT: under `-t`, BSD ignores the embedded X's and appends its own component
(`sp.XXXXXX.json.NGFyn6qEKz`), so the file really is unique. Measured. Your new check must never
see that line, because it skips lines carrying `-t`.

**If you conclude the two forms cannot be separated without changing R4, STOP and report.** That is
a different permission, not a judgement call you may make here.

## Tests — three cases and a mutation you actually run

1. **Flags** `_a=$(mktemp /tmp/foo-XXXXXX.json)`.
2. **Silent** on `_a=$(mktemp /tmp/foo-XXXXXX)`.
3. **Silent** on `_a=$(mktemp -t sp.XXXXXX.json)` — R4's shape, unchanged.

Declare the mutation in the suite header and run it: revert your detection to the naive `X{3,}`
form **inside the function body**, show case 2 goes red, restore, show green again. Record
`baseline_rc`, `mutated_rc` and the red line in the report. A guard whose negative control was
never run is the lying-green disease. Run the whole existing suite too: R1–R6 must all still pass.

## Constraints — shared tree, hard

- Two files. No `git add -A`, no `reset --hard`, no `clean`, no `stash`, no `worktree prune`, no
  push to origin.
- **Each edit its own commit, with the reasoning in the body** — not "fix": why this shape, and the
  provenance of the claims it changes. Revert must be one `git revert`.
- Check the index in its own step and gate it in the command; if foreign files are staged, do not
  commit at all and say so.
- Do not touch any `CLAUDE.md`, `.claude/settings.json`, or permission configuration.
- `rc=0` means nothing by itself — read the summary line; `rc=$?` after a pipe is the last stage's.
  Derive every zero a second way.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-138296ce" "<question>" \
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