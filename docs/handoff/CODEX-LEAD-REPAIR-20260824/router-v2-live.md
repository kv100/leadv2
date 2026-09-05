# CODEX-LEAD-ROUTER-V2-LIVE-01

Retire legacy GLM-first behavior and make smart routing v2 the truthful default.

Premise:
- `leadv2-dispatch-code.sh` currently defaults `LEADV2_ROUTER_V2` to off, so real dispatch remains legacy GLM-first with hand-kept exceptions.
- Canonical config already declares GLM, Codex/Terra, Sonnet, and review-only Opus/Haiku arms plus quota/headroom policy.
- Runtime supports bounded parallel lanes; provider/model choice should depend on task shape, live quota/lockout, reliability, and write collisions, not a fixed primary provider.
- A legacy reviewer-pool test is already red because it asserts an obsolete exact five-line output while the resolver emits additional truthful fields.

Required behavior:
1. Make router v2 the default production path with an explicit, tested rollback flag to legacy behavior.
2. Route build arms by task shape plus live quota/headroom/reliability. Do not merely rotate a fixed ladder or rename GLM-first.
3. Preserve distinct provider pools: Codex models share OpenAI quota; Sonnet/Opus/Haiku share Anthropic scope; GLM remains its own pool.
4. Keep Opus eligible for architecture/review judgment but not ordinary code build unless canonical policy explicitly allows it.
5. Preserve safe fallback behavior for missing/malformed/stale quota telemetry; journal why the chosen arm won and which inputs were unknown.
6. Respect dispatcher concurrency/collision controls; do not reintroduce fixed WIP=1.
7. Update the obsolete exact-output reviewer-pool test to assert the stable contract rather than suppressing the new fields.
8. Add/extend behavioral tests for task-shape routing, quota withdrawal, unknown quota, provider lockout, legacy rollback, concurrency admission, and audit output.

Non-goals:
- Do not change the root Codex model/effort, plugin lifecycle hooks, or pre-tool guard.
- Do not remove GLM as a provider.

acceptance:
  surface: log_line
  observable: Two dispatch resolutions with different task shapes or quota states choose the appropriate available arms and emit a compact reason naming task fit, quota/headroom, and unknown inputs; legacy mode remains an explicit rollback only.
  authored_at: 2026-08-24T18:25:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-router-v2.py,plugins/leadv2/scripts/leadv2-router-v2.sh,plugins/leadv2/config/leadv2-routing.yaml,plugins/leadv2/scripts/tests/test-smart-routing-v2-*.py,plugins/leadv2/scripts/tests/test-leadv2-router-*.sh,plugins/leadv2/scripts/tests/test-glm-policy-resolve.sh
