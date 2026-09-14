# developer.full.md — dispatch-030d9ee4 / PLUGIN-MARK-FINISHED-NO-RELEASE-01

Full analysis, diff rationale, test output, and the required negative control live in the task's
own report at `docs/handoff/PLUGIN-MARK-FINISHED-NO-RELEASE-01/report.md` (per the mission's own
`## Report` instruction). Not duplicated here to avoid drift between two copies — read that file.

Summary of what changed (see report.md for full diff rationale + pasted command output):

1. `leadv2-active-registry.sh`'s `mark_finished` op: rc=4 (not-registered) is now checked before
   rc=8 (recovered-refusal); the actual release now sets `target["stale"] = True` after stamping
   terminal_status (reusing the existing `stale` skip-convention already honored by
   `check_writes_conflict` / `check_limits` / `register`'s admission loop — never removes the row,
   because `leadv2-lane-heartbeat.sh` reads terminal_status/terminal_evidence off it post-finish);
   rc=0 is now verified by re-reading `active.yaml` after the write, exiting 9 on a lost edit.
2. New suite `plugins/leadv2/scripts/tests/test-mark-finished-releases-writeset.sh`, registered via
   `# run-all-triggers: leadv2-active-registry.sh` — 4 cases (syntax, finish-releases-conflict,
   unregistered-id refused, read-only-dir write-failure refused), all green.
3. Negative control run against a scratch copy (never the tracked file): commenting out the
   `stale` assignment reproduces the original bug and Test 2 goes red (report.md has full output,
   including the `finish_rc=9` detail showing the post-write verify catches it before rc=0 is ever
   returned).
4. Ran `tests/run-all.sh --scope changed`: new suite passes; of the 9 other `NOT-KNOWN-RED`
   nested-suite failures surfaced in that concurrent sweep, 4 reproduce identically against a
   pre-fix baseline scratch copy of `leadv2-active-registry.sh` (pre-existing, unrelated — none
   reference `mark_finished`), and 5 pass both standalone-with-fix and at baseline (only flip red
   inside the concurrent sweep, consistent with documented concurrent-runner noise — two other
   lanes are live in this repo per `LEADV2_ACTIVE_OTHER_SESSIONS`). Detail table in report.md.
5. Falsification set: `bash -n` on both changed/new shell files — clean. No `.py` files changed
   (Python is embedded via heredoc in the `.sh`; exercised at runtime by the 4 live test cases).

Left alone: lane-cap resolution order, write-set conflict taxonomy, live
`~/.claude/leadv2-state/*/active.yaml`, the 4 pre-existing-red suites (out of scope).

Committed on branch `worktree-PLUGIN-MARK-FINISHED-NO-RELEASE-01` as instructed.

DELIVERABLE_COMPLETE
