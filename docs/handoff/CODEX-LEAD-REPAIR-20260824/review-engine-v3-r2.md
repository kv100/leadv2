# REVIEW-ENGINE-V3-CORE-01-R2

Narrow core replacement for the parked broad review lane. Change only the shared
review engine and one new bounded test.

Required behavior:

1. Default fanout is one independent reviewer.
2. Always-on Haiku hack detection is removed. A security/hack pass runs only for
   protected/high-risk paths or an explicit environment flag.
3. Per-finding verifier LLM calls are off by default. They run only for disputed
   High/Critical findings under an explicit/risk policy.
4. Review state is keyed by task plus diff hash. A changed diff starts a fresh
   state rather than inheriting attempts from an earlier implementation.
5. First pass is exhaustive. After a failed pass and a changed diff, the one
   allowed recheck is targeted to the prior High/Critical blockers; it must not
   request another full census. Hard-cap the sequence at those two passes.
6. Preserve independent reviewer selection, fail-closed gate output and existing
   explicit overrides.
7. Add executable no-provider fixtures proving default call count, risk-triggered
   escalation, fresh-diff state and targeted recheck prompt/mode.

Do not touch product-close, dispatcher, root skills or hooks. No real provider
calls. Commit both files and leave the worktree clean.

acceptance:
  surface: review_gate
  observable: Ordinary changes invoke one reviewer, risk alone enables extra security review, and a changed failed diff gets only one targeted blocker recheck as proven by executable fixtures.
  authored_at: 2026-08-24T21:33:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/scripts/tests/test-review-engine-v3-core.sh
