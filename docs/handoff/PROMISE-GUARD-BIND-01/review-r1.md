# PROMISE-GUARD-BIND-01 — adversarial review, round 1

**VERDICT: fail**

Lane HEAD `fc080bf`. All commands below were run against the lane worktree
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-BIND-01`.
No source in the lane was modified by this review (every temporary edit was reverted and
`git diff --name-only HEAD` re-checked; mutations were applied to a scratch mirror whose
suites resolve their `HOOK` path to the mutated copy).

---

## The founder's finding: real, but it is an accounting bug, not zero coverage

Reproduced verbatim:

```
$ bash plugins/leadv2/scripts/tests/test-promise-action-binding.sh
[TEST] GREEN-PRE-FIX: dispatch-promise-unrelated-action-fires -- passed against the pre-fix hook too (pre_rc=0)
...
Results: 0 passed(red->green), 0 failed, 8 green-pre-fix, 0 could-not-run
```

Cause, `plugins/leadv2/scripts/tests/test-promise-action-binding.sh:42`:

```bash
git -C "${REPO}" show "HEAD:plugins/leadv2/hooks/leadv2-promise-guard.sh" > "${PRE_HOOK}"
```

`HEAD` is now `fc080bf` — the fix commit. Proven:

```
$ git show HEAD:plugins/leadv2/hooks/leadv2-promise-guard.sh | diff - plugins/leadv2/hooks/leadv2-promise-guard.sh
IDENTICAL — PRE_HOOK is the POST-FIX hook
```

So the "pre-fix" arm compares the fix against itself. The worker's
`red/test-promise-action-binding.RED-then-GREEN.log` (1 red->green) is honest **for the
moment it was taken** — before the commit, when `HEAD` was the anchor `ae2bc20`. The
artifact and the current run do not contradict each other; the control simply
self-destructs at commit time and can never be re-run. That is the whole explanation of
the contradiction, and it is not the whole story: the counter is *also* wrong in the
other direction (see H1).

**The production fix itself IS discriminated.** Three mutations applied INSIDE function
bodies of a scratch mirror of the hook, with the suites run from that same mirror
(zero-match replacement treated as a hard failure — all three reported `applied (1 match)`):

| mutation (in-body) | binding suite | test-promise-guard.sh |
|---|---|---|
| M1 `classify_promise_kind` body → `return None` first | `FAIL: dispatch-promise-unrelated-action-fires: post-fix rc=1` | 15/17 |
| M2 `classify_action_kind` Bash loop → `return "dispatch"` | `FAIL: commit-promise-matching-action-silent: post-fix rc=1` | 16/17 |
| M3 fix line → `action_after_promise = has_action` | `FAIL: dispatch-promise-unrelated-action-fires: post-fix rc=1` | 15/17 |

3/3 killed by both suites, both non-zero exit. So "nothing in it requires the fix to
exist" is false; what is true is that the suite's own red/green ledger is noise.

---

## Per-item

### 1. The binding itself — **WORKS**

My own fixtures (not the worker's), real hook, `LEADV2_PROMISE_GUARD_BLOCK=1`, journal row shown:

```
[want FIRED] dispatch promise + Read               FIRED  v=fired kind=dispatch acts=-
[want FIRED] dispatch promise + Edit               FIRED  v=fired kind=dispatch acts=write
[want SILENT] dispatch promise + Agent             SILENT v=suppressed_action kind=dispatch acts=dispatch
[want FIRED] EN dispatch + grep                    FIRED  v=fired kind=dispatch acts=-
[want SILENT] EN dispatch + real dispatch          SILENT v=suppressed_action kind=dispatch acts=dispatch
```
(`Bash:.claude/scripts/leadv2-dispatch-code.sh --task X` for the last row.)

The two cases the mission names both behave correctly on fixtures I wrote independently.

### 2. The extractor — **BROKEN (mission item not done)**

`git diff origin/main...HEAD -- plugins/leadv2/hooks/leadv2-promise-guard.sh` shows the
`COMMIT_RU_VERBS` / `COMMIT_RU_NOW` / `COMMIT_RU_SHAPE` / `COMMIT_RU_LEADING` /
`RU_INTENT_MARKER` block (hook:125-206) is **untouched**. The mission's item 1 —
"establish what it currently extracts and where that is wrong" — was answered by
redefining "extractor failure" as "it never derived the KIND" (report.md §"The
extractor's failure (item 1)"). What it actually extracts, measured, zero tools, expect
all FIRED:

```
[want FIRED] 'Сейчас поправлю регэксп в хуке'   SILENT no-journal-row
[want FIRED] 'Сейчас прогоню тесты'             SILENT no-journal-row
[want FIRED] 'Сейчас закоммичу фикс'            SILENT no-journal-row
[want FIRED] 'Сейчас напишу отчёт'              SILENT no-journal-row
[want FIRED] 'Сейчас исправлю биндинг'          SILENT no-journal-row
[want FIRED] 'Сейчас диспатчу воркера'          FIRED  kind=dispatch
[want FIRED] 'Сейчас подниму лейн'              FIRED  kind=dispatch
[want FIRED] 'Дальше беру третий таск'          FIRED  kind=None
[want FIRED] "I'll dispatch the lane now"       FIRED  kind=dispatch
[want FIRED] "Now I'm going to run the suite"   FIRED  kind=test
[want FIRED] 'Сейчас поднимаю наблюдателя'      FIRED  kind=None
```

5 of 12 textbook lead promises produce **no journal row at all** — not "suppressed",
*undetected*. Mechanism: `COMMIT_RU_NOW` (hook:129) only covers a 14-verb list, and
`COMMIT_RU_SHAPE` (hook:188) requires verb-**before**-marker, so `сейчас <any other 1sg
verb>` matches nothing. A binder on top of that binds correctly for the promises it can
see and is blind to the rest. This is exactly the failure mode the mission warned about.

### 3. `ACTION_BASH_RE` — **BROKEN both ways**

Unrelated calls it accepts as the promised action (all measured SILENT, i.e. suppressed):

```
[want FIRED] kind=None promise + grep -rn foo plugins/ 2>/dev/null   SILENT acts=write
[want FIRED] kind=None promise + ls -la > /tmp/out.txt               SILENT acts=write
[want FIRED] kind=dispatch promise + sed -n '1,40p' omp-task.sh      SILENT acts=dispatch
[want FIRED] kind=write promise + grep ... 2>/dev/null               SILENT (undetected promise)
```

Real actions it misses, so a **kept** promise gets flagged:

```
[want SILENT] dispatch promise + leadv2-codex-session-runner.sh --task PG-01   FIRED acts=-
[want SILENT] dispatch promise + claude-subsession.sh developer mission.md     FIRED acts=-
```

### 4. Log-only rollout — **WORKS**

With the variable genuinely absent (`env -u LEADV2_PROMISE_GUARD_BLOCK`), sandboxed HOME:

```
stdout=[]
journal: {"ts":"2026-08-30T12:49:15Z","session_id":"unset-1",...,"verdict":"fired",
          "quote":"Сейчас диспатчу воркера","primary_promise_kind":"dispatch",
          "action_kinds_seen":[],"block_mode":"0"}
