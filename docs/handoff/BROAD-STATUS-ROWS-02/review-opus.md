status: fail
reviewer_says: do_not_merge

Scope: commit c0fe726 in `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-ROWS-02`
(3 files, +248/-8). Everything marked "CONFIRMED BY RUN" below was executed against a scratch copy of
`plugins/leadv2/scripts/` (no file under `plugins/` was modified in the worktree or the main repo).

Baseline runs, for the record:

```
$ bash plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh
[TEST] PASS: T1a  [TEST] PASS: T1b  [TEST] PASS: T2  [TEST] PASS: T3a  [TEST] PASS: T3b
[TEST] === 5 passed, 0 failed ===          EXIT=0
$ bash plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh   -> 7 passed, 0 failed
$ bash plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh         -> 2 passed, 0 failed
$ bash -n {leadv2-broad-status.sh, tests/test-broad-status-row-identity.sh, tests/run-all.sh}  -> OK (all three)
```
(no mypy/tsc applies — the diff is bash with an embedded python3 heredoc; `bash -n` plus the executed
suites are the equivalent gate.)

Negative controls I ran myself (the diff ships no RED artifact, so I produced one):

```
M1  revert the fix inside the loop body:  linia = id_display  ->  linia = linia_name if linia_name else id_display
    [TEST] FAIL: T1a: expected 2 identity rows, got 0
    [TEST] FAIL: T1b  [TEST] FAIL: T2  [TEST] FAIL: T3a  [TEST] PASS: T3b
    === 1 passed, 4 failed ===
M2  neutralise the dedup inside the block:  `if _tid_key in _seen_tids:` -> `if False:`
    [TEST] FAIL: T2: expected exactly 1 row for the duplicated task_id, got 2
    === 4 passed, 1 failed ===
```
So both fixes ARE reached at runtime (not lying-green), and T1/T2 are real controls. **T3b is not**:
it passes with the entire fix reverted — see Medium-2.

---

## Critical

**C1 — `plugins/leadv2/scripts/leadv2-broad-status.sh:587-590` (`TABLE_ROW_CAP = 6`) +
`plugins/leadv2/scripts/leadv2-lanes-snapshot.sh:1661-1690`: requirement B is closed by claim, and a
measured mechanism that drops a cross-repo lane is still live. CONFIRMED BY RUN.**

The snapshot merge *appends* foreign rows to the end of the table (`doc["table"].append(...)`), after
own-repo rows have been ranked and capped (`CAP_ROWS = 20`, snapshot:1358-1360; never-started and codex
rows are also appended after that, :1387/:1405). The renderer then keeps only the FIRST 6 rows
(`rows_out = rows_out_full[:TABLE_ROW_CAP]`). A foreign-repo lane is therefore the systematic casualty
of the cap, and the founder is told it was junk.

Inputs -> output (scratch run: 7 own-repo active lanes + 1 foreign `repo=persona-engine` lane):
```
| dispatch-00000001 … dispatch-00000006 |          <- 6 own rows only
С прошлого удара: +7 линии подняты, 0 закрыто.
(скрыто: 2 мусорных/лишних строк таблицы, 3 строк очереди — docs/leadv2/founder-status-full.md)
$ grep -c 'persona-engine/dispatch-ffffffff' founder-status-full.md -> 1   # full doc only
```
The cross-repo lane is absent from the pulse and is described to the founder as "мусорных/лишних строк
таблицы". That is exactly defect B ("a cross-repo lane was missing from the table entirely"), untouched
by this diff. The commit message's counter-claim — "Verified via a live repro against
leadv2-lanes-snapshot.sh --all-repos that the cross-repo merge itself already includes both own- and
foreign-repo lanes" — covers only the MERGE, is not on disk anywhere in
`docs/handoff/BROAD-STATUS-ROWS-02/` (no developer deliverable exists there), and says nothing about the
renderer cap. The task explicitly allowed "an honest 'the snapshot is single-repo, here is the
evidence'"; what landed is neither the evidence nor the fix.

Required fix: exempt foreign rows from `TABLE_ROW_CAP` (reserve at least one slot per repo, or rank
foreign rows with the others instead of by append order), and name a hidden foreign lane in the
hidden-note by repo rather than folding it into "мусорных". If B is genuinely a non-issue, attach the
run that shows a foreign row surviving with >6 own lanes.

## High

**H1 — `leadv2-broad-status.sh:369-376` (dedup key): the key ignores `repo`, so it deletes a lane whose
rendered identity is DISTINCT. CONFIRMED BY RUN.**

