status: fail
reviewer_says: do_not_merge

Scope: `c0fe726..b9a1e62` in `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-ROWS-02`
(round-2 delta: 3 files, +263/-36). Everything marked RAN was executed against a scratch copy of
`plugins/leadv2/scripts/`; no file under `plugins/` was modified in the worktree or the main repo.

Baseline (worktree, unmutated):

```
$ bash plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh   -> 9 passed, 0 failed  EXIT=0
$ bash plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh    -> 9 passed, 0 failed  EXIT=0
$ bash plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh          -> 2 passed, 0 failed  EXIT=0
$ bash -n leadv2-broad-status.sh test-broad-status-row-identity.sh test-broad-status-lanes-blind.sh -> OK (3 files)
$ ast.parse of the embedded python heredoc (824 lines)                  -> OK
```
(no mypy/tsc applies — bash + one embedded python3 heredoc; `bash -n` + `ast.parse` + the executed
suites are the equivalent gate.)

## RED/GREEN mutation pairs — I produced them, the round again shipped none

Five mutations, each inserted INSIDE the code body of the shipped `leadv2-broad-status.sh` in a scratch
copy, each reverted afterwards. RAN.

```
M-CAP          rows_out reserve-loop (:637-644)  ->  rows_out = rows_out_full[:TABLE_ROW_CAP]
   blind:    FAIL T5a: foreign-repo lane was cut by the row cap        === 8 passed, 1 failed ===
   identity: === 9 passed, 0 failed ===   (identity suite is blind to the cap — see NEW-4)
M-DEDUP-REPO   _key = (_row.get("repo"), str(_tid_raw))  ->  (None, str(_tid_raw))
   identity: FAIL T4: repo-blind dedup key ate one of the two lanes (own=1 foreign=0)   8/1
M-MISSING-TID  _key = ("__missing_task_id__", _idx)  ->  ("__missing_task_id__", 0)
   identity: FAIL T5: expected 2 degraded rows for task_id-less lanes, got 1            8/1
M-IDENTITY     the `if tid and tid != "?"` arm (:410-414)  ->  `if False: pass`
   identity: FAIL T1a T1b T1c T2 T3a T4 T6                                              2/7
   blind:    FAIL T5b                                                                   8/1
M-CLOSED-NAME  cause = (f"{linia_name} — " if linia_name else "") + sostoyanie  ->  sostoyanie
   identity: FAIL T6: closed line lost identity or human name:
             "Закрыто сегодня: CLOSED-NAME-01 (worker exited)"                          8/1
M-REPO-PREFIX  linia = f"{_repo_slug}/{linia}"  ->  linia = linia      (extra probe for prior M2)
   identity: FAIL T3b, FAIL T4                                                          7/2
GREEN (all mutations reverted): identity 9/9, blind 9/9.
```
Every fix in this round is reached at runtime. None of them is lying-green. That is the good news and
it is the whole of it.

## Prior findings — verdicts

