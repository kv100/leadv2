# CORE-OFFLINE-CODEX-RECURSION-01 — fix round 2 (Codex delta re-review)

**Work in the worktree you are already in:**
`~/Projects/leadv2/.claude/worktrees/CORE-OFFLINE-CODEX-RECURSION-01-FIX1`.
Keep the existing diff; extend it. Do NOT start a new tree and do NOT revert round 1.

Round 1 was right and its green bar is real (suite 12/0, core-offline 21/21, re-run by the
lead). Codex then attacked the widened token walk and broke it four ways — each verdict came
from actually running the detector, not from reading the diff. All four are in the parser you
just widened.

## Findings to fix

### HIGH-1 — `env -a` / `--argv0` missing from `ENV_ARG_OPTS` (:260) — FALSE-KILL

`env -a leadv2-supervise.sh grep pattern f` executes **grep**, but the walk treats the `-a`
argument as the program and kills the session. This is exactly the CODEX-LEAD-RECURSION-
FALSEKILL-01 regression round 1 was told not to reintroduce. Add `-a` and `--argv0` as
argument-taking (`--argv0=X` attached form too — `_next_operand` already handles attached).

### HIGH-2 — `env -S` is not an arg-consuming option (:309) — RECURSION BYPASS

`env -S "leadv2-supervise.sh"` and `env -S "bash leadv2-supervise.sh"` are NOT detected.
`-S` **splits its string into the command env executes**, so the string is a command line, not
an opaque operand. It needs its own parse: take the `-S` value, run it back through the same
`shell_tokens` → `eval_tokens` path (respecting the existing recursion `depth` guard so a
crafted nest cannot blow the stack). Handle both `-S value` and `--split-string=value`.

### HIGH-3 — `time` and `coproc` in `CONTROL_WORDS` (:268) — RECURSION BYPASS

Generic "skip the word" is wrong for both:
- `time -p leadv2-supervise.sh` → `-p` becomes the apparent program, not detected. `time`
  takes `-p`; skip its flags, then continue at the real program.
- `coproc worker { leadv2-supervise.sh; }` → not detected, yet bash runs the launcher.
  `coproc` may be followed by an optional NAME and then a command or a `{ … }` group; descend
  into the group rather than skipping to the next token.

Remove `time` and `coproc` from `CONTROL_WORDS` and give each explicit handling.

### MEDIUM-4 — closing words `fi` / `done` / `}` as leading tokens (:303) — FALSE-KILL

`if true; then :; fi leadv2-supervise.sh` and friends are **syntax-invalid** — bash rejects
them before anything executes — yet the walk skips the closing word and trips. Simplest
correct fix: drop the closing words (`fi`, `done`, `}`) from `CONTROL_WORDS`; only *opening*
words head a command. State in a comment why closing words are deliberately not skipped.

## Hard constraints (unchanged, and now load-bearing)

- **Every existing negative case must stay non-tripping.** Codex confirmed these are currently
  clean — they must remain so: `env -u PATH grep <launcher> f`, `exec -a name grep <launcher> f`,
  `time cat <launcher>`, `{ echo <launcher>; }`, `env -S "grep <launcher> f"`,
  `if grep -q <launcher> f; then :; fi`, and the `--` sentinel forms.
- No new env var. Minimal diff. Do not touch `LAUNCHER_RE`, `is_launcher`, `scan_command`,
  `split_unquoted`.

## Test coverage — this is where round 1 fell short

Codex's exact words: the added positive tests "are genuine for their exact shapes" but do not
falsify the parser paths above. Add cases for each finding:

Positive (must TRIP): `env -S "bash <launcher>"`, `time -p <launcher>`,
`coproc worker { <launcher>; }`.
Negative (must NOT trip): `env -a <launcher> grep pattern f`,
`env --argv0=<launcher> grep pattern f`, `if true; then :; fi <launcher>` (syntax-invalid,
must not kill).

## Acceptance (paste verbatim)

1. Per-finding before/after parser verdict table — all four, showing the pre-fix wrong verdict
   and the post-fix right one.
2. All new cases: fail against the pre-fix parser, pass after. Show both.
3. Full negative-case list above re-run post-fix, all non-tripping.
4. `bash plugins/leadv2/scripts/tests/test-codex-session-runner.sh` → `FAIL=0`.
5. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` → `failed=0`, `passed >= 21`.

## Deliverable

Append `## Fix round 2` to `docs/handoff/CORE-OFFLINE-CODEX-RECURSION-01/diagnosis.md`,
ending with `DELIVERABLE_COMPLETE`. Do not commit.
