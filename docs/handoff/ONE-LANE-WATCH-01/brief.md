# ONE-LANE-WATCH-01 — one working instrument, armed automatically, replacing the 54-file zoo

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ONE-LANE-WATCH-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-watch-v2.sh,plugins/leadv2/scripts/tests/test-lane-watch-v2.sh,plugins/leadv2/hooks/hooks.json,plugins/leadv2/commands/leadv2.md,tests/run-all.sh,docs/handoff/ONE-LANE-WATCH-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## The founder's ask, in his words

> "есть же вот эти все мониторы, гарды, смотрители, сторожи, пульсы, биты, хертбиты, broad status
> и тд, но мне надо реально ОДИН и рабочий инструмент. вот то что ты делаешь сейчас — это наконец-то
> работает. было бы найс чтобы на уровне плагина так было: я запустил сессию, и стартует вот такая
> штука после начала работы, она говорит мне что в работе, помогает тому что застряет, ловит баги и
> сразу стартует."

Counted on this tree, 2026-09-01: **54 files** under `plugins/leadv2/{scripts,hooks}` match
`pulse|beat|watch|idle|status|guard|monitor` — including eleven separate `leadv2-status-*` scripts,
three beat scripts, and three lane watchers. The founder still had to ask "ну что там?" by hand all
day. **This lane is not allowed to make that 55.**

## What already works, and must be preserved — the lead's session watchdog

The lead built a watchdog in this session that caught four real failures the shipped guards missed.
It is a scratchpad script running as a session Monitor, so it dies with the session and exists in no
repo. Its logic is the starting point; the four failures are the acceptance cases:

| Version | What it could not see | How it was caught |
|---|---|---|
| v1 | a worker died while sibling lanes were healthy | `SUITE-LOCK-ORPHAN-FD-04` silent 45m |
| v1 | a process alive but hung, producing nothing | `PLUGIN-PAPERCUTS-01` silent 40m, its own runner logged `STDOUT_IDLE idle_s=1200 ... observation only` and did nothing |
| v1 | **every codex lane** — it watched `~/.claude/cache/glm-runs` only | three lanes idle 49m / 93m / 153m, reported as healthy |
| v2 | a lane re-dispatched a minute ago, whose worktree is still old | false alarm on `GUARDS-MUST-PROVE-THEY-FIRE-01` |

The v3 shape that survives all four:

- liveness = **mtime of files inside the lane's own worktree**, excluding lead-written bookkeeping
  (`docs/leadv2/`, `docs/handoff/dispatch-*`, `LEAD_V2_STATE.md`, `.git/`). Every provider must touch
  the worktree to do work, so this is arm-agnostic by construction;
- a stall threshold (20m), a post-dispatch grace period (15m, derived from the provider run dir),
  and a heartbeat (12m) that names every lane and its idle age — so silence is provably "still
  working", never "the lead stopped looking";
- report each lane at most once per stall, so one dead lane cannot flood the session.

## [Critical] 1 — it must arm itself when a session starts

The founder must not have to remember it. Arm it from the session-start path so that a `/leadv2`
session begins watching automatically, and say in `report.md` which hook or command does the arming
and what happens when two sessions in different repos are open at once (it must not double-report).

It must also be **cheap**: it runs for the life of a session, so a poll cycle must not become the
fork pressure that `FORK-STORM-KILLS-HOOKS-01` just removed. Use the merged fork-free wait
(`lib/leadv2-sleep.sh`); state the per-cycle cost in `report.md`.

## [Critical] 2 — replace, do not add

Census the 54 and produce, in `report.md`, a table: file → what it reports → superseded by this
tool / kept and why. Then **delete or retire** the ones this tool subsumes, in this lane. A
consolidation that leaves all 54 in place has failed the entire point of the task.

`leadv2-idle-lead-guard.sh` is the first candidate and the clearest case: it consults
`lane-liveness.sh --all`, which was measured today returning **231 rows, 0 alive** while a lane was
actively writing, with codex lanes absent from the output entirely. Its predicate is a constant, so
it can never fire correctly. Either it is rebuilt on this tool's signal or it is retired — say which.

Do not touch a guard that gates correctness (edit guards, phase guards, safety guards). This lane
consolidates **observability**, not enforcement.

## [Critical] 3 — it must help, not only report

The founder asked for three verbs: *tells me what is in work, helps what is stuck, catches bugs and
restarts*. Reporting is done. For the other two, decide from the runtime and justify in `report.md`:

