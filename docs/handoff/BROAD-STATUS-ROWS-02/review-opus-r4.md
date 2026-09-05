status: fail
reviewer_says: do_not_merge

Scope: `23cada2..1ea7be5` (round-4 delta: 5 files, +256/-31) in
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-ROWS-02`.
Everything marked RAN was executed against a scratch copy of `plugins/leadv2/scripts/`
(byte-identical to lane HEAD, verified with `diff -q` after every restore). One temporary untracked
file (`tests/.r4-select.sh`) was created for the selector replay and deleted.
`git status --porcelain -- plugins/ tests/` is EMPTY at the time of writing.

Code-intel routing note (honest, not a skipped step): both indexes available in this session are
built for `~/Projects/persona-engine`. `get_risk(["plugins/leadv2/scripts/leadv2-broad-status.sh"])`
returns `no git metadata available`, and `tests/run-all.sh` resolves to persona-engine's *own*
unrelated file (co-change partners `platform/orchestrator/v4-runner.sh`,
`agent/state/post-form-defaults.json`). Neither index covers this diff, so nothing from them is
cited below. Every claim here is a run.

## Baseline — four suites, re-run, not taken on trust

```
$ bash plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh -> === 22 passed, 0 failed ===  EXIT=0
$ bash plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh   -> === 11 passed, 0 failed ===  EXIT=0
$ bash plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh    -> === 14 passed, 0 failed ===  EXIT=0
$ bash plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh          -> 2 passed, 0 failed           EXIT=0
```
The lead's numbers are correct, including the renderer-truth recovery 16/6 -> 22/0.

The five newly-mapped suites, run individually at HEAD:

```
test-pulse-readable-rendering.sh   7 passed, 0 failed   EXIT=0
test-pulse-empty-board.sh         10 passed, 0 failed   EXIT=0
test-single-lead-beat.sh           9 passed, 0 failed   EXIT=0
test-broad-status-relay-scope.sh  25 passed, 0 failed   EXIT=0   (not mapped; does not read the renderer)
test-broad-status-duty.sh         28 passed, 10 failed  EXIT=1   ~13 min wall clock   <-- N4-7
```

Always-on via `run-all.sh:82` -> `run-core-offline.sh`, red BEFORE this lane too (I re-ran both
against `d4f5408`'s renderer in scratch — PRE-EXISTING, **not** this lane's regression):

```
test-broad-status-foreign-lanes.sh   HEAD: PASS=5 FAIL=3    anchor d4f5408: PASS=5 FAIL=3
test-glm-deferred-ladder.sh          HEAD: FAIL=1           anchor d4f5408: FAIL=1
```

Type gate (bash + one embedded python heredoc; no `.py`/`.ts` in the changeset, so `mypy --strict`
and `tsc --noEmit` do not apply — `bash -n` + `ast.parse` are the equivalent):

```
$ bash -n plugins/leadv2/scripts/leadv2-broad-status.sh \
          plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh \
          plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh \
          plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh \
          tests/run-all.sh
bash -n: OK (5 files, no output)

$ python3 ast.parse(<PY heredoc extracted from leadv2-broad-status.sh>)
  ast.parse OK (PY, 975 lines)

$ git diff --name-only 23cada2..HEAD | grep -E '\.(py|ts|tsx)$'
  no .py/.ts in changeset -> mypy --strict / tsc --noEmit N/A
```

## `--scope changed` selector replay. RAN.

Live `tests/run-all.sh` code (`add_suite()` + the changed-file loop + `EXTRA_SUITE_MAP`), the only
edit being `changed="${_TEST_CHANGED:-...}"` so the selection can be driven without dirtying the
lane. `_TEST_CHANGED="plugins/leadv2/scripts/leadv2-broad-status.sh"`:

```
plugins/leadv2/scripts/tests/run-core-offline.sh      (always-on, run-all.sh:82)
tests/test-status-surface-bash32.sh                   (always-on)
tests/test-status-surface-single-lead.sh              (always-on)
tests/test-status-surface-fast-names.sh               (always-on)
plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh
plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh
plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh
plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh      <- new
plugins/leadv2/scripts/tests/test-broad-status-duty.sh                <- new
plugins/leadv2/scripts/tests/test-pulse-readable-rendering.sh         <- new
plugins/leadv2/scripts/tests/test-pulse-empty-board.sh                <- new
plugins/leadv2/scripts/tests/test-single-lead-beat.sh                 <- new
```
All 8 `EXTRA_SUITE_MAP` rows select. R3-1b is genuinely done. My r3 report named
`test-broad-status-relay-scope.sh` as a seventh renderer-reading suite — **I was wrong**; it
exercises the relay, never the renderer (25/0 either way). The author's grep-based census is the
better one. It does omit `test-glm-deferred-ladder.sh`, which also references the renderer, but
`run-core-offline.sh` runs it unconditionally, so the hole is closed by accident, not by the map.

## My own in-body RED/GREEN mutation pairs (nine, all inside the function body, all reverted). RAN.

Six are controls that exist. Three are controls that do NOT exist.

```
MU1  :703-709  the R3-2 floor branch  ->  `_foreign_slots = min(_foreign_row_count, FOREIGN_ROW_RESERVE)`
      blind FAIL T6a (got 2 rows) + FAIL T6b (8 чужих)          === 12 passed,  2 failed ===
