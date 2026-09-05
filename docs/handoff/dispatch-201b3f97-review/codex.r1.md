# Adversarial review — SCOPE-DISCIPLINE-01

Reviewed `6ae373a...14bbaf6` in worktree `201b3f97`.

## Findings

### HIGH — deletions and rename sources outside the write-set are silently accepted

`lv2_selfcheck_run` extracts only `+++ b/<path>` lines
(`plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh:105-115`).  It deliberately
drops `/dev/null`, never reads `--- a/<path>`, and therefore validates only a rename
destination.  The scope gate consequently returns `GREEN` for:

```diff
--- a/outside/old.txt
+++ b/inside/new.txt
```

with `write_set_csv=inside`, even though the diff touched `outside/old.txt`.  A
deletion of `outside/deleted.txt` produces an empty changed set and is also `GREEN`.
This violates the required bounce for any diff touching a path outside the declared
write-set and is exactly a silent trim/evasion.  Collect both sides of every diff
file header (excluding `/dev/null`), dedupe them, and add red-first coverage for an
out-of-scope deletion and a rename whose source is out of scope.

### MEDIUM — scope kill switch does not restore the prior output byte-for-byte

With `LEADV2_SCOPE_DISCIPLINE=0`, C0 still adds a `scope_discipline_disabled` table
row and increments `skipped` (`:152-155`).  Compared with the pre-C0 code path this
changes `selfcheck.md`, `LV2_SELFCHECK_SKIPPED`, and the product-close journal's
`skipped=` field.  The current direct test only asserts absence of `scope:` failures;
it cannot establish the stated byte-restore property.  The kill-switch branch should
perform no C0 bookkeeping/output at all, and a regression should compare the
kill-switch artifact/globals against a pre-C0 fixture.

### MEDIUM — the four new scope tests are not red-first and leave the bypass untested

Cases 16–19 are explicitly “direct-only” and run only against the modified library
(`test-builder-selfcheck-gate.sh:685-690`); the source comments concede their
red-first claim is manual.  Thus their claimed 30/0 result does not prove the new
gate was red before the change.  They also generate only `+++` records, so they cannot
detect the deletion/rename-source bypass above.  Use a pre-change implementation or a
falsifying mutant and make the new legs fail it; include file-header fixtures for
deletion and rename source/destination handling.

## Checks and evidence

- Direct probe: out-of-set rename source with in-set destination: `RC=0`,
  `FAILED=0`, `verdict: GREEN`.
- Direct probe: out-of-set deletion: `RC=0`, `FAILED=0`, `verdict: GREEN`.
- The stop-gate fallback correctly selects the newest first-parent commit without
  `pc_stop_gate_autocommit` in this history (`36c6ceb`); it is genuinely pre-gate.
  Its 100-commit cap remains untested, but does not affect this branch.
- The long focused suites began passing their exercised legs, but the execution
  environment ended the invocations before their final summaries; this does not
  mitigate the reproducible direct bypasses above.

VERDICT: FAIL
