# MENUBAR-PANEL-02 — the panel the founder sees uses a different code path than the one that was fixed

**Repo to change: `~/Projects/leadv2`.** Branch only — no commit to main, no push, no merge.

## What happened (this is the important part — read it before touching code)

Two sessions fixed the same panel on 2026-08-04 in two different places, and they collided:

- `c1e8cbf` (mine) fixed **`leadv2-status-surface.sh`**: honour terminal rows so dead lanes
  stop rendering, never count the lead's own session, aggregate across repos with a label,
  and render `<task_id> · <phase> · <arm> <age>` with sig8 only as fallback. 23/0 in
  `test-status-surface-single-lead`, 12/0 in the bash-3.2 suite, both green post-merge.
- `3afe03a` (a parallel session, SWIFTBAR-FAST-NAMES-01) changed **the widget**
  `leadv2-status-surface.5s.sh` so that it **never calls the renderer on its render path** —
  it reads two cache files and does its own sig8→name mapping via `labels.map`.

So the fix and the surface the founder actually looks at no longer meet. Evidence, all from
the founder's live machine:

Cached path (what SwiftBar renders every 5s):
```
🛠 8: 4caee2e8 opus now (9s)
4caee2e8 · · · worker          <- sig8, and three EMPTY fields where phase/model/age belong
  sig 4caee2e8                 <- a second row per lane, reads as duplication
```

Forced live render (`LEADV2_STATUS_SYNC=1`), i.e. the renderer's `--all` payload:
```
🛠 4: 4caee2e8 opus now
mode=single-lead active 4 4caee2e8 opus now
  4caee2e8 · worker · opus now · persona-engine
  bcd7cdf0 · worker · opus now · persona-engine
  50e51359 · worker · kimi 14m · persona-engine
```

Meanwhile the SAME renderer's table output, run directly, is correct:
```
lanes (0 live, 1 dead, 1 done в последний час)
  VOICE-CUSTOMER-CONTROL-01  worker confirmed·done  sonnet  25m  a911068a
```

## The three things this proves

1. **The `--all` payload path did not get the fix.** My tests exercised the table path. The
   widget consumes `--all`. Same script, two outputs, only one corrected.
2. **The lead is still counted as a lane, and `--all` proves it**: three rows tagged `opus`,
   which is the LEAD model, not a worker arm. `4caee2e8` is additionally mislabelled
   `persona-engine` when that lane lives in `~/Projects/leadv2` — so the repo attribution in
   this path is wrong too.
3. **Empty fields.** `4caee2e8 · · · worker` renders three empty separators. Either the
   cached payload lost the fields or the label map drops them. Never print a separator for a
   field you do not have.

## Required

- Make `--all` (and therefore the widget) honour exactly what the table path already
  honours: terminal rows retire a lane, the lead session is never a lane, repo attribution
  comes from the ledger the lane is actually in, and names/phases render when known.
  **One source of truth for lane rows — both outputs must be projections of the same
  computed list, not two independent walks.** If that means the table path and `--all` share
  a single function, do that.
- Fix the repo attribution so a lane in `~/Projects/leadv2` is not labelled `persona-engine`.
- Drop the empty-field separators, and drop the duplicated `sig <hex>` sub-row when the row
  already shows a name.
- The cached path must not present a stale count as confident. The wrapper already has a
  staleness story (`⚠️ кэш устарел`) — make sure it actually triggers here.

## Rules

- **bash 3.2** — SwiftBar launches with a minimal environment. `test-status-surface-bash32.sh`
  exists for exactly this and must stay green.
- Do NOT revert `3afe03a`'s caching; the 5-second cadence is wanted. Fix the disagreement.
- Keep `test-status-surface-single-lead.sh` (23 cases) green — it encodes the fixed
  behaviour and must not be weakened to make `--all` pass.
- `.env` READS only.

## Done means