MU2  :798      `elif live_lane_count == 0 and malformed_row_count:` -> `and False`
      blind FAIL T8a: malformed rows rendered as a false empty board   13/1
MU3  :648      `if malformed_row_count:` (the NAMED degraded prefix line) -> `if False:`
      ident 11/0 · blind 14/0 · renderer 22/0     <-- NO SUITE SEES IT.  N4-3
MU4  :1106-09  per-side wording -> the old combined `{n} строк таблицы не поместилось`
      blind FAIL T6b: hidden count wrong (4 строк таблицы)      13/1   (MX-6 control CONFIRMED)
MU5  :434      `_digest_key = f"{_repo_slug}::{tid}" ...` -> `_digest_key = tid`
      ident FAIL T7: digest key collapsed the foreign lane ... +0 линии подняты   10/1  (MX-4 CONFIRMED)
MU6  :735-745  the round-robin selection -> flat first-N encounter order
      ident 11/0 · blind 14/0 · renderer 22/0     <-- NO SUITE SEES IT.  N4-4
MU7  :610      col-1 renders `(linia_name or linia)` — the pre-IDENTITY contract
      ident 6/5 · blind 12/2 · renderer 16/6      <-- strong control, three suites (R3-1a CONFIRMED)
MU8  :221      `malformed_row_count = 0`
      blind FAIL T8a + T8b                                       12/2
MU9  :222      `table_rows = [r for r in table_rows if isinstance(r, dict)]` -> `pass`   (the real MX-5)
      blind FAIL T8b: malformed rows dropped silently            13/1   (MX-5 control CONFIRMED)

