# BEAT-LOOP-ORPHANS-01 — fix round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BEAT-LOOP-ORPHANS-01`
LANE_WRITES: plugins/leadv2/hooks/lib/leadv2-hook-session-kind.sh,plugins/leadv2/hooks/leadv2-single-lead-beat.sh,plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh,plugins/leadv2/scripts/leadv2-lane-pulse-watch.sh,plugins/leadv2/scripts/leadv2-backlog-pump.sh,plugins/leadv2/scripts/leadv2-task-judge.sh,plugins/leadv2/scripts/leadv2-codex-session-runner.sh,plugins/leadv2/scripts/glm-coder.sh,plugins/leadv2/scripts/freepool-coder.sh,plugins/leadv2/scripts/kimi-coder.sh,plugins/leadv2/scripts/claude-subsession.sh,plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh,docs/handoff/BEAT-LOOP-ORPHANS-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `cc80a42` — the lead's
salvage commit of your round-1 work; the worker died at wall clock before committing). Run with
`LEADV2_SUITE_LOCK_DISABLE=1`. Budget your turns: commit after step 2 and again at the end.

## Review verdict on round 1 (reviewer opus, `review-findings.json`) — status=fail high=5
1. **`hooks/lib/leadv2-hook-session-kind.sh` rule 3** — `*/docs/handoff/*|*-runs/*` never matches a
   real worker transcript. Worker transcripts live at `~/.claude/projects/<munged-cwd>/<sid>.jsonl`
   exactly like a lead's. So every headless worker with no env pin falls through to `lead` — not
   `unknown` — and arms its loop. The mechanism as shipped does not stop the measured orphans.
2. **`test-beat-loop-orphans.sh` case E7** asserts `~/.claude/projects/-Users-x/abc.jsonl -> lead`,
   enshrining that misclassification as expected behaviour.
3. **`leadv2-task-judge.sh:214`, `leadv2-codex-session-runner.sh:439`** — headless `claude -p`
   spawners outside the four gated launchers set neither `LEADV2_WORKER_ARM` nor
   `LEADV2_SUBSESSION_ROLE`, so env-pin mechanisms 1–2 do not cover them.
4. **`leadv2-single-lead-beat-loop.sh:170`** — the owner-check call is unguarded while the lib is
   sourced conditionally; a missing lib → rc 127 kills the founder beat on iteration 1.
5. **No `report.md`** — none of the brief's proof exists (suite green, NC1/NC2 red, a real run with
   clean `pgrep -f single-lead-beat-loop`).

## Do
1. Make the classifier decide from the TRANSCRIPT'S OWN CONTENT when env pins are absent: read the
   first ~20 lines of the transcript jsonl — a headless `claude -p` session's first user message is
   the mission text (contains `LANE ROOT:` / `WORKTREE PIN:` / `LANE_WRITES:` / `LEADV2_LANE_OUTCOME`),
   and the munged-cwd directory name contains `-claude-worktrees-` for every lane worker. Either
   signal → `worker`. Neither signal AND no env pin → `unknown`, and `unknown` must NOT arm a loop
   (fail closed for loops, journal one line `session_kind=unknown reason=<why>`). Fix E7 to assert
   this. Delete rule 3 as written.
2. Census every `claude -p` spawn site in `plugins/leadv2` (`grep -rn "claude -p\|claude --print\|-p \"" plugins/leadv2/scripts plugins/leadv2/hooks`),
   paste the census in report.md, and export `LEADV2_SUBSESSION_ROLE=<role>` at each one that
   lacks it (task-judge, session-runner, any others found). Add a grep-gate case to the suite:
   zero unpinned spawn sites.
3. Guard the owner-check call like its siblings (`command -v … && …`), and add the case: lib
   absent → beat still runs, journals `owner_check=unavailable`.
4. Live proof, RUN and paste: dispatch a tiny fixture task on the freepool arm (or run
   `glm-coder.sh` against a throwaway worktree with a 1-line mission), wait for exit, then
   `pgrep -fl 'single-lead-beat-loop|lane-pulse-watch|backlog-pump' | grep worktrees` → empty.
   Paste the before/after counts.
5. Mutation negative controls, RUN and paste red: (a) make the classifier return `lead` for the
   `-claude-worktrees-` path → E7 red; (b) drop the `LEADV2_SUBSESSION_ROLE` export at one spawn
   site → grep-gate red. Revert both.
6. `report.md` with everything above; commit in the lane.
