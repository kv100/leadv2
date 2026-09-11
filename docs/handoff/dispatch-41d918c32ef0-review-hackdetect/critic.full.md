# Hack-Detection Review: build-attempt-2.diff

## Analysis Summary

Scanned diff for TODO/FIXME band-aids, magic numbers, broad except handlers, hardcoded credentials/secrets, and silent fallbacks.

## Findings

**No hacks detected.**

### Checks performed:

1. **TODO/FIXME band-aids**: None found (grep for TODO|FIXME|XXX|HACK returned empty)
2. **Magic numbers**: 
   - Values 0, 1, 2 used as receipt freshness return codes
   - All properly documented with inline comments explaining semantics
   - rc 0 = stale, rotated aside → proceed
   - rc 1 = honoured → check sentinel for completion  
   - rc 2 = stale but rotation failed → error, must propagate
3. **Broad exception handlers**: N/A (shell script, not Python)
4. **Hardcoded credentials/secrets**: None found
5. **Silent error fallbacks**: None detected
   - rc 2 failures are explicitly propagated via `exit` or `return` in all runners (GLM, Kimi, session-runner)
   - Error conditions logged with `log_error`
   - No swallowed exceptions; when completion_proof_present returns 1, the fallthrough is intentional (no proof found, continue searching)

### Files changed:
- `plugins/leadv2/scripts/leadv2-glm-session-runner.sh` (lines 10–27)
- `plugins/leadv2/scripts/leadv2-kimi-session-runner.sh` (lines 40–58)
- `plugins/leadv2/scripts/leadv2-session-runner.sh` (lines 70, 85–95, 102–104, 111–113, 120–122)
- `plugins/leadv2/scripts/lib/leadv2-receipt-freshness.sh` (comment update lines 139–141)
- `plugins/leadv2/scripts/tests/test-stale-receipt-requeue.sh` (test cases 8–9, lines 173–247)

### Code quality observations:

- **GLM/Kimi runners** (lines 10–27, 40–58): Three-way branch correctly routes rc=0 (proceed), rc=1 (sentinel check), rc≥2 (error exit)
- **Session runner** (lines 85–95): `completion_proof_present()` returns error codes directly; `elif [[ "$receipt_freshness_rc" != "0" ]]` catches rc≥2 and propagates
- **Error propagation** (lines 102–104, 111–113, 120–122): After calling `completion_proof_present()`, checks `$?` for rc=2 and exits with it
- String comparisons on numeric codes (`[[ "$receipt_freshness_rc" == "0" ]]`) work correctly in bash
- Test coverage: Cases 8–9 verify rotation failure detection and rc 2 propagation across all three runners
- No variable scope issues; `receipt_freshness_rc` properly local

DELIVERABLE_COMPLETE
