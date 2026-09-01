# BEAT-LOOP-ORPHANS-01 — headless worker sessions arm beat loops that outlive them; 53 loops drove load to 244

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BEAT-LOOP-ORPHANS-01`
LANE_WRITES: plugins/leadv2/hooks/leadv2-single-lead-beat.sh,plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh,plugins/leadv2/hooks/leadv2-lane-watch-arm.sh,plugins/leadv2/scripts/leadv2-lane-watch-v2.sh,plugins/leadv2/scripts/leadv2-lane-pulse-watch.sh,plugins/leadv2/scripts/leadv2-backlog-pump.sh,plugins/leadv2/hooks/lib/leadv2-hook-session-kind.sh,plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh,tests/run-all.sh,docs/handoff/BEAT-LOOP-ORPHANS-01/
Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Measured 2026-09-01 21:50 local (lead, `ps -eo pid,ppid,etime,command`)
- 53 × `leadv2-single-lead-beat-loop.sh`, plus `leadv2-lane-pulse-watch.sh` and `leadv2-backlog-pump.sh`
  loops, all `ppid=1`, ages 9 min … 8 h 50 min, every one running from a path under
  `.claude/worktrees/<closed-lane>/plugins/leadv2/…` — i.e. armed by a headless worker session
  (`claude -p` from glm-coder / freepool / claude-subsession) whose plugin hooks fired SessionStart /
  UserPromptSubmit / Stop exactly like a lead's.
- Each loop forks `pulse-beat`, `broad-status`, `status-collector`, `lanes-snapshot`, `lane-liveness`,
  `inbox drain`, `lane-detail` every cadence: 37 + 13 + 12 + 10 + 8 + 7 + 6 + 6 children at one instant.
  Load average 244 / 179 / 115; a 22-case suite took 71 s and the review gate's falsifiability probe
  timed out at 60 s (RESUME-LANE-ACCEPTS-PATH-01 blocked on it).
- The lead killed 132 orphans by hand (`kill -9` on every loop whose command path contains
  `.claude/worktrees/`). New ones kept appearing every few minutes while workers ran.

## The rule this lane ships
**A loop belongs to the session that armed it and dies with it.** Two mechanisms, both required:
1. **Headless sessions never arm a loop.** One shared predicate, `hooks/lib/leadv2-hook-session-kind.sh`
   → `lead | worker | unknown`, derived from evidence the hook already has: the transcript path
   (worker sessions run under `docs/handoff/<task>/…` or a `*-runs/<id>` dir), `LEADV2_WORKER_ARM` /
   `LEADV2_SUBSESSION_ROLE` env exported by every launcher (add it to any launcher that lacks it —
   glm-coder, freepool-coder, kimi-coder, claude-subsession), and `CLAUDE_CODE_ENTRYPOINT`. Every
   arming hook (beat, lane-watch `--arm-from-hook`, pulse-watch, backlog-pump) calls it first and exits
   0 silently for `worker`. `unknown` arms (fail-open) but journals `loop_armed_by_unknown_session`.
2. **A loop exits when its owner is gone.** Each loop records the owner session id + the lead's
   claude pid at arm time (the hook has `$PPID`) and, every iteration, exits when that pid is dead OR
   the owner's transcript mtime is older than `LEADV2_LOOP_ORPHAN_MAX_MIN` (default 30). SessionEnd
   still disarms (argv-verified kill, as today) — this is the belt for when SessionEnd never fires.

## Suite `test-beat-loop-orphans.sh`
(a) hook invoked with worker evidence → no loop process, no pidfile; (b) lead evidence → armed;
(c) armed loop whose recorded owner pid is dead → exits within one iteration (use a 1-s cadence env);
(d) transcript-mtime rule fires. Mutation negative control, RUN and paste red: make the predicate
return `lead` unconditionally → (a) red; delete the owner-pid check → (c) red. Register in
`tests/run-all.sh`.

## Evidence for report.md
Suite green + both controls red + a real freepool run (short mission) after which
`pgrep -f single-lead-beat-loop` shows no loop from its worktree path.

## Do NOT
Change what the beat/pulse loops emit or their cadence; change the lane watcher's stall rules
(ONE-LANE-WATCH-01-R2 owns those); kill anything from a hook (SessionEnd's argv-verified kill stays).