- A test asserting the table output and the `--all` output describe the SAME lane set for
  one fixture (this is the regression that let the two drift).
- A test proving a lead/opus session appears in NEITHER output.
- A test proving a lane in a second repo is attributed to that repo in `--all`.
- A test proving no empty `·` separators are emitted for missing fields.
- Both status-surface suites pasted in full. `bash -n` + `/bin/bash -n` clean.
- Do NOT run `run-core-offline.sh`.

## Attempt 2 — the founder's live panel, 2026-08-04 20:03 (this is the acceptance target)

Attempt 1 (lane `b12e69cc`, glm) produced NOTHING — byte-clean worktree, no stream file — and
was then mislabelled `dead / e2e_regression`. Nothing about the mission changed. This attempt
excludes glm.

Names now resolve, so that half works. What the founder still sees, verbatim from his screenshot:

```
menu bar title:  6: MENUBAR-PANEL-02 glm 16m

MENUBAR-PANEL-02 · · · worker
  sig b12e69cc
VOICE-PAGE-SCROLL-AND-WE · · · worker
SWIFTBAR-FAST-NAMES-01 · · · queued
VOICE-CUSTOMER-CONTROL-0 · · · queued
PERSONA-FABRICATES-A-BIO · · · queued
LANE-CLOSE-LOOP-01 · · · queued
⚠ · feeddark · terminals
⚠ · leadv2 · terminals
⚠ · replyaud · terminals
⚠ · replyaud2 · terminals
⚠ · repro · terminals
```

Six defects in that one picture, all still open:

1. **`· · ·` — three empty fields.** The row has slots for phase, model and age and fills none
   of them, while the TITLE of the very same lane shows `glm 16m`. The data exists and the row
   does not use it. Empty fields must never render a separator.
2. **`sig b12e69cc` as a second row.** The lane already shows its name; the sig sub-row is pure
   duplication and doubles the height of every named lane.
3. **The count is wrong and includes corpses.** `6:` — but `MENUBAR-PANEL-02` (`b12e69cc`) is
   DEAD: its worktree is byte-clean and its ledger row reads `terminal=dead cause=e2e_regression`.
   A lane with a terminal row must not be counted or displayed as live. This is the ORIGINAL
   defect of this task, still unfixed on this path.
4. **Queued TASKS are being rendered as lanes.** `SWIFTBAR-FAST-NAMES-01`,
   `VOICE-CUSTOMER-CONTROL-0`, `PERSONA-FABRICATES-A-BIO`, `LANE-CLOSE-LOOP-01` are backlog
   rows, not running workers — and they inflate the count to six. Either give them their own
   clearly-labelled section with its own count, or drop them. They must not share a number with
   live lanes.
5. **Names truncated mid-word.** `VOICE-PAGE-SCROLL-AND-WE`, `VOICE-CUSTOMER-CONTROL-0`. Truncate
   on a separator with an ellipsis, or shorten from the middle — never cut a word so that
   `-CONTROL-0` reads as a different task than `-CONTROL-01`.
6. **Five `⚠ <repo> terminals` rows** occupy nearly half the panel. Four of those repos
   (`feeddark`, `replyaud`, `replyaud2`, `repro`) are not repos this operator is working in.
   Collapse the whole warning family into ONE line (`⚠ 5 repos: terminals unreadable`) that can
   be expanded, and do not warn about repos with no lanes at all.

## Acceptance for attempt 2

Everything in the original "Done means" below, PLUS:

- A test proving a row with a known model and age renders them, and a row missing a field emits
  NO separator for it.
- A test proving a lane whose ledger row is terminal is neither counted in the title nor listed.
- A test proving queued backlog rows are not counted in the live-lane number.
- A test proving a long task name is truncated without producing a string that could be mistaken
  for a different task id.
- The warning family renders as one collapsed line for N repos.

Run the status-surface suites only. Do NOT run `run-core-offline.sh`.
