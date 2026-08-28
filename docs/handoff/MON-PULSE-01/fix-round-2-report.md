# MON-PULSE-01 fix-round 2 — H1..H4 + M3

Branch: `worktree-60ec85a4` (on top of merge of `worktree-21a4f402` @ 817699b).

## Fixes
- **H1** `leadv2-lane-pulse-watch.sh`: default timeout now DERIVED from the
  dispatcher's worker-timeout envs (`GLM/FREEPOOL/KIMI/CODEX_TIMEOUT`, the
  values the coder launchers honor): `4 x max + 300s` grace, floor 3600 →
  default 14700s > measured p100 13415s (12/107 = 11% historical lanes
  exceeded the old 3900s constant). On timeout the watcher writes a final
  `watch_timeout` pulse — never silent death. `--print-timeout` seam locks
  the derivation (W8).
- **H2** W4 rebuilt: both halves run with `LEADV2_LANE_PULSE_BIN` pointed at
  the REAL writer; W4a proves the baseline (unpatched scratch copy DELIVERS),
  W4b proves the flip (patched copy misses). No vacuous pass possible.
- **H3** beat-loop pidfile keyed by project root (`cksum` of the absolute
  path) in the shared state root — each worktree gets its own loop + beat.
  Smaller change than one-loop-scans-all: the lane scan was already per-root
  (`LEADV2_PROJECT_ROOT` passed to the heartbeat bin); only the pidfile name
  was repo-global. Locked by B7 (two roots, one shared pid dir, both loops
  armed, 2 pidfiles).
- **H4** `leadv2-broad-status.sh` now reads each board lane's LAST
  `tasks/<id>/pulse.md` line and renders it verbatim in founder-status.md
  ("Пульс линий" section, capped 6). Locked by the new end-to-end suite
  `test-lane-pulse-founder.sh`: fake journal → REAL watcher → REAL
  `leadv2-pulse-beat.sh --now` → REAL composer → founder-status.md contains
  the dispatch_terminal lane line (F1); no pulse.md → no empty section (F2).
- **M3** grepped the emitters: bare `worker_died` is journaled NOWHERE; the
  only string is `cause=worker_died` inside a `dispatch_terminal` row
  (`leadv2-dispatch-ledger.sh:1009`). EXIT_PAT dropped the dead token; such
  rows pulse under kind `worker_died` (W9).

## Falsification (raw tails)
```
$ bash -n <all 6 touched .sh>          → ALL-SYNTAX-OK
$ test-lane-pulse-watch.sh             → 12 passed, 0 failed
$ test-single-lead-beat-loop.sh        → 8 passed, 0 failed
$ test-lane-pulse-founder.sh           → 2 passed, 0 failed
$ tests/run-all.sh --scope changed     → 6 passed, 1 failed
  Failures (blocking): run-core-offline.sh
  → pre-existing baseline red (LANE-PLACEMENT P-g/P-h/P-i; memory
    run-all-changed-preexisting-reds; lane placement untouched by this diff)
```
Dev-red observed and fixed: W8 initially expected sub-floor env values
(4300/8300) — derivation maxes with a 3600 floor, so the assertions were
wrong, not the code; corrected to 20300/29100. Negative controls W4b/W6 run
RED-by-design inside the green suites (see suite output above).
