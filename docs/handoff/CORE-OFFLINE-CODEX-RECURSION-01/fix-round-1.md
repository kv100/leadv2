# CORE-OFFLINE-CODEX-RECURSION-01 — fix round 1 (Codex HIGH)

Work in the SAME lane worktree you already used:
`~/Projects/leadv2/.claude/worktrees/CORE-OFFLINE-CODEX-RECURSION-01`.
Keep your existing diff; add to it. Do not revert your round-1 changes — Codex confirmed the
root-cause verdict (the stub was fictional, the detector's envelope handling is correct).

## The finding (HIGH, confirmed with runtime evidence, not a code-read)

`_launcher_spawn_detected` (`plugins/leadv2/scripts/leadv2-codex-session-runner.sh`, parser
body ~:290-332) is **fail-open for real shell forms that DO execute a launcher**. Codex ran
your parser against them and got `launcher-first=False` on all four:

| command in `command_execution.command` | parser stops at |
|---|---|
| `exec .claude/scripts/leadv2-supervise.sh` | `exec` |
| `env -i LEADV2_TASK_ID=x bash .claude/scripts/leadv2-supervise.sh` | `-i` |
| `if .claude/scripts/leadv2-supervise.sh; then :; fi` | `if` |
| `bash .claude/scripts/leadv2-supervise.sh` | `bash` — **verify this one yourself first** |

Note the last row: plain `bash <launcher>` is the shape the passing recursion test uses via
`/bin/zsh -lc "env NAME=v bash …"`, so it must already work at the nesting level the test
exercises. Reproduce each row against the parser BEFORE changing anything, and report which
actually fail — do not take this table on faith. Fix only what you reproduce.

This matters in production: the guard exists to stop a codex child session burning tokens
resuming itself under its own flock. Every form it misses is 6 wasted Codex turns.

## What to change

Extend the token walk so these reach the launcher token:

- **`exec`** — treat as a transparent prefix, like the interpreters already in `INTERPRETERS`.
- **`env`** — advance past option flags (`-i`, `-u NAME`, `--ignore-environment`, `-C dir`,
  `--`) and `NAME=value` assignments, to the first real operand. Model it on the existing
  `_next_operand` / `TIMEOUT_ARG_OPTS` / `XARGS_ARG_OPTS` handling — reuse, don't duplicate.
- **Shell control words** — skip a leading `if`, `then`, `else`, `elif`, `do`, `while`,
  `until`, `!`, `{`, `time` when they head a sub-command.

## Hard constraints — the same one as round 1

**Do not weaken CODEX-LEAD-RECURSION-FALSEKILL-01.** Widening the walk is exactly how the
original over-broad guard got written. After the change, the launcher must STILL be reachable
only at **execution position**. These must all remain non-tripping, and your `mention` test
case must still pass:

- `grep -n leadv2-supervise.sh docs/x.md`
- `sed -n 1,5p .claude/scripts/leadv2-codex-session-runner.sh`
- `echo see .claude/scripts/leadv2-fanout.sh for details`

Add at least these as new negative cases too, since the walk now sees further:
`env -i FOO=bar grep leadv2-supervise.sh x.md` (launcher is a grep operand, must NOT trip)
and `cat .claude/scripts/leadv2-fanout.sh` (operand, must NOT trip).

## Codex's LOW (address only if free)

The FALSEKILL assertion's "absence of the recursion string" clause is redundant given `rc=4`.
Leave it — redundant is not wrong, and removing it buys nothing.

## Acceptance (paste verbatim into the deliverable)

1. Reproduction table: each of the 4 rows above, parser verdict BEFORE your fix.
2. Same table AFTER — every genuine execution form now trips.
3. New positive test cases for the forms you fixed + new negative cases above; the suite runs
   `FAIL=0`.
4. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` → `failed=0`, `passed >= 21`.
5. **Non-tautological proof**: each NEW positive case fails against the pre-fix parser and
   passes after. Show both.

## Deliverable

Append a `## Fix round 1` section to
`docs/handoff/CORE-OFFLINE-CODEX-RECURSION-01/diagnosis.md`, ending with
`DELIVERABLE_COMPLETE`. Do not commit.
