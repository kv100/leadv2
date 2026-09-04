# FP-08 Fix Report

## Summary
Fixed two issues in the freepool arm:
1. Wait unification: Made freepool worker liveness check use the same waiter as GLM/Kimi arms.
2. Capability floor: Freepool is now ranked below codex/sonnet for Standard/Heavy work until quality gate flips.

## Changes
- `leadv2-dispatch-product-close.sh`: Added freepool case to `pc_worker_alive()` function to properly track freepool worker liveness using its status subcommand and run directory.
- `leadv2-dispatch-code.sh`: No functional changes needed; freepool already used correct liveness check via `_dispatch_worker_liveness()`.
- `lib/leadv2-route-arbiter.sh`: Modified util() function for freepool to apply capability floor (increase cost by 50 for Standard/Heavy code/docs work) and journal applications via state file.

## Testing
- Verified syntax of all changed files with `bash -n`.
- Ran the leadv2 test suite (suite-run) - all tests passed.
- Specific freepool tests in `test-freepool-*.sh` passed.
- No regressions in related dispatch or routing tests.

## Verification
- The freepool arm now correctly waits for worker completion in product-close phase.
- Capability floor journals appear when freepool is demoted for Standard/Heavy work.
- Freepool remains eligible for Trivial/Light/bulk work as expected.