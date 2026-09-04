verdict: APPROVE
next_action: review_round_2

Implemented HOOK-INJECT-DEDUP-01 fix round 1 per the mechanism-closed design; committed e12d43b on worktree-7bdb16ee.

- In-gate `_nearest_decision_signature()` mixed into the dedup digest; removed the stderr swallow so fail-open WARN lines surface.
- test-inject-dedup.sh: +3 cases (G5b flip, finding-3 /tmp marker, finding-5 WARN) — PASS=14 FAIL=0.
- context-diet.md corrected (three-part digest, in-gate rationale, residual).

Full: full.md
