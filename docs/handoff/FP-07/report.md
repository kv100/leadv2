# FP-07 report

Fixed the Codex review mission to state that `rg` exit 1 is a normal no-match
and every potentially empty search must use `rg ... || true`. The review engine
now performs one durable, author-safe retry after `review_body_lost`, selecting
only an untried distinct `:ok:` pool arm and journaling
`review_arm_retry from=<a> to=<b>`. If no candidate exists, or the replacement
also loses its body, it remains blocked.

Raw verification output:

```text
PASS: lost sonnet body retries once on distinct opus and passes
PASS: both bodies lost blocks after one distinct retry
PASS: negative control ran red: same-arm retry is caught
review-body-lost-retry-distinct-arm: PASS=3 FAIL=0
test-review-body-persist.sh: 13 passed, 0 failed
test-review-codex-base.sh: 11 passed, 0 failed
test-review-engine-v3-core.sh: PASS=5 FAIL=0
test-review-arm-failclosed-nonzero.sh: PASS=17 FAIL=0
bash -n leadv2-review-run.sh: PASS
git diff --check: PASS
```

DELIVERABLE_COMPLETE
