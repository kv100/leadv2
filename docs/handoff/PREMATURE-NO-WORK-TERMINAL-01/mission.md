# PREMATURE-NO-WORK-TERMINAL-01 — terminal rows written while the worker is still alive

Repo: ~/Projects/leadv2 (canonical plugin). CRITICAL dispatch-pipeline bug, live evidence 2026-08-03 in persona-engine:
- 08:42:49Z the ledger got `{"task_sig":"0814b8c0","task_id":"FEED-SCAN-USABLE-CANDIDATES-01","terminal":"no_work","cause":"empty_diff"}` — yet the codex worker (codex-companion job task-mscze7da-7gcurn, cwd .claude/worktrees/0814b8c0) was STILL RUNNING 1h42m later and its worktree held a 94-line diff in agent/pre-actions/scan-feed.sh.
- docs/handoff/dispatch-0814b8c0/review-gate.md shows `status: blocked / reason: no_work` with an EMPTY review.diff — the gate measured the diff before the worker wrote anything.
- Same shape earlier same day: 966f2d52, 526b905e, d7cf9e71 all `no_work/empty_diff`; d7cf9e71 and 0814b8c0 are the SAME task_id → the false terminal caused a re-dispatch and a duplicate concurrent worker on one task. This reproduces the audited supervisor-era "empty dispatch" disease from inside the close watcher.

FIND the writer: the close/watch path that emits terminal rows (leadv2-dispatch-product-close.sh and/or the review/e2e gate steps it calls in .claude/scripts/ and plugins/leadv2/scripts/ — trace which file actually wrote cause=empty_diff).

REQUIREMENTS:
1. A terminal `no_work`/`empty_diff` row may be written ONLY when the worker is provably finished: provider-status/job-registry says done AND the launch handle's process (codex-companion job / glm child / kimi child) is gone. While alive → no terminal, keep watching (bounded by the existing worker timeout, then `dead/timeout` terminal is fine).
2. Re-measure the in-scope diff AT worker exit (not at watcher wake-up) before classifying empty_diff.
3. Duplicate-dispatch guard already refuses same task-sig; verify the false-terminal path was what allowed the re-dispatch of the same task_id and that requirement 1 closes it (state why in the report).
4. Tests: extend the relevant test suite with a stubbed slow worker: watcher wakes while stub alive → NO terminal row; stub writes diff then exits → terminal reflects the real diff (not empty); stub exits with genuinely empty diff → empty_diff terminal allowed.

ACCEPTANCE: bash -n touched files; run the touched suites + plugins/leadv2/scripts/tests/run-core-offline.sh (NOTE: 8 suites fail on PRISTINE main — pre-existing drift, thread CORE-OFFLINE-8-FAILS-ON-MAIN-01 — only compare against baseline, do not chase them). Report: writer file:line, per-requirement status, test summary. Do NOT commit.

NON-GOALS: no admission-guard/kimi changes, no SwiftBar changes, no supervisor-loop changes.
Rollback: git checkout of touched files.
