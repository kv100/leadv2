# architect — CORE-OFFLINE-CODEX-RECURSION-01 fix round 1

Design only. No implementation. Lane worktree:
`~/Projects/leadv2/.claude/worktrees/CORE-OFFLINE-CODEX-RECURSION-01` (round-1 diff kept, added to).

## 0. Reproduction FIRST (done, not taken on faith)

Extracted the live parser body from `plugins/leadv2/scripts/leadv2-codex-session-runner.sh`
(`_launcher_spawn_detected`, lines ~199-350) into a standalone driver at `/tmp/repro09c/parser.py`
and fed it Codex's four rows plus the FALSEKILL negatives. Verdicts against the **current** (round-1)
parser:

| # | command | verdict | Codex claimed |
|---|---|---|---|
| 1 | `exec .claude/scripts/leadv2-supervise.sh` | **pass** (fail-open) | fails ✅ |
| 2 | `env -i LEADV2_TASK_ID=x bash .claude/scripts/leadv2-supervise.sh` | **pass** (fail-open) | fails ✅ |
| 3 | `if .claude/scripts/leadv2-supervise.sh; then :; fi` | **pass** (fail-open) | fails ✅ |
| 4 | `bash .claude/scripts/leadv2-supervise.sh` | **TRIP** | fails ❌ **Codex is wrong** |
| — | `/bin/zsh -lc "env NAME=v bash …supervise.sh"` (the recursion test's shape) | TRIP | — |
| n1 | `grep -n leadv2-supervise.sh docs/x.md` | pass ✅ | — |
| n2 | `sed -n 1,5p …codex-session-runner.sh` | pass ✅ | — |
| n3 | `echo see …leadv2-fanout.sh for details` | pass ✅ | — |
| n4 | `env -i FOO=bar grep leadv2-supervise.sh x.md` | pass ✅ (already correct) | — |
| n5 | `cat .claude/scripts/leadv2-fanout.sh` | pass ✅ (already correct) | — |

**Row 4 does not reproduce.** `bash` is in `INTERPRETERS`; `rest[0]` is a non-`-` token, so the
operand branch reaches `is_launcher(<launcher>)` and returns True. Fix scope is rows **1, 2, 3 only**.
Row 4 must be added as a *regression* positive (it already passes) — not as a fix.

Both new negatives (n4, n5) already pass pre-fix; their value is as **post-fix** guards, since the
walk will see further after the change. They must be added regardless.

## 1. Root cause per failing row

All three die in the same place: the leading-wrapper strip loop in `eval_tokens`
(runner `~:283-303`). The loop only advances on `sudo|env|command|nohup|setsid`, `NAME=value`,
`timeout`, `xargs`; anything else `break`s and becomes `prog`.

| row | token that breaks the loop | why it is not an operand |
|---|---|---|
| 1 | `exec` | POSIX special builtin; replaces the shell with its operand. The operand IS execution position. |
| 2 | `-i` | `env` is stripped, but `_next_operand`-style flag handling was never applied to it, so the very next token (a flag) becomes `prog`. |
| 3 | `if` | reserved word; `split_unquoted` already splits `; ` so the sub-command is `if <launcher>`. The launcher heads the condition list = execution position. |

## 2. Design — three surgical extensions to the strip loop

All three are **execution-position-preserving**: every token skipped is a shell keyword or wrapper
that itself consumes no operand into non-execution position (the one exception, `env`'s arg-taking
flags, is handled by consuming the flag's argument, exactly as `timeout`/`xargs` already do). The
token the walk lands on is still the *program*, and `is_launcher` is still tested only there (or on
an interpreter's script operand). This is the invariant that keeps
CODEX-LEAD-RECURSION-FALSEKILL-01 intact.

### 2a. `exec` — transparent prefix

Add `"exec"` to the existing flat wrapper tuple alongside `sudo|env|command|nohup|setsid`.
`exec [-cl] [-a name] cmd` — the `-a` form takes an argument. Rather than a special case, route
`exec` through the same `_next_operand` treatment as `env` (2b) with
`EXEC_ARG_OPTS = {"-a"}`. Cheapest correct form: one shared branch.

### 2b. `env` — flag-aware advance (reuse `_next_operand`, do not duplicate)

Introduce next to `TIMEOUT_ARG_OPTS` / `XARGS_ARG_OPTS`:

```
ENV_ARG_OPTS = {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}
EXEC_ARG_OPTS = {"-a"}
```

and move `env`/`exec` out of the flat tuple into:

```
if t in ("env", "exec"):
    i = _next_operand(toks, i + 1,
                      ENV_ARG_OPTS if t == "env" else EXEC_ARG_OPTS)
    continue
```

`_next_operand` already handles `-i`, `--ignore-environment`, attached (`-u=X`, `--chdir=/x`),
and the `--` sentinel; it stops at the first non-`-` token. It stops on `NAME=value` too — the
outer loop's `^[A-Za-z_]\w*=` branch then consumes those. So
`env -i LEADV2_TASK_ID=x bash <launcher>` walks `env → -i → LEADV2_TASK_ID=x → bash` and hits the
interpreter branch. **Reuse, zero duplication.**

Negative safety: `env -i FOO=bar grep <launcher> x.md` lands on `grep` — not a launcher, not an
interpreter → `False`. Preserved.

### 2c. Shell control words — transparent

```
CONTROL_WORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while",
                 "until", "!", "{", "}", "time", "coproc"}
```

with a strip-loop branch `if t in CONTROL_WORDS: i += 1; continue`.

- `fi`/`done`/`}` are included so a trailing sub-command fragment degenerates to an empty walk
  (`i >= len(toks)` → `False`) instead of `prog="fi"`. Harmless, and it avoids a future surprise.
- `time` and `!` are also real binaries/paths in other positions, but the strip loop only inspects
  **leading** tokens, so `grep ! x` (operand `!`) is untouched.
- `(`/`)` need no entry — `split_unquoted` already splits on them.

### 2d. Ordering constraint inside the loop

The control-word branch must be checked **before** the `NAME=value` regex (no overlap in practice,
but keeps the read order keyword → wrapper → assignment) and the whole loop must remain
`while i < len(toks)` with every branch strictly advancing `i` — `_next_operand` can return `i`
unchanged only when `toks[i+1]` is already an operand, and the `i+1` start guarantees progress.
No new unbounded-loop surface.

### Explicitly NOT changed

- `is_launcher` / `LAUNCHER_RE` — untouched. Widening the *pattern* is how FALSEKILL-01 happened.
- `scan_command` recursion depth cap (4), `split_unquoted`, `shell_tokens`.
- The interpreter/`eval`/here-string branches.
- Codex's LOW (redundant "absence of recursion string" clause in the FALSEKILL assertion) — **left
  as-is per mission**: redundant is not wrong.

## 3. Test plan — `plugins/leadv2/scripts/tests/test-codex-session-runner.sh`

The existing idiom is whole-runner cases driven by `STUB_MODE`, asserting `rc=5` +
`"CODEX-LEAD RECURSION"` (positive) or `rc=4` + `calls=$runner_stall_max` (negative). Keep that
surface — it exercises the real detector on real `item.completed`/`command_execution` envelopes,
not a hand-lifted parser copy.

**New positive stub modes** (each emits one `command_execution` line, wrapped in the production
`/bin/zsh -lc "…"` shape like the existing `recursion` mode):

| mode | command emitted | expected |
|---|---|---|
| `recursion-exec` | `exec .claude/scripts/leadv2-supervise.sh` | rc=5, 1 exec call |
| `recursion-env` | `env -i LEADV2_TASK_ID=x bash .claude/scripts/leadv2-supervise.sh` | rc=5, 1 exec call |
| `recursion-if` | `if .claude/scripts/leadv2-supervise.sh; then :; fi` | rc=5, 1 exec call |
| `recursion-bash` | `bash .claude/scripts/leadv2-supervise.sh` | rc=5, 1 exec call (**regression**, already green pre-fix) |

**Negative extension:** append two lines to the existing `mention` mode:
`env -i FOO=bar grep leadv2-supervise.sh x.md` and `cat .claude/scripts/leadv2-fanout.sh`.
The existing `falsekill` assertion (rc=4, calls=stall_max, no recursion string) then covers 5
mention shapes instead of 3 — no new case block needed, no new assertion to write.

Net: +4 assertions → `passed` rises from 17 to 21 (≥21 satisfied), `failed=0`.

**Non-tautological proof (acceptance #5).** Run the new positive modes against the **pre-fix**
parser and show rc=4 (stall-capped, guard never fired); then post-fix show rc=5. Mechanically:
`git stash` the parser hunk (tests only in tree) → run → record → `git stash pop` → run → record.
`recursion-bash` is expected rc=5 in **both** runs and must be labelled a regression case, not
claimed as proof — claiming it would be exactly the tautology the acceptance bar forbids.

## 4. Risks

| risk | mitigation |
|---|---|
| Control-word list re-opens FALSEKILL-01 | Every entry is a reserved word that can only head a command list; leading-token-only scope; 5 negatives in `mention` mode assert it. |
| `exec` sharing the `env` branch mis-parses `exec -a name cmd` | `EXEC_ARG_OPTS={"-a"}` consumes the name; add no test (out of the mission's reproduced set) but the code path is the audited `_next_operand`. |
| `_next_operand` returning an index past `len(toks)` | `eval_tokens` already guards `if i >= len(toks): return False` after the loop. Unchanged. |
| Stub-mode proliferation makes the suite slow | 4 new modes, each one runner invocation against the stub — same cost class as the existing `recursion` case. |
| Parallel session reverts the lane diff | Re-`git diff` the two files immediately before staging (repo rule). Do **not** commit — mission says so. |

## 5. Out of scope for the implementer

- `LAUNCHER_RE` changes of any kind.
- Codex's LOW (redundant assertion clause).
- Any change to `leadv2-supervise.sh`, `leadv2-fanout.sh`, or the dispatch ladder.
- Committing, pushing, or touching `docs/leadv2/`.
- `bash <launcher>` "fix" — it is not broken.

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: "Running plugins/leadv2/scripts/tests/run-core-offline.sh prints a final results line reading failed=0 with a passed count of 21 or higher, and the four new recursion-form cases each print a PASS line naming the shape they cover (exec, env, if, bash)."
    authored_at: 2026-08-03T00:00:00Z
  - surface: file_artifact
    observable: "docs/handoff/CORE-OFFLINE-CODEX-RECURSION-01/diagnosis.md ends with a '## Fix round 1' section containing a BEFORE table showing exec/env/if as non-tripping and bash as tripping, an AFTER table showing all four tripping, a before/after pair for each new positive case, and DELIVERABLE_COMPLETE as its last line."
    authored_at: 2026-08-03T00:00:00Z
  - surface: log_line
    observable: "The falsekill case still reports PASS with five launcher-mention shapes (grep, sed, echo, env -i ... grep, cat) and no CODEX-LEAD RECURSION message anywhere in its output."
    authored_at: 2026-08-03T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-codex-session-runner.sh, plugins/leadv2/scripts/tests/test-codex-session-runner.sh

DELIVERABLE_COMPLETE
