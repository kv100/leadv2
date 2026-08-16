verdict: BLOCK
next_action: review_round_2

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=3 medium=4 low=3

Suite is green (38/38) while three High defects stand.

- H1: `docs/handoff/${TASK}/…` pointer is a dead path (TASK is sig8, dir is `dispatch-<sig8>`); test asserts the wrong string.
- H2: summary/`verdict:` use primary-arm counts, rows use all arms — reproduced `PASS — 0 finding(s)` above an upheld Critical.
- H3: parse-failure guard never fires once a second arm emits any row (default fanout 3).

Full: critic.full.md
