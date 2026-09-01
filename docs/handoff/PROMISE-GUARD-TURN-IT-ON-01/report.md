# PROMISE-GUARD-TURN-IT-ON-01 — round 3

## Round 3 evidence

### Root cause
`test-promise-guard-classified-block.sh` cases 2 and 6 asserted a SILENT verdict on
"hook printed nothing" alone, with no check that the hook actually ran. Under the
review gate's PATH-shimmed jq/grep/python3 probe, `_run_hook`'s own transcript build
failed, printed nothing, and both cases misread that as a real SILENT verdict — a
false-negative gate indistinguishable between "correctly silent" and "broken."

### Fix (commit af18aaa)
- `_run_hook` now captures the hook's real exit code and returns a distinct
  could-not-run sentinel (rc=2), treated as hard FAIL everywhere — never a skip.
- Added the missing `bash -n` guard on the hook itself (present in sibling suites,
  absent here).
- Added a `_journal_lines` helper returning `-1` (never a valid count) instead of
  silently reading `0` when the journal file or `wc`/`python3` is broken.
- `plugins/leadv2/hooks/leadv2-promise-guard.sh` itself is untouched:
  `git diff HEAD~1..HEAD -- plugins/leadv2/hooks/leadv2-promise-guard.sh` is empty.

### Note on `leadv2-suite-falsifiable.sh`
`plugins/leadv2/scripts/leadv2-suite-falsifiable.sh` does not exist in this repo
(confirmed via `find` and `grep -r FALSIFIABLE`). There is no separate falsifiability
runner — falsifiability is built inline into each suite as red-then-green /
mutation-control cases. Ran the suites directly instead; verdicts below.

### Suite runs, foreground, HEAD=af18aaa

```
$ bash plugins/leadv2/scripts/tests/test-promise-action-binding.sh
exit=0
Results: 2 passed(red->green), 0 failed, 8 green-pre-fix, 0 could-not-run

$ bash plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh
exit=0
Results: 12 passed(red->green), 0 failed, 29 green-pre-fix, 0 could-not-run

$ bash plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh
exit=0
classified-block: 8 passed, 0 failed
```

Each `pre_rc=1 -> post_rc=0` line is the mutation control per case (fails against an
injected pre-fix mutation, passes against the real hook). All three suites'
`sandbox-control`/`control:` lines confirm the real journal
(`~/.claude/leadv2-promise-guard.jsonl`, 1968 lines) was untouched by the test runs.

### Mutation negative control
Hook temporarily forced to always return `verdict=suppressed_action` (never block) →
`test-promise-guard-classified-block.sh` went red (non-zero, FIRED-expecting cases
failed). Hook change reverted; `git diff HEAD~1..HEAD -- plugins/leadv2/hooks/leadv2-promise-guard.sh`
confirmed empty post-revert.

### Tree state
`git status` post-fix shows only lead/orchestrator-owned files dirty (LEAD_V2_STATE.md,
docs/handoff/dispatch-*/phases.d/*.yaml, scheduled-decisions.md, task journals) —
none touched by af18aaa, all outside this task's LANE_WRITES scope.

Final commit: `af18aaa456c2dbebee9343b6c52e74773691c8ef`.

DELIVERABLE_COMPLETE
