# CORE-OFFLINE-CODEX-RECURSION-01 — fix round 3 (critic BLOCK, Critical)

Same worktree. Keep the diff, fix one thing. Full findings:
`docs/handoff/CORE-OFFLINE-CODEX-RECURSION-01/critic-round2.md`.

## The one Critical — the round-2 `coproc` handling (:341-349) is wrong in BOTH directions

An independent critic proved it by executing the commands with a marker file, not by reading:

- **FALSE-KILL** — `coproc grep leadv2-supervise.sh somefile.txt`: real bash runs only `grep`
  (marker proves the launcher never ran), the parser flags it, and the end-to-end runner kills
  the session `rc=5` after one call. That is precisely the "launcher as a grep operand" class
  CODEX-LEAD-RECURSION-FALSEKILL-01 exists to prevent, newly reachable through `coproc`.
- **FAIL-OPEN** — `coproc .claude/scripts/leadv2-supervise.sh --flag`: bash genuinely executes
  the launcher (marker shows `LAUNCHER-RAN args=[--flag]`), the parser misses it, and the
  runner burns all 6 attempts.

**Root cause:** the code decides "this token is a skippable NAME" from *"is there another token
after it"*. Real bash (`man bash` §Coprocesses) decides from *"is the NEXT token a
compound-command opener"* — a NAME is syntactically disallowed before a **simple** command.

Correct rule, implement exactly this:

| form | meaning | parser must |
|---|---|---|
| `coproc { cmd; }` | anonymous, compound | descend into the group |
| `coproc NAME { cmd; }` | named, compound | skip NAME, descend into the group |
| `coproc cmd args…` | simple command — **NAME not allowed** | treat `cmd` as the program |

So: after `coproc`, if the next token is `{` → descend. Else if the token AFTER the next one is
`{` → skip the NAME, descend. Otherwise the next token IS the program.

## The test passed for the wrong reason — fix that too

`test-codex-session-runner.sh:57-58,251-265` covers only `coproc worker { launcher; }`, the one
shape where the buggy heuristic happens to agree with real grammar. Add all three forms:

Must TRIP: `coproc .claude/scripts/leadv2-supervise.sh --flag`, `coproc { <launcher>; }`,
`coproc worker { <launcher>; }` (keep).
Must NOT trip: `coproc grep <launcher> somefile.txt`, `coproc worker { grep <launcher> f; }`.

Each new case: show it fails against the pre-round-3 parser and passes after.

## Non-blocking, address only if trivial

`:506` — the call site cannot distinguish a Python traceback from a clean "not detected", so a
parser exception is a silent fail-open. If a one-line distinction is possible (e.g. a distinct
exit code for an internal error, logged loudly), do it; otherwise leave it and say so — it is
currently unexploited and widening this diff is worse.

Confirmed sound by the critic, do NOT re-touch: the `env -S` depth guard (bounded at depth 4,
40-case fuzz, 0 crashes) and the coproc brace arithmetic.

## Acceptance

1. Before/after parser verdict for all five coproc cases above.
2. `bash plugins/leadv2/scripts/tests/test-codex-session-runner.sh` → `FAIL=0`.
3. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` → `failed=0`, `passed >= 21`.
4. Re-run the round-2 negative list; all still non-tripping.

Append `## Fix round 3` to `docs/handoff/CORE-OFFLINE-CODEX-RECURSION-01/diagnosis.md`, ending
`DELIVERABLE_COMPLETE`. Do not commit.
