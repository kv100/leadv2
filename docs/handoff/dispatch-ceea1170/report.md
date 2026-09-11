# Report — dispatch-ceea1170 (docs-only: duplicate-caller-race 65597 1788781088)

## Mission
Docs-only audit dispatch exercising the duplicate-caller-race machinery. Epoch
1788781088 = 2026-09-07 14:38:08 EEST (lane spawn); 65597 = dispatcher pid.

## What was done
Reconciled `plugins/leadv2/docs/duplicate-caller-race.md` against the live
`plugins/leadv2/scripts/leadv2-dispatch-code.sh`:

- **Knob table**: defaults 30 / 7200 / 1 / 1 / 1 confirmed at
  `leadv2-dispatch-code.sh:725-737` (`PENDING_TTL`, `CONFIRMED_TTL`,
  `OUTCOME_LEDGER`, `CHECKPOINT_CUTOFF`, `EVIDENCE_ATTRIBUTION`).
- **Classifier fast-path**: `classify_product_work` (:3892-3917) still matches
  `docs?-only|documentation-only|pure diagnosis|diagnosis-only|tooling-only|plugin-only`
  — this mission's prefix hits `explicit_mission_fast_path`, so the terminal row is
  written by dispatch-code.sh itself, per the doc's "Note on mission strings".
- **Regression suites**: all four named suites exist under
  `plugins/leadv2/scripts/tests/` (duplicate-caller-race, dispatch-outcome-ledger,
  dispatch-ledger-partial-close, dispatch-retry-dead).

Result: **no drift found**. Appended a dated Audit-trail section to the doc recording
the reconciliation.

## Files changed
- `plugins/leadv2/docs/duplicate-caller-race.md` — appended "Audit trail" section.

## Falsification set
No shell or Python files changed, so `bash -n` / `py_compile` sets are empty by
construction. Changed-scope test runner output is pasted below.

## Changed-scope run
See raw output pasted by the lane below this heading.

```
$ bash tests/run-all.sh --scope changed
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ceea1170/plugins/leadv2/scripts/tests/run-core-offline.sh
RC=0
```
Green: core-offline (always-on) passed with exit 0 — run concurrently with a foreign
run-all (pid 12536), which per memory can flip nested suites NOT-KNOWN-RED; it did not.

No shell or Python files were changed, so `bash -n` / `python3 -m py_compile` sets are
empty by construction.
