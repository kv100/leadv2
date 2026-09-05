DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01 — the migration that removed EXTRA_SUITE_MAP dropped
16 script→suite mappings. Those suites exist on disk, are green, and CI never selects them.

MEASURED 2026-09-04 on main (do not re-derive; DO re-measure after your fix):
branch `worktree-DARK-SUITES-UNREACHABLE-BY-RUNNER-01` added 18 mappings to the old
`EXTRA_SUITE_MAP`. main replaced that mechanism with per-suite `# run-all-triggers:` headers
(`tests/run-all.sh`, `scan_suite_triggers()`). Of those 18: 1 survives as a header, 1 names a suite
that does not exist, and 16 name a REAL suite file carrying NO header for that stem:

  leadv2-lane-liveness.sh        -> tests/test-lane-liveness-authoritative.sh
  leadv2-lanes-snapshot.sh       -> tests/test-lane-liveness-lies.sh
  leadv2-active-registry.sh      -> tests/test-lane-liveness-lies.sh
  leadv2-lane-liveness.sh        -> tests/test-lane-liveness-sentinel.sh
  leadv2-dispatch-code.sh        -> tests/test-lane-registry-self-deadlock.sh
  leadv2-dispatch-ledger.sh      -> tests/test-dispatch-terminal-deregisters-lane.sh
  leadv2-dispatch-code.sh        -> tests/test-dispatch-ledger-partial-close.sh
  leadv2-dispatch-code.sh        -> tests/test-dispatch-ledger-task-id.sh
  leadv2-dispatch-ledger.sh      -> tests/test-dispatch-ledger-task-id.sh
  leadv2-dispatch-ledger.sh      -> tests/test-t-core-dispatch-ledger.sh
  leadv2-status-surface.sh       -> tests/test-status-surface-close-phase.sh
  leadv2-status-surface.sh       -> tests/test-status-surface-cwd.sh
  leadv2-state-path.sh           -> tests/test-status-surface-cwd.sh
  leadv2-status-surface.sh       -> tests/test-status-surface-handle-identity.sh
  leadv2-single-lead-beat.sh     -> tests/test-broad-status-relay-scope.sh
  leadv2-beat-owner.sh           -> tests/test-broad-status-relay-scope.sh
(all paths relative to plugins/leadv2/scripts/)

THE WORK.

1. Give each of those 16 suites a `# run-all-triggers:` header naming the stem(s) that must select
   it. A suite named twice above gets ONE header naming both stems.
2. This list is a SAMPLE, not the population. It comes from one branch that happened to be
   measured. Sweep every suite under the four suite directories and report how many carry NO
   header at all — a suite with no header is selected by nothing but its own filename, which is
   the same darkness one level down. Report the count and the names; FIX only the 16 above in this
   task unless a swept suite is trivially the same shape, and say which you fixed.
3. The one mapping naming a suite that does not exist (`test-lanes-snapshot.sh`) is not yours to
   create. Say so in the report and name what would have covered it.

ACCEPTANCE — selection is the whole point; a green suite CI never runs is worth nothing.

1. For at least THREE of the 16, prove CI selection end to end: touch the source script, run
   `tests/run-all.sh --scope changed`, and show the suite named in the selected set. Verbatim.
   Pick three that map to DIFFERENT source scripts, not three headers in one file.
2. NEGATIVE CONTROL, mandatory: delete the header you just added from ONE suite, re-run
   `--scope changed` for its stem, and show the suite is NO LONGER selected; restore it, show it
   selected again. Both outputs verbatim. A header that does nothing and a header that works are
   indistinguishable by silence — that class was caught four separate times on 2026-09-04.
3. Run the 16 suites. Report the count line verbatim. If any is RED, do NOT fix its content and do
   NOT add it to `tests/known-red-suites.txt` — report it as a finding with its failure line. The
   list may only shrink.

CONSTRAINTS. Shared plugin tree feeding three repositories; the founder authorised work in this
tree this session. Never `git add -A`. Do not push to origin. `tests/known-red-suites.txt` and
`tests/known-failures.txt` may only shrink. Do not restore `EXTRA_SUITE_MAP` — it was deleted
deliberately because it serialised every wave through one file; re-adding it is the defect this
task exists to close, not the fix.