GREEN (scratch restored, `diff -q` byte-identical to lane HEAD): ident 11/0, blind 14/0, renderer 22/0.
```

The round's own `round4-red/` logs are, this time, **genuine suite runs** — I reproduced every one
of them (RED-R3-4-MX5 = 13/1 == my MU9; RED-R3-4-MX4 = 10/1 == my MU5; RED-R3-4-MX6 = 13/1 == my
MU4; RED-R3-1 = 16/6 == my MU7's renderer arm). R3-4 is the cleanest work on this lane so far.

## Prior findings — verdicts

| # | Prior finding (r3) | Verdict | Evidence |
|---|---|---|---|
| **R3-1** H | renderer-truth 16/6 since `c0fe726`, CI blind, contract clash on col-1 | **FIXED** | RAN. 22/0 at HEAD. `1982923` re-specifies T9 in its own commit with the reasoning; the assertion was **strengthened**, not weakened — `[[ "$COL1" == "dispatch-aabbccdd" ]]` (exact equality on the parsed column) replaces a `grep -q` + negative-hex heuristic. T2/T8/T10 bodies are untouched; only their `ROW` lookup was retargeted from the human-name text to the identity. MU7 reds all three suites, so the new contract has real kill power. `cca50e9` adds 5 map rows; the replay above shows 8 select. Residual: N4-7 |
| **R3-2** H | foreign-only board renders 2 of 6 and lies "8 не поместилось"; T6 `-eq 2` locks it in | **PARTIAL — the degenerate case only** | RAN. `_own_row_count == 0` now gives foreign the whole cap (fixture 2: 6 of 6, "4 чужих"), and T6a/T6b were re-specified deliberately in `60a4c8e` to assert the cap is FILLED. But the fix is a special case, not a floor: **1 own + 10 foreign -> 3 of 6 rows, "8 чужих строк не поместилось"** (fixture 5), and **2 own + 4 foreign — total 6, cap 6, nothing overflows — renders 4 rows and says "2 чужих строк не поместилось"** (fixture 6). See N4-1 |
| **R3-3** H | `isinstance` filter deletes rows uncounted -> false `ДОСКА ПУСТА` | **FIXED for the lie, PARTIAL for the remedy** | RAN. Fixture 4: no `ДОСКА ПУСТА`; headline `⚠ СТРОКИ ТАБЛИЦЫ НЕ ЧИТАЮТСЯ — 3 строк(и) повреждены; неизвестно, пуста ли доска на самом деле`; `empty_since_path` correctly untouched. MU2/MU8/MU9 all red T8a/T8b. "Empty" and "unreadable" are again distinguishable. But the rows are summarised in a prefix line, **not rendered as named degraded rows**, the table still prints the positive claim `\| (живых линий нет) \| — \| — \|`, and MU3 deletes the prefix line with all three suites green. See N4-3, N4-6 |
| **R3-4** H | MX-4/5/6 revert with zero suite failures | **FIXED** | RAN. MX-4 -> row-identity T7 (MU5 = 10/1). MX-5 -> lanes-blind T8b (MU9 = 13/1). MX-6 -> lanes-blind T6b (MU4 = 13/1). All three logs in `round4-red/` are real suite runs and I reproduced each number independently |
| **M** | foreign slots allocated alphabetically; a whole repo can be permanently invisible | **PARTIAL** | RAN. Round-robin by repo added at `:735-745` — fixture 8 (3 repos x 4 lanes + 7 own) now gives m3-market and persona-engine one slot each instead of both to the first repo. But with `FOREIGN_ROW_RESERVE=2` and 3 live repos, **respiro-ios still gets zero slots on every beat**; within a repo the order is still `sorted(session_by_task.items())` (`leadv2-lanes-snapshot.sh:411`), so a 6-hour-silent `stale` lane outranks an actively-writing one (fixture 7); and MU6 reverts the whole round-robin with every suite green. See N4-4, N4-5 |
| **M** | per-side hidden counts computed at `:701-703` then discarded | **FIXED** | RAN. `:1106-1109` renders `N своих строк не поместилось` / `N чужих строк не поместилось`; fixture 3 shows both in one line. MU4 reds T6b. Residual: `table_rows_hidden` at `:769` is now assigned and never read (N4-8) |
| **M** | commit message overclaims ("degrades instead of crashing"; 2 of 4 RED logs not suite reds) | **PARTIAL** | READ + RAN. The artifact problem is fixed — all 11 `round4-red/` logs are real suite runs. Four textual overclaims remain, listed in the contradiction scan: the MX-5 failure mode is misdescribed, the round-robin comment claims a liveness ordering that does not exist, `cca50e9` says "six" where seven suites referenced the renderer, and `test-broad-status-row-identity.sh:34-36` still says *"Each T is proven with a RED/GREEN mutation pair … round3-red/"* while T7's pair lives in `round4-red/` and most Ts have no pair at all |
| **L** (r3-8) | no `developer.summary.md` / `developer.full.md` | **NOT FIXED** | READ. Fourth round asked, fourth round absent. `docs/handoff/BROAD-STATUS-ROWS-02/` has `context.yaml`, `lane-mission.md`, 8 round-2 logs and `round4-red/` — no developer deliverable (protocol §5) |
| **L** (r3-9) | digest-key format change makes every foreign lane look "raised" once after deploy | **NOT FIXED (advisory)** | READ. `prev_lanes` on disk still holds bare task_ids; no note in any of the five commit messages |
| **L** (r3-10/11) | numeral agreement; `TABLE_ROW_CAP`/`FOREIGN_ROW_RESERVE` duplicated as bare literals | **NOT FIXED (advisory)** | READ. `2 своих строк не поместилось`, `3 строк(и) повреждены`; blind `:272 -eq 5`, `:306 -eq 6`, `:356 -eq 4` |

## NEW findings

### High

**N4-1 — `plugins/leadv2/scripts/leadv2-broad-status.sh:703-711`: the under-fill and its false
sentence survive for every board with 1-3 own lanes, which is the ordinary board. RAN.**

```python
if _own_row_count == 0:
    _foreign_slots = min(_foreign_row_count, TABLE_ROW_CAP)
elif _foreign_row_count == 0:
    _foreign_slots = 0
else:
    _foreign_slots = min(_foreign_row_count, FOREIGN_ROW_RESERVE)
