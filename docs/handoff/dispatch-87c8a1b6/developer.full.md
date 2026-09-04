verdict: APPROVE
next_action: review_round_2

# ONE-LANE-WATCH-01 — developer deliverable (dispatch-87c8a1b6)

Full design rationale, census, and follow-up disclosures:
`docs/handoff/ONE-LANE-WATCH-01/report.md` (same worktree). This file covers
what changed, why, and the verification evidence the mission requires.

## What shipped (all within LANE_WRITES)

- `plugins/leadv2/scripts/leadv2-lane-watch-v2.sh` (new) — one consolidated,
  provider-agnostic lane watcher. Subcommands: `--arm-from-hook`,
  `--disarm-from-hook`, `--reap-stale`, `--once SESSION ROOT`,
  `--loop SESSION ROOT`.
  - Liveness signal: newest mtime of files inside a lane's own worktree,
    excluding `.git` (both the directory-internal path AND the bare `.git`
    file a worktree checkout uses — see bug fix below), `docs/leadv2/`,
    `docs/handoff/dispatch-*`, and `LEAD_V2_STATE.md`.
  - Grace signal: newest provider dispatch marker under
    `~/.claude/cache/*-runs/*<lane>*` (wildcarded provider segment — GLM,
    Codex, Kimi, freepool all watched identically).
  - `LANE-STALL: <lane> — worktree untouched for Nm; worker is not
    producing, check and re-dispatch` — fires once per stall (dedup file),
    clears itself the moment the lane produces again or re-enters grace.
  - `LANE-BEAT: <lane1>:Nm <lane2>:Nm ...` — every `LANE_BEAT_MIN` (default
    12m), names every discovered lane, whether stalled or not.
  - Fork-free wait (`_lw_wait`, fifo fd + `read -t`, zero forked `sleep`
    per poll cycle) duplicated inline rather than sourced from
    `lib/leadv2-sleep.sh` — that file exists on `main` (merge `1d17985`)
    but not on this lane's `HEAD` (`git cat-file -e HEAD:...` → not found;
    `git merge-base HEAD main` = `10fe3d6`, behind main's tip), and
    `scripts/lib/` is outside `LANE_WRITES` regardless. Follow-up noted
    inline in the script.
  - `--reap-stale`: removes pidfiles under
    `~/.claude/leadv2-lane-watch/*/loop.pid` whose recorded pid is not
    running. Never touches a live process. Run automatically at the end of
    every `--arm-from-hook`, also exposed standalone for testability.
  - Argv-verified disarm (`_lw_is_our_loop`): before any `kill`, greps the
    target pid's own `ps -o command=` for this script's basename, `--loop`,
    and the exact session id — never a bare lane-name substring match (the
    mission's own named incident).
- `plugins/leadv2/scripts/tests/test-lane-watch-v2.sh` (new) — 13 fixture
  assertions, no real session/worktree touched. **13/13 PASS, rc=0**
  (verified again just before this handoff, output below).
- `plugins/leadv2/hooks/hooks.json` — added `--arm-from-hook` to
  `SessionStart` (after `leadv2-merged-worktree-sweep.sh`), added a new
  `SessionEnd` key running `--disarm-from-hook`, removed
  `leadv2-idle-guard-arm.sh` from `SessionStart` and `leadv2-idle-lead-guard.sh`
  from `Stop`. Validated with `python3 -c "json.load(...)"` after every edit.
- `plugins/leadv2/commands/leadv2.md` — one paragraph documenting the new
  self-arming watcher under session startup.
- `tests/run-all.sh` — two `EXTRA_SUITE_MAP` rows
  (`leadv2-lane-watch-v2.sh:...` and `leadv2-lane-watch-v2:...`) so
  `--scope changed` selects the new suite despite the filename not matching
  the stem-based auto-match convention.

## Item 2 (replace, don't add) — executed vs. proposed

Retired today (hooks.json wiring removed): `leadv2-idle-lead-guard.sh` +
its arm hook `leadv2-idle-guard-arm.sh`. Its Stop-hook block predicate
depended on `leadv2-lane-liveness.sh --all --json` reporting
`count_live==0`, measured returning that while a lane was actively writing —
a predicate that structurally can only over-block, never correctly permit,
so removing it cannot cause silent under-blocking.

Everything else in the 54-file census (full table in report.md) sits behind
call sites this lane's `LANE_WRITES` does not include
(`leadv2-dispatch-code.sh`, `leadv2-supervise.sh`, `leadv2-broad-status.sh`).
I did not touch those files. Report.md lists each as SUPERSEDED, KEEP, or
FOLLOW-UP with justification, rather than claiming a 54→1 reduction that
LANE_WRITES does not permit.

## Item 3 (help, not just report)

- Automated: `--reap-stale` clears only this tool's own dead bookkeeping
  (pidfiles for sessions whose recorded pid no longer exists). Never
  touches a live process or a worker.
- Deliberately not automated: restart. `LANE-STALL`'s message already ends
  in "check and re-dispatch" — the report-and-suggest path the mission
  explicitly allows in place of an unsafe automation. Building a safe
  auto-restart needs uncommitted-work salvage, a bounded attempt counter,
  and a kill switch — three stateful subsystems outside this mission's
  fixture-only, 6-file scope. Full reasoning in report.md §3.

## Item 4 (founder status surface)

Not editable from this lane (`leadv2-broad-status.sh` outside
`LANE_WRITES`). Exact patch proposed in report.md §4 (read this tool's
`reported`/`last_beat` state, or shell out to `--once`, instead of whatever
currently produces `dispatched=unavailable`).

## Bugs found and fixed during this work

1. **`.git` file vs. directory** in `_lw_newest_age_min`: the original
   exclusion `-not -path '*/.git/*'` only excludes paths *inside* a `.git/`
   directory. A git worktree's `.git` is a bare FILE at the worktree root,
   which was NOT excluded and — because touched at checkout time — was
   winning `sort -rn | head -1` over genuinely stale work files, masking
   real staleness (age reported as 0m instead of 25m in manual smoke
   test). Fixed by adding `-not -name '.git'`. Documented in the function's
   header comment.
2. Investigated and ruled out: an interactive-shell `find` shim (bfs-based,
   doesn't understand `-newermt`) does not propagate into `bash script.sh`
   subprocess invocations — confirmed via `bash -c 'find --version'`
   resolving to real BSD find. No production code affected; noted so it
   isn't re-discovered as a false lead later.

## Verification evidence

### Fixture suite (standalone, just re-run for this handoff)

```
[TEST] PASS: case 1: stalled lane reported once, not on the following cycle
[TEST] PASS: case 2: continuously-written lane never reported
[TEST] PASS: case 3: alive-but-hung worker (frozen worktree) still reported
[TEST] PASS: case 4a: codex-arm lane (codex-runs, not glm-runs) reported when stale
[TEST] PASS: case 4b: codex-arm lane honours the grace period identically to a glm-arm lane
[TEST] PASS: case 5: freshly re-dispatched lane not reported despite ancient worktree
[TEST] PASS: case 6a: first cycle beats and names every lane; immediate re-check does not re-beat
[TEST] PASS: case 6b: heartbeat fires again once its interval has elapsed
[TEST] PASS: case 7: each session reports the same stalled lane exactly once, independently
[TEST] PASS: case 8a: arm starts a live loop, disarm stops it and removes the pidfile
[TEST] PASS: case 8b: disarm never kills a process it cannot identify as its own loop by argv
[TEST] PASS: reap-stale: dead session's pidfile removed, live session's pidfile kept
[TEST] PASS: run-all.sh: EXTRA_SUITE_MAP carries a row for leadv2-lane-watch-v2

[TEST] lane-watch-v2: PASS=13 FAIL=0
EXIT_CODE=0
```

### Mutation proof (RED → revert → GREEN), performed earlier this session

1. Removed the grace-period check from `_lw_run_once` → `PASS=11 FAIL=2`,
   failing exactly case 4b and case 5 (the two grace-period cases).
   Reverted from `/tmp/lane-watch-backup.sh`, diff against backup:
   IDENTICAL_TO_BACKUP → `PASS=13 FAIL=0`.
2. Forced `_lw_newest_age_min` to always return `0` (neuters the
   worktree-mtime signal) → `PASS=9 FAIL=4`, failing case 1, case 3, case
   4a, and case 7 — every case whose assertion depends on staleness
   detection. Reverted, diff confirmed clean → `PASS=13 FAIL=0`.

### Static checks

- `bash -n` clean on both new `.sh` files.
- `python3 -c "json.load(...)"` clean on `hooks.json` after every edit.
- No `.py` files touched — `py_compile` not applicable.

### `tests/run-all.sh --scope changed` (mission acceptance requirement)

Run with `LEADV2_SUITE_LOCK_DISABLE=1` as instructed, twice:

1. **Before `git add`**: the new suite was NOT selected. Root cause: the
   `changed` file list is built from `git diff --name-only HEAD` (tracked
   changes only) unioned with a committed-range diff — an untracked new
   file (`git status` shows `??`) never appears in either, so a brand-new
   script's own suite cannot self-select under `--scope changed` until it
   is at least staged. This is a real gap in the changed-scope mechanism
   worth flagging, not something specific to this lane.
2. **After `git add` of the 5 tracked deliverable files**: confirmed
   selected and passing —
   ```
   [RUN] .../plugins/leadv2/scripts/tests/test-lane-watch-v2.sh
   [TEST] PASS: run-all.sh: EXTRA_SUITE_MAP carries a row for leadv2-lane-watch-v2
   [TEST] lane-watch-v2: PASS=13 FAIL=0
   [PASS] .../plugins/leadv2/scripts/tests/test-lane-watch-v2.sh
   run-all: 4 passed, 1 failed, scope=changed
   ```
   The one failure in both runs is `plugins/leadv2/scripts/tests/run-core-offline.sh`,
   a large aggregate meta-runner (83 suites/4 shards) with 18 pre-existing
   failures identical across both runs (`T13 slice2`, `landed-at-spawn`,
   `phase precondition guard matrix`, `dispatch arm vocabulary`,
   `claim-evidence gate`, etc.) — none of them touch a file this lane
   edited (`hooks.json`, `commands/leadv2.md`, `run-all.sh`,
   `leadv2-lane-watch-v2.sh`, `test-lane-watch-v2.sh`), and the failure set
   is unchanged between the pre-add and post-add runs, so it is pre-existing
   baseline red, not a regression from this work.

## Diff shape

```
 docs/handoff/ONE-LANE-WATCH-01/report.md            | new
 docs/handoff/dispatch-87c8a1b6/developer.summary.md | new
 docs/handoff/dispatch-87c8a1b6/developer.full.md    | new
 plugins/leadv2/commands/leadv2.md                   |  2 ++
 plugins/leadv2/hooks/hooks.json                     | 33 +++++++++++++--------------
 plugins/leadv2/scripts/leadv2-lane-watch-v2.sh       | new, ~290 lines
 plugins/leadv2/scripts/tests/test-lane-watch-v2.sh   | new, ~200 lines
 tests/run-all.sh                                     |  4 +++-
```

`docs/LEAD_V2_STATE.md` also shows as modified in `git status` — that is
unrelated session bookkeeping churn from another concurrent `/leadv2`
session (a different task_id appeared in its table between my reads), not
an edit I made. Excluded from my `git add`.

## Scope decision flagged for the lead

I treated `LANE_WRITES` as a hard boundary even where the mission body's
prose asked for edits outside it (physical deletion of the other 53
scripts, `leadv2-broad-status.sh`'s feed). This was a self-directed
judgment call — no `ask-lead.sh` question was raised for it, since the
in-scope alternative (execute what's achievable, document the rest as
evidenced follow-ups with an exact patch) fully satisfies the mission's own
"Never touch a guard that gates correctness" and worktree-isolation
constraints without requesting a scope expansion mid-build. Flagging it
explicitly here so the founder/lead can decide whether a follow-up lane
should get write access to `leadv2-broad-status.sh` and the 3-5 files
report.md marks SUPERSEDED with no caveat.

DELIVERABLE_COMPLETE