Identity is repo-qualified (`linia = f"{_repo_slug}/{linia}"`, :440-441) but the dedup key is not
(`_tid_key = str(_row.get("task_id") or "?")`, :371). Inputs: own-repo row `task_id=dispatch-11111111`
plus foreign row `{task_id: dispatch-11111111, repo: persona-engine}`:
```
dedup ON  (as shipped):  | dispatch-11111111 | - own repo lane | пишет сейчас (10 байт в потоке) |
dedup OFF (M2 mutation): | dispatch-11111111 | … |  AND  | persona-engine/dispatch-11111111 | … |
```
The foreign lane vanishes: no row, no degraded line, no hidden-count. This is the fix for defect A
re-creating defect B on a second path. In a shared tree where the same task id is worked from two repos
this is not hypothetical. Required fix: key the dedup on the SAME tuple that is rendered —
`(row.get("repo"), task_id)` — never on a subset of it.

**H2 — `leadv2-broad-status.sh:371` (`or "?"`): all task_id-less rows collapse onto one key, so the
second such lane vanishes silently — a regression of the `:203-213` lesson ("a lane that cannot be read
must render as a NAMED DEGRADED ROW, never vanish"). CONFIRMED BY RUN.**

Inputs: two distinct table rows with no `task_id` ("lane A" / "lane B"):
```
dedup OFF: | ? (dispatch id unknown) | — | тихо 1 мин |   x2  (ugly, but both lanes visible)
dedup ON:  | ? (dispatch id unknown) | — | тихо 1 мин |   x1  (lane B is gone from the beat entirely)
```
Today all three own-repo producers set `task_id` (snapshot:1358/1387/1405), so this is latent rather
than firing — but the renderer's own `or "?"` fallback exists because the field is not guaranteed, and
requirement A says the same ("falling back to the sig8 when task_id is absent"), a fallback this diff
did not implement. Required fix: never dedupe on a synthesised key — an identity-less row keeps its own
row (sig8 or index-qualified key) — and any row the dedup does drop must be counted into the hidden note
at :903-911.

**H3 — `leadv2-broad-status.sh:431` (`linia = id_display`): requirement A's fallback order is inverted —
the founder's task_id ranks LAST and, in the common case, appears nowhere in the row. CONFIRMED BY RUN.**

`id_display` (:396-402) prefers `dispatch-<dispatch_id>` from lane_detail and only then falls back to
`tid`. Inputs: `task_id="BROAD-STATUS-ROWS-02"`, `dispatch_id="9f3a1c22"`, mission_title
`"BROAD-STATUS-ROWS-02 -- rebuild the founder status pulse table"`:
```
| dispatch-9f3a1c22 | - rebuild the founder status pulse table | пишет сейчас (42 байт в потоке) |
```
`BROAD-STATUS-ROWS-02` appears in neither column (`product_sentence` strips the leading id token). The
founder asks about the task he named and the pulse answers with a hex handle he has never seen. The task
text was explicit: "task_id, falling back to the sig8 when task_id is absent". Required fix: use `tid`
when it is a real task id and `id_display`/sig8 only when it is not; the dispatch id already has a home
on the diagnostic detail line (`detail_lines.append(f"{id_display} — …")`, :526).

## Medium

**M1 — `leadv2-broad-status.sh:519` (`closed_items.append({"name": linia, …})`): the closed-lanes prose
line lost its human name. CONFIRMED BY RUN.**
`linia` used to be the human name when resolvable; it is now always the identity, and `closed_parts`
(:658) renders prose, not a table column:
```
Закрыто сегодня: dispatch-5b7d0e91 (pid gone)     # was: "make the review engine select (pid gone)"
```
Required fix: `"name": linia_name or linia` for closed items — identity belongs in the table column, the
sentence needs the name (PULSE-READABLE-01).

**M2 — `plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh:84-96` (header) and T3a/T3b: a
claim not backed by the code, plus a tautological assertion. CONFIRMED BY RUN.**
The header states "Each T below is proven with a RED/GREEN mutation pair". My M1 mutation (full revert
of the identity fix) leaves **T3b PASSING** — the foreign row has no resolvable `mission_title`, so
pre-fix it already rendered `persona-engine/dispatch-ffffffff` through the id fallback. T3b therefore
locks behaviour that was never broken and is not a control for requirement B at all (a real B test needs
>6 rows, foreign appended last — see C1). No RED output exists anywhere in
`docs/handoff/BROAD-STATUS-ROWS-02/` to back the header. Required fix: delete the unbacked sentence, or
replace T3 with a cap-aware fixture that fails against today's renderer.

**M3 — requirement violation and duplication: `tests/test-broad-status-row-identity.sh` is a new 215-line
file; the task said "extending `plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh` rather
than duplicating it".** The blind suite is 213 lines and already owns the identical harness (scratch
repo, `beat_env`, stub claude, `LEADV2_BURN_GOVERNOR=0`). The new file re-implements all of it plus three
near-identical 16-line collector stubs that differ only in their JSON payload; one stub taking a payload
path (as my own probes used) replaces ~50 of those lines. Confirmed by reading both files.