_own_row_budget = TABLE_ROW_CAP - _foreign_slots
```
This is a special case for `own == 0`, not the floor the commit message claims ("the reserve is a
FLOOR … never a CEILING"). The ceiling is still unconditional whenever *both* sides have rows, and
neither side inherits the other's unused slots. The under-fill condition is exactly
`_own_row_count < _own_row_budget and _foreign_row_count > _foreign_slots`, i.e. **any board with
1-3 own lanes and 3+ foreign lanes**. Under CONCURRENCY-2-LANES-01 (WIP = 2 own lanes per session)
that is the normal shape, not an edge case.

Measured, fixture 6 — 2 own + 4 foreign, six lanes total, `TABLE_ROW_CAP` six, nothing can
possibly overflow:

```
| OWN-01                    | - filler lane 1 | пишет сейчас (1 байт в потоке) |
| OWN-02                    | - filler lane 2 | пишет сейчас (2 байт в потоке) |
| persona-engine/FOREIGN-01 | — | тихо 0 мин |
| persona-engine/FOREIGN-02 | — | тихо 0 мин |
(скрыто: 2 чужих строк не поместилось, …)
```
Two slots empty and a sentence stating that two rows did not fit. That sentence is false, on the
one founder surface whose entire purpose is not making false statements — the same class as the
"мусорных/лишних" lie this task was opened to delete and the "8 не поместилось" lie round 4 was
opened to delete. Fixture 5 (1 own + 10 foreign) is the louder version: 3 of 6 rows, `8 чужих
строк не поместилось`, three slots empty; my r3 report named this exact shape verbatim and it was
not addressed.

Required fix (unchanged from r3): two-pass fill. Pass 1 grants each side `min(count, floor)` —
`FOREIGN_ROW_RESERVE` for foreign, `TABLE_ROW_CAP - foreign_floor` for own. Pass 2 hands every
still-unused slot to whichever side still has rows, until `TABLE_ROW_CAP` is reached. Then
`_own_rows_hidden + _foreign_rows_hidden == max(0, total - TABLE_ROW_CAP)` becomes an invariant
you can assert directly, instead of a number that happens to be right in three fixtures.

**N4-2 — no assertion covers the mixed under-fill, so N4-1 will survive the next round too. READ.**

`test-broad-status-lanes-blind.sh` fixtures: T5 = 7 own + 1 foreign, T6 = 10 foreign + 0 own,
T7 = 6 foreign + 7 own. Every one has `own_count` of 0 or 7 — never the 1-3 range where the bug
lives. T6a/T6b therefore give the fix full green while the defect is untouched, which is the same
false-confidence shape as the old `-eq 2`. E2E-KILLRATE-01 rule 1: the assertion must keep the
production arithmetic real and fail on the real defect.

Required: add T9 with 2 own + 4 foreign asserting `rendered == min(total, TABLE_ROW_CAP)` (6) and
that no `не поместилось` clause is emitted, plus T10 with 1 own + 10 foreign asserting 6 rendered
and `5 чужих строк не поместилось`. Then mutate the fill loop and paste the RED.

### Medium

**N4-3 — `leadv2-broad-status.sh:646-652`: the named degraded prefix line has no negative control.
RAN (MU3).** `if malformed_row_count: table_prefix.append(...)` -> `if False:` leaves
row-identity 11/0, lanes-blind 14/0, renderer-truth 22/0. T8b passes on the headline alone
(`grep -q '3 строк' && grep -qi 'не читаются'` — the `⚠ СТРОКИ ТАБЛИЦЫ НЕ ЧИТАЮТСЯ — 3 строк(и)`
headline satisfies both), so the table-region marker is uncovered. This is precisely the
belt-and-suspenders that T3 provides on the `lanes.ok=false` path — the malformed path needs the
same. Required: assert the marker in `founder-status-full.md`'s table region specifically, the way
T3 does, and mutate it.

**N4-4 — `leadv2-broad-status.sh:735-745`: the round-robin foreign selection has no negative
control. RAN (MU6).** Replacing the whole `while`/`_repo_buckets` block with a flat first-N slice
leaves all three suites green. A Medium fix with zero coverage is one refactor away from silently
reverting. Required: a fixture with 2 foreign repos x 3 lanes + 7 own asserting one row from EACH
repo, not two from the first.

**N4-5 — `leadv2-broad-status.sh:727-733` + `leadv2-lanes-snapshot.sh:411,448-453`: the reserved
foreign slots still go to the least-live lanes, and the comment says the opposite. RAN.**

The comment claims the per-repo bucket order "is the liveness order the upstream rows already
arrive in — a dead row never reaches `rows_out_full`". Both halves are wrong. Upstream is
`for tid, s in sorted(session_by_task.items())` — alphabetical by task_id, never liveness. And
`leadv2-lanes-snapshot.sh:448-453` classifies anything with `age_s <= 86400` as `stale` and emits
it; the renderer's `continue` at `:607` diverts only closed/tombstone rows, so `stale` rows do
reach `rows_out_full`. Fixture 7 (7 own + 4 foreign in one repo, the two alphabetically-first
silent for 6 h, the two last actively writing):

```
| persona-engine/AAA-STALE-01 | — | тихо 360 мин |
| persona-engine/BBB-STALE-02 | — | тихо 360 мин |
```
Both reserved slots go to lanes that have said nothing since breakfast; `YYY-ACTIVE-03` and
`ZZZ-ACTIVE-04` are hidden. Compounding: with three live repos (persona-engine, m3-market,
respiro-ios) and `FOREIGN_ROW_RESERVE = 2`, round-robin still leaves the third repo at zero slots
on every beat — fixture 8's `respiro-ios` never appears, and the hidden line names no repo.
Required: sort each repo's bucket by `(status != "active", age_s)` before popping, and either
raise the reserve to `min(len(repos), ...)` or rotate the starting repo per beat so the third repo
is not structurally invisible.

**N4-6 — `leadv2-broad-status.sh:840-843`: the malformed-only board still prints a positive false
claim inside the table. RAN.** With every row unreadable, `rows_out` is empty and the placeholder
`| (живых линий нет) | — | — |` fires — "there are no live lanes", stated as fact, three lines
under a headline that says we do not know whether the board is empty. The round-4 brief asked for
"a NAMED degraded row"; what shipped is a summary line plus the unchanged empty-table placeholder.
Required: when `malformed_row_count` and `not rows_out`, render
`| (нечитаемых строк: N) | — | коллектор вернул не-объект |` instead of the "нет" placeholder, and
assert the placeholder is ABSENT.

**N4-7 — `tests/run-all.sh:126`: `test-broad-status-duty.sh` was added to `EXTRA_SUITE_MAP` while
it is red and takes ~13 minutes. RAN.** At HEAD it is `28 passed, 10 failed` (T3a/T3b loop cycle,
T4a-T4f loop/watchdog timing, T7 crontab skip logging, T8b `supervisor-role.md` wording drift).
None of the ten touch the renderer's table output, and the suite's own header warns that a
supervise snapshot costs ~25 s in a bare fixture, so this is environmental/pre-existing rather than
this lane's regression — CONFIRMED: the same suite at the lane anchor `d4f5408` is `24 passed,
14 failed`, and HEAD's ten failures are a strict SUBSET of the anchor's fourteen, so this lane
improved the suite and broke nothing in it. Either way, mapping a red 13-minute suite onto every renderer edit converts `--scope changed` from a gate
into a guaranteed red wait, which is how R3-1 happened in the first place (a red suite nobody
reads). Fix the suite or quarantine it explicitly; do not leave it mapped and red.

### Low

**N4-8 — `leadv2-broad-status.sh:769`: `table_rows_hidden` is now dead.** It is assigned from the
two per-side counters and read nowhere (only `:414`'s comment still refers to it). Delete it or
keep it as the asserted invariant `table_rows_hidden == max(0, total - TABLE_ROW_CAP)` demanded by
N4-1.

**N4-9 — `test-broad-status-row-identity.sh:34-36` still claims every T has a RED/GREEN pair and
points at `round3-red/`.** T7's pair is in `round4-red/`; T1a/T1b/T2/T3a/T3b/T5/T6 have none. Same
sentence flagged in r3 as R3-7, still there.

**N4-10 — no `GREEN-R3-4-MX5-L1-guard.log`.** Every other RED in `round4-red/` has its GREEN
partner; MX-5's does not, so the "revert -> RED, restore -> GREEN" loop is only half on disk, while
`1ea7be5` advertises the pattern `round4-red/{RED,GREEN}-R3-4-MX{4,5,6}-*.log`. (I ran it:
restored = 14/0.)

**N4-11 — numeral agreement.** `2 своих строк не поместилось`, `3 строк(и) повреждены`. Pre-existing
style (`3 строк очереди`), listed for consistency only.

**N4-12 — `TABLE_ROW_CAP` / `FOREIGN_ROW_RESERVE` still duplicated as bare literals in assertions**
(`-eq 5` at blind `:272`, `-eq 6` at `:306`, `-eq 4` at `:356`). Changing the cap reds three tests
for the wrong reason.

**N4-13 — still no `developer.summary.md` / `developer.full.md`.** Fourth round. The only prose
record of this round is five commit messages, three of which contain a claim I had to correct in
the contradiction scan.

**N4-14 — `tests/run-all.sh` cannot go green at HEAD in any scope**, because `run-all.sh:82`
always adds `run-core-offline.sh`, which always runs `test-broad-status-foreign-lanes.sh` (5/3)
and `test-glm-deferred-ladder.sh` (FAIL=1). I verified both are identical at the lane anchor
`d4f5408`, so they are **not** this lane's doing — but it means "CI is green" is not a sentence
anyone can truthfully say about this branch, and a future round-5 red will again be hard to see.

## Requirements

- **A (identity = task_id, human title in "Что делает", dedupe by identity)** — **MET, and now
  reconciled.** The contradicting `renderer-truth` T9 was re-specified deliberately in its own
  commit, strengthened rather than weakened, and MU7 proves the new contract is enforced by three
  suites at once.
- **B (cross-repo lane must appear in the table)** — **MET for the 0-own, 7-own and 6+7 shapes;
  still BROKEN for 1-3 own lanes** (N4-1), and a third repo is still structurally invisible while
  stale lanes outrank live ones (N4-5).
- **Regression guard (empty vs unreadable)** — **RESTORED** (R3-3). Both `lanes.ok=false` and
  `lanes.ok=true`-with-malformed-rows now produce distinct, honest headlines, and three of my
  mutations red it. Residual: the in-table placeholder still asserts "нет" (N4-6).
- **Tests / negative controls** — six of my nine mutations are caught, including all three that
  round 3 shipped uncontrolled. Two of this round's own fixes (the degraded prefix line, the
  round-robin) are uncontrolled, and the shape that still fails has no fixture at all (N4-2).
- **"Do not weaken an assertion to make a fix pass"** — **HONOURED.** I checked every changed
  assertion: T9 got strictly stronger (parsed-column equality vs. a grep heuristic); T2/T8/T10 were
  not touched, only their row lookup; T6 went from `-eq 2` to `-eq 6` plus a new exact hidden-count
  check; T13/T2c changed meaning deliberately and said so. No weakening found.

## The four fixtures, rendered verbatim

Harness: unmodified `plugins/leadv2/scripts/` at `1ea7be5` copied to scratch, stubbed collector,
`LEADV2_BROAD_STATUS_BEAT_AT=2026-08-30T12:00:00Z`, hermetic `LEADV2_PROJECT_ROOT`/`LEADV2_STATE_ROOT`,
`LEADV2_BURN_GOVERNOR=0`.

### Fixture 1 — 7 own + 1 foreign

```
2026-08-30T12:00:00Z [BROAD_STATUS] dispatched=1
09:23 · посты н/д · комменты н/д · реплаи н/д

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
(скрыто: 2 своих строк не поместилось, 3 строк очереди — docs/leadv2/founder-status-full.md)
[BROAD_STATUS_END]
```
Correct. Cap filled, foreign row survives, hidden arithmetic 8-6=2, and the count is now attributed
to the side it came from ("своих") — the R3-6 fix, visible.

### Fixture 2 — 10 foreign + 0 own (must FILL the cap)

```
2026-08-30T12:00:00Z [BROAD_STATUS] dispatched=1
09:23 · посты н/д · комменты н/д · реплаи н/д