| # | Prior finding | Verdict | Evidence |
|---|---|---|---|
| C1 | foreign lane cut by `TABLE_ROW_CAP` | **FIXED for the stated shape, but the fix creates NEW-1/2/3** | RAN. 7 own + 1 foreign renders 5 own + `persona-engine/FOREIGN-01`; `(скрыто: 2 …)` — arithmetic correct (8 rendered−6 shown). M-CAP reds blind T5a. Cap now unbounded and own-starving: NEW-2, NEW-3 |
| H1 | dedup key ignores `repo` | **FIXED as a key, but the surviving row is fabricated — NEW-1** | RAN. `(repo, task_id)` at :373-376; own + foreign `SHARED-ID-01` render as 2 rows; M-DEDUP-REPO reds T4. The second row shows the FIRST row's stream bytes — NEW-1 |
| H2 | `or "?"` collapses task_id-less rows | **FIXED** (nit NEW-8) | RAN. `("__missing_task_id__", _idx)` :377; 2 task_id-less lanes → 2 rows; M-MISSING-TID reds T5. Both rows are byte-identical in col 1 (`? (dispatch id unknown)`) — present, not "named" |
| H3 | identity preferred the dispatch id | **FIXED** | RAN. `task_id=BROAD-STATUS-ROWS-01`, `dispatch_id=aaaaaaaa` → `\| BROAD-STATUS-ROWS-01 \|`; T1c asserts the dispatch id must NOT win; M-IDENTITY reds 7 assertions |
| M1 | closed-lane prose lost the human name | **FIXED** | RAN. `Закрыто сегодня: CLOSED-NAME-01 (- retire the stale queue worker — …)`; T6 + M-CLOSED-NAME red |
| M2 | T3b is not a control | **FIXED by measurement, header still stale** | RAN. T3b reds under M-REPO-PREFIX, so it IS a control (for the repo prefix). But the suite header (:14-27) still lists only T1/T2/T3 for a 6-test suite, still claims "Each T … proven with a RED/GREEN mutation pair", and **no RED artifact exists in `docs/handoff/BROAD-STATUS-ROWS-02/`** — the brief demanded it in writing. See NEW-10 |
| M3 | extend, do not duplicate | **PARTIAL** | READ. One cap test was folded into the blind suite (+49). The parallel suite grew 215→338 lines with 6 near-identical 16-line collector stubs that differ only in a JSON payload; one stub taking a payload path replaces ~90 of them (my own probe harness is 20 lines and covered all 6 shapes) |
| M4 | fixtures cannot distinguish task_id from dispatch id | **FIXED** | READ+RAN. All fixtures now use founder-style task ids with a distinct `dispatch_id`; T1c is the falsifier |
| L1 | `_row.get()` without `isinstance` guard | **NOT FIXED** | READ. :371-373 still `_row.get(...)`; the upstream filter at :204 is `not (isinstance(r, dict) and r.get("error"))`, so a non-dict element survives it and reaches the new loop → `AttributeError`, whole beat dies |
| L2 | dedup drops invisible in the accounting | **NOT FIXED** (now near-inert) | READ. `table_rows_hidden` (:645) is computed from `rows_out_full`, i.e. post-dedup. With the repo-aware key the dedup should now only drop true duplicates, so the exposure is small |
| L3 | verification claimed, artifact not on disk | **RECURRED** | READ. `docs/handoff/BROAD-STATUS-ROWS-02/` holds no developer deliverable, no RED output, no before/after render. The commit message asserts "Suites: … 9/9 … 9/9 … 2/2" (true — I re-ran them) but the brief's "leave the RED output in the handoff dir" and "a rendered before/after of the table" were both ignored |

## NEW findings

### High

**NEW-1 — `leadv2-broad-status.sh:227-229` + `:405`: the foreign row H1 rescued joins the OWN repo's
`lane_detail` on a bare `task_id` and renders the own lane's state as its own. RAN.**

`detail_by_task` is keyed on `str(l.get("task_id"))` and is built from `lane_detail`, which is
own-repo-only. `d = detail_by_task.get(tid)` at :405 does not look at `row["repo"]`. Fixture = the
round's own T4 shape, with the foreign lane made deliberately silent (`age_s: 3600`):

```
| SHARED-ID-01                 | - own-repo half of the shared id | пишет сейчас (55 байт в потоке) |
| persona-engine/SHARED-ID-01  | - own-repo half of the shared id | пишет сейчас (55 байт в потоке) |
```
The second row is entirely fabricated: mission title, worker, `writing_now`, `stream_bytes=55` and the
`dispatch_id` all belong to the own-repo lane. A foreign lane that has been dead for an hour is reported
to the founder as actively writing. Before this round that row was deleted (H1); now it lies, which is
worse — and the suite's T4 marks it PASS because it only counts rows. Required fix: join `detail_by_task`
only for own-repo rows (`d = detail_by_task.get(tid) if not row.get("repo") else None`), or key
`detail_by_task` on `(repo, task_id)`. Add the assertion to T4: the foreign row must NOT carry the own
lane's `stream_bytes`.

**NEW-2 — `leadv2-broad-status.sh:637-644`: foreign rows are never truncated, so `TABLE_ROW_CAP` is
defeated without bound. RAN.**

`if _is_foreign: rows_out.append(_line)` has no counter. 10 foreign lanes, 0 own:

```
| persona-engine/FOREIGN-01 (dispatch id unknown) | — | тихо 0 мин |
… 10 rows …
(скрыто: 3 строк очереди — …)          <- table_rows_hidden = 0
```
Ten rows in the founder-facing pulse against PULSE-READABLE-01 rule 2 ("max ~6 rows"), the rule the
comment at :620-622 cites two lines above. This is not theoretical: `leadv2-lanes-snapshot.sh:411-471`
emits one foreign row per entry in each foreign repo's `active.yaml`, with **no cap and no status
filter** (`active` and `stale` both reach the table; only `dead` is diverted to `closed_items`), across
every root `leadv2-projects.sh` lists. Required fix: reserve, do not exempt — e.g. cap foreign at
`min(_foreign_row_count, max(1, TABLE_ROW_CAP // 3))` or one slot per repo, and count the remainder into
`table_rows_hidden`.

**NEW-3 — `leadv2-broad-status.sh:636`: `_own_row_budget = max(0, TABLE_ROW_CAP - _foreign_row_count)`
lets foreign lanes evict every own-repo lane, and the founder is told his own live lanes were junk. RAN.**

Fixture 7 own + 6 foreign:

```
| persona-engine/FOREIGN-01 (dispatch id unknown) | — | тихо 0 мин |
… FOREIGN-02..06 …
С прошлого удара: +7 линии подняты, 0 закрыто.
(скрыто: 7 мусорных/лишних строк таблицы, 3 строк очереди — …)
```
Zero own-repo rows. The delta line says 7 lanes were raised and the table shows none of them; all seven
are folded into "мусорных/лишних строк" — verbatim the lie C1 was raised to kill, now pointed at the
lead's own lanes. Four foreign lanes already squeeze the own board to two rows. Required fix: the own
budget must have a floor (`_own_row_budget = max(TABLE_ROW_CAP - _foreign_slots, TABLE_ROW_CAP - 2)` or
similar) — a reserved slot for a guest may never be a reserved slot for all guests.

**NEW-4 — `tests/run-all.sh:120-121`: the Critical's ONLY control is not selected by CI on a change to
the file it guards. RAN.**

`blind T5a` is the sole assertion that reds under M-CAP; the identity suite is 9/9 under that mutation.
Replaying run-all.sh's `--scope changed` selector for a lone change to
`plugins/leadv2/scripts/leadv2-broad-status.sh`:

```
stem-candidate suites that exist:  (none)
EXTRA_SUITE_MAP rows selected:
   plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh
   plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh
is the blind suite selected?  NO — test-broad-status-lanes-blind.sh has NO EXTRA_SUITE_MAP row at all
```
The blind suite ran in this lane only because the commit also edited the suite file itself. The next
edit to `leadv2-broad-status.sh` alone will not run it, and the cap fix reverts silently green. This is
E2E-KILLRATE-01 rule 3 verbatim. Required fix: add
`leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh` to
`EXTRA_SUITE_MAP` and prove it with the replay above.

### Medium

**NEW-5 — `leadv2-broad-status.sh:501-515` + `:890-891`: identity became repo-qualified in the dedup key
and in the rendered row, but `current_lane_digest` / `prev_lanes` are still keyed on the bare `task_id`.
RAN.**
Two consequences, both measured. (a) A foreign row never enters the digest at all (`d is None` and no
`mission_title` → no `linia_name`), so 3 foreign lanes render while the same screen says
`С прошлого удара: +0 линии подняты, 0 закрыто.` — the delta line contradicts the table above it, and a
foreign lane can never be reported closed either. (b) With a shared task_id the own and foreign rows
collapse to ONE digest entry: 2 rendered rows, `+1 линии подняты`. Required fix: key the digest on the
same tuple the row renders.

**NEW-6 — `leadv2-broad-status.sh:960`: `f"{table_rows_hidden} мусорных/лишних строк таблицы"`.**
The Critical's brief said a hidden lane "may never be counted as junk". Foreign rows are no longer
hidden, so the letter is met — but the same sentence now labels own-repo lanes evicted by NEW-3, and
lanes hidden by the ordinary cap, as junk. Split the note: `N линий не поместилось` vs actual junk.

