# CORE-OFFLINE-CODEX-RECURSION-01 — architect prepass (design only, no implementation)

Repo `~/Projects/leadv2`, branch `main` @ `58d1e99`. Class Standard, diagnosis-then-fix, minimal diff.

## 0. Premise correction (measured this turn)

- Backlog row claims "8 of 21 passing" for `run-core-offline.sh`. That is wrong. The lead's
  measurement (passed=20 failed=1 missing=0) is the one to carry forward; nothing in this prepass
  contradicts it.
- Measured directly here: `bash plugins/leadv2/scripts/tests/test-codex-session-runner.sh`
  → `[TEST] Results: PASS=6 FAIL=1`, failing case
  `recursion case rc=4 calls=6` (expected rc=5 calls=1). Confirmed.

## 1. Runtime evidence — which of the two candidate mechanisms is real

### Mechanism 1 — "log never written" — **DISPROVED**, it is cosmetic stderr noise

The message in the failure output is emitted by **line 432**, which is *not* the append at :434:

```
431:   progress_before="$("$PROGRESS_TOOL" "$TASK_ID" 2>/dev/null || printf -- 'unknown-before')"
432:   log_size_before="$(wc -c < "$LOGF" 2>/dev/null || printf -- '0')"
433:   set +e
434:   (cd "$PROJECT_ROOT" && "${cmd[@]}") >> "$LOGF" 2>&1
```

- `TASK_DIR` (:63) and `mkdir -p "$TASK_DIR"` (:64) do run; `PROJECT_ROOT` is assigned exactly
  once (:15) and never reassigned (`grep -n 'PROJECT_ROOT=' …` → 15, 46, 67; 46/67 are `env
  PROJECT_ROOT=…` prefixes, not assignments). The **directory exists**.
- What does not exist on **attempt 0** is the **file** `codex-session-runner.log` — nothing
  creates it before :434's first `>>`. `wc -c < "$LOGF"` fails its *input* redirection; bash's
  redirection diagnostic is printed before the `2>/dev/null` on the same command takes effect
  (redirections apply left-to-right), so the message escapes. The `|| printf -- '0'` fallback
  still yields `log_size_before=0`, which is the correct value.
- Consequence: **no** functional effect. By the time `_launcher_spawn_detected` (:193) runs at
  :434+, the file exists (created by the append) and is read normally. The rest of the run in the
  observed output confirms this — turns 1..5 read the log fine and the stall counter advances off
  real content.
- Verdict: one-line cosmetic fix is worth taking anyway, because this diagnostic is precisely what
  sent the backlog row down the wrong path. **Fix, but do not claim it as the root cause.**

### Mechanism 2 — "detector shape mismatch" — **REAL, but inverted: the STUB is wrong, not the detector**

Detector (:345-356) accepts only `item.type == "command_execution"` and reads `item.command`.
The stub (test :33-35) emits `{"type":"response_item","item":{"type":"function_call",
"name":"exec_command","arguments":"{\"cmd\":\"…\"}"}}`.

Checked against a **real** captured `codex exec --json` stdout stream —
`~/Projects/persona-engine/docs/handoff/99af3fa28923/codex-session-runner.log`, 278 lines,
produced by the same runner in production. Shape census (`obj.type`, `obj.item.type`):

```
87 ('item.started',   'command_execution')
84 ('item.completed', 'command_execution')
36 ('item.completed', 'agent_message')
 7 ('thread.started', 'thread.started')
 7 ('turn.started',   'turn.started')
 7 ('turn.completed', 'turn.completed')
 4 ('item.started',   'file_change')     4 ('item.completed', 'file_change')
 1 ('item.started',   'mcp_tool_call')   1 ('item.completed', 'mcp_tool_call')
```

Verbatim production sample of a shell call:

```json
{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc \"pwd && sed -n '1,240p' /Users/kostiantyn.vlasenko/.codex/skills/source-command-leadv2/SKILL.md && sed -n '1,260p' ref/01-orchestrator.md\"","aggregated_output":"","exit_code":null,"status":"in_progress"}}
```

