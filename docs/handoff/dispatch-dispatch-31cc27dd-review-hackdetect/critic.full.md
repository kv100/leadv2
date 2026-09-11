## Hack-Detection Report

### Findings

**FINDING: severity=Critical file=plugins/leadv2/scripts/tests/test-lib-fails-closed.sh line=31 dimension=hack desc=Test expects rc=0 but implementation returns rc=2; test will fail**

The test on line 31 uses glob pattern `'rc=0'*` to verify the exit code. Line 30 captures both stderr and then appends `; echo "rc=$?"`. The leadv2-phase-record.sh implementation (line 16) explicitly `return 2` for the journal_missing case. When the test runs, the output will contain `rc=2`, not `rc=0`, causing the glob match to fail and the test to call `bad()` on line 35. The assertion is incompatible with the implementation—either the code should return 0 (per the comment on line 33: "record rc still 0") or the test should check for `rc=2`.

**FINDING: severity=Medium file=plugins/leadv2/scripts/leadv2-phase-record.sh line=16 dimension=hack desc=Magic number `return 2` lacks named constant; meaning unclear without documentation**

The exit code 2 is hard-coded to represent "journal_missing" error but has no symbolic constant. Callers and tests must guess the meaning or refer to implementation details. Define a documented constant (e.g., `JOURNAL_MISSING_RC=2` at the top of the script) and use it consistently.

---

### Other Dimensions Checked

- **TODO/FIXME band-aids**: None found.
- **Broad except (Python)**: Not applicable (bash-only diff).
- **Hardcoded creds/secrets**: None found.
- **Silent fallbacks**: Diff REMOVES the old silent fallback (line 13: `return 0`), replacing it with loud stderr output (line 14-15)—this is a fix, not a new hack.

DELIVERABLE_COMPLETE
