# PLUGIN-PAPERCUTS-01 — report (2026-09-01)

Lane: worktree-PLUGIN-PAPERCUTS-01 (base: main @ 2192dab anchor).
Suite: `plugins/leadv2/scripts/tests/test-plugin-papercuts.sh` — 11 passed, 0 failed, rc=0.

## Defect 1 [Critical] — orphaned beat loops pulsing from fixture dirs

Fix: `plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh`

Three mechanisms, all on the real call path:

1. **INT/TERM handler only cleaned up, did not exit** — bash continues after a
   trapped handler returns, so `kill <loop>` left the loop beating. This is why
   "killing them did not reduce the count — they respawn." The handler now
   `exit 0`s (and clears the EXIT trap so cleanup runs once).
2. **Pidfile cleanup was unconditional `rm -f $PID_FILE`** — a late-exiting OLD
   loop deleted a NEWER loop's live claim, blinding the re-arm guard, so the
   next dispatch armed a second concurrent loop for the same root. The cleanup
   now removes the pidfile only if it still names the exiting pid.
3. **Reader-error fail-open was unbounded** — the H-2 rule (reader errors never
   stop the loop) let a loop whose heartbeat errors on every pass (torn-down
   fixture tree, merged lane worktree) beat blind until the 24h lifetime cap.

**Actual cause of the orphans (runtime-derived, not read from source):** the
loop outliving the run that started it — mechanisms 1+3. The 2026-08-31
`pgrep -fa` artifact in the brief shows the fixture-dir loops (repo-glm /
repo-codex / target) at 3h–22h old with ppid=1: nothing that short-lived run
left them behind deliberately; they survived because kill didn't stop them (1)
and blindness never ended (3). Mechanism 2 explains the multiplicity/respawn
observation. Suite-leaves-one-behind (a missing teardown guard) was NOT the
primary cause — P2b still adds the regression guard for it.

`UNKNOWN_MAX` (default 12 consecutive UNKNOWN passes ≈ 1h at 300s cadence)
now stops the loop; `LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX=0` restores the
unbounded pre-fix behaviour; the pre-existing suite's B8 case (5+ unknown
passes stay alive) remains green under the default.

Live probe 2026-09-01T00:25Z (post-fix worktree binaries not yet everywhere,
but no fixture-root loops remain):

```
$ pgrep -fl single-lead-beat-loop
38086 …/worktrees/ADOPTION-GUARANTEES-A-PASSABLE-GATE-01/plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh
56484 /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh
```

Both are live lanes in build phase (legitimate), zero fixture-root loops.

## Defect 2 [Critical] — codex arm pinned a tier the launcher rejects

Fix: `plugins/leadv2/config/leadv2-routing.yaml:74` (`tier: spark` →
`tier: volume`) + `_codex_tier_validate()` in `leadv2-dispatch-code.sh` called
at all three codex-tier export sites (legacy resolver, arbiter path, fallback
substitution). A launcher-rejected tier now fails LOUDLY at resolution time
(`route_tier_invalid` journal + stderr refusal, exit 1) instead of winning the
auction and dying at spawn, silently falling through to a costlier arm.

Correct current tier established from the launcher, not the brief: the
2026-08-31 probe in the brief — `unknown --tier: spark (expected
top|standard|volume)` — and the suite P3/P3b pair live today (spark refused,
volume resolves and dispatches rc=0). `volume` is the launcher's cheapest
valid tier for this cheap leg. CHEAP-ARMS-ARE-SWITCHED-OFF-01 did NOT land a
tier fix on our base (the anchor commit `fa8d516` predates and main still had
`tier: spark`), so this is not a duplicate.

Acceptance 4 (spawn failure → costlier arm must log as a FAILURE naming arm +
reason): the codex `spawn_failed` journal line now carries
`detail=<first launcher stderr line>`, e.g. the launcher's own
"unknown --tier" text — no longer indistinguishable from a deliberate choice
(suite P4).

## Defect 3 [Medium] — `--resume-lane` rejected absolute paths

Fix: `leadv2-dispatch-code.sh`, two sites: the env-pin candidate join (absolute
value used as-is instead of `<worktrees>/<abs>`) and `_resolve_pinned_placement`
(a path-shaped `--resume-lane` takes the same validation contract as
`--worktree`; the bare-ref refusal message now prints BOTH accepted shapes).
Bare-name form still works (P5 regression guard). Declared NEGATIVE CONTROL —
see below.