**`response_item` / `function_call` / `exec_command` occurs zero times in the real stream.** The
detector is aligned with production; the stub is a fixture that models a shape this codex version
never emits. So the guard is **not** blind in production — it is blind only to a fictional shape.

This is *not* "changing the test's expectation to match the code": the expectation `rc=5,
calls=1` is correct and stays. What changes is the **fixture's fidelity** — the stub must emit the
shape production actually emits. Evidence for that is the production log above.

### Coverage gap found while checking constraint 1

`grep -rln 'launcher_spawn|FALSEKILL|recursion'` over `plugins/leadv2/scripts/tests/` returns only
`run-core-offline.sh` and `test-codex-session-runner.sh`. **There is no test anywhere covering the
CODEX-LEAD-RECURSION-FALSEKILL-01 negative cases.** The narrowing that must not be weakened is
currently unprotected by any automated assertion. Acceptance item 4 ("re-run the FALSEKILL-01
negative cases") therefore cannot be satisfied by re-running something — the cases must be
written. Adding them is in scope and is the cheapest possible insurance against a future
re-widening of the guard.

## 2. Design — changes, exact files

### Change A — stub emits the production JSON shape (root-cause fix)

File: `plugins/leadv2/scripts/tests/test-codex-session-runner.sh`, stub heredoc, current :33-35.

Replace the `response_item`/`function_call` line emitted under `STUB_MODE == recursion` with the
production `item.completed` / `command_execution` shape, wrapped in `/bin/zsh -lc "…"` exactly as
production does:

```
{"type":"item.completed","item":{"id":"item_1","type":"command_execution",
 "command":"/bin/zsh -lc \"env LEADV2_TASK_ID=CODEX-SMOKE-RECURSION bash .claude/scripts/leadv2-supervise.sh\"",
 "aggregated_output":"","exit_code":0,"status":"completed"}}
```
(single line in the file; JSON quoting inside the bash single-quoted heredoc needs the same
`\\"` escaping style already used on the existing line.)

Detector trace for this string, walked against the code so the implementer knows what must hold:
`scan_command` → `split_unquoted` keeps the quoted `-lc` body intact → `eval_tokens`:
`/bin/zsh` basename `zsh` ∈ `INTERPRETERS`, `-lc` sets `has_c` → operand is the body →
recursive `scan_command` → `env` and `VAR=` prefixes stripped by the wrapper loop → `bash`
interpreter → operand `.claude/scripts/leadv2-supervise.sh` → `LAUNCHER_RE`
`^(?:[^\s/]*/)*(?:LEADV2_)?leadv2-(?:fanout|supervise)(?:\.sh)?$` matches → detected on turn 0 →
`_append_receipt "recursion_detected"` → `exit 5`, `calls=1`.

Existing recursion assertion at test :177-183 is unchanged.

### Change B — negative-case suite for FALSEKILL-01 (new coverage, acceptance item 4)

File: same test file. Add stub mode `mention` and one new case `CODEX-SMOKE-FALSEKILL`.

Stub mode `mention` emits, per turn, three `command_execution` items whose commands *name* a
launcher without executing it:

| # | command (inside `/bin/zsh -lc "…"`) | why it must not trip |
|---|---|---|
| 1 | `grep -n leadv2-supervise.sh docs/x.md` | launcher is a `grep` operand |
| 2 | `sed -n '1,5p' .claude/scripts/leadv2-codex-session-runner.sh` | launcher is a `sed` operand |
| 3 | `echo see .claude/scripts/leadv2-fanout.sh for details` | bare mention in a briefing echo |

Assertion: `rc == 4`, `calls == runner_stall_max`, and output does **NOT** contain the exit-5
string `"CODEX-LEAD RECURSION: Codex tried to spawn"`. Note the stall-path message is
`"CODEX-LEAD RECURSION suspected"` — substring `"CODEX-LEAD RECURSION"` alone is NOT a valid
negative assertion; the implementer must match the exit-5-specific prefix. This is the single
highest-risk detail in the whole change.

Net effect on the suite: `PASS=6 FAIL=1` → `PASS=8 FAIL=0` (7 existing + 1 new).
`run-core-offline.sh` suite count is unchanged (still 21 suites, `passed=21 failed=0` at suite
granularity — the implementer must confirm `passed >= 20` and that no suite name disappeared).

### Change C — silence the misleading first-turn diagnostic (cosmetic, one line)

File: `plugins/leadv2/scripts/leadv2-codex-session-runner.sh`, immediately after :73
(`LOGF=` … after `mkdir -p "$TASK_DIR"` has run):

```
: >> "$LOGF"          # create-if-absent; the first turn's `wc -c < "$LOGF"` otherwise
                      # prints a bogus "No such file or directory" that reads like the
                      # log was never written (CORE-OFFLINE-CODEX-RECURSION-01)
```

Alternative if the implementer prefers zero behaviour change to file creation: guard :432 with
`[[ -s "$LOGF" ]] &&`. Either is acceptable; `: >> "$LOGF"` is preferred because it also makes
`_launcher_spawn_detected`'s `FileNotFoundError` branch unreachable, removing a fail-open path.
Both are idempotent and cannot affect the append at :434 or the offset arithmetic (empty file →
size 0 → same offset as today's fallback).

### Explicit non-goals

- **No change to `_launcher_spawn_detected` (:193-357).** The narrowing is correct against the
  real stream; touching it is exactly the weakening the mission forbids, and there is no
  production evidence justifying a `function_call` arm. If a future codex CLI starts emitting
  `response_item`/`function_call`, that is a new task with its own captured stream as evidence —
  record it, do not pre-build for it.
- No change to `STALL_MAX`, the stall-streak logic, receipts, or the flock/lock protocol.
- No new `PE_*` / `LEADV2_*` env flag (mission constraint; nothing here needs one).
- No change to the recursion case's `rc=5 / calls=1` expectation.
- No changes to the other 20 offline suites.
- No commit, no push — the lead reviews and commits.

## 3. Non-tautological proof plan (acceptance item 3)

The recursion test must FAIL at pre-fix HEAD and PASS after, proven in an isolated tree — never by
swapping files in the shared `main` checkout (the shared-tree edit policy and parallel-session
revert hazard both apply here).

1. `git worktree add /tmp/coc01-pre 58d1e99` → run
   `bash /tmp/coc01-pre/plugins/leadv2/scripts/tests/test-codex-session-runner.sh` → paste the
   `[TEST] Results:` line (expected `PASS=6 FAIL=1`) plus the `recursion case rc=…` line.
2. Apply changes A/B/C in a second worktree (or the lane worktree) → run the same command → paste
   `PASS=8 FAIL=0`.
3. `git worktree remove` both. Both result lines go verbatim into the deliverable.

The two runs must use the same command string so the comparison is not confounded.

## 4. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | Negative-case assertion matches `"CODEX-LEAD RECURSION"` and passes against the *stall* message, so a re-widened guard would still go green — a silently useless test | Assert on the exit-5-specific prefix `"CODEX-LEAD RECURSION: Codex tried to spawn"` AND on `rc == 4`. State this in the diagnosis. |
| R2 | JSON escaping inside the single-quoted `STUB` heredoc mangles the command string; detector silently sees nothing and the test fails for the wrong reason | Before asserting, have the implementer `printf` one stub line and pipe it through `python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["item"]["command"])'` — the decoded command must be exactly the `/bin/zsh -lc "…"` string. Paste that check in the diagnosis. |
| R3 | The `mention` mode's 3-commands-per-turn × 6 turns lengthens the offline gate | Negligible (stub is local, `LEADV2_RUNNER_RETRY_SLEEP_S=0`); if wall-clock regresses, drop to one command per turn rotating by attempt. |
| R4 | Change C creates the log file, altering the first-turn `log_size_before` path | Empty file → `wc -c` = 0 = today's fallback value; offset arithmetic identical. No behaviour change. Verified by the full suite going green. |
| R5 | Fixing the stub reveals the *other* stub modes also drift from the real shape (e.g. `turn.completed`, `thread.started`) | Census above confirms `thread.started` and `turn.completed` DO appear verbatim in production. Only the recursion line was fictional. No further fixture work needed. |
| R6 | A parallel `claude` session in `~/Projects/leadv2` reverts the edit between edit and stage | `git diff <file>` immediately before `git add` (lead's step, not the implementer's — no commit in this lane). |
| R7 | `plugins/leadv2/scripts/leadv2-codex-session-runner.sh` is a canonical plugin `.sh`; `LEADV2_LEAD_GUARD=1` blocks the `Edit` tool on it | Known gotcha — fix-forward via a `/tmp` python patcher invoked through `Bash`, per the recorded lead-edit-guard workaround. Applies to Change C only. |

## 5. Mandatory constraint checklist

1. **Env var naming** — no new env vars introduced. Existing ones referenced (`LEADV2_PROJECT_ROOT`,
   `LEADV2_TASK_ID`, `LEADV2_RUNNER_STALL_MAX`, `LEADV2_RUNNER_MAX_ATTEMPTS`,
   `LEADV2_RUNNER_RETRY_SLEEP_S`, `LEADV2_CODEX_BIN`) all follow `LEADV2_*`. No drift. PASS.
2. **File paths** — both write targets verified present on disk this turn. PASS.
3. **`claude -p` commands** — none in this change. N/A.
4. **Concurrent access** — no two steps read+write the same file; the runner's own `flock` on
   `.session-runner.lock` is untouched. Test cases run sequentially against per-case temp
   `PROJECT_ROOT`s. PASS.
5. **Config contradiction** — no env-var semantics changed. PASS.

## 6. Acceptance

```yaml
acceptance:
  - surface: log_line
    observable: >
      Running `bash plugins/leadv2/scripts/tests/test-codex-session-runner.sh` prints a final
      line reading "[TEST] Results: PASS=8 FAIL=0" and no "[TEST] FAIL:" line appears anywhere
      in the output.
    authored_at: 2026-08-03T00:00:00Z
  - surface: log_line
    observable: >
      In that same run, the recursion case's runner output ends with the line
      "[leadv2-codex-session-runner] ERROR: CODEX-LEAD RECURSION: Codex tried to spawn a leadv2
      launcher/dispatcher from its already-running child session; stopping immediately", and the
      lines "attempt 1/6" through "attempt 5/6" are absent — the runner stopped after one turn.
    authored_at: 2026-08-03T00:00:00Z
  - surface: log_line
    observable: >
      Running `bash plugins/leadv2/scripts/tests/run-core-offline.sh` prints a summary line
      showing failed=0 and passed at 20 or higher, with missing=0.
    authored_at: 2026-08-03T00:00:00Z
  - surface: log_line
    observable: >
      The same test file run inside a throwaway worktree checked out at commit 58d1e99 prints
      "[TEST] Results: PASS=6 FAIL=1" together with a "recursion case rc=4 calls=6" line — the
      before/after pair proving the fix is not tautological.
    authored_at: 2026-08-03T00:00:00Z
  - surface: log_line
    observable: >
      The new FALSEKILL negative case prints "[TEST] PASS:" for a scenario in which the fake
      Codex turn greps, seds and echoes launcher filenames, and the run's output contains no
      "CODEX-LEAD RECURSION: Codex tried to spawn" line — the narrowed guard still does not fire
      on a bare mention.
    authored_at: 2026-08-03T00:00:00Z
  - surface: file_artifact
    observable: >
      docs/handoff/CORE-OFFLINE-CODEX-RECURSION-01/diagnosis.md exists and contains the verbatim
      production JSON sample line showing item.type "command_execution", the four acceptance
      outputs pasted verbatim, and a section naming what was deliberately left unchanged.
    authored_at: 2026-08-03T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/tests/test-codex-session-runner.sh, plugins/leadv2/scripts/leadv2-codex-session-runner.sh

DELIVERABLE_COMPLETE
