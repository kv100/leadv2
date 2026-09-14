# Unanchored flat-list adversarial review (regression fixture for
# PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01 round 2, bug #2: multiple bracket
# findings of the SAME severity with NO trailing (path:line) anchor must not
# collapse into a single dedup row.

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=3 medium=0 low=0

Findings:
- [high] First unanchored finding with no trailing location at all
- [high] Second unanchored finding, a completely different issue
- [high] Third unanchored finding, yet another distinct issue

Padding sentence so the review body clears the floor comfortably every run.