## Defect 4 [Medium] — `task-add.sh` printed success, wrote nothing

**Verdict: repo-local defect in the CONSUMING repo**
(`~/Projects/persona-engine/scripts/task-add.sh`), not in a plugin-side
library — the script talks to Supabase directly via curl and had no
persistence check. The plugin repo has no task-add code to fix.

Fix (in persona-engine, the only place it can live): the POST is verified by
reading back the fingerprint; on an unreachable/erroring Supabase with no
existing row it now exits non-zero with
`"work_items POST did not persist … NOTHING was written; refusing to print a
success line"` (persona-engine `scripts/task-add.sh:250`). Healthy write still
exits 0 with the row.

**Committed:** persona-engine `main` @ `7b8e2ac9a` (2026-09-01, this
session): single-file commit `git add scripts/task-add.sh` after re-diffing
against the working tree immediately before staging (44+/6−, only our fix,
attributed to PLUGIN-PAPERCUTS-01 in the message). The prior session had left
it uncommitted fearing collision with parallel sessions there; before
committing I verified the file was untouched for 12h and the diff contained
only this lane's fix. Suite P7/P7b grade the committed version.

The suite exercises a copy of the script inside the fixture tree with a stubbed
curl (dead network ⇒ rc≠0 + nothing-persisted error; healthy POST ⇒ rc=0 with
row) — P7/P7b.

## Suite (acceptance map)

`test-plugin-papercuts.sh` — hermetic (fixture git repos under mktemp, stub
heartbeat/beat/journal/GLM/codex/lane-worktree binaries, `LEADV2_PULSE_MODE=0`
+ `LEADV2_SINGLE_LEAD_BEAT=0` on every dispatch run; kills only pids the suite
recorded or read from fixture pidfiles; Bash 3.2-safe, every `${arr[@]}`
guarded under `set -u`):

- P1 — run arms a beat loop then exits ⇒ loop stops itself (acceptance 1)
- P2a — old loop exits without deleting a newer loop's pidfile claim; P2b —
  suite-scope run leaves no beat loop behind (acceptance 2)
- P3 — routing cell with launcher-rejected tier ⇒ loud resolution-time error,
  no fallthrough; P3b — valid tier resolves normally (acceptance 3)
- P4 — codex spawn failure journals arm + launcher reason, then falls back
  (acceptance 4)
- P5 — `--resume-lane <bare-name>` works (acceptance 5)
- P6 — `--resume-lane <abs-path>` works; P6b — unknown ref refuses rc=5 with
  the accepted-shapes message (acceptance 6)
- P7 — backlog add that cannot persist ⇒ rc≠0, never a success line; P7b —
  persisting write still rc=0 (acceptance 7)

## EXTRA_SUITE_MAP + selection proof

`tests/run-all.sh`: mapped
`leadv2-dispatch-code.sh`, `leadv2-single-lead-beat-loop.sh`,
`leadv2-routing.yaml`, `codex-task.sh` → `test-plugin-papercuts.sh`; also
repaired a bad-merge block in the stem scanner (unterminated `$(basename …)`
inside unbalanced quotes left the config-yaml / gitignore / allowlist branches
interleaved — rewritten as one if/elif chain, same documented behaviours, plus
`leadv2-routing.yaml` gets a synthetic stem like `freepool-arm.yaml`).
Selection proven with `--scope changed` (raw output appended below).

## Declared negative control: P6 (path-form `--resume-lane`)

Mutation inside the production body on the real call path
(`_resolve_pinned_placement` path-form branch in `leadv2-dispatch-code.sh`
neutered), suite RED, reverted (md5 `aff9fb15b26658c8144989ad9efd7d09`
verified byte-identical), suite GREEN:

```
RED:   [TEST] FAIL: P6: absolute path form refused; rc=5 err=[leadv2-dispatch-code]   accepted shapes: --resume-lane <bare-lane-ref> …
       test-plugin-papercuts: 10 passed, 1 failed
       RED_SUITE_RC=1
GREEN: test-plugin-papercuts: 11 passed, 0 failed
       GREEN_SUITE_RC=0
```

## Self-check (raw)

- `bash -n`: leadv2-dispatch-code.sh, leadv2-single-lead-beat-loop.sh,
  test-plugin-papercuts.sh, run-all.sh — all OK (no Python files changed).
