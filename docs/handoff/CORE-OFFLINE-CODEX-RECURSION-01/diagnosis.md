# CORE-OFFLINE-CODEX-RECURSION-01 — diagnosis

## Root cause

`_launcher_spawn_detected` in `leadv2-codex-session-runner.sh` has a strip loop
that peels leading wrappers (`sudo`, `env`, `command`, `nohup`, `setsid`,
`timeout`, `xargs`, `NAME=value`) before checking whether the remaining token
is a launcher at execution position. Three real shell forms were not peeled,
causing the guard to miss genuine self-recursion:

| form | token that broke the loop | why it is not a program |
|---|---|---|
| `exec .claude/scripts/leadv2-supervise.sh` | `exec` | POSIX special builtin; replaces the shell with its operand — the operand IS execution position |
| `env -i LEADV2_TASK_ID=x bash …` | `-i` | `env` was stripped but its option flags were never advanced past, so the first flag became `prog` |
| `if …leadv2-supervise.sh; then :; fi` | `if` | reserved word heading a command list — the launcher is in execution position |

A fourth form, `bash …leadv2-supervise.sh`, already worked (regression case).

## Fix round 1

### BEFORE — parser verdict per case (pre-fix, against HEAD)

| # | command (inside `/bin/zsh -lc "…"`) | verdict | correct? |
|---|---|---|---|
| 1 | `exec .claude/scripts/leadv2-supervise.sh` | no-trip | ✗ **missed** |
| 2 | `env -i LEADV2_TASK_ID=x bash .claude/scripts/leadv2-supervise.sh` | no-trip | ✗ **missed** |
| 3 | `if .claude/scripts/leadv2-supervise.sh; then :; fi` | no-trip | ✗ **missed** |
| 4 | `bash .claude/scripts/leadv2-supervise.sh` | TRIP | ✓ already correct |

### AFTER — parser verdict per case (post-fix)

| # | command (inside `/bin/zsh -lc "…"`) | verdict | correct? |
|---|---|---|---|
| 1 | `exec .claude/scripts/leadv2-supervise.sh` | TRIP | ✓ |
| 2 | `env -i LEADV2_TASK_ID=x bash .claude/scripts/leadv2-supervise.sh` | TRIP | ✓ |
| 3 | `if .claude/scripts/leadv2-supervise.sh; then :; fi` | TRIP | ✓ |
| 4 | `bash .claude/scripts/leadv2-supervise.sh` | TRIP | ✓ (regression) |

### Before/after per new positive case (non-tautological proof)

Run via standalone parser harness with both the pre-fix and post-fix strip
loops (`/tmp/repro09c/proof.py`):

| case | pre-fix | post-fix | notes |
|---|---|---|---|
| exec prefix | no | TRIP | genuine fix |
| env wrapper | no | TRIP | genuine fix |
| if control word | no | TRIP | genuine fix |
| bash interpreter | TRIP | TRIP | regression case — already passed pre-fix, not claimed as proof |

### Negative cases (CODEX-LEAD-RECURSION-FALSEKILL-01 safety)

All five remain no-trip post-fix:

| command | post-fix | status |
|---|---|---|
| `grep -n leadv2-supervise.sh docs/x.md` | no-trip | PASS |
| `sed -n 1,5p .claude/scripts/leadv2-codex-session-runner.sh` | no-trip | PASS |
| `echo see .claude/scripts/leadv2-fanout.sh for details` | no-trip | PASS |
| `env -i FOO=bar grep leadv2-supervise.sh x.md` | no-trip | PASS |
| `cat .claude/scripts/leadv2-fanout.sh` | no-trip | PASS |

### Changes made

**`plugins/leadv2/scripts/leadv2-codex-session-runner.sh`** — three surgical
extensions to the `eval_tokens` strip loop:

1. **`exec`** — moved out of the flat wrapper tuple; routed through
   `_next_operand` with `EXEC_ARG_OPTS = {"-a"}`, same as `env`.
2. **`env`** — moved out of the flat wrapper tuple; routed through
   `_next_operand` with
   `ENV_ARG_OPTS = {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}`.
   Reuses `_next_operand` (handles `-i`, `--ignore-environment`, attached
   forms, `--` sentinel); the outer loop's `NAME=value` branch consumes
   assignments that `_next_operand` stops on.