- **stuck**: when a lane is stalled past the threshold, what can be done automatically and safely?
  A stale watcher blocking `lane_is_live` can be reaped — that exact blocker cost three dispatches
  today. A half-finished worker must NOT be killed silently.
- **restart**: an automatic re-dispatch is powerful and dangerous. If you propose it, it must be
  bounded (max attempts per lane), must never re-dispatch a lane with uncommitted work without
  salvaging first, and must be one flag away from off. If the runtime says it cannot be made safe,
  say so and deliver report-and-suggest instead. **Do not ship an unbounded auto-restart.**

## [Medium] 4 — one line the founder can read

The heartbeat is for the lead. The founder reads a table (see his standing format: line / what it
fixes / who / state / ETA). Whatever surface he already has — `leadv2-broad-status.sh` is the
incumbent — must be fed from THIS tool's signal rather than its own, so the status he reads and the
alarm the lead gets can never disagree. Today they did: broad-status said `dispatched=unavailable`
while four lanes were running.


### A fifth bug, found after this brief was written — inherit the fix, not the bug

The grace period first used the run directory's **mtime**. A live worker refreshes that directory
continuously, so the grace window never expired and **the stall alarm could not fire for any live
lane** — `GUARDS-MUST-PROVE-THEY-FIRE-01` sat 23 minutes past the threshold in complete silence and
was noticed only because a human was reading the heartbeat. Grace must use **birth time**
(`stat -f %B` on macOS), never mtime.

The same measurement produced an improvement. A worker can be writing its provider run directory
while touching no file in the worktree — it is reading and planning, which is not a stall. So the
tool needs TWO signals and reports only when both are quiet, with a hang backstop so an
eternally-"thinking" worker is still caught:

| signal | meaning |
|---|---|
| worktree untouched | producing no files |
| provider run dir untouched | producing nothing at all |
| alarm | both quiet, OR worktree dead past `HANG_MIN` |

Verified both ways on real lanes: four live lanes ⇒ silent; two parked dead lanes ⇒ reported, with
both numbers in the text (`worktree untouched 47m, provider output 999999m`).

Acceptance case 9: a lane writing its provider run dir but not its worktree ⇒ NOT reported before
`HANG_MIN`, reported after.

## Acceptance

Fixture-based, never a real session, never a real worktree:

1. a lane whose fixture worktree stops changing past the threshold ⇒ reported once, not repeatedly;
2. a lane whose fixture worktree is changing ⇒ never reported (the false-alarm guard);
3. a lane whose worker process is alive but whose worktree is frozen ⇒ still reported (the hang case
   v1 missed);
4. a lane on a non-GLM arm ⇒ watched identically (the codex blindness that made three lanes
   invisible);
5. a lane dispatched within the grace period ⇒ not reported, whatever its worktree age;
6. the heartbeat fires on schedule and names every active lane with its idle age;
7. two concurrent sessions ⇒ each watches its own lanes without duplicate reports;
8. arming happens automatically on session start, and disarming on session end leaves no orphan
   process (regression guard against the leak class just fixed).

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Removing the grace-period check must turn case 5 red; removing the
  worktree-mtime signal must turn case 4 red.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- Measure a suite's exit code WITHOUT a pipeline: `cmd > log 2>&1; echo $?`. Reading `$?` after
  `cmd | tail` measures `tail` — the lead got a false "exit 0" that way today.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Never kill a process outside the fixture tree. A watcher's owner must be identifiable from its
  own argv before anything sweeps it — the lead killed his own watchdog today because his filter
  matched the lane name inside its command line.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

The founder starts a session in any of the three repos, and without doing anything he gets: a
periodic line saying what is in work and how long each lane has been quiet, an alarm the moment a
lane stops producing on any arm, and an automatic unblock of the stale-watcher class. The count of
observability scripts goes DOWN, and the number he has to trust goes to one.

## Reference implementation — the session watchdog, verbatim

This is the v3 script that caught all four failures above. It is a scratchpad file in the lead's
session and will vanish with it; that is the whole reason this lane exists. Treat it as a starting
point and a behavioural spec, not as code to paste unchanged — it has no suite, no arming, and no
multi-session handling, which are exactly what this lane must add.

