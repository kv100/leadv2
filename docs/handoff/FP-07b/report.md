# FP-07b report

**Diagnosis (corrected from the backlog premise).** The resolver's `pool=` emission is correct
(D2's `_emit_pool_lines`, verified by probe: `--review-pool` prints the gate block AND
`reviewer=/pool=/refusal=`). The real gap: review-run's `resolve_review_pool_call` still had the
pre-A2 tail — `python3 … 2>/dev/null || printf fallback` — which discarded resolver stderr and, on
any stdout lacking a `pool=` line (gate-shape-only output, argparse exit 2, python missing),
parsed as a **silent empty pool**: the FP-07 retry then had zero candidates with nothing on any
surface. The close-gate copy got the dispatch-8e2a32be A2 hardening; review-run never did.

**Fix (single-owner, bash-side; resolver untouched).** `leadv2-review-run.sh:resolve_review_pool_call`
now mirrors the close-gate copy: stderr → `${HANDOFF}/review-pool-resolver.err`, rc journaled via a
new `review_pool_resolver` decision line, and a stdout with no `pool=` line fails closed
(`refusal=resolver_error_failclosed`) instead of parsing as success. Primary selection and the
retry read the same `${pool}`.

**Tests** (`test-review-body-lost-retry-distinct-arm.sh`, extended in place, PASS=6 FAIL=0): retry
driven by a fixture captured from the REAL resolver (deterministic fake quota-live), gate-shape-only
fail-closed case, negative control 1 (same-arm retry) and 2 (wrong-token parse) both RUN RED.
Neighboring suites: body-persist, v3-core 5/0, failclosed 17/0, fanout-visibility 23/0,
pool-degrades 2/0, verifier-distinct-arm 1/0, codex-base 11/0 — all green. bash -n + git diff --check PASS.
Mid-development red run (stdout passthrough bug): PASS=0 FAIL=6 — captured, fixed, re-run green.

DELIVERABLE_COMPLETE