| Линия | Что делает | Состояние |
|---|---|---|
| persona-engine/FOREIGN-01 | — | тихо 0 мин |
| persona-engine/FOREIGN-02 | — | тихо 0 мин |
| persona-engine/FOREIGN-03 | — | тихо 0 мин |
| persona-engine/FOREIGN-04 | — | тихо 0 мин |
| persona-engine/FOREIGN-05 | — | тихо 0 мин |
| persona-engine/FOREIGN-06 | — | тихо 0 мин |

С прошлого удара: +10 линии подняты, 0 закрыто.
Решений не ждёт.
(скрыто: 4 чужих строк не поместилось, 3 строк очереди — docs/leadv2/founder-status-full.md)
[BROAD_STATUS_END]
```
The cap is FILLED and `4` is the true drop count. R3-2's headline case is dead. This is the
round's best result — and the only fill case the fix actually handles.

### Fixture 3 — 6 foreign + 7 own

```
2026-08-30T12:00:00Z [BROAD_STATUS] dispatched=1
09:23 · посты н/д · комменты н/д · реплаи н/д

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
(скрыто: 3 своих строк не поместилось, 4 чужих строк не поместилось, 3 строк очереди — docs/leadv2/founder-status-full.md)
[BROAD_STATUS_END]
```
Cap filled, own floor of 4 holds, delta agrees with the board (13 = 7+6), and the hidden count is
now split per side. No starvation in either direction.

### Fixture 4 — malformed collector table (3 non-dict elements, `lanes.ok=true`)

```
2026-08-30T12:00:00Z [BROAD_STATUS] dispatched=1
⚠ СТРОКИ ТАБЛИЦЫ НЕ ЧИТАЮТСЯ — 3 строк(и) повреждены; неизвестно, пуста ли доска на самом деле