```bash
#!/bin/bash
# Per-lane stall watchdog, v2 — provider-agnostic.
#
# v1 watched ~/.claude/cache/glm-runs only. Three of the four live lanes were on
# Codex, so v1 could not see them at all and stayed silent for 30 minutes while
# they sat idle. This version watches the ONE thing every provider must touch to
# be doing work: files inside the lane's own worktree.
#
# Noise paths are excluded because the session's own bookkeeping (journals,
# active registry, dispatch phase dirs) is written by the LEAD, not the worker,
# and would make a dead lane look alive.
set -u

WORKTREES="${HOME}/Projects/leadv2/.claude/worktrees"
STALE_MIN="${LANE_STALL_MIN:-20}"
BEAT_MIN="${LANE_BEAT_MIN:-12}"
ACTIVE_LANES="${ACTIVE_LANES:-}"
GRACE_MIN="${LANE_GRACE_MIN:-15}"
HANG_MIN="${LANE_HANG_MIN:-45}"
reported=""
last_beat=0

# Minutes since this lane was last DISPATCHED, derived from its provider run
# directory. A freshly re-dispatched lane has an old worktree until its worker
# writes the first file, and reporting that as a stall is a false alarm -- it
# fired on GUARDS-MUST-PROVE-THEY-FIRE-01 sixty seconds after dispatch.
dispatch_age_min() {
  local lane="$1" newest m best=999999
  for d in "${HOME}"/.claude/cache/glm-runs/*"${lane}"* "${HOME}"/.claude/cache/freepool-runs/*"${lane}"*; do
    [ -e "$d" ] || continue
    m=$(stat -f %B "$d" 2>/dev/null) || continue   # %B = birth; %m is refreshed by the live worker
    newest=$(( ( $(date +%s) - m ) / 60 ))
    [ "$newest" -lt "$best" ] && best=$newest
  done
  printf '%s' "$best"
}

# Minutes since the lane's provider run directory was last WRITTEN. A worker that is
# reading and planning produces output here while touching no worktree file.
output_age_min() {
  local lane="$1" m best=999999 age
  for d in "${HOME}"/.claude/cache/glm-runs/*"${lane}"* "${HOME}"/.claude/cache/freepool-runs/*"${lane}"*; do
    [ -e "$d" ] || continue
    m=$(stat -f %m "$d" 2>/dev/null) || continue
    age=$(( ( $(date +%s) - m ) / 60 ))
    [ "$age" -lt "$best" ] && best=$age
  done
  printf '%s' "$best"
}

newest_age_min() {   # $1 = worktree path -> minutes since the newest worker-written file
  local w="$1" newest
  newest=$(find "$w" -type f \
      -not -path '*/.git/*' \
      -not -path '*/docs/leadv2/*' \
      -not -path '*/docs/handoff/dispatch-*' \
      -not -name 'LEAD_V2_STATE.md' \
      -newermt '-600 minutes' -print0 2>/dev/null \
    | xargs -0 stat -f '%m' 2>/dev/null | sort -rn | head -1)
  [ -n "$newest" ] || { printf '999'; return 0; }
  printf '%s' $(( ( $(date +%s) - newest ) / 60 ))
}

while true; do
  now=$(date +%s)
  live_report=""
  for lane in ${ACTIVE_LANES}; do
    w="${WORKTREES}/${lane}"
    [ -d "$w" ] || continue
    age=$(newest_age_min "$w")
    live_report="${live_report}${lane}:${age}m "
    # Grace: a lane dispatched within GRACE_MIN has not had time to write yet.
    d_age=$(dispatch_age_min "$lane")
    if [ "$d_age" -lt "${GRACE_MIN}" ]; then continue; fi
    case " $reported " in *" $lane "*) continue;; esac
    o_age=$(output_age_min "$lane")
    if [ "$age" -ge "$STALE_MIN" ] && { [ "$o_age" -ge "$STALE_MIN" ] || [ "$age" -ge "$HANG_MIN" ]; }; then
      echo "LANE-STALL: ${lane} — worktree untouched ${age}m, provider output ${o_age}m; check and re-dispatch"
      reported="${reported} ${lane}"
    fi
  done

  # Heartbeat: silence must never mean "the lead stopped looking". One line every
  # BEAT_MIN minutes naming each lane's idle age, so a quiet session is provably
  # a working session.
  if [ $(( now - last_beat )) -ge $(( BEAT_MIN * 60 )) ]; then
    echo "LANE-BEAT: ${live_report:-no active lanes}"
    last_beat=$now
  fi
  sleep 60
done
```