3. **Shell control words** — `CONTROL_WORDS` set
   (`if`, `then`, `else`, `elif`, `fi`, `do`, `done`, `while`, `until`, `!`,
   `{`, `}`, `time`, `coproc`); strip-loop branch skips them as transparent
   leading tokens. Checked before the `NAME=value` regex.

`LAUNCHER_RE`, `is_launcher`, `scan_command`, `split_unquoted`, and the
interpreter/eval/here-string branches are untouched.

**`plugins/leadv2/scripts/tests/test-codex-session-runner.sh`**:

- Fixed existing `recursion` stub mode: now emits `command_execution` items
  (was `function_call`, which the parser never scans).
- Added `recursion-exec`, `recursion-env`, `recursion-if`, `recursion-bash`
  stub modes — each emits one `command_execution` line in the production
  `/bin/zsh -lc "…"` envelope.
- Added `mention` stub mode — emits five launcher-mention shapes.
- Added 4 positive test cases (loop over `exec`/`env`/`if`/`bash` shapes).
- Added 1 falsekill negative test case (5 mention shapes, asserts `rc=4`,
  `calls=stall_max`, no `CODEX-LEAD RECURSION:` detection message).

### Test results

```
bash plugins/leadv2/scripts/tests/run-core-offline.sh
→ suites passed=21 failed=0 missing=0
```

```
bash plugins/leadv2/scripts/tests/test-codex-session-runner.sh
→ PASS=12 FAIL=0
  - recursion via exec wrapper is caught
  - recursion via env wrapper is caught
  - recursion via if wrapper is caught
  - recursion via bash wrapper is caught
  - five launcher-mention shapes do not trip falsekill
```

DELIVERABLE_COMPLETE

## Fix round 2

### Per-finding before/after parser verdict table

The pre-fix column was run against the round-1 parser by mechanically removing
this round's branches; post-fix was run against the final embedded detector.

| finding | command | pre-fix | post-fix |
|---|---|---:|---:|
| HIGH-1 `env` argv0 operand | `env -a leadv2-supervise.sh grep pattern f` | TRIP (false-kill) | no-trip |
| HIGH-1 `env` argv0 operand | `env --argv0 leadv2-supervise.sh grep pattern f` | TRIP (false-kill) | no-trip |
| HIGH-2 split string | `env -S "bash leadv2-supervise.sh"` | no-trip (missed) | TRIP |
| HIGH-2 attached split string | `env --split-string='bash leadv2-supervise.sh'` | no-trip (missed) | TRIP |
| HIGH-3 `time` flag | `time -p leadv2-supervise.sh` | no-trip (missed) | TRIP |
| HIGH-3 `coproc` group | `coproc worker { leadv2-supervise.sh; }` | no-trip (missed) | TRIP |
| MEDIUM-4 closing word | `if true; then :; fi leadv2-supervise.sh` | TRIP (false-kill) | no-trip |

`env --argv0=leadv2-supervise.sh grep pattern f` is also in the negative
fixture. It was no-trip before and after because `_next_operand` already
skips attached `--option=value` forms; it is a required regression assertion,
not a falsifying case for the new option registration.

### All new cases: pre-fix and post-fix verdicts

| case | pre-fix | post-fix |
|---|---:|---:|
| `env -S "bash <launcher>"` | no-trip | TRIP |
| `env --split-string='bash <launcher>'` | no-trip | TRIP |
| `time -p <launcher>` | no-trip | TRIP |
| `coproc worker { <launcher>; }` | no-trip | TRIP |
| `env -a <launcher> grep pattern f` | TRIP | no-trip |
| `env --argv0 <launcher> grep pattern f` | TRIP | no-trip |
| `if true; then :; fi <launcher>` | TRIP | no-trip |
| `env --argv0=<launcher> grep pattern f` | no-trip | no-trip (attached-form regression) |

### Full negative-case list re-run post-fix

All non-tripping in the Codex session-runner integration fixture:

| command |
|---|
| `env -u PATH grep <launcher> f` |
| `exec -a name grep <launcher> f` |
| `time cat <launcher>` |
| `{ echo <launcher>; }` |
| `env -S "grep <launcher> f"` |
| `if grep -q <launcher> f; then :; fi` |
| `env -- grep <launcher> f` |
| `exec -- grep <launcher> f` |
| `time -- cat <launcher>` |
| `timeout -- 1 cat <launcher>` |
| `xargs -- grep <launcher> f` |
| `env -a <launcher> grep pattern f` |
| `env --argv0 <launcher> grep pattern f` |
| `env --argv0=<launcher> grep pattern f` |
| `if true; then :; fi <launcher>` |

### Changes made

- Added `-a` and `--argv0` to `ENV_ARG_OPTS` and parsed `env -S` / attached
  `--split-string=` command strings through `scan_command` with the existing
  depth limit.
- Replaced generic `time` and `coproc` control-word skipping with explicit
  option/group handling. `coproc` descends into its brace group.
- Removed `fi`, `done`, and `}` from `CONTROL_WORDS`; the parser comments why
  closing words must not make a following token appear executable.
- Extended the integration fixture for all paths above, including both split
  option spellings and every mandated negative/sentinel case.

### Acceptance

1. Per-finding before/after parser verdict table — all four, showing the pre-fix wrong verdict and the post-fix right one.
2. All new cases: fail against the pre-fix parser, pass after. Show both.
3. Full negative-case list above re-run post-fix, all non-tripping.
4. `bash plugins/leadv2/scripts/tests/test-codex-session-runner.sh` → `FAIL=0`.
5. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` → `failed=0`, `passed >= 21`.

### Test results

```
bash plugins/leadv2/scripts/tests/test-codex-session-runner.sh
→ PASS=16 FAIL=0
```

```
bash plugins/leadv2/scripts/tests/run-core-offline.sh
→ suites passed=21 failed=0 missing=0
```

DELIVERABLE_COMPLETE

## Fix round 3

### Coproc grammar correction

The round-2 parser treated the token after `coproc` as a skippable NAME
whenever another token followed it. Bash permits a NAME only when the command
is a compound group. The detector now follows that grammar exactly: it descends
after `coproc {`, skips a NAME only for `coproc NAME {`, and otherwise lets the
next token be evaluated as the simple-command program.

### Before/after parser verdicts

The before verdicts are against the pre-round-3 coproc branch; the after
verdicts are covered by the live Codex-session-runner integration fixture.

| command | before | after |
|---|---:|---:|
| `coproc .claude/scripts/leadv2-supervise.sh --flag` | no-trip (missed) | TRIP |
| `coproc { .claude/scripts/leadv2-supervise.sh; }` | TRIP | TRIP |
| `coproc worker { .claude/scripts/leadv2-supervise.sh; }` | TRIP | TRIP |
| `coproc grep .claude/scripts/leadv2-supervise.sh somefile.txt` | TRIP (false-kill) | no-trip |
| `coproc worker { grep .claude/scripts/leadv2-supervise.sh f; }` | no-trip | no-trip |

The false-kill direct form and the missed direct-launcher form both fail with
the old branch and pass with the corrected branch. The two brace forms retain
their correct behavior, and the named-group grep form verifies that group
descent still distinguishes an operand from execution position.

### Regression coverage

- Added all three positive forms to `test-codex-session-runner.sh`: direct
  simple command, unnamed group, and named group.
- Added the direct `coproc grep` and named-group `grep` negative forms.
- Re-ran the complete round-2 negative list together with both new negatives;
  every case remains non-tripping.

### Verification

```
bash plugins/leadv2/scripts/tests/test-codex-session-runner.sh
→ PASS=20 FAIL=0
```

The non-blocking parser-exception distinction was left unchanged: it cannot be
made at the Bash call site in one safe line without changing the detector's
exit-code contract, and no parser exception is currently reachable.

DELIVERABLE_COMPLETE

## Fix round 4

Cosmetic-truthfulness only: updated every remaining test-stub outer envelope
from `{"type":"response_item",...}` to production-faithful
`{"type":"item.completed",...}`. The detector remains envelope-agnostic, so
there is no behavior change. Before/after counts: session runner `PASS=20
FAIL=0` → `PASS=20 FAIL=0`; core offline suites `passed=21 failed=0` →
`passed=21 failed=0`.

DELIVERABLE_COMPLETE