09:23 · посты н/д · комменты н/д · реплаи н/д

НЕ ЧИТАЮТСЯ 3 строк(и) таблицы (повреждённый формат от сборщика) — это НЕ означает, что этих линий нет, они unreadable

| Линия | Что делает | Состояние |
|---|---|---|
| (живых линий нет) | — | — |

С прошлого удара: +0 линии подняты, 0 закрыто.
Решений не ждёт.
(скрыто: 3 строк очереди — docs/leadv2/founder-status-full.md)
[BROAD_STATUS_END]
```
`ДОСКА ПУСТА` is gone and "empty" vs "unreadable" are distinguishable again — R3-3's blocking half
is fixed. The residual is the last table line: `(живых линий нет)` still asserts, as fact, the
thing the headline two lines above says is unknown (N4-6).

### Extra fixture 5 — 1 own + 10 foreign (N4-1, the under-fill that survived)

```
| Линия | Что делает | Состояние |
|---|---|---|
| OWN-01 | - the only own lane | пишет сейчас (1 байт в потоке) |
| persona-engine/FOREIGN-01 | — | тихо 0 мин |
| persona-engine/FOREIGN-02 | — | тихо 0 мин |

С прошлого удара: +11 линии подняты, 0 закрыто.
(скрыто: 8 чужих строк не поместилось, 3 строк очереди — docs/leadv2/founder-status-full.md)
```
3 rows of a 6-row budget; at most 5 rows genuinely did not fit, the beat says 8.

### Extra fixture 6 — 2 own + 4 foreign, total == cap (N4-1, the everyday board)

```
| Линия | Что делает | Состояние |
|---|---|---|
| OWN-01 | - filler lane 1 | пишет сейчас (1 байт в потоке) |
| OWN-02 | - filler lane 2 | пишет сейчас (2 байт в потоке) |
| persona-engine/FOREIGN-01 | — | тихо 0 мин |
| persona-engine/FOREIGN-02 | — | тихо 0 мин |