- Changed-scope runner: see appended output. Known baseline reds
  (2026-08-28 memory, reproduced at parent commit then): foreign-failure
  fixture, LANE-PLACEMENT-01, C5-registered-arm-silent — not introduced here.

## Files changed (lane branch)

- plugins/leadv2/scripts/leadv2-dispatch-code.sh (defects 2+3)
- plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh (defect 1)
- plugins/leadv2/config/leadv2-routing.yaml (defect 2)
- tests/run-all.sh (EXTRA_SUITE_MAP + stem-scanner repair)
- plugins/leadv2/scripts/tests/test-plugin-papercuts.sh (new)
- docs/handoff/PLUGIN-PAPERCUTS-01/report.md (this file)

Outside the plugin: `~/Projects/persona-engine/scripts/task-add.sh` (defect 4,
uncommitted there — flagged above).

## Re-verification addendum (2026-09-01, final session — all raw outputs below are from THIS session)

The closing session re-derived every claim from scratch against the uncommitted lane tree, then
committed. Prior sessions' raw outputs were not on disk; the outputs below are the real ones.

- `bash -n` (all four changed shell files): OK — dispatch-code, beat-loop, test-plugin-papercuts,
  run-all. No Python files changed on the lane; `python3 -m py_compile` n/a.
- Suite green: `test-plugin-papercuts: 11 passed, 0 failed` / `SUITE_RC=0`; zero
  `/tmp/leadv2-plugin-papercuts-*` leftovers after the run.
- Declared negative control re-run end-to-end: production mutation
  `leadv2-dispatch-code.sh:857` (`== /*` → `== /MUTATION-NEVER` in `_resolve_pinned_placement`) —
  ```
  RED:   [TEST] FAIL: P6: absolute path form refused; rc=5 err=[leadv2-dispatch-code] accepted shapes: ...
         test-plugin-papercuts: 10 passed, 1 failed / SUITE_RC=1
  ```
  revert byte-exact (md5 `aff9fb15b26658c8144989ad9efd7d09` both before and after),
  ```
  GREEN: test-plugin-papercuts: 11 passed, 0 failed / SUITE_RC=0
  ```
- Selection proof, `--scope changed`: run-all.sh has no dry-run mode, so the proof ran the REAL
  selection code with only the executor stubbed (`bash "${suite}"` → `true`) from a probe copy at
  the same relative path. 24 suites selected; `test-plugin-papercuts.sh` among them, pulled in by
  the EXTRA_SUITE_MAP rows for all four changed production files (leadv2-dispatch-code.sh,
  leadv2-single-lead-beat-loop.sh, leadv2-routing.yaml via its synthetic stem, codex-task.sh)
  plus the changed-suite-selects-itself rule.
- Neighbour suites that grade the touched seams (raw rc / pass-fail):
  ```
  test-single-lead-beat-loop             rc=0   9/0
  test-lane-registry-outlives-dispatcher rc=0   10/0
  test-arm-admission                     rc=0   18/0
  test-effort-routing                    rc=0   9/0 (SUMMARY pass=9 fail=0)
  test-lane-pulse-watch                  rc=1   11/1
  test-arm-capability-honoured           rc=1   1/3
  test-lane-placement-pin                GREEN  27/0  (was 24/3 at base!)
  ```
  Baseline discrimination — each red was re-run in a temp worktree at HEAD (anchor, pre-fix):
  * `test-lane-pulse-watch` W8 derived-timeout mismatch (default=29100 glm=20300 max=29100
    pinned=777 vs expected 14700/20300/29100/777): IDENTICAL red at base ⇒ pre-existing.
  * `test-arm-capability-honoured` (router-exclusion green fails + mutation-anchor zero-match):
    IDENTICAL three FAILs at base ⇒ pre-existing; the anchor string exists exactly once in both
    base and lane copies of dispatch-code, so the suite's own matcher, not our diff, is the cause.
  * `test-lane-placement-pin`: RED at base (24/3: P-b dispatch exited 3, worker cwd mismatch,
    P-h(b) prompt pin missing) → **GREEN 27/0 on the lane** ⇒ our defect-3 fix REPAIRS this
    known baseline red (matches the 2026-08-28 pre-existing-red memory entry for
    LANE-PLACEMENT-01).
  `run-core-offline` (repo-wide, >10 min with its own documented baseline reds) was not re-run;
  every suite it would run that touches our seams is covered above.
