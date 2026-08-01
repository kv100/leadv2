# N-7b — badge dead-count honours the recency window

Task: `dispatch-246e9a23`. Canonical repo `~/Projects/leadv2`.

## What changed

`dead_n` moved from **before** the TTL-drop loop to **after** it, so the badge's
red number and the lanes-header "N dead" figure count only dead lanes still
in-window — the same window `done_recent` already honours. No new convention:
`DEAD_TTL` (`LEADV2_STATUS_DEAD_TTL_S`, default 3600s) is the window. A
belt-and-braces `r.get("outcome") != "completed"` guard is added so a completed
lane can never be re-conflated into the red count by a future refactor.

### `plugins/leadv2/scripts/leadv2-status-surface.sh`
- Deleted the pre-drop `dead_n = sum(... cls == "dead")` assignment; `live_n`
  stays pre-drop (live rows are never dropped, so pre/post is identical).
- Inserted **after** `rows = _kept` (post-TTL-drop, pre-collapse), before
  `done_recent`:
  ```python
  dead_n = sum(1 for r in rows
               if r["cls"] == "dead" and r.get("outcome") != "completed")
  ```
- Rewrote the comment block above `live_n` to state the dead count is in-window
  (post-TTL, pre-collapse), name `DEAD_TTL` + N-7b, keep the round-3 dead≠done
  note, and note collapse only touches done rows.
- Updated the adjacent TTL-loop comment (codex non-blocking finding): it no
  longer claims `dead_n` "stays pre-drop".

`_aged`, `done_recent`, the collapse rule, the TSV row format, and every field
offset are untouched. `.10s.sh` derives its number from the header — fixing the
source fixes the badge; no edit there.

### `plugins/leadv2/scripts/tests/test-status-surface.sh`
Appended three cases (helpers `_ledger`, `_run`, `_outcome`, `sig_has` already
existed):
- **N7B-T1** — one dead lane, journal age `NOW-1200` (< 3600) → header `1 dead`.
- **N7B-T2** — same fixture aged `NOW-7000` (> DEAD_TTL, < 7200 terminal
  age-out, so genuinely TTL-dropped) → header `0 dead` + non-zero
  `скрыто по возрасту`.
- **N7B-T3** — terminal lane whose run dir carries `.outcome=completed` →
  header `0 dead`, row renders `done(completed)`.

Suite count **87 → 90**. The non-regression invariant is *zero failures*, not
the literal 87 — so `90/90` is the expected passing output.

## Tests (honest)

```
test-status-surface.sh           === 90 passed, 0 failed ===
test-status-surface-cwd.sh       === 7 passed, 0 failed ===
test-dispatch-ledger-task-id.sh  === 6 passed, 0 failed ===
```
All three new N7B cases PASS. The suite's own `/bin/bash -n` (bash 3.2) check
passes on `leadv2-status-surface.sh`.

## End-to-end gate (acceptance #1)

Under `env -i HOME=$HOME PATH=/usr/bin:/bin` against the live shared state:

```
title:   🔴 3 / 🟢 2
header:  lanes (2 live, 3 dead, 0 done в последний час, 248 скрыто по возрасту · 3 projects)
visible dead rows: 3  (dead(exit=76)?, stale(59m silent)?, stale(6m silent)? — all in-window, all cls=dead)
```

Badge 🔴3 == header "3 dead" == 3 visible dead rows. Before this fix the same
state rendered 🔴 250 (all-time archive total) against 3 visible dead rows.

## Cross-provider review gate

Codex adversarial review of the full diff: **VERDICT: ship**. Findings:
- No NameError path — `dead_n` assigned unconditionally before `out`.
- Synthetic warn row still counts red (`.get("outcome")` → None ≠ "completed").
- `dead_shown + aged_dead == dead_total` holds; `_aged` aggregates dropped
  done+dead rows (not double-counted).
- No TSV schema / field-offset regression.
- Non-blocking: TTL-loop comment said `dead_n` stays pre-drop — **fixed**.

## Non-goals (untouched, as scoped)

`DONE_TTL=900` vs "done в последний час" wording mismatch; collapse rule;
`_aged` semantics; 7200s terminal age-out; TSV schema; `.10s.sh`;
`LEADV2_SKIP_DRIFT_GUARD` unset; no new file under `scripts/` (no shared-tree
symlink required by this lane); no destructive git; `b2fb70e` stands.

DELIVERABLE_COMPLETE
