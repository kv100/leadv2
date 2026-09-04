verdict: APPROVE
next_action: continue

Design ready. Brief's `set -e` root cause is wrong — engine is `set -uo pipefail`; three real fail-open holes need trap fixes.

- H1: `_engine_arm_job:1015` writes `.rc` only on the normal path — TERM/`set -u` skip it.
- H2: `classify_arm_failure:493` requires `-s out_file`, so a died arm falls through to `ran`.
- H3: all `review-gate.md` writes are inline; a parent abort leaves no artifact.

Full: architect.full.md
