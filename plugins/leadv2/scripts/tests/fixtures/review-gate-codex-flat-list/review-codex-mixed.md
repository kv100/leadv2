# Mixed-shape adversarial review (regression fixture for
# PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01 round 2, bug #3: a report carrying
# BOTH a structured `FINDING:` line and a flat bracket-severity bullet must
# have every finding of both shapes counted, not just the structured one.

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=2 medium=0 low=0

FINDING: severity=High file=file.txt line=1 dimension=correctness desc=structured finding from FINDING line

Findings:
- [high] Flat bracket finding alongside a structured one (file.txt:2)

Padding sentence so the review body clears the floor comfortably every run.