С прошлого удара: +6 линии подняты, 0 закрыто.
(скрыто: 2 чужих строк не поместилось, 3 строк очереди — docs/leadv2/founder-status-full.md)
```
Six lanes, six slots, nothing can overflow — and the founder is told two rows did not fit.
`founder-status-full.md` does carry all six rows, which limits the damage but does not make the
compact beat's sentence true.

### Extra fixture 7 — 7 own + 4 foreign in one repo, stale-first (N4-5)

```
| OWN-01 | - filler lane 1 | пишет сейчас (1 байт в потоке) |
| OWN-02 | - filler lane 2 | пишет сейчас (2 байт в потоке) |
| OWN-03 | - filler lane 3 | пишет сейчас (3 байт в потоке) |
| OWN-04 | - filler lane 4 | пишет сейчас (4 байт в потоке) |
| persona-engine/AAA-STALE-01 | — | тихо 360 мин |
| persona-engine/BBB-STALE-02 | — | тихо 360 мин |

(скрыто: 3 своих строк не поместилось, 2 чужих строк не поместилось, 3 строк очереди — …)
```
`YYY-ACTIVE-03` and `ZZZ-ACTIVE-04` (writing 5 s ago) are hidden behind two lanes silent for six
hours, because the reserve is filled in `sorted(task_id)` order.

### Extra fixture 8 — 3 foreign repos x 4 lanes + 7 own (N4-5, round-robin partial)

```
| OWN-01 | - filler lane 1 | пишет сейчас (1 байт в потоке) |
| OWN-02 | - filler lane 2 | пишет сейчас (2 байт в потоке) |
| OWN-03 | - filler lane 3 | пишет сейчас (3 байт в потоке) |
| OWN-04 | - filler lane 4 | пишет сейчас (4 байт в потоке) |
| m3-market/M3--01 | — | тихо 0 мин |
| persona-engine/PER-01 | — | тихо 0 мин |