### Low

**NEW-7 — `leadv2-broad-status.sh:398-399 / 559-562 / 639`: `rows_out` and `rows_out_is_foreign` are two
parallel lists joined by `zip()`.** There is exactly one append site today, so they are in sync. A future
`rows_out.append(...)` that forgets the sibling list makes `zip()` truncate the table with no error and
no hidden-count. `rows_out.append((line, is_foreign))` removes the class.

**NEW-8 — `leadv2-broad-status.sh:410-415`: every foreign row carries `(dispatch id unknown)` in the
identity column, permanently.** Foreign lanes structurally never join `lane_detail`, so the marker is
100 % predictable and carries no information, while nearly doubling column 1
(`persona-engine/FOREIGN-01 (dispatch id unknown)`). Suppress it when `row.get("repo")` is set.

**NEW-9 — `tests/test-broad-status-lanes-blind.sh:250` `[[ "$T5_OWN_ROWS" -ge 1 ]]`.** The assertion
guarding "own rows still render alongside the reserved foreign slot" passes with 6 of 7 own lanes
evicted, and cannot see NEW-3 at all. Assert the exact expected count (5 for that fixture).

**NEW-10 — `tests/test-broad-status-row-identity.sh:14-27`: the header documents T1/T2/T3 for a suite
that now has T1a-c, T2, T3a-b, T4, T5, T6.** The unbacked "Each T … proven with a RED/GREEN mutation
pair" sentence prior review asked to remove or back is still there, and the handoff dir still has no RED
output — the third round in a row that this evidence obligation was written down and not met.

## Requirements

- **A (identity = task_id, human title only in "Что делает", dedupe by identity)** — MET. Verified by
  T1c + M-IDENTITY, T4 + M-DEDUP-REPO, T5 + M-MISSING-TID.
- **B (cross-repo lane must appear in the table)** — MET for ≤`TABLE_ROW_CAP` foreign lanes, at the cost
  of NEW-1 (the row that appears is fabricated), NEW-2/NEW-3 (the cap is defeated / own lanes starve)
  and NEW-5 (the foreign lane is still invisible to the delta line).
- **Regression guard (:203-213, empty vs unreadable)** — INTACT. blind T1a/T1b/T1c/T2/T2b green; the
  silent-vanish path prior review found above it is closed (H2/H1 both red under mutation). L1's
  `AttributeError` crash path is unrelated to this guard and still open.
- **Tests / negative controls** — the assertions are real (5 in-body mutations, 5 reds, all reverted
  green), but the artifact obligation was ignored again (NEW-10, L3), the Critical's control is not CI-
  selected (NEW-4), and T4/T5b are too weak to see NEW-1/NEW-3.

## Contradiction scan

- `EXTRA_SUITE_MAP` — both mapped paths exist and are 100755; **the blind suite has no row** (NEW-4).
- Commit message "test-broad-status-row-identity 9/9 (was 5), lanes-blind 9/9 (was 7), lane-pulse-founder
  2/2" — re-ran, all three true.
- Commit message "Foreign rows now get a reserved slot; only own-repo rows compete for the remainder" —
  contradicted by the code: foreign rows get an UNBOUNDED number of slots and the remainder can be zero
  (NEW-2, NEW-3).
- Code comment `:630` "Foreign rows get a RESERVED slot (never truncated)" — "reserved" and "never
  truncated" are different policies; the code implements the second. The comment reads as the first.
- `bool(_repo_slug)` vs snapshot output: own-repo rows never carry `repo` (`leadv2-lanes-snapshot.sh`
  main table) and foreign rows always do (:470), so the flag is correct at the source. No drift.
- Suite header T-list vs the suite's actual tests — stale (NEW-10).
- Env vars (`LEADV2_LANES_ALL_REPOS`, `LEADV2_LANE_FRESH_S`, `LEADV2_FOREIGN_SCAN_DEADLINE_S`,
  `LEADV2_BURN_GOVERNOR`), flag semantics, file paths: none.

DELIVERABLE_COMPLETE
