# Hack-Detection Review: BEAT-LOOP-ORPHANS-01

## Scope
Analyzed `docs/handoff/BEAT-LOOP-ORPHANS-01/build-attempt-2.diff` for:
- TODO/FIXME band-aids
- Magic numbers
- Broad except clauses
- Hardcoded credentials/secrets
- Silent fallbacks

## Findings

FINDING: severity=Critical file=plugins/leadv2/hooks/leadv2-single-lead-beat.sh line=139 dimension=hack desc=Broad except Exception with silent fallback — catches all Python errors and prints empty string, masking failures

## Analysis

### Confirmed Issues

**Line 139-141 (Critical):** Python code with broad `except Exception:` that silently prints `''` (empty string). This masks any Python parsing errors when extracting `HOOK_EVENT` from JSON input. The same pattern appears with `TRANSCRIPT_PATH` on line 136-142 — identical vulnerability.

Pattern:
```python
except Exception:
    print('')
```

This is dangerous because:
1. It catches all exceptions (not specific ones)
2. It prints empty output, making the error invisible to the caller
3. If JSON parsing fails, `HOOK_EVENT` becomes empty string, causing silent failures downstream
4. Caller code then uses the empty variable without knowing extraction failed

### Silent Fallbacks (Intentional, Not Hacks)

Multiple `2>/dev/null || true` patterns throughout:
- Line 265, 373, 421, 500, 609, 711, etc.

These are **intentional guards**, not hacks, because:
1. They are documented in surrounding comments as fail-open patterns
2. They guard optional dependencies (e.g., classifier lib may be absent in line 606-620)
3. The callers explicitly check for the guarded failures and journal them
4. Example line 618-620: journals `owner_check=unavailable` when lib is missing

### Magic Numbers (Not Hacks)

1. **Line 332-343:** `for i in 1 2 3 4 5 6 7 8` — intentional limit on process ancestor walk. Documented in comment as "walking up to 8 ancestors." This is acceptable.

2. **Line 394:** `LEADV2_LOOP_ORPHAN_MAX_MIN="${...:-30}"` — default 30 minutes for transcript staleness. Documented and configurable via env.

3. **Test durations (lines 1010, 1030, etc.):** `LEADV2_SINGLE_LEAD_BEAT_LOOP_S=1`, sleep durations. These are intentional test parameters, not magic.

### Audit Results

- **Band-aids (TODO/FIXME):** None found
- **Hardcoded credentials/secrets:** None found
- **Broad exception clauses:** One found (line 139-141)
- **Other silent fallbacks that mask errors:** Only the Python exception on lines 136-142
- **Intentional silent patterns:** Many; all documented and justified

## Recommendation

Fix line 139-141 and lines 136-142 by replacing broad `except Exception:` with specific exception handling or removing the catch entirely and letting Python errors propagate (so the hook fails loudly if input is malformed).

DELIVERABLE_COMPLETE
