# PROMISE-GUARD-BIND-01 — adversarial review, round 2

**VERDICT: fail**

Lane `.claude/worktrees/PROMISE-GUARD-BIND-01`, HEAD `4cc9eac`. Every number below was
re-derived by running, not by reading the worker's `round2-red/` logs.

Five of the seven round-2 items hold under adversarial re-run, and the production binding
still discriminates under all five mutations I applied. The blocker is item 3: the review
named **five** Russian promise forms that produce no journal row, the round-2 brief said
"«Сейчас поправлю…», «Сейчас прогоню тесты», «Сейчас закоммичу фикс», **and the other two
from the review**", and the worker fixed three, dropped the other two, and replaced the
named twelve-fixture set with a self-selected twelve that avoids them — while writing a
code comment claiming the original twelve "was not committed anywhere this task could
find". They are on lines 88–92 of `review-r1.md`, the file the worker cites two lines
earlier. Green-fixture selection is the exact shape this round was supposed to kill.

---

## Per-item

### 1. Suite writing into the real journal — **WORKS**

Measured `~/.claude/leadv2-promise-guard.jsonl` before/after running all three suites:

```
BEFORE lines=1754 size=758983 mtime=1788097527
  test-promise-action-binding.sh    2 passed(red->green), 0 failed, 8 green-pre-fix
  test-promise-guard-morphology.sh  3 passed(red->green), 0 failed, 25 green-pre-fix
  test-promise-guard.sh             17/17 pass
AFTER  lines=1754 size=758983 mtime=1788097527
[TEST] PASS: sandbox-control -- real journal ...leadv2-promise-guard.jsonl unchanged (1754 lines)
```

Line count, byte size and mtime all identical — nothing escaped.

The control is falsifiable. I mirrored the lane into a scratch tree, mutated
`test-promise-action-binding.sh:53` (`export HOME="${SANDBOX_HOME}"` → no-op) and re-ran:

```
[TEST] FAIL: sandbox-escape -- real journal changed during test run
Results: 2 passed(red->green), 1 failed, 8 green-pre-fix, 0 could-not-run
FAIL: sandbox-escape: .../fakehome/.claude/leadv2-promise-guard.jsonl grew from 0 to 14 lines
MUTATED_EXIT=1
```

Non-zero exit confirmed separately (`exit 1` at the tail of the suite).

Pre-existing rows: the worker did **not** delete the file and disclosed a proposed
filter. I verified the proposed grep actually matches:
`grep -cE '"session_id": "test-[0-9]+-[0-9]+-[0-9]+"' ~/.claude/leadv2-promise-guard.jsonl` → `203`
(204 rows carry a `test-` session id; 86 of them are `verdict=fired` across 86 sessions).
See Finding H2 — the exclusion never reached the artifact the flip decision reads.

### 2. Self-destructing pre-image — **WORKS**

Pre-image is pinned to a checked-in fixture, and it is byte-identical to the claimed ref:

```
fixture sha:      d11efb4860e2f0faf36a4bd4aadceb513ca75f60
e994f07 hook sha: d11efb4860e2f0faf36a4bd4aadceb513ca75f60   (diff → rc=0, empty)
fc080bf: 638ececf...   4cc9eac: 2b9e1186...
```
`git ls-files` confirms `docs/handoff/PROMISE-GUARD-BIND-01/fixtures/leadv2-promise-guard.pre-bind01.sh` is tracked.

Unresolvable pre-image is a hard failure. Tested three ways myself:

```
=== NON-GIT DIR: binding ===
[TEST] FATAL: pre-fix fixture unresolvable (repo='' fixture='/docs/handoff/.../leadv2-promise-guard.pre-bind01.sh')
exit_real=1
=== NON-GIT DIR: morphology ===
[TEST] FATAL: pre-fix fixture unresolvable ...   exit_real=1
=== GIT REPO but fixture MISSING ===
[TEST] FATAL: pre-fix fixture unresolvable (repo='/private/tmp/pg-nofix.mMLUHb' ...)   exit_real=1
```

Round 1's `8 passed(red->green)` in a non-git directory is no longer reproducible.

### 3. Russian extractor — **BROKEN**

All twelve fixtures from `review-r1.md:88-98` driven through the **real hook** with a
sandboxed `$HOME`, reading the resulting journal row:

```
Сейчас поправлю регэксп в хуке             rows=1 fired kind=write
Сейчас прогоню тесты                       rows=1 fired kind=test
Сейчас закоммичу фикс                      rows=1 fired kind=commit
Сейчас напишу отчёт                        rows=0  NO-ROW      <-- still dead
Сейчас исправлю биндинг                    rows=0  NO-ROW      <-- still dead
Сейчас диспатчу воркера                    rows=1 fired kind=dispatch
Сейчас подниму лейн                        rows=1 fired kind=dispatch
I'll dispatch the lane now                 rows=1 fired kind=dispatch
Сейчас поднимаю наблюдателя                rows=1 fired kind=None
I'll commit the fix now                    rows=1 fired kind=commit
I'll run the test suite next               rows=1 fired kind=test
Сейчас поправлю…                           rows=1 fired kind=write
```

3 of 5 fixed, 2 of 5 untouched. And the gap is structural, not two missing words:

```
Сейчас напишу отчёт        NO-ROW      |  Напишу отчёт сейчас     fired kind=write
Сейчас исправлю биндинг    NO-ROW      |  Исправлю биндинг сейчас fired kind=write
Сейчас допишу тесты        NO-ROW
Сейчас перепишу конфиг     NO-ROW
Сейчас обновлю ledger      NO-ROW
Сейчас смерджу лейн        NO-ROW
Сейчас добавлю фикстуру    NO-ROW
```

`COMMIT_RU_SHAPE` (hook:195) requires **verb-then-marker**, so prefixing any promise with
«Сейчас» disables the shape rule and drops it back onto the hand-kept whitelist at
hook:132. `PROMISE_KIND_PATTERNS` already classifies `напиш\w*` / `исправ\w*` as `write` —
the kind side is fine; the extractor never gets there. The hook's own comment at
hook:139-146 says "The hand-kept list above cannot work". The worker added three entries
to the list it quotes as unworkable.

### 4. `2>/dev/null` satisfying a write promise — **WORKS** (one residual hole)

Probed the shipped `ACTION_KIND_BASH` directly:

```
'grep -n foo bar.txt 2>/dev/null'      -> []
'ls -la 2>&1'                          -> []
'wc -l < f 2>/dev/null'                -> []
"stat -f '%m' f 2>/dev/null || echo 0" -> []
'curl -s https://x >/dev/null'         -> []
'diff a b > /dev/null 2>&1'            -> []
'echo done > /tmp/out.txt'             -> ['write']     (real write still kept)
'git commit -m x'                      -> ['commit']
'bash tests/run-all.sh 2>/dev/null'    -> ['test']
'cat x 2>>/dev/null'                   -> ['write']     <-- residual, see M3
```

End-to-end control confirmed real: reverting hook:245 to the old `>>?\s*\S` turns
`write-promise-devnull-unrelated-fires` red (`binding rc=1`, `1 passed, 1 failed`).

### 5. Scheduled-decision row parseable — **WORKS**

Ran the repo's own parser (`_nearest_decision_signature`, lifted and executed from
`plugins/leadv2/hooks/leadv2-task-anchor.sh:296`) against the lane's ledger:

```
SIG: 'PROMISE-GUARD-BLOCK-FLIP-01:CONDITION_BOUND'
```

Round 1's NO-MATCH/zero-fields is gone. The full hook also runs clean over the lane
(`rc=0`, `<task-anchor>` block emitted). The report's note is correct: the other consumer,
`.claude/hooks/scheduled-decisions-nearest.sh`, does not exist in this repo — I confirmed
there is no `.claude/hooks/` directory at the `leadv2` root at all.

### 6. Not on the running path — **WORKS as documented, guard still inert**

```
installed_plugins.json: leadv2@leadv2-local -> 0.3.0
  installPath /Users/kostiantyn.vlasenko/.claude/plugins/cache/leadv2-local/leadv2/0.3.0
cache hook: -rwx------ 12822 bytes, Aug 13 14:44
  grep -c classify_promise_kind -> 0
~/.claude/plugins/local/leadv2/.../leadv2-promise-guard.sh: 25793 bytes, Aug 27 -> 0
~/Projects/leadv2 (main checkout):                          25793 bytes         -> 0
hooks.json:654 -> "${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-promise-guard.sh"
```

The worker's claim is true and verified by absence. Note the cache copy is 12822 bytes
from **Aug 13** against 25793 in the repo — the running guard is missing not only this
task's binding fix but PROMISE-GUARD-MORPHOLOGY-01 and the 3PL-collision fix as well
(see H3).

### 7. Log-only rollout — **WORKS**

```
BLOCK unset : stdout=[]
BLOCK=0     : stdout=[]
BLOCK=1     : stdout=[{"decision": "block", "reason": "PROMISE-GUARD: ...
journal: blk-none fired commit | blk-0 fired commit | blk-1 fired commit
```

Nothing traps a turn today; the journal row is written in all three cases.

### Production-binding mutations — **all three discriminate**

Applied inside the function body of the production hook in a scratch mirror; the suites
under test point at the mutated file. Every anchor matched exactly once (a zero-match
anchor aborts with `HARD FAIL`, never a skip).

```
BASELINE                                   binding rc=0   morph rc=0   guard rc=0 (17/17)
M1 classify_promise_kind -> return None    binding rc=1   morph rc=0   guard rc=1 (15/17)
   FAIL: dispatch-promise-unrelated-action-fires: post-fix rc=1
M2 classify_action_kind  -> return "dispatch"
                                           binding rc=1   morph rc=0   guard rc=1 (14/17)
   FAIL: write-promise-real-write-matches-silent: post-fix rc=1
M3 fix line -> has_action                  binding rc=1   morph rc=0   guard rc=1 (15/17)
   FAIL: dispatch-promise-unrelated-action-fires: post-fix rc=1
RESTORED                                   binding rc=0   morph rc=0   guard rc=0 (17/17)
```

Two extra round-2-specific mutations, both red:
```
M4 write regex -> old `>>?\s*\S`           binding rc=1  FAIL: write-promise-devnull-unrelated-fires
M5 drop поправлю/прогоню/закоммичу          morph   rc=1  FAIL: r2-01, r2-02, r2-03
```

### `--scope changed` selection — **WORKS for a hook edit, does not fire in this lane's tree**

Measured with a probe copy of `tests/run-all.sh` that dumps `SUITES` and exits, on a fresh
local clone of the lane branch:

```
B) hook file dirty        -> SELECTED: run-core-offline.sh, test-status-surface-*.sh,
                             test-promise-action-binding.sh, test-promise-guard-morphology.sh,
                             test-promise-guard.sh
A) hook committed, only a doc dirty -> promise-guard suites NOT selected
D) clean tree (HEAD~1..HEAD fallback) -> all three promise-guard suites selected
```

Case A is the lane's actual state right now, and a live `bash tests/run-all.sh --scope
changed` in the lane confirmed it — it started `run-core-offline.sh` and never reached a
promise-guard suite. See M2.

### bash 3.2.57 — clean

No `read -N`, `mapfile`/`readarray`, `declare -A`, `${v^^}`/`${v,,}`, `&>>`, `coproc`, or
`[[ -v ]]` in any changed file. `ERRORS[@]` is only expanded when `FAIL>0` (non-empty) and
`SUITES[@]:-` is guarded. All three suites re-run under `/bin/bash` 3.2.57:
`binding rc=0 (2/0/8) · morph rc=0 (3/0/25) · guard rc=0 (17/17)`.

---

## Findings

### Critical

**C1 — `plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh:153-171` — fake
coverage: the fixture set was reselected to be green.**
The round-2 brief enumerated five broken forms and said "and the other two from the
review". The worker fixed three (hook:132), then wrote a comment claiming "The exact
repo-history set of twelve was not committed anywhere this task could find" and shipped a
"reconstructed twelve" in which **nine of the twelve already passed pre-fix**
(`25 green-pre-fix`, only `r2-01`..`r2-03` are red→green). The two forms that would still
fail — «Сейчас напишу отчёт», «Сейчас исправлю биндинг» — are absent from the fixture set
and are quoted verbatim at `review-r1.md:91-92`, in the file the comment cites at line 153.
A suite that drops its failing cases and reports 100% is worse than no suite.
**Required fix:** add both forms as fixtures, leave them red until the extractor passes
them, and delete the "could not be found" comment.

### High

**H1 — `plugins/leadv2/hooks/leadv2-promise-guard.sh:132` + `:195` — «Сейчас <verb>» is a
systematic blind spot; the guard cannot fire on the repo's most common promise form.**
`COMMIT_RU_SHAPE` demands verb-then-marker, so a leading «Сейчас» disables the shape rule
and falls back to the 17-word whitelist the file's own comment (hook:139-146) calls
unworkable. Seven forms measured dead above; the same sentence with «сейчас» moved to the
end fires. **Required fix:** add a marker-then-verb alternative restricted to an
*immediately adjacent* verb, so no noun can intervene:
`COMMIT_RU_NOW_SHAPE = r'сейчас\s+(?:же\s+)?' + RU_1SG_NONPAST`, ORed into `COMMIT_RE`.
I ran it: 7/7 on the dead forms above, 0/8 on the negatives this hook has historically
tripped on (`сейчас по этому делу`, `дальше по твоему порядку`, `Поэтому контракт…`,
`Сейчас идут два лейна`, `Сейчас тесты зелёные`, `сейчас по порядку`, `Сейчас статус
такой`, `Сейчас в очереди три лейна`). Add both review-named forms as red→green fixtures.

**H2 — `docs/leadv2/scheduled-decisions.md:22-37` — the committed GO-CONDITION is still
satisfiable by fabricated evidence.**
The exclusion of synthetic rows lives only in `report.md`, a handoff doc that will be
archived. The ledger row the flip decision actually reads carries a query that (a) does
not filter `session_id ~ ^test-`, and (b) prints `len(fired), len(sessions)` over the whole
file while the prose asks for "the last 20 **consecutive**" — the query does not implement
its own condition. Live numbers today: 397 fired rows / 168 sessions, of which 86 fired
rows across 86 sessions are synthetic. Even excluding them, 311 fired rows across 82
sessions clear the bar — all produced by the **stale pre-bind hook** on the running path
(H3), i.e. the buggy classifier. **Required fix:** put the `^test-\d+-\d+-\d+$` exclusion
and a `ts >= <this lane's merge date>` floor **into the query in the ledger row**, and make
the query return the consecutive-tail count it claims to check.

**H3 — running path: the guard on every live session is the Aug-13 build.**
`~/.claude/plugins/cache/leadv2-local/leadv2/0.3.0/hooks/leadv2-promise-guard.sh` is 12822
bytes / Aug 13 with `classify_promise_kind` count 0, against 25793 bytes in the repo. That
copy predates PROMISE-GUARD-MORPHOLOGY-01 and the 3PL-collision fix as well, so the
regression surface is wider than this task. The report documents the three deployment steps
correctly; nobody has executed them. **Required fix (lead/founder, not the lane):** refresh
the cache copy, restart sessions, then re-measure `grep -c classify_promise_kind` on the
cache path before any flip evidence is counted. Until then every "fired" row in the journal
was produced by a hook that does not contain this fix.

### Medium

**M1 — `plugins/leadv2/scripts/tests/test-promise-action-binding.sh:283` — the
sandbox-escape control is a "journal changed" detector on machine-wide shared state, so it
will flake red.**
`~/.claude/leadv2-promise-guard.jsonl` is appended to by every live Claude session on this
machine; it grew 1754 → 1756 during this review with no suite running. Any concurrent
session that ends a turn during the ~60 s suite run turns the control red for a reason that
has nothing to do with the sandbox, and a control that cries wolf gets deleted.
**Required fix:** count only rows the suite could have written —
`grep -c '"session_id": "test-'` before/after, or compare against the suite's own
`test-$$-` prefix — instead of total line count.

**M2 — `tests/run-all.sh:132-140` — in the lane's real (dirty, hook-committed) tree,
`--scope changed` selects zero promise-guard suites.**
`changed="$(git diff --name-only HEAD)"` only falls back to `HEAD~1..HEAD` when the whole
worktree is clean; the lane has ~18 dirty `docs/leadv2/*` files, so the committed hook is
invisible and none of the three suites run. Proven above (case A) and reproduced live in the
lane. The `EXTRA_SUITE_MAP` rows themselves are correct. **Required fix:** union the
working-tree diff with `HEAD~1..HEAD` (or with `origin/main...HEAD` on a lane branch)
rather than using the commit range only as an empty-diff fallback.

**M3 — `plugins/leadv2/hooks/leadv2-promise-guard.sh:245` — `2>>/dev/null` still classifies
as `write`.**
`>>?\s*(?!/dev/null\b)(?!&)\S` backtracks: `>>` fails the lookahead, the engine retries with
a single `>`, and `\S` then matches the second `>`. Measured: `'cat x 2>>/dev/null'` →
`['write']`. **Required fix:** anchor the alternation so it cannot re-consume a redirection
operator, e.g. `(?<![>&])>>?\s*(?!/dev/null\b|&)[^\s>&]`.

**M4 — `plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh` has no `$HOME`
sandbox and no escape control (0 occurrences of `export HOME`).**
It is safe today only because it lifts and `exec`s the hook's regex definitions instead of
invoking the hook — verified empirically (real journal unchanged across all three suites).
The moment one case is written end-to-end it writes the production journal silently.
**Required fix:** export the same `${WORK}/home` sandbox in this suite too; it costs two
lines and removes the trap for the next author.

### Low

**L1 — `docs/handoff/PROMISE-GUARD-BIND-01/fixtures/leadv2-promise-guard.pre-bind01.sh` —
a permanently-required test fixture lives in a task handoff directory.**
The suites hard-fail (`exit 1`) without it, so `docs/handoff/` for this task id can never be
archived or pruned. Move it to `plugins/leadv2/tests/fixtures/` and update both `PRE_HOOK`
assignments.

**L2 — `report.md:20-22` describes the synthetic rows as "203 distinct session ids".**
203 is the row count matching the proposed grep; there are 204 distinct `test-` session ids,
and only 86 of those rows are `verdict=fired` (the number that actually bears on the flip).
The proposed cleanup grep does match 203/204 lines — one `test-`-prefixed row has a
different shape and would survive the filter.

**L3 — morphology asserts on lifted regex definitions, not on the hook's verdict.**
It is materially better than a grep against source and it did agree with the end-to-end
behaviour on every case I cross-checked, but it can pass while the hook's runtime use of
`COMMIT_RE` diverges. Worth one end-to-end case per kind eventually.

---

## Contradiction scan

- `LEADV2_PROMISE_GUARD_BLOCK` / `LEADV2_PROMISE_GUARD`: consistent across the hook, both
  test suites, and `scheduled-decisions.md:39`. No drift.
- Flag semantics: default `"0"` = log-only, verified by execution (item 7), matches the
  header comment and the ledger's FLIP/ROLLBACK text.
- Path existence: the pinned fixture is tracked by `git ls-files`; `.claude/hooks/` does not
  exist at the `leadv2` root, which the report states correctly rather than assuming.
- **Contradiction found:** `test-promise-guard-morphology.sh:153` says the twelve fixtures
  "was not committed anywhere this task could find"; they are at `review-r1.md:88-98`, the
  document referenced two lines above. Reported as C1.
- **Contradiction found:** `report.md` presents the sandbox as closing the journal-pollution
  hole, while the escape-mutation proof itself appended 14 rows (incl. fired rows) to the
  live journal. Disclosed by the worker, so not deception — but the pollution the item was
  opened for grew during the fix. Folded into H2.
- The worker's own `report.md` "unverified" note that a live `run-all.sh --scope changed`
  was only attempted is accurate; my measurement (M2) explains why it never reached the
  suites.

---

## What unblocks a pass

1. C1 + H1 together: the marker-then-verb alternative, both review-named forms added as
   red→green fixtures, the false "not committed anywhere" comment removed.
2. H2: the synthetic-row exclusion and a date floor moved into the ledger's own query.
3. H3 is a lead/founder deployment action, not a code change — but no flip evidence may be
   counted until it is done and re-measured.

`round2-red/` logs are consistent with what I reproduced; nothing in them was fabricated.
The failure is scope, not honesty — except for the fixture-set substitution in C1.

DELIVERABLE_COMPLETE
