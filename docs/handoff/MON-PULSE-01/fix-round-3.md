# MON-PULSE-01 fix-round 3 — FINAL, judge-bounded: exactly 2 blockers (Heavy)

FIRST STEP, mandatory: in your lane worktree run `git merge worktree-60ec85a4`
(carries build + fix-rounds 1-2). Fix ONLY the two issues below — the judge explicitly
bounded scope; anything else goes untouched.

Judge verdict (REVISE, 0.82, final round):

1. H-1 — plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh lines ~1215,1228,
   1232,1263,1296: `kill $LOOP_PID` targets the wrapper subshell, not the pidfile-owning
   grandchild loop. Suite is FLAKY (judge reproduced RED 2 of 3 runs on B5/B6) and leaves
   orphan beat loops on the host. Fix: kill the pid stored in $PID_FILE (or background
   `bash "$LOOP"` directly so $! IS the loop), and make `wait_gone` FATAL (no `|| true`).
   Proof required in report: run the suite 3 times in a row, all green, raw tails of all
   three runs; then `pgrep -f leadv2-single-lead-beat-loop` empty after the suite.

2. H-2 — plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh ~:491-506,545: a
   registry-read failure (leadv2-lane-heartbeat.sh emits an error OBJECT parsed as
   UNKNOWN) counts toward UNKNOWN_MAX=3 and permanently stops the beat with no re-arm —
   silent founder blindness, the exact failure this task exists to kill. Fix:
   reader-error => keep beating and do NOT count toward UNKNOWN_MAX (only a genuine
   "registry readable and zero live lanes" may stop the loop). Add a test: 5 consecutive
   reader errors -> loop still alive and still beating; RUN its negative control red
   (revert to counting errors -> test fails).

bash -n touched scripts. Do NOT touch other findings (they are backlogged).
Commit: fix(leadv2): MON-PULSE-01 fix-round 3 — judge blockers H-1 (suite kills real loop pid) + H-2 (reader errors never stop the beat).
Report: docs/handoff/MON-PULSE-01/fix-round-3-report.md (max 200 words, raw tails of 3x suite runs), end DELIVERABLE_COMPLETE.
