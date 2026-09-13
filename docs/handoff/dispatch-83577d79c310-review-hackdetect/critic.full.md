# Hack-Detection Review: dispatch-83577d79c310-review-hackdetect

## Scan Results

FINDING: severity=Critical file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=228 dimension=hack desc=Calls undefined function _lv2_phys; no definition found in diff or reachable scope
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=23 dimension=hack desc=Silent fallback with || true swallows git log error without logging; subject uninitialized on failure
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=27 dimension=hack desc=Silent fallback with || true on git rev-parse; parent uninitialized on failure
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=29 dimension=hack desc=Silent fallback with || true on git diff --stat; diffstat uninitialized on failure
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=71 dimension=hack desc=Silent fallback with || true masks cd/pwd failure; caller cannot distinguish no-dir from permission-denied
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=585 dimension=hack desc=Uses python3 -c for realpath; fragile, breaks if python3 unavailable or version-incompatible
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=595 dimension=hack desc=Uses python3 -c for realpath in symlink target check; same portability risk as line 585
FINDING: severity=Medium file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=130 dimension=hack desc=Array indexing uses last element as default (${#_PC_CAND_ROOT[@]}-1) without documenting why; fragile if order changes
FINDING: severity=Medium file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=164 dimension=hack desc=Silent fallback with || true on symbolic-ref; default left as empty string if git fails

## Evidence

- Line 228: `if [[ "${_PC_CAND_KIND[$i]:-}" == "lane" && "$(_lv2_phys "${root}")" != "$(_lv2_phys "${ROOT}")" ]]; then` — `_lv2_phys` is called twice but never defined anywhere in the diff. Grep confirms no definition.
- Lines 23–29, 71, 164, 202, 585, 595, 607: All use `|| true` pattern without logging failures; script continues silently with uninitialized or empty variables.
- Line 130: `shared="${_PC_CAND_SHARED[${#_PC_CAND_ROOT[@]}-1]:-0}"` — uses last candidate's shared value as default across a loop iteration; no comment explaining why this is safe if candidate order changes.
- Lines 585, 595, 647: Inline `python3 -c` calls; assumes python3 is available and import behavior is stable.

## Test Coverage

New test files added:
- `test-lane-worktree-places-env.sh`: Tests `place_lane_env` function; 2 test cases (fresh env, missing source).
- `test-review-gate-counts-the-right-repo.sh`: 5 test cases for path-to-repo resolution; does not test failure modes of `_lv2_phys` or python3 fallback paths.

## Summary

One critical blocker: `_lv2_phys` function is called on a new code path but never defined. This will cause runtime failure when line 228 executes. Multiple high-severity silent fallbacks reduce debuggability. Python inline code introduces portability risk.

DELIVERABLE_COMPLETE
