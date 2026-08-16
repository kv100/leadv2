# Codex Adversarial Review

Target: branch diff against b90e40ed36d2e2f39d232d859330bb7f5c7c07eb
Verdict: needs-attention

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=3 medium=0 low=0
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-broad-status.sh line=83 dimension=correctness desc=Failure emits READY without replacing founder-status.md, so the mandated verbatim relay can publish a stale healthy status as the degraded beat.

Findings:
- [high] Degraded status relays stale content (plugins/leadv2/scripts/leadv2-broad-status.sh:83)
  When collection fails, this emits READY without replacing founder-status.md, so the instructed verbatim relay can present the previous healthy snapshot as the failed beat.
  Recommendation: Atomically write a degraded founder-status.md artifact before emitting READY, and apply the same handling to render failures.
- [high] Composer-failure ready line is malformed and stale (plugins/leadv2/scripts/leadv2-supervise-loop.sh:397-398)
  This fallback emits READY without a new degraded artifact and supplies the failure reason as at while leaving the reason placeholder empty, so the relay points to stale data and hides the failure cause.
  Recommendation: Publish a degraded artifact before READY and pass a timestamp plus the reason to all three printf placeholders.
- [high] New integration test cannot execute its loop scenarios (plugins/leadv2/scripts/tests/test-broad-status-duty.sh:184-187)
  timeout executes external commands rather than shell functions, so every timeout invocation of loop_env returns 127 and the loop, watchdog, kill-switch, and cron checks deterministically fail or test nothing.
  Recommendation: Invoke timeout around env with explicit assignments, or use a bash -c wrapper that defines and calls loop_env.

Next steps:
- Fix the degraded-artifact paths and make the integration test invoke a real executable before rerunning it.
