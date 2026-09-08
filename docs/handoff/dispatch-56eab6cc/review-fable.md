LABEL=critic-dispatch-56eab6cc-review-1788897664 SESSION_ID=17af9b86-0578-4a73-8223-f21d57c7f111
--- body from: docs/handoff/dispatch-56eab6cc-review/critic.full.md ---
REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=2 medium=1 low=3

# Critic review — dispatch-56eab6cc (lane B2-GATE-BUDGET-3), diff `docs/handoff/dispatch-56eab6cc/review.diff`

Scope: the 118-line diff only (`tests/known-red-suites.txt`, `tests/run-all.sh`), cross-checked
against the live tree at 62da3911 and the tests it names. No files modified.

## Findings

### High 1 — the review artifact is stale main history, not the lane's work (`review.diff` whole file)
- `review.diff.repos` names lane **B2-GATE-BUDGET-3**, whose mission is "two suites eat 64% of the
  close gate budget" (known-red budget carve-out). Nothing in the diff addresses that mission.
- Every hunk is already on `main` and was authored by other lanes: scope forwarding = `74630f8a`,
  EXTRA_SUITE_MAP rows = `d7cbe811`, `LEADV2_TEST_CONTEXT` export = `29545513`. Probe:
  ```
  git log --oneline --find-object=760f3475 -3   # diff's NEW blob
  8efac28f fix(run-all): --scope changed is deterministic and refuses instead of degrading
  git log --oneline --find-object=e78060a8 -3   # diff's OLD blob
  65734576 wip(SUITE-MAP): CHECKPOINT — self-registration markers across 102 suites
  git rev-parse HEAD:tests/run-all.sh ; git hash-object tests/run-all.sh
  c4b64cd5…  c4b64cd5…   (HEAD blob != diff's b/ blob 760f3475)
  ```
  So `b/tests/run-all.sh` in the diff is an intermediate main state that `8efac28f` has since
  superseded. A PASS on this diff would gate nothing the lane actually changed.
- Corollary from `e2e-gate.log`: the gate on this lane ran with
  `SCOPE_RESULT selected=0 total=95 … verdict=nothing_to_run`, and `e2e-gate-passed.flag` exists.
  The lane passed its gate on zero suites. Flagging for lead; outside diff scope.

### High 2 — `core_offline_scope_arg` forwards `changed-since`, which the nested runner rejects (`tests/run-all.sh` diff lines 57-61, 111-115)
- run-all accepts three scopes: `tests/run-all.sh:55-57` → `changed|changed-since|all`.
- The diff's function returns `${SCOPE}` verbatim, so `tests/run-all.sh --scope changed-since`
  invokes `run-core-offline.sh --scope changed-since`.
- `plugins/leadv2/scripts/tests/run-core-offline.sh:85-89` accepts only `''|all|changed` and
  `exit 2` otherwise. Result: under the diff as written, every `--scope changed-since` run marks
  the core-offline entry FAILED (rc=2), a whole-run red for a valid CLI input.
- Already repaired on main by `8efac28f` (HEAD `tests/run-all.sh:122-133` maps `changed-since`
  → `changed`). This confirms the diff is pre-fix. GLM's review claim that "SCOPE is validated
  to changed|all" is wrong against the live parser.

### Medium 1 — the declared control suite does not cover the case that was broken (`tests/test-run-all-forwards-scope.sh:94-95`)
```
check_forward "changed" "changed" ...
check_forward "all"     "all"     ...
```
No `changed-since` case. Neither mutant M1/M2 nor the real defect in High 2 is caught by the suite
the diff's comment block cites as its negative control. A third row
`check_forward "changed-since" "changed"` is the minimal fix (against HEAD's version).

### Low 1 — known-red removal is justified but only by external evidence (`tests/known-red-suites.txt` line 9 removed)
Probe: `bash plugins/leadv2/scripts/tests/test-idle-lead-guard.sh` → `PASS=19 FAIL=0`. Green on
main, so the row removal is correct. The diff carries no note of which commit turned it green.

### Low 2 — redundant EXTRA_SUITE_MAP row (`tests/run-all.sh` diff line 79)
`leadv2-glm-policy-resolve:` (no `.py`) never fires: the exact-path branch assigns the stem with
extension, and the `.py` row on the next line is the one that selects. Harmless.

### Low 3 — new stdout line in the core-offline branch (`tests/run-all.sh` diff line 112)
`run-all: delegating scope=…` is printed before the captured transcript. No consumer greps for it
(`grep -rn "run-all: " plugins/leadv2/scripts/ci-gate.sh leadv2-e2e-entrypoint.sh` → none), and
`e2e-gate.log` shows it renders cleanly. Informational only.

## Things checked and found fine
- `plugins/leadv2/tests/test-arm-pool-reachability.sh` and `test-exclusion-stages.sh` exist and
  self-declare the same triggers via `# run-all-triggers:` headers; the map rows are duplicates by
  design (belt-and-braces).
- `.claude/leadv2-overrides/status-collector-facts.sh` exists; synthetic stem shape matches the
  `.gitignore` precedent immediately below it.
- `lib/leadv2-test-context.sh:42` honours `LEADV2_TEST_CONTEXT=1` as the fast path; exporting it
  from run-all is consistent with the writers' contract (refuse → rc=3 only without redirect).
- `SCOPE` is assigned and validated before the run loop, so the function never trips `set -u`.

## Verdict rationale
FAIL on two Highs: the artifact under review does not represent the lane (High 1), and the code
as diffed has a real whole-run-red defect on a valid scope value (High 2), now fixed upstream.
LEAD_ACTION: regenerate `review.diff` for B2-GATE-BUDGET-3 against current `main` (62da3911) and
re-run review; also inspect why the lane's e2e gate passed with `selected=0`.

DELIVERABLE_COMPLETE
