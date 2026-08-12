# PLUGIN-RELIABILITY-02 test-gate proof

Deliverable: `plugins/leadv2/scripts/tests/test-plugin-reliability-02.sh`.

The test creates a sandbox GLM-style run directory with real `pgid` and
`.lockref` records, starts a `setsid` group with a real sleeping child, and
invokes `leadv2-dispatch-product-close.sh` with a one-second worker timeout.
It asserts that the group child is dead after the production timeout reap call
site executes.

Red proof (historical script materialized with
`git show c6c44b5:plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`):

```text
FAIL: setsid group child <pid> survived close-timeout reap
RED_RC=1
```

Green proof (current HEAD):

```text
ok: real close-timeout reap killed setsid group child (gate rc=5)
GREEN_RC=0
```

The close gate's own `rc=5` is the expected `worker_timeout` branch result;
the test runner returns zero only after confirming its setsid group child died.

DELIVERABLE_COMPLETE
