# DISPATCH-HONESTY-01 Round 1 Report

## Outcome

Implemented both fixes in `plugins/leadv2/scripts/leadv2-dispatch-code.sh`.

- A primary architect `rc=124` is reclassified as `quota_exceeded` only when a bounded fresh probe of the selected credential proves `usable_now == 0.0` in its binding window. Otherwise it remains `timeout`, so the existing fallback class allowlist is unchanged.
- The dispatcher now transports `--writes` through one registration bridge and reads the exact row back from the resolved `active.yaml`. A missing declaration refuses with the row owner and `declared_but_not_persisted`, instead of presenting the victim lane's scope as `undeclared`.

## Acceptance evidence

The two requested suites pass, including their in-function negative controls:

```text
[ok] exhausted selected credential reclassifies rc=124 as quota_exceeded and opens the existing fallback
[red-control §1 raw]
... architect_prepass task=badc0de1 status=failed reason=timeout rc=124 ...
[ok] negative control: unconditional timeout classification blocks fallback
=== all checks passed ===
[ok] declared --writes reaches the real scratch active.yaml registry row
[red-control §2 raw]
... proof=present=1 owner=DISPATCH-WRITES-NEGATIVE writes=<missing> ...
[ok] negative control: losing --writes in the bridge is caught by registry read-back
=== all checks passed ===
```

Full raw output, including the two mutation controls, is in [`round1-red.txt`](round1-red.txt).

Additional checks:

- `bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh plugins/leadv2/scripts/tests/test-prepass-timeout-on-exhausted-credential-falls-back.sh plugins/leadv2/scripts/tests/test-dispatch-writes-reaches-registry.sh`: pass (no output, exit 0).
- `git diff --check`: pass (no output, exit 0).
- `test-writeset-refusal-names-blocker.sh`: 4/4 pass.
- `test-writeset-pending-overlap.sh`: 7/7 pass.
- `test-mission-writeset.sh`: 21 pass, 1 pre-existing usage-mutation failure (`source pattern not found`).
- `tests/run-all.sh --scope changed`: the offline core runner selected 122 suites and hit its built-in 600s ceiling; this is recorded as ambient runner timeout, not as a targeted acceptance failure.

The changed-scope runner's raw bounded result was:

```text
[CORE-OFFLINE] scope=changed running 122 of 95 suites...
[CORE-OFFLINE] SCOPE_RESULT selected=122 total=95 base=main@50fe7c3dda changed=3 unmapped=0...
[SUITE-TIMEOUT] .../run-core-offline.sh exceeded 600s ceiling...
[FAIL] run-core-offline.sh
```

No Python files were changed, so `python3 -m py_compile` had no applicable
files. The complete raw acceptance and red-control output is preserved in
[`round1-red.txt`](round1-red.txt).