**M4 — the suite cannot detect H3 or a future re-inversion: every fixture uses
`task_id = "dispatch-<hex>"` (:151-152, :181-182, :210-211), the one degenerate case where
`id_display == task_id`.** T1/T2/T3 pass identically whether identity is sourced from the task_id or from
the dispatch id. Required fix: at least one fixture with a founder-style task id and a *different*
`dispatch_id`, asserting that the task id is what lands in "Линия".

## Low

**L1 — `leadv2-broad-status.sh:370-373`: `_row.get(...)` without the `isinstance(_row, dict)` guard its
sibling filter at :199-200 carries.** `leadv2-lanes-snapshot.sh:1684` appends whatever `json.loads(line)`
yields onto the merged table, which may be a string or a number; that raises `AttributeError` and kills
the whole beat. The downstream loop had the same exposure before this diff, so it is not a new class of
bug — but the new loop is now the first crash site and it sits above the LANE-DETAIL-BLIND-01 guard the
task asked to protect. Confirmed by reading.

**L2 — dedup drops are invisible in the accounting.** `table_rows_hidden` / `hidden_note` (:590,
:903-911) exist for exactly "rows the founder is not seeing"; rows removed at :369-376 are not counted
there, so the pulse's own arithmetic cannot reveal H1/H2 when they fire. Confirmed by reading.

**L3 — commit-message claim without artifact:** "Verified via a live repro against
leadv2-lanes-snapshot.sh --all-repos …". `docs/handoff/BROAD-STATUS-ROWS-02/` holds only context.yaml,
lane-mission.md, the review-* files and review.diff — no developer deliverable, no probe output. Per the
repo's evidence contract that claim needs its output or an `UNVERIFIED:` prefix.

---

## Requirements met / unmet

- **A (identity in "Линия", human title only in "Что делает", dedupe by identity)** — PARTIALLY MET.
  The column no longer carries `human_name()` and the fix is genuinely reached (M1 goes RED); but the
  identity source is inverted (H3: dispatch id preferred over task_id, task_id absent from the row), the
  "sig8 when task_id is absent" fallback was not implemented (renders `? (dispatch id unknown)`, H2), and
  the dedup key is not the rendered identity (H1).
- **B (cross-repo lane missing from the table)** — UNMET. No code change; the "already fine" verdict
  covers only the snapshot merge, has no artifact on disk, and a measured renderer-level mechanism
  (`TABLE_ROW_CAP = 6` vs foreign rows appended last) still drops the cross-repo lane and labels it junk
  (C1). H1 adds a second drop path.
- **Regression guard (:203-213, empty vs unreadable)** — TEXT INTACT, SPIRIT REGRESSED. The `lanes_ok` /
  `lanes_fail_reason` block is untouched and `test-broad-status-lanes-blind.sh` is 7/7 green, but the
  diff introduces a NEW silent-vanish path above it (H1/H2): a lane can now disappear with no named
  degraded row and no hidden-count — the exact failure that guard was written against.
- **Tests (real negative controls, extend the blind suite)** — PARTIALLY MET. T1 and T2 are genuine
  controls (I measured RED/GREEN myself, M1/M2); T3 is not (Medium-2). The suite duplicates the blind
  suite instead of extending it (Medium-3), its fixtures are shaped so the identity-source bug cannot be
  seen (Medium-4), and the mutation evidence the task demanded is not in the handoff directory.
- **CI wiring (`EXTRA_SUITE_MAP` row, proven with `--scope changed`)** — MET. Selection proof against the
  lane's own diff:
  ```
  $ git diff --name-only HEAD~1..HEAD | (stem match against tests/run-all.sh EXTRA_SUITE_MAP)
  leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh
  leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh
  ```
  The row's key form (`<stem>.sh`) matches the matcher at tests/run-all.sh:148-153, and the mapped path
  exists and is executable.

## Contradiction scan

- `LEADV2_LANES_ALL_REPOS` — default `1` (leadv2-lanes-snapshot.sh:84) and the collector calls
  `leadv2-lanes-snapshot.sh --json` (leadv2-status-collector.sh:118), i.e. the full call the foreign merge
  is gated on. No contradiction with the commit message on that point.
- `EXTRA_SUITE_MAP` new row path `plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh` exists,
  mode 100755. No path drift.
- The comment at :369-375 claims the dedup guards "the same lane appearing once from an own-repo read and
  once from a foreign-repo read" — the two reads come from two DIFFERENT repo registries
  (leadv2-lanes-snapshot.sh:390-470 reads each foreign root's own active.yaml), so that pair is not
  necessarily one lane; the comment justifies H1's behaviour instead of describing it.
- Test-header claim "Each T … proven with a RED/GREEN mutation pair" contradicts the measured M1 result
  for T3b (Medium-2).
- Everything else scanned (env-var names, flag semantics, file paths): none.

DELIVERABLE_COMPLETE
