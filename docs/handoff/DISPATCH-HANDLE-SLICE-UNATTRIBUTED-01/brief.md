# DISPATCH-HANDLE-SLICE-UNATTRIBUTED-01 — an unreviewed handle parser is the running spawn path

LANE ROOT: to be created from current main.

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-spawn-handle-parse.sh,tests/run-all.sh,docs/handoff/DISPATCH-HANDLE-SLICE-UNATTRIBUTED-01/

## What the lead found, 2026-09-01

`plugins/leadv2/scripts/leadv2-dispatch-code.sh` sat MODIFIED and uncommitted in the main tree,
written by no lane in this session. Three hunks, all in `_spawn_worker_body`:

- the glm branch and the kimi branch replaced `handle="$(… | tail -1)"` with: strip the trailing
  newline, take everything after the last `/`, then **take the first half of the remaining string
  by character count**, on the stated assumption that the launcher prints `$RUNS/$handle$handle`;
- the codex branch made the error-detail grep case-insensitive.

It is load-bearing **right now**: journal rows from this session show correct full handles
(`handle=260901-031642-SUITE-LOCK-IS-MACHINE-WIDE-01-353b`), so the halving is currently producing
the right answer and reverting it would corrupt every GLM/Kimi handle. It was committed to main as
a salvage precisely because it is the running behaviour — not because it was reviewed.

## Why it still needs a lane

A parser that recovers a value **by halving a string** holds only while the launcher's last line is
exactly the doubled form. Nothing asserts that. A launcher that ever prints one copy, or an
odd-length line, yields a silently truncated handle — and a truncated handle means status polling
watches a run that does not exist, which is the "lane verdicts lie" shape we keep paying for.

## [Critical] 1 — assert the launcher's output contract

Pin what `glm-coder.sh` / `kimi-coder.sh` actually print on a successful start, in a test, from the
real launcher output shape. If it is the doubled form, say so and parse it by construction
(`h=$(( ${#s} / 2 ))` guarded by `[[ "${s:0:h}" == "${s:h}" ]]`), never by unguarded halving.

## [Critical] 2 — refuse a handle that does not round-trip

An extracted handle must be verifiable: its run directory exists, or the spawn is a launch failure
(the empty-handle guard immediately below already has this shape). A handle that names nothing must
never be journalled as `worker_spawned`.

## Acceptance

1. doubled launcher line ⇒ correct handle;
2. single-copy launcher line ⇒ correct handle OR an explicit launch failure, never a truncation;
3. odd-length line ⇒ never a silent half;
4. extracted handle whose run dir is absent ⇒ `spawn_failed`, not `worker_spawned`;
5. mutating the parser to `handle="${_glm_temp}"` (no slice) ⇒ the suite goes RED.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path; RED, revert, GREEN, clean
  `git diff --stat`.
- Measure a suite's exit code WITHOUT a pipeline: `cmd > log 2>&1; echo $?`.
- Bash 3.2.57 only. `git add <file> <file>`, never `git add <dir>`.

## Live evidence, same day

The empty-handle guard fired on a real dispatch minutes after this brief was written:

```
ERROR: spawn(glm-flash) handle= weekly=53% (resets 2026-09-07T02:00:41Z). Threshold=80% has no live run record -- treating as launch failure
worker_spawned by=router model=freepool task=168e6ff1
```

The handle came back EMPTY and the arm fell through to freepool. Empty is the one truncation the
guard below already catches; a half-length handle is the one it does not. Whatever the launcher
printed there, the parser produced nothing from it — so the output contract is not what the parser
assumes at least some of the time, and that is the case [Critical] 1 must pin.
