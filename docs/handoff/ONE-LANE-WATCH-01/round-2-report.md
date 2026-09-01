# ONE-LANE-WATCH-01 round 2 — report

Lane: `worktree-ONE-LANE-WATCH-01-R2` (branched from main after round-1 merge `c49cc9f`).
Files touched: `plugins/leadv2/scripts/leadv2-lane-watch-v2.sh`,
`plugins/leadv2/scripts/tests/test-lane-watch-v2.sh`. `tests/run-all.sh` and
`plugins/leadv2/hooks/hooks.json` needed no change (round 1 already wired both).

## The four defects and their fixes

### 1 — grace used mtime, so it never expired for a live provider [Critical]

`_lw_dispatch_age_min` read `stat -f %m` on the provider run dir. A runner
rewrites that dir whether or not the worker produces (probe 2026-09-01,
`codex-openai-codex/state/TESTS-POLLUTE-REAL-JOURNAL-01-*`: `broker.json` is
rotated to `.stale-<ts>` roughly every 30 min and rewritten — `ls -la` shows
four rotations between 15:51 and 20:01) — so `d_age` stayed near zero and the
grace gate skipped the stall check forever. The lead measured a lane 23 min
past `STALE_MIN` in silence, noticed only by a human reading the heartbeat.

Fix: dispatch age now uses **birth** time (`stat -f %B`, macOS st_birthtime),
via a new `_lw_birth_epoch` helper that falls back to `%m` only where `%B` is
unavailable (GNU stat), with the degradation direction stated in a comment
(mtime fallback can only make a lane look fresher, never older).

Fixture proof (suite case `r2-1`): `touch` cannot set st_birthtime on macOS;
`SetFile -d` can — probed: after `SetFile -d $(date -v-40M ...)` on a fresh
dir, `stat -f "birth=%B mtime=%m"` reports `birth=now-2400 mtime=now`. The
case builds a run dir born 40 min ago, touched 1 s ago, worktree quiet 30 min
⇒ REPORTED. Under round 1's code that case is silent.

### 2 — the run-dir glob was `*-runs`, so a codex lane had no dispatch age [Critical]

Round 1 globbed `"${RUN_ROOT_PARENTS}"/*-runs/*"${lane}"*` — matched
`glm-runs`/`freepool-runs`, never a codex lane's state under
`~/.claude/plugins/data/codex-openai-codex/state/<LANE>-<hash>` (probe:
`TESTS-POLLUTE-REAL-JOURNAL-01-14806a70f0cacf75` exists there; that lane
alarmed 2 min after a healthy dispatch).

Fix is structural, as ordered: one `lane_dirs` helper is the single place
that knows the provider arms (glm-runs + freepool-runs under each run root,
plus the codex state root — overridable via `LEADV2_LANE_WATCH_CODEX_STATE`
for fixtures). Both signal consumers feed from it via `done < <(lane_dirs …)`;
adding an arm later is a one-line change.

### 3 — one signal was not enough [Critical]

A lane is now STALLED only when BOTH are quiet past `STALE_MIN`:
worktree output age (`_lw_newest_age_min`, unchanged) AND provider output age
(new `_lw_provider_output_age_min`). Alarm text carries both numbers:

```
LANE-STALL: <LANE> — worktree untouched 30m, provider output 30m; check and re-dispatch
```

Provider output deliberately is NOT the run dir's own mtime (defect 1's
exact measurement: a dir "touched one second ago" must not read as output).
It is the newest plain file directly inside a run dir, excluding dotfiles
(`.stream_state`, `.lockref` are the runner's own bookkeeping); a run dir
with no files has produced nothing since it was CREATED, so its birth time is
the honest fallback. No hang backstop exists — fresh provider output always
suppresses (suite case `r2-3`: worktree quiet 30 m + provider produced 1 m
ago ⇒ NOT reported).

### 4 — the retired idle-guard's one real job absorbed [Critical]

Round 1 dropped `leadv2-idle-guard-arm.sh` / `leadv2-idle-lead-guard.sh`
correctly (their liveness input, `leadv2-lane-liveness.sh --all`, measured
0/231 while a lane wrote — a constant predicate), but the guard also answered
"there is queued work and no live lane". That now lives in the watcher,
derived the same honest way: zero lanes with EITHER signal fresh, while the
project's `docs/tasks.yaml` has ≥1 row with status ∈ {queued,ready,pending}
(same predicate the old guard used) ⇒ `LANE-IDLE: no live lane, N task(s)
queued`. Reported once per queued-count (a 60 s poll loop must not spam),
re-reported when the count changes, cleared when a lane goes live or the
queue drains. No tasks file ⇒ silent (projects without a task store can
never trigger it).

## Acceptance map

| # | case | result |
|---|------|--------|
| 1 | run dir born 40 m, touched 1 s, worktree 30 m ⇒ REPORTED | suite `r2-1` PASS |
| 2 | codex lane dispatched 1 m ⇒ NOT reported | suite `4b` PASS |
| 3 | worktree 30 m, provider produced 1 m ago ⇒ NOT reported | suite `r2-3` PASS |
| 4 | both quiet 30 m ⇒ reported with both numbers | suite `r2-4` PASS |
| 5 | zero live + ≥1 open task ⇒ `LANE-IDLE` | suite `r2-5` PASS |
| 6 | zero live + zero open ⇒ silent | suite `r2-6` PASS |
| 7 | round-1's 13 cases still pass | PASS (19/0 total) |
| 8 | `%B`→`%m` in the dispatch-age helper ⇒ suite RED | RED 16/3 exit 1 (cases 4a, r2-1, r2-4 — exactly the birth-dependent ones), reverted byte-identical (sha256 match), GREEN 19/0 |

## Live probes (not fixtures)

- `--once liveprobe` with `LEADV2_LANE_WATCH_LANES="TESTS-POLLUTE-REAL-JOURNAL-01
  ONE-LANE-WATCH-01-R2"` against the real run roots, 2026-09-01 ~20:48:
  `LANE-BEAT: TESTS-POLLUTE-REAL-JOURNAL-01:999999m ONE-LANE-WATCH-01-R2:999999m`
  and NO stall — the lane round 1 false-alarmed on 2 min after dispatch stays
  quiet while its provider output is fresh.

## Known residual (documented, deliberately not "fixed")

A runner that keeps appending to its lane's journal after the worker died
keeps the provider-output signal fresh, so such a lane stays unreported by
the stall rule — the mission explicitly forbids a hang backstop that
overrides fresh provider output (an earlier iteration false-alarmed the
working lane it was meant to protect). The BEAT line still exposes the
worktree age every cycle, which is how the original 23-min lane was noticed
by a human.

## Negative-control note

`_lw_run_once` grew a second decision (LANE-IDLE) beside the stall decision;
its behavioural proofs are `r2-5`/`r2-6`/`r2-7` (fires once per count,
re-fires on change, silent when a lane is live or the queue is empty).