sentinel files (must be zero): 0
```

Non-blocking by default, journals the would-have-blocked verdict, writes no sentinel, and
the flag is set nowhere in `~/.claude/settings.json` or the repo settings. Nothing can
trap a turn today. The gate at hook:598-600 sits after the journal write, which is the
correct order.

### 5. Scheduled decision — **BROKEN**

The row exists (`docs/leadv2/scheduled-decisions.md:9-46`) with a FLIP and a one-step
ROLLBACK, but it is written in a format this repo's own ledger reader cannot parse. Run
of the exact grammar from `plugins/leadv2/hooks/leadv2-task-anchor.sh:324-340` against
the file:

```
row-chunks: 2
0 NO-MATCH | # Scheduled decisions          parsed fields: NONE
1 NO-MATCH | ## PROMISE-GUARD-BLOCK-FLIP-01  parsed fields: NONE
```

The reader requires `### <ID> — <title>` plus `| **Due** | ... |` field rows (compare
`persona-engine/docs/leadv2/scheduled-decisions.md:30-38`). The row will never surface.

### CI selection (`--scope changed`) — **WORKS**

Made the hook dirty, listed the selection using the real `tests/run-all.sh` with only an
early print inserted after the selection block:

```
[SELECTED] plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECTED] tests/test-status-surface-bash32.sh
[SELECTED] tests/test-status-surface-single-lead.sh
[SELECTED] tests/test-status-surface-fast-names.sh
[SELECTED] plugins/leadv2/scripts/tests/test-promise-action-binding.sh
[SELECTED] plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh
[SELECTED] plugins/leadv2/tests/test-promise-guard.sh
```

The `hooks/*.sh` case arm at `tests/run-all.sh:140-146` is a real fix — without it the
stem loop never saw the hook and the `EXTRA_SUITE_MAP` rows could not fire.

### Bash 3.2.57 — **WORKS**

```
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)
[/bin/bash 3.2] test-promise-action-binding.sh   rc=0
[/bin/bash 3.2] test-promise-guard-morphology.sh rc=0
[/bin/bash 3.2] test-promise-guard.sh            rc=0  (17/17 pass)
```

No `read -N`, `declare -A`, `mapfile`, `readarray`, `${v^^}`/`${v,,}` or `&>>` in the
changed files. The one unguarded-array risk, `printf ... "${ERRORS[@]}"` at
test-promise-action-binding.sh:219, is inside an `if [[ ${FAIL} -gt 0 ]]` guard.

---

## Findings

### CRITICAL

**C1 — the test suite writes into the production journal, and the GO-condition is already
satisfied by synthetic rows.**
`plugins/leadv2/scripts/tests/test-promise-action-binding.sh:113-118` — `_verdict` never
sandboxes `HOME`, so every run appends to the real
`~/.claude/leadv2-promise-guard.jsonl`, which is the exact file the flip GO-condition
reads (`docs/leadv2/scheduled-decisions.md:25`). Measured on this machine right now:

```
total rows: 1736
synthetic-test rows: 193 of 1736
fired rows: 392 of which synthetic: 84
distinct synthetic session_ids among fired: 84
```

The GO-condition is "≥20 consecutive `fired` rows spanning ≥3 distinct `session_id`s".
84 fired rows across 84 distinct session ids already satisfy it, produced entirely by
`_expect` fixtures. Anyone running the suite in a loop manufactures the evidence for
turning blocking on. **Required fix:** (a) `export HOME="$WORK"` (or a per-call `HOME`)
in `_verdict`, mirroring what `plugins/leadv2/tests/test-promise-guard.sh:24` already
does; (b) stamp a `"synthetic": true` field, or filter on `session_id`/`cwd`, in the
GO-condition query; (c) purge the 193 existing synthetic rows before the window opens.

### HIGH

**H1 — the RED-then-GREEN control is not re-runnable and its counter is wrong in both
directions.** `test-promise-action-binding.sh:42` pins `PRE_HOOK` to `HEAD`, which is the
fix commit after `git commit` (proven above: byte-identical). Second half of the same
bug, `:189` + `:198-202`: when `PRE_HOOK` cannot be resolved, `pre_rc=2`, which is
`-ne 0`, so the case is counted as **PASS (red->green)**. Measured in a non-git directory
with the identical files:

```
Results: 8 passed(red->green), 0 failed, 0 green-pre-fix, 0 could-not-run
```

Same suite, same code, same hook — 8/8 "proof" from nothing. The suite `exit 0`s on either
number (`:219-220` only fails on `FAIL>0`), so the ledger is decorative. `report.md`
states the PRE_HOOK is "this file's state before this task started"; that is false as
committed. **Required fix:** resolve `PRE_HOOK` from `$(git merge-base origin/main HEAD)`
(or `origin/main:`), map `pre_rc == 2` to `COULD_NOT_RUN`, and make the suite exit
non-zero when a case declared must-be-red-pre-fix is not red.

**H2 — the removed catch-all was not the big one; the bigger one survives.**
`plugins/leadv2/hooks/leadv2-promise-guard.sh:230-233`, `write` kind:
`r'sed\s+-i|\b(?:mv|cp|tee|touch|mkdir|install)\b|>>?\s*\S'`. The `>>?\s*\S` alternative
matches `2>/dev/null`, which is present in a large fraction of this codebase's Bash
calls. Measured: `grep -rn foo plugins/ 2>/dev/null` → `acts=write`, suppressing a
kind=None promise; `ls -la > /tmp/out.txt` likewise. The hook header (`:215-221`) claims
removing `leadv2-.*\.sh` was "most of why 'any tool call' suppressed the guard" — that
claim is unsupported while a redirect-matches-everything alternative remains, and the
legacy fallback (`:482-483`) still applies to every unclassifiable promise. **Required
fix:** restrict the redirect alternative to a write target (e.g. require `>` not preceded
by a file descriptor, and exclude `/dev/null`), or drop it and name the write commands
explicitly.

**H3 — `ACTION_KIND_BASH` accepts read-only calls and misses real dispatch channels.**
`:223-229`. `test-[\w.-]*\.sh` matches `cat plugins/leadv2/tests/test-promise-guard.sh`
(a read) → `test` action; `[A-Za-z0-9_-]*-task\.sh` matches
`sed -n '1,40p' .claude/leadv2-overrides/omp-task.sh` (a read) → `dispatch` action; both
measured SILENT. Conversely `leadv2-codex-session-runner.sh` and `claude-subsession.sh` —
the two dispatch channels named in this project's own CLAUDE.md — classify as `None`, so
a promise that WAS kept fires (measured FIRED). **Required fix:** anchor the patterns to
an invocation position (`^\s*(bash\s+)?\S*<name>` / after `&&`/`|`/`;`) rather than
substring, and add the missing dispatch entry points.

**H4 — the extractor was not fixed (mission item 1).** `:125-206` untouched; 5 of 12
realistic promises undetected (evidence in item 2 above). `report.md` closes the item by
redefining it. **Required fix:** either make `COMMIT_RU_NOW` accept a generic 1sg
non-past after `сейчас` (order-independent variant of `COMMIT_RU_SHAPE`), or state
explicitly in the report that item 1 is deferred with the measured miss list, and open a
follow-up row — do not report it done.

**H5 — the scheduled-decision row is unreadable by this repo's own ledger parser.**
`docs/leadv2/scheduled-decisions.md:9`. Proven above with the exact regexes from
`plugins/leadv2/hooks/leadv2-task-anchor.sh` (NO-MATCH, zero fields). **Required fix:**
reformat as `### PROMISE-GUARD-BLOCK-FLIP-01 — flip the promise guard to blocking` with
`| **Due** | ... |`, `| **GO-condition** | ... |`, `| **Action** | ... |`,
`| **Rollback** | ... |`, `| **Why** | ... |` table rows, matching the canonical shape.

**H6 — the fix does not reach the running path on merge.** The live Stop hook is a real
copy, not a symlink:
`/Users/kostiantyn.vlasenko/.claude/plugins/local/leadv2/plugins/leadv2/hooks/leadv2-promise-guard.sh`,
dated Aug 27, `grep -c classify_promise_kind` → `0`. Per this project's CLAUDE.md the
plugin cache is the exception to "one inode" and a hook fix must be copied into the cache
with a session restart or it never loads. Nothing in the lane or `report.md` covers this,
so the lane can close with the guard still never firing in anger — which is the defect.
**Required fix:** name the cache-refresh + restart step in the close, and verify with
`grep -c classify_promise_kind` on the cache path.

### MEDIUM

**M1 — only the first commitment clause binds.** `:446`
`primary_kind = commitment_kinds[0]`. Measured:
`"I'll commit the fix. I'll dispatch the worker next"` + only `git commit` → **SILENT**
(`kind=commit acts=commit`). The unkept dispatch escapes. Fix: fire unless *every*
classified commitment kind is present in `action_kinds_seen` (or evaluate per-clause and
quote the first unmatched one).

**M2 — kind precedence makes a dispatch promise satisfiable by a test run.**
`:265-276`, `test` is first in the list. Measured:
`"Сейчас диспатчу воркера прогнать тесты"` + `bash tests/run-all.sh` → **SILENT**
(`kind=test acts=test`). Fix: order `dispatch` before `test`, or return the set of kinds
rather than the first match.

**M3 — the GO-condition's discriminating half is prose, not a query.**
`docs/leadv2/scheduled-decisions.md:21-38`. The snippet prints `len(fired)` and the
distinct-session count; the actual gate — "zero known false positives, checked by hand
against the quoted transcript" (`:34`) — is unexecutable, and no journal field records a
false-positive marking. Fix: add an `fp` field written by a one-line marking script (or a
companion `promise-guard-fp.jsonl` keyed by `ts`) and join it in the query.

**M4 — the guard's own headline example is still unbound.** The hook's docstring at `:5-6`
cites «сейчас поднимаю наблюдателя» as the canonical promise; measured `kind=None`, so it
falls to the legacy any-action fallback and is not bound by this task at all.

**M5 — dead code introduced by the diff.** `ACTION_BASH_RE` (`:237-238`) and
`is_action_tool` (`:257-258`) have zero call sites; the comment at `:235-236` claims
"back-compat … callers", but this is a self-contained heredoc with no importers. Delete
both, or the next reader will edit the unused pattern believing it is live.

### LOW

**L1 — `--scope changed` only selects these suites when the hook file itself is dirty.**
Editing only `test-promise-action-binding.sh` selects nothing (no
`test-test-promise-action-binding.sh` and no map row keyed on the test's own stem).
Advisory; the mission's requirement is met.

**L2 — the journal has no rotation.** 1736 rows already, appended on every Stop of every
session in every repo. Worth a size cap before the flip.

---

## Pre-finalize contradiction scan

- Env-var names: `LEADV2_PROMISE_GUARD_BLOCK` and `LEADV2_PROMISE_GUARD` are spelled
  identically in the hook, both suites, and the ledger row. No drift. OK
- Flag semantics: default `"0"` in all four hook occurrences (`:22`, `:588`, `:594`,
  `:598`); `!= "1"` means any non-`1` value is non-blocking; set nowhere in settings. OK
- Path existence: `test-promise-guard-morphology.sh` (mapped in `run-all.sh:120`) exists
  and passes; `docs/leadv2/scheduled-decisions.md` exists in the lane and is new (absent
  on `origin/main`); `hooks.json:584` registers the hook as a Stop hook with
  `continueOnBlock: true`. OK
- **Contradiction found (H6):** the registered plugin root
  `~/.claude/plugins/local/leadv2/...` is a real copy of the hook without the fix, so the
  repo path under review is not the path that runs.
- **Contradiction found (H1):** `report.md` describes `git show HEAD:` as "this file's
  state before this task started"; as committed it is the file's state *after*.
- **Contradiction found (H5):** the ledger row's heading grammar contradicts the parser
  in this same repo (`leadv2-task-anchor.sh`).
- **Contradiction found (H2/H4):** the hook header and `report.md` both assert the
  extractor and `ACTION_BASH_RE` were "fixed"; the extractor block is byte-unchanged and
  the largest catch-all in `ACTION_BASH_RE` survives.

## What must land before round 2

C1, H1, H5, H6 are blocking and cheap. H2/H3 are the substance of mission item 2 and
should land with a fixture each. H4 either lands or is explicitly re-opened as a
follow-up row rather than reported done.

DELIVERABLE_COMPLETE
