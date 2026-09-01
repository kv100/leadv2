# ONE-LANE-WATCH-01 round 2 — the merged watcher carries two bugs the lead already measured

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ONE-LANE-WATCH-01-R2`

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-watch-v2.sh,plugins/leadv2/scripts/tests/test-lane-watch-v2.sh,tests/run-all.sh,docs/handoff/ONE-LANE-WATCH-01/

Branch from current main (round 1 merged as `c49cc9f`). Run suites with
`LEADV2_SUITE_LOCK_DISABLE=1`.

Round 1 is good work and it is merged: 13/0, and a `if false` on the stall decision inside the
production body takes it to 9/4 exit 1, so the suite is not blind. What follows is not a rewrite —
it is two defects the lead hit on **real lanes this session** while running an equivalent watcher by
hand, both of which round 1 reproduces exactly.

## [Critical] 1 — the grace window uses mtime, so it never expires for a live provider

`_lw_dispatch_age_min` reads `stat -f %m` on the provider run directory. A running worker rewrites
that directory continuously, so `d_age` stays near zero and

```
if [ "$d_age" -lt "$GRACE_MIN" ]; then … continue
```

skips the stall check **forever** for exactly the lanes worth watching. Measured: a lane sat 23
minutes past `STALE_MIN` in complete silence, and was noticed only because a human was reading the
heartbeat — the precise failure this tool exists to prevent.

Dispatch age must come from **birth** time: `stat -f %B` on macOS (fall back to `%m` only where
`%B` is unavailable, and say so in a comment). Birth time is what "how long since this lane was
dispatched" actually means.

Test: a run directory created 40 minutes ago and touched one second ago, with a worktree untouched
for 30 minutes ⇒ the lane IS reported. Under round 1's code that case is silent.

## [Critical] 2 — the run-dir glob is `*-runs`, so a codex lane has no dispatch age at all

`for d in "${RUN_ROOT_PARENTS}"/*-runs/*"${lane}"*` matches `glm-runs` and `freepool-runs`. A codex
lane's state lives under `~/.claude/plugins/data/codex-openai-codex/state/`, which matches nothing,
so `best` stays `999999`: grace never applies and a codex lane is reported as stalled **seconds
after it is dispatched**. Measured on `TESTS-POLLUTE-REAL-JOURNAL-01`, which alarmed two minutes
after a healthy dispatch.

Fix it structurally, not by adding one more glob in one more place. One helper that every caller
uses, so adding an arm later is a one-line change:

```bash
lane_dirs() {
  local lane="$1"
  printf '%s\n' \
    "${HOME}"/.claude/cache/glm-runs/*"${lane}"* \
    "${HOME}"/.claude/cache/freepool-runs/*"${lane}"* \
    "${HOME}"/.claude/plugins/data/codex-openai-codex/state/*"${lane}"*
}
```

Consume it with `done < <(lane_dirs "$lane")`. The same helper feeds [Critical] 3.

## [Critical] 3 — one signal is not enough: alarm only when BOTH are quiet

Round 1 decides on worktree mtime alone. A worker that is reading and planning writes its provider
run directory while touching no worktree file — reporting that is a false alarm, and false alarms
are how a watcher gets ignored. Two signals, and the alarm fires only when both are quiet:

| signal | meaning |
|---|---|
| worktree untouched | producing no files |
| provider run dir untouched | producing nothing at all |
| alarm | BOTH quiet past `STALE_MIN` |

The lead's hand-run version does exactly this and its alarm text carries both numbers, which is
what makes it actionable:

```
LANE-STALL: GUARDS-MUST-PROVE-THEY-FIRE-01 — worktree untouched 20m, provider output 24m; check and re-dispatch
```

Keep that shape. Do not add a "hang backstop" that overrides fresh provider output — an earlier
iteration had one and it re-introduced the false alarm it was meant to fix.

## [Critical] 4 — the removed idle-guard's one real job must not vanish

Round 1's hooks.json drops `leadv2-idle-guard-arm.sh` and `leadv2-idle-lead-guard.sh`. That is
right: `GUARDS-MUST-PROVE-THEY-FIRE-01` measured their liveness input (`leadv2-lane-liveness.sh
--all`) reporting **0 alive out of 231 rows** while a lane was actively writing, so the predicate
was a constant.

But the idle guard answered a question this watcher does not: *there is queued work and no live
lane*. Standing founder rule — never end a turn with zero lanes. Absorb it here, derived the same
honest way the stall check is: zero lanes with a live worktree or live provider dir, while
`docs/tasks.yaml` has at least one open row ⇒ emit `LANE-IDLE: no live lane, N task(s) queued`.
Derive "live" from the same two signals, never from `lane-liveness --all`.

## Acceptance

1. run dir born 40m ago, touched 1s ago, worktree quiet 30m ⇒ REPORTED (kills [Critical] 1);
2. codex lane dispatched 1m ago ⇒ NOT reported (kills [Critical] 2);
3. worktree quiet 30m, provider dir touched 1m ago ⇒ NOT reported (kills [Critical] 3);
4. both quiet 30m ⇒ reported, with both numbers in the text;
5. zero live lanes + ≥1 open task ⇒ `LANE-IDLE` emitted (kills [Critical] 4);
6. zero live lanes + zero open tasks ⇒ silent;
7. round 1's 13 cases still pass;
8. mutating `%B` back to `%m` in the dispatch-age helper ⇒ the suite goes RED.

## Rules

- Mutation INSIDE the production body on the real call path; RED, revert, GREEN, clean
  `git diff --stat`.
- Measure a suite's exit code WITHOUT a pipeline: `cmd > log 2>&1; echo $?`.
- No `grep` against script source as an assertion; a printed `FAIL:` that leaves `$?` at 0 is not
  an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop, even if partial.
- Do not reorder hook arrays in `.claude/settings.json`, and do not touch
  `scheduled-decisions-inject.sh`.

## Done means

The one instrument the founder asked for — armed by the plugin, not by a session — reports a dead
worker within `STALE_MIN` on **any** arm, stays quiet for a working one, and says so out loud when
there is queued work and nothing running.
