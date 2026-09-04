# Hack Detection Review: BROAD-STATUS-ROWS-02

## Summary

Diff analyzed for TODO/FIXME band-aids, magic numbers, broad exception handlers, hardcoded credentials/secrets, and silent fallbacks.

**Finding count:** 1 (Medium severity).

## Detailed Analysis

### TODO/FIXME Band-Aids
- **Result:** None found.
- The diff contains no unresolved `TODO` or `FIXME` comments. Comments present are all explanatory of design intent (e.g., "BROAD-STATUS-ROWS-01 fix A", "LANE-OBSERVABILITY-02 change 3").

### Magic Numbers
- **Result:** None found.
- Test fixtures contain hardcoded values (stream_bytes: 111, 222, 333, 444; grep count checks -eq 2, -eq 1), but these are intentional test data, not unexplained constants.
- Numeric literals in test setup are semantically justified by their context.

### Broad Exception Handlers
- **Result:** None found.
- No bare `except:` or `except Exception:` clauses.
- Python code in test stubs uses inline `[[ -z "$out" ]] && exit 1` guards; no silent exception suppression.

### Hardcoded Credentials / Secrets
- **Result:** None found.
- Stub responses are mock data (Russian placeholder text "нет данных за сегодня\nвопросов нет").
- No API keys, tokens, passwords, or auth material embedded in the diff.

### Silent Fallbacks

**FINDING: severity=Medium file=plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh line=162 dimension=hack desc=Error suppression combines stderr redirection with || true, silently swallowing all script failures and risking false test passes if leadv2-broad-status.sh outputs corrupted state**

**Details:**
```bash
bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
```

**Why it's a problem:**
1. Both `>/dev/null 2>&1` and `|| true` suppress errors — the combination is redundant and masks test failures.
2. If `leadv2-broad-status.sh` crashes mid-execution and writes partial/corrupted output to `$FOUNDER_STATUS`, the test will not detect the error because stderr is redirected to `/dev/null` AND the exit code is masked by `|| true`.
3. The test only checks file *existence* (line 238) and *content patterns* (grep lines 243-278), but if the script outputs garbage or partial JSON before crashing, the content checks may still pass by accident.

**Mitigation present:**
- The test does validate output file existence and grep for expected patterns afterward (lines 238-240, 243-244, 260, 269, 274).
- This catches *complete* script failures (file not created) but not *partial* failures (file created but corrupted).

**Severity:** Medium (affects test reliability; does not affect production code).

---

## Defensive Fallbacks (Intentional, Not Hacks)

The following fallbacks are intentional and safe:

1. **Line 19:** `str(_row.get("task_id") or "?")`
   - Explicit fallback to a sentinel string when task_id is missing. Documented in preceding comment. Acceptable.

2. **Line 62:** `chto = product_sentence(mission_title) or linia_name or "—"`
   - Three-tier fallback chain: product_sentence → linia_name → literal "—" (dash).
   - All tiers are safe; no silent failures, only graceful degradation to a placeholder.

---

## Conclusion

**One actionable finding:** Line 233 in the test file silently suppresses stderr and exit codes with a combined `>/dev/null 2>&1 || true` pattern. Recommend removing `|| true` and letting real failures propagate, or replacing it with conditional error handling that explicitly decides when to ignore failures.

**Proposed fix:** Either:
- Remove `|| true` and let script failures fail the test.
- Replace with: `bash "$BROAD_STATUS_SH" >/dev/null 2>&1; [[ $? -eq 0 ]] || log "WARN: script exited with code $?"` (log it but don't fail).
- Or: Remove stdout/stderr redirection entirely and capture actual output for debugging.

DELIVERABLE_COMPLETE
