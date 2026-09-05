# PREPASS-PROVIDER-FALLBACK-01-R10-TARGETED

Targeted continuation on the existing R9 worktree at `ae50455`. Do not run a new
full audit. Fix only the two reproducible High blockers from the native final
review:

1. EXIT cleanup must never delete a live GLM/Codex worker registry row during the
   interval after spawn and before slot disarm. Transfer/stamp worker ownership for
   every successful worker arm, or otherwise atomically disarm owner cleanup before
   a live worker can be exposed. Add an executable signal-window fixture.
2. SIGTERM must stop an active fallback promptly rather than waiting for the full
   architect timeout. Make provider execution independently interruptible and kill
   its process group immediately, then clean the disposable workspace. Add a
   bounded probe whose timeout is much larger than the expected signal latency.

Preserve all eight green R9 fixtures. Run bash-n and the focused fixture suite.
Commit both files and leave the worktree clean.

acceptance:
  surface: review_gate
  observable: Live GLM/Codex rows survive lead EXIT ownership cleanup, fallback SIGTERM returns promptly, and the focused executable suite passes.
  authored_at: 2026-08-24T21:37:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh
