status: fail
reviewer_says: do_not_merge

Scope: `b9a1e62..23cada2` (round-3 delta: 4 files, +469/-62) in
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-ROWS-02`.
Everything marked RAN was executed against a scratch copy of `plugins/leadv2/scripts/`.
One temporary append to the lane's own copy (for the `--scope changed` probe) was reverted;
`git status --porcelain -- plugins/ tests/` is empty at the time of writing.

## Baseline — the three suites, re-run, not taken on trust

```
$ bash plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh   -> === 10 passed, 0 failed ===  EXIT=0
$ bash plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh    -> === 11 passed, 0 failed ===  EXIT=0
$ bash plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh          -> 2 passed, 0 failed            EXIT=0
```
The lead's numbers are correct. They are also not the whole picture — see R3-1.

Type gate (bash + one embedded python heredoc; no `.py`/`.ts` in the changeset, so `mypy --strict`
and `tsc --noEmit` do not apply — `bash -n` + `ast.parse` are the equivalent):

```
$ bash -n plugins/leadv2/scripts/leadv2-broad-status.sh \
          plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh \
          plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh \
          tests/run-all.sh
bash -n: OK (4 files, no output)

$ python3 -c 'ast.parse(<PY heredoc extracted from leadv2-broad-status.sh>)'
ast.parse OK; python heredoc lines: 892

$ mypy --strict     -> N/A (no Python file in the changeset; the python is an embedded heredoc)
$ npx tsc --noEmit  -> N/A (no TypeScript in the changeset)
```

## My own RED/GREEN mutation pairs (six, all in-body, all reverted). RAN.

Three are controls that exist. Three are controls that do NOT exist.

```
MX-1  :688  _foreign_slots = min(_foreign_row_count, FOREIGN_ROW_RESERVE)
            ->  _foreign_slots = _foreign_row_count                 (round-2 exemption restored)
      blind: FAIL T6 (got 10 rows), FAIL T7 (0 own rows)            === 9 passed, 2 failed ===
      ident: 10/0   (identity suite is blind to the cap)

MX-2  :689  _own_row_budget = TABLE_ROW_CAP - _foreign_slots
            ->  max(0, TABLE_ROW_CAP - _foreign_row_count)          (own floor removed)
      blind: FAIL T7: own-repo lanes starved by a foreign surge, got 0 own rows   10/1

MX-3  :433  d = detail_by_task.get(tid) if not _repo_slug else None
            ->  d = detail_by_task.get(tid)                          (bare-tid join restored)
      ident: FAIL T4b: foreign row fabricated the own-repo lane's liveness:
             | persona-engine/SHARED-ID-01 | - own-repo half of the shared id | пишет сейчас (55 байт в потоке) |   9/1

MX-4  :434  _digest_key = f"{_repo_slug}::{tid}" if _repo_slug else tid  ->  _digest_key = tid
      ident 10/0 · blind 11/0 · founder 2/0      <-- NO SUITE SEES IT.  NEW-5's fix is uncontrolled.

MX-5  :211  table_rows = [r for r in table_rows if isinstance(r, dict)]  ->  pass
      ident 10/0 · blind 11/0 · founder 2/0      <-- NO SUITE SEES IT.  L1's fix is uncontrolled.

MX-6  :1026 "{n} строк таблицы не поместилось"  ->  "{n} мусорных/лишних строк таблицы"
      ident 10/0 · blind 11/0 · founder 2/0      <-- NO SUITE SEES IT.  NEW-6's fix is uncontrolled.

GREEN (scratch restored byte-identical): ident 10/0, blind 11/0, founder 2/0.
```

Three fixes this round shipped with a working negative control. Three shipped with none, against the
round's own written rule ("Every fix keeps its negative control and you RUN it"). MX-4/5/6 revert to
the pre-fix behaviour and the whole gate stays green.

## Prior findings — verdicts

| # | Prior finding (r2) | Verdict | Evidence |
|---|---|---|---|
| H NEW-1 | rescued foreign row joins own `lane_detail` on a bare task_id, renders false liveness | **FIXED** | RAN. `:433` `d = detail_by_task.get(tid) if not _repo_slug else None`. Fixture own+foreign `SHARED-ID-01`, foreign `age_s=3600` renders `тихо 60 мин`. MX-3 reds T4b — the requested strictening happened |
| H NEW-2 | foreign rows exempt from the cap, unbounded | **PARTIAL — bound added, over-corrects into a new lie** | RAN. `FOREIGN_ROW_RESERVE = max(1, 6//3) = 2` at `:684`; 10 foreign renders 2. But 4 of 6 cap slots go **unused** and the founder is told `8 строк таблицы не поместилось` when they did fit. New finding R3-2 |
| H NEW-3 | `max(0, 6 - foreign)` evicted all 7 own lanes, junk-lie on own repo | **FIXED** | RAN. `_own_row_budget = 6 - _foreign_slots` gives a floor of 4. 6 foreign + 7 own renders 4 own + 2 foreign, `7 строк таблицы не поместилось`, no `мусорн`. MX-2 reds T7; T5b is `-eq 5` now, not `-ge 1` (NEW-9 fixed) |
| H NEW-4 | blind suite has no `EXTRA_SUITE_MAP` row | **FIXED and PROVEN** | RAN. `tests/run-all.sh:122`. Selector replayed with `changed="plugins/leadv2/scripts/leadv2-broad-status.sh"`; output below — the blind suite is now selected on a lone renderer edit |
| M NEW-5 | digest keys on the bare task_id | **FIXED in code, UNCONTROLLED in tests** | RAN. `:434` `_digest_key`; 7 own + 1 foreign renders `+8 линии подняты`, 10 foreign renders `+10`. MX-4 reverts it and all three suites stay green; `round3-red/M-NEW5.log` is a hand-observed print, not a suite RED |
| M NEW-6 | "мусорных/лишних строк таблицы" labels hidden lanes junk | **FIXED in code, UNCONTROLLED** | RAN. `:1026` now `"{n} строк таблицы не поместилось"`; dedup drops split into `"{n} дублирующих строк"`. MX-6 reverts silently green. And the new wording is itself false in the foreign-only shape (R3-2) |
| L NEW-7 | two parallel lists joined by `zip()` | **FIXED** | READ. `:598` `rows_out.append((line, bool(_repo_slug)))`; one list of pairs, unpacked at `:764-765` |
| L NEW-8 | `(dispatch id unknown)` permanent on every foreign row | **FIXED** | RAN. `:456` `... or _repo_slug`; renders `| persona-engine/FOREIGN-01 |` clean |
| L NEW-9 | blind `-ge 1` cannot see own-row starvation | **FIXED** | READ+RAN. blind `:267` `[[ "$T5_OWN_ROWS" -eq 5 ]]`; MX-2 reds T7 |
| L NEW-10 | stale suite header, unbacked RED claim | **PARTIAL** | READ. Header now lists T1a-c/T3a-b/T4a-b/T5/T6 and points at `round3-red/`. The retained "Each T is proven with a RED/GREEN mutation pair" is still untrue for this round: `round3-red/` holds reds for T4b, T6, T7 only |
| L1 | `_row.get()` with no `isinstance` guard | **"FIXED" — and the fix is worse than the crash** | RAN. `:211` drops non-dicts. A table of 2 non-dict rows now renders `ДОСКА ПУСТА` (R3-3). No test |
| L2 | dedup drops uncounted | **FIXED** | READ. `_dedup_dropped_count` at `:393`/`:404`, surfaced at `:1027`. Untested (no suite greps `дублирующ`) |
| L3 | no RED artifact / no before-after render / no developer deliverable | **PARTIAL — 2 of 3** | READ. `round3-red/` now holds 4 mutation logs + `before-after-renders.md` + `before-round2-renders.md`. Still **no** `developer.summary.md` / `developer.full.md` (protocol §5), third round running. 2 of the 4 "RED" logs are not suite reds: `M-NEW5.log` is a print, `M-L1.log` is a traceback with `EXIT=0` |
| M3 (r1) | six near-identical collector stubs | **NOT FIXED** | READ. Round 3 added two more; 8 now, each ~16 lines differing only in a python payload. Advisory |

`--scope changed` selector replay (NEW-4 proof), run against the live `tests/run-all.sh` code
(`add_suite()` + the changed-file loop + `EXTRA_SUITE_MAP`) with
`changed="plugins/leadv2/scripts/leadv2-broad-status.sh"`:

```
SELECTED: .../plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh
SELECTED: .../plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh
SELECTED: .../plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh
```

## NEW findings

### High

**R3-1 — `plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh` went 22/0 -> 16/6 in this
lane, is still red at HEAD, and `--scope changed` does not select it. RAN.**

The finding all three review rounds (mine included) missed, because none of us ran the *other*
broad-status suites. Bisected by checking out each lane commit's `leadv2-broad-status.sh` into a
scratch tree and running the suite unchanged:

```
d4f5408 (lane anchor, pre-change)   === 22 passed, 0 failed ===
c0fe726 (round 1)                   === 16 passed, 6 failed ===
b9a1e62 (round 2)                   === 16 passed, 6 failed ===
23cada2 (round 3, HEAD)             === 16 passed, 6 failed ===

FAIL: T2:  col-2 wrong or prepass leaked: <no row>
FAIL: T8:  live row cell count wrong: <no row>
FAIL: T9:  col-1 wrong: <no row>
FAIL: T10: col-2 fails the plain-sentence contract: []
FAIL: T13: name churned after mission rewrite
FAIL: T2c: prepass removal broke the frozen name
```

Root cause is single and structural: `test-broad-status-renderer-truth.sh:199` anchors all six on
`ROW="$(grep -m1 '^| Browser door retry queue fix |')"` — col-1 as the human mission name. `:281-286`
states the contract outright: *"T9 — col-1 is a human name, never a hex id"*. BROAD-STATUS-ROWS-02's
IDENTITY decision inverts exactly that: col-1 is now the lane identity (`task_id`), the human name
moved to col-2. The repo now carries two contradicting contracts for the same column, one of them
encoded in a suite red for three rounds with nobody noticing.

Why nobody noticed: `--scope changed` for a `leadv2-broad-status.sh` edit looks for
`test-leadv2-broad-status.sh` (does not exist) plus the three `EXTRA_SUITE_MAP` rows. There is no row
for `test-broad-status-renderer-truth.sh`, nor for `test-pulse-readable-rendering.sh`,
`test-broad-status-foreign-lanes.sh`, `test-pulse-empty-board.sh`, `test-broad-status-duty.sh`,
`test-broad-status-relay-scope.sh` — all six read `leadv2-broad-status.sh`. NEW-4 added one row and
stopped; the hole it was raised for is still open for six other suites, one of which this lane broke.
E2E-KILLRATE-01 rule 4: kill rate may not go down. Six assertions died here.

Calibration: `test-broad-status-foreign-lanes.sh` is 5/3 both before and after the lane —
pre-existing, NOT this lane's regression. `test-pulse-readable-rendering.sh` 7/0 and
`test-pulse-empty-board.sh` 10/0 are green at HEAD.

Required fix: reconcile the contract in one place — update `test-broad-status-renderer-truth.sh`
T2/T8/T9/T10/T13/T2c to the new column contract (and say so in the header, superseding the old rule
with a dated line), and add `EXTRA_SUITE_MAP` rows for every suite that sources
`leadv2-broad-status.sh`. Prove both with a `--scope changed` replay and a green run.

**R3-2 — `leadv2-broad-status.sh:684-703`: a foreign-only board renders 2 of 6 rows and tells the
founder 8 lanes "не поместилось" while 4 slots sit empty. RAN.**

`_foreign_slots = min(_foreign_row_count, FOREIGN_ROW_RESERVE)` makes the reservation a hard
**maximum**, not a floor. Own rows inherit unused foreign slots (`_own_row_budget = 6 -
_foreign_slots`); foreign rows never inherit unused own slots. Measured (fixture 2 below): 10 foreign,
0 own -> 2 rows rendered, `(скрыто: 8 строк таблицы не поместилось …)`. Six rows were available. The
sentence is a false statement on the one founder surface whose entire purpose is not making false
statements — the same class as the "мусорных/лишних" lie this task was opened to delete, in a new
costume. 1 own + 10 foreign is worse: 3 rows, 8 hidden, 3 slots wasted.

Worse, `test-broad-status-lanes-blind.sh:302` **locks the defect in**:
`if [[ "$T6_FOREIGN_ROWS" -eq 2 ]]` — an exact-count assertion asserting the under-fill. A future
correct fix (fill the cap) reds T6 and reads as a regression.

Required fix: two-pass fill. Pass 1 grants each side its floor (`min(count, reserve)` for foreign,
`min(count, CAP - foreign_slots)` for own); pass 2 distributes the remaining slots to whichever side
still has rows, until `CAP` is reached. `table_rows_hidden` then only goes non-zero when the board
genuinely exceeds 6. Retarget T6 at the invariant that matters —
`foreign_rows <= max(FOREIGN_ROW_RESERVE, CAP - own_rows)` and `rendered == min(total, CAP)` — not at
the literal 2.

**R3-3 — `leadv2-broad-status.sh:211`: the L1 crash-fix silently deletes unreadable rows, and a
malformed collector table now renders the false empty-board headline. RAN.**

```python
table_rows = [r for r in table_rows if isinstance(r, dict)]
```
The comment above it says *"Degrade it out of the table instead of crashing; 'not a lane' is exactly
what a non-dict row is."* It does not degrade it. It deletes it, uncounted — not in
`table_rows_hidden`, not in `_dedup_dropped_count`, not in `degraded`, not in `foreign_error_rows`.
Measured, collector returns `lanes.ok=true`, `table: ["junk1","junk2"]`:

```
2026-08-30T13:00:00Z [BROAD_STATUS] dispatched=1
⚠ ДОСКА ПУСТА — ничего не выполняется, 0 мин
...
| (живых линий нет) | — | — |
```

That headline is the exact 2026-08-21 persona-engine incident this suite family
(`LANE-DETAIL-BLIND-01`) exists to prevent: a confident claim of zero activity, byte-identical to a
genuinely empty board, while lanes run. The round traded an `AttributeError` (loud, kills the beat,
gets investigated) for a silent lie. It also violates the round-3 brief's regression clause verbatim:
*"a lane that cannot be read must render as a NAMED degraded row, never vanish."* And there is no
test — MX-5 removes the line and all three suites stay green; the author's own
`round3-red/M-L1.log` records `EXIT=0` beside its traceback, i.e. the crash was already invisible to
the harness.

Required fix: route non-dict rows the way `repo_read_error` rows are already routed — emit a NAMED
degraded row (e.g. `| (нечитаемая строка N) | — | коллектор вернул не-объект |`) or fold them into
`foreign_error_rows`, and count them. Add a blind-suite test: a table of only non-dict entries must
NOT produce `ДОСКА ПУСТА` and must produce a visible marker. Mutate it and paste the RED.

**R3-4 — three of this round's fixes shipped with no negative control. RAN (MX-4, MX-5, MX-6).**

`_digest_key` (NEW-5), the non-dict filter (L1) and the hidden-count wording (NEW-6) are each
revertible to their pre-fix form with zero suite failures across all three suites. The round's own
brief: *"Every fix keeps its negative control and you RUN it."* `round3-red/` contains 4 logs for 12
claimed fixes, and 2 of the 4 are not suite reds. Required: an assertion per fix, each with its own
in-body RED pasted into `round3-red/`. NEW-6 in particular is trivially testable
(`grep -q 'не поместилось'` / `! grep -q 'мусорн'` on the T5 fixture).

### Medium

**R3-5 — `leadv2-broad-status.sh:693-700` + `leadv2-lanes-snapshot.sh:412,448-453`: the two reserved
foreign slots are allocated by list order, not by liveness or by repo. READ.**

Foreign rows are appended repo-by-repo in the shell loop's repo order, and within a repo by
`for tid, s in sorted(session_by_task.items())` — alphabetical. The reserve loop takes the first two
it meets. With three live repos (persona-engine, m3-market, respiro-ios) and
`FOREIGN_ROW_RESERVE = 2`, if the first repo has >= 2 lanes the other two repos are **permanently
invisible** on the founder board, and the hidden count names no repo. Compounding it,
`leadv2-lanes-snapshot.sh:448-453` classifies anything with `age_s <= 86400` as `stale` and still
emits it, so a 23-hour-dead alphabetically-earlier lane takes a reserved slot ahead of a live lane in
another repo. Required fix: allocate the foreign slots round-robin across distinct `repo` values, and
order within a repo by liveness (`status == "active"` first, then `age_s` ascending), not by task_id.

**R3-6 — `leadv2-broad-status.sh:701-703`: the per-side hidden counts are computed and thrown away.
READ.**

`_own_rows_hidden` and `_foreign_rows_hidden` exist and are immediately summed into one scalar; the
founder line at `:1025-1026` says `7 строк таблицы не поместилось` with no split. The round-3 brief
asked verbatim to *"report the hidden count honestly per side."* Two named locals were created for it
and discarded one line later. Required fix: render `3 своих + 4 из других репо не поместилось` (or
equivalent) and assert it.

**R3-7 — the commit message and the identity-suite header overclaim the evidence. READ.**

`23cada2` says *"RED artifacts (4 mutations, each reverted)"* — `M-NEW5.log` is a two-line print with
no suite invocation, `M-L1.log` is a traceback with `EXIT=0` and no suite. Two real suite reds, not
four. The same commit says *"a non-dict table row degrades instead of crashing"* — contradicted by
R3-3: it vanishes. `test-broad-status-row-identity.sh` header still asserts *"Each T is proven with a
RED/GREEN mutation pair"* while `round3-red/` covers T4b/T6/T7 only. Either produce the missing pairs
or scope the sentence to the tests that have one.

### Low

**R3-8 — no `developer.summary.md` / `developer.full.md` in `docs/handoff/BROAD-STATUS-ROWS-02/`.**
Third round asked, third round missing. `round3-red/` is a real improvement and closes two thirds of
L3; the deliverable itself is still absent, so the only prose record of what changed and why is the
commit message, which R3-7 shows is not accurate.

**R3-9 — `leadv2-broad-status.sh:434`: the digest key format change makes every foreign lane appear
"raised" exactly once after deploy.** `prev_lanes` on disk holds bare task_ids, and foreign lanes were
never in the digest at all before this round, so the first beat reports `+N линии подняты` for lanes
that have been running for hours. Self-healing after one beat; worth one line in the commit message
so the first pulse is not misread.

**R3-10 — `leadv2-broad-status.sh:1026-1028`: neither new hidden-count string is asserted anywhere,**
and `2 строк таблицы не поместилось` does not agree in case with the numeral (the pre-existing
`3 строк очереди` has the same flaw, so this is consistency, not a new defect).

**R3-11 — `TABLE_ROW_CAP` / `FOREIGN_ROW_RESERVE` are magic numbers duplicated as bare literals in
the assertions** (`-eq 5` at blind `:267`, `-eq 2` at `:302`, `-eq 4` at `:346`). Changing the cap
reds three tests for the wrong reason. Export them from the renderer or derive them in the suite.

## Requirements

- **A (identity = task_id, human title in "Что делает", dedupe by identity)** — MET in the renderer,
  but it silently supersedes `test-broad-status-renderer-truth.sh` T9's opposite contract without
  updating it (R3-1). Not landable until that is reconciled.
- **B (cross-repo lane must appear in the table)** — MET for the 1-foreign and 6-foreign shapes.
  BROKEN as stated for the foreign-heavy shape: 2 of 6 rows and a false "не поместилось" (R3-2), and
  a whole repo can be permanently invisible (R3-5).
- **Regression guard (:203-213, empty vs unreadable)** — **BROKEN this round** (R3-3): a malformed
  collector table now produces `ДОСКА ПУСТА`. blind T1a/T1b/T1c/T2/T2b are still green, but they only
  cover `lanes.ok=false`, never a `lanes.ok=true` table of unreadable elements.
- **Tests / negative controls** — three fixes with working controls (MX-1/2/3 red, revert green),
  three with none (MX-4/5/6 green), one suite broken and unnoticed for three rounds (R3-1).

## The three fixtures, rendered verbatim

Harness: unmodified `plugins/leadv2/scripts/` at `23cada2` copied to scratch, stubbed collector,
`LEADV2_BROAD_STATUS_BEAT_AT=2026-08-30T12:00:00Z`, hermetic `LEADV2_PROJECT_ROOT`/`LEADV2_STATE_ROOT`.

### Fixture 1 — 7 own + 1 foreign

```
2026-08-30T12:00:00Z [BROAD_STATUS] dispatched=1
08:03 · посты н/д · комменты н/д · реплаи н/д

| Линия | Что делает | Состояние |
|---|---|---|
| OWN-01 | - filler lane 1 | пишет сейчас (1 байт в потоке) |
| OWN-02 | - filler lane 2 | пишет сейчас (2 байт в потоке) |
| OWN-03 | - filler lane 3 | пишет сейчас (3 байт в потоке) |
| OWN-04 | - filler lane 4 | пишет сейчас (4 байт в потоке) |
| OWN-05 | - filler lane 5 | пишет сейчас (5 байт в потоке) |
| persona-engine/FOREIGN-01 | — | тихо 0 мин |

С прошлого удара: +8 линии подняты, 0 закрыто.
Решений не ждёт.
(скрыто: 2 строк таблицы не поместилось, 3 строк очереди — docs/leadv2/founder-status-full.md)
[BROAD_STATUS_END]
```
Correct: 6 rendered of 8, foreign present and free of the always-true dispatch-id marker, hidden
arithmetic 8-6=2, no "мусорн" wording, delta counts all 8.

### Fixture 2 — 10 foreign + 0 own

```
2026-08-30T12:00:00Z [BROAD_STATUS] dispatched=1
08:03 · посты н/д · комменты н/д · реплаи н/д

| Линия | Что делает | Состояние |
|---|---|---|
| persona-engine/FOREIGN-01 | — | тихо 0 мин |
| persona-engine/FOREIGN-02 | — | тихо 0 мин |

С прошлого удара: +10 линии подняты, 0 закрыто.
Решений не ждёт.
(скрыто: 8 строк таблицы не поместилось, 3 строк очереди — docs/leadv2/founder-status-full.md)
[BROAD_STATUS_END]
```
**R3-2.** Two rows of a six-row budget. `8 … не поместилось` is false — four slots are empty. Ten
lanes are running, the founder sees two, and nothing says which repos the other eight belong to.

### Fixture 3 — 6 foreign + 7 own

```
2026-08-30T12:00:00Z [BROAD_STATUS] dispatched=1
08:03 · посты н/д · комменты н/д · реплаи н/д

| Линия | Что делает | Состояние |
|---|---|---|
| OWN-01 | - filler lane 1 | пишет сейчас (1 байт в потоке) |
| OWN-02 | - filler lane 2 | пишет сейчас (2 байт в потоке) |
| OWN-03 | - filler lane 3 | пишет сейчас (3 байт в потоке) |
| OWN-04 | - filler lane 4 | пишет сейчас (4 байт в потоке) |
| persona-engine/FOREIGN-01 | — | тихо 0 мин |
| persona-engine/FOREIGN-02 | — | тихо 0 мин |

С прошлого удара: +13 линии подняты, 0 закрыто.
Решений не ждёт.
(скрыто: 7 строк таблицы не поместилось, 3 строк очереди — docs/leadv2/founder-status-full.md)
[BROAD_STATUS_END]
```
The r2 High is genuinely dead: neither side is starved (4 own floor + 2 foreign reserve), the delta
line agrees with the board (13 = 7+6), and no row is called junk. This is the round's best result.
Residual: the 7 hidden are not split per side (R3-6) and nothing says four of them are foreign.

### Bonus fixture — the NEW-1 falsifier (own + foreign sharing a bare task_id, foreign silent 1h)

```
| SHARED-ID-01 | - own-repo half of the shared id | пишет сейчас (55 байт в потоке) |
| persona-engine/SHARED-ID-01 | — | тихо 60 мин |
```
r2's fabricated-liveness High is dead: the foreign row reports its own silence.

### Bonus fixture — R3-3, collector table of two non-dict elements

```
2026-08-30T13:00:00Z [BROAD_STATUS] dispatched=1
⚠ ДОСКА ПУСТА — ничего не выполняется, 0 мин
...
| (живых линий нет) | — | — |
```

## Contradiction scan

- `EXTRA_SUITE_MAP` — the three mapped paths exist and are executable; selection proven by replay.
  **Six other suites that read `leadv2-broad-status.sh` have no row** (R3-1).
- Commit message "test-broad-status-row-identity 10/10, lanes-blind 11/11, lane-pulse-founder 2/2" —
  re-ran all three, all true.
- Commit message "RED artifacts (4 mutations, each reverted)" — 2 of the 4 are not suite reds (R3-7).
- Commit message "a non-dict table row degrades instead of crashing" — **false**, it vanishes (R3-3).
- Code comment `:684-696` "A reservation must be BOUNDED on both sides … Neither side may starve the
  other" vs the code: foreign is bounded ABOVE by a hard max and can starve itself while own slots go
  unused (R3-2). The comment describes a floor; the code implements a ceiling.
- Code comment `:206-211` "Degrade it out of the table instead of crashing" vs
  `[r for r in table_rows if isinstance(r, dict)]` — "degrade" and "delete" are different operations
  (R3-3).
- `test-broad-status-renderer-truth.sh:281` "col-1 is a human name, never a hex id" vs this task's
  IDENTITY decision "col-1 is the task_id" — two live, contradictory contracts (R3-1).
- Suite header "Each T is proven with a RED/GREEN mutation pair" vs `round3-red/` contents — stale
  (R3-7).
- `bool(_repo_slug)` vs `leadv2-lanes-snapshot.sh:470` — own rows never carry `repo`, foreign always
  do. Correct at the source, no drift.
- Env vars / flags: `FOREIGN_ROW_RESERVE` and `TABLE_ROW_CAP` are module constants; no new `LEADV2_*`
  var, no `.env` or settings drift. `LEADV2_LANES_ALL_REPOS`, `LEADV2_LANE_FRESH_S`,
  `LEADV2_FOREIGN_SCAN_DEADLINE_S`, `LEADV2_BURN_GOVERNOR` read as before. None.
- Paths: `round3-red/` exists with all 6 referenced files; `docs/handoff/BROAD-STATUS-ROWS-02/` has
  no `developer.*.md` (R3-8).

## Verdict

**BLOCK.** Four High (R3-1 a green suite broken and unnoticed for three rounds and CI-invisible;
R3-2 the foreign-only board under-fills the cap and lies about why; R3-3 the L1 fix reintroduces the
false empty-board headline this file exists to kill; R3-4 three fixes with no negative control) plus
three Medium. The round's actual achievements are real and should be kept: NEW-1, NEW-3, NEW-4,
NEW-7, NEW-8, NEW-9 and L2 are fixed, and three of them are mutation-proven by my own in-body pairs.

DELIVERABLE_COMPLETE