(скрыто: 3 своих строк не поместилось, 10 чужих строк не поместилось, 3 строк очереди — …)
```
Round-robin works as far as it can: m3-market no longer monopolises both slots. `respiro-ios` gets
zero, every beat, and the hidden line names no repo.

## Contradiction scan

- **`EXTRA_SUITE_MAP`** — all 8 mapped paths exist, are readable, and select on a renderer change
  (replay above). `test-broad-status-relay-scope.sh` from my r3 list does NOT read the renderer —
  my error, corrected. `test-glm-deferred-ladder.sh` does and is unmapped, but `run-core-offline.sh`
  is always-on so it runs anyway.
- **`cca50e9` "six suites … five of them; the sixth, foreign-lanes, is already covered by
  run-core-offline.sh's always-on set"** — the always-on claim is TRUE (`run-all.sh:82-85`,
  `run-core-offline.sh:343`). The count is off by one: seven suites referenced the renderer and
  were unmapped; `test-glm-deferred-ladder.sh` (`run-core-offline.sh:324`) is not mentioned.
  Harmless, but it is a claim the runs do not support.
- **`1ea7be5` "MX-5 … R3-3's new T8 mutates the same guard and fails (render failure ->
  СТАТУС НЕ СОБРАН)"** — the control EXISTS (MU9 = 13/1, confirmed) but the described failure is
  wrong: the suite fails on **T8b "malformed rows dropped silently, not surfaced"**, and
  `founder-status.md` is still written (header `dispatched=1 degraded=1`), not replaced by
  `СТАТУС НЕ СОБРАН`. Right conclusion, wrong mechanism in the message.
- **`60a4c8e` / code comment `:727-733` "round-robin … BY INDEX (first-seen order per repo, which
  is the liveness order the upstream rows already arrive in — a dead row never reaches
  rows_out_full)"** — **false on both halves.** Upstream is `sorted(session_by_task.items())`
  (`leadv2-lanes-snapshot.sh:411`), alphabetical; and `stale` rows up to `age_s <= 86400`
  (`:448-453`) do reach `rows_out_full` (fixture 7 renders two of them). The `continue` at
  `leadv2-broad-status.sh:607` diverts closed/tombstone rows, not silent ones.
- **`60a4c8e` "the reserve/floor split only applies when both sides have rows to compete for the
  cap"** — literally true and exactly the defect: when both sides have rows the cap is *not* filled
  (N4-1). The commit describes a floor and the code still implements a ceiling in the branch that
  matters most.
- **`66ba7eb` "surface them as a named degraded table_prefix line"** — TRUE this time (fixture 4),
  unlike round 3's "degrades instead of crashing". But it is a prefix line, not the "named degraded
  row" the brief asked for, and the table still prints `(живых линий нет)`.
- **`test-broad-status-row-identity.sh:34-36`** "Each T is proven with a RED/GREEN mutation pair …
  round3-red/" — stale, and now also wrong about the directory.
- **Renderer-truth T13/T2c** — semantics deliberately inverted (name-freeze -> description tracks
  current work). Documented in the suite and the commit. I could not find any surviving assertion
  that the *name-freeze* mechanism still works; if `linia_name` freezing is now unreachable, say so
  and delete it, otherwise it is untested code. Advisory, not counted as a finding.
- **Env vars / flags** — no new `LEADV2_*` variable this round. `TABLE_ROW_CAP` and
  `FOREIGN_ROW_RESERVE` remain module constants. `LEADV2_LANES_ALL_REPOS`, `LEADV2_LANE_FRESH_S`,
  `LEADV2_FOREIGN_SCAN_DEADLINE_S`, `LEADV2_BURN_GOVERNOR` read as before. No `.env`/settings drift.
- **Paths** — `round4-red/` exists; all log paths named in the five commit messages resolve,
  except `GREEN-R3-4-MX5-*.log`, which is advertised by the pattern
  `round4-red/{RED,GREEN}-R3-4-MX{4,5,6}-*.log` in `1ea7be5` and does not exist (N4-10).
  `docs/handoff/BROAD-STATUS-ROWS-02/developer.{summary,full}.md` still absent.
- **Lane cleanliness** — `git status --porcelain -- plugins/ tests/` is empty; the only dirty paths
  are lead-owned `docs/leadv2/*` state files untouched by this lane.

## Verdict

**BLOCK.** Two High: N4-1, the under-fill and its false "не поместилось" sentence, still fires on
the ordinary 1-3-own-lane board — including a board with exactly `TABLE_ROW_CAP` lanes where
nothing can overflow at all; and N4-2, no fixture exists in the 1-3-own range, so the green suite is
again defending a shape it does not test. Both are one arithmetic block (`:703-711`) and two
assertions away from done.

Everything else this round is real and should be kept. R3-1 is fully fixed and the assertion was
strengthened, not weakened — I mutated it three ways and it held. R3-4 is fully fixed: all three
previously-uncontrolled fixes now red their suite, and I reproduced every `round4-red/` number
independently. R3-3's blocking half — the false empty-board headline — is dead. R3-6 is fixed. The
`EXTRA_SUITE_MAP` hole is closed and proven by replay. This is the first round on this lane where
the artifacts on disk matched what the commit messages claimed.

DUTY-ANCHOR-BASELINE (N4-7, RAN, ~13 min each):

```
anchor d4f5408 : === 24 passed, 14 failed ===  EXIT=1
   T3a T3b T4a T4b T4c T4d T4e T4f T7 T8a T8b(leadv2.md) T8b(supervisor-role.md) T8c x2
HEAD   1ea7be5 : === 28 passed, 10 failed ===  EXIT=1
   T3a T3b T4a T4b T4c T4d T4e T4f T7 T8b(supervisor-role.md)
```
HEAD's failure set is a strict subset of the anchor's. `test-broad-status-duty.sh` is red for
reasons that predate this lane (loop/watchdog timing on this host, crontab-skip logging, and one
doc-wording drift), and the lane made it four assertions better, not worse. The finding stands only
as "do not map a permanently-red 13-minute suite into `--scope changed` without saying so".

DELIVERABLE_COMPLETE
