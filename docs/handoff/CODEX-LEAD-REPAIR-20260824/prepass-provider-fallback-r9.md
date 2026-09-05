# PREPASS-PROVIDER-FALLBACK-01-R9

Bounded review fix on the existing R7 worktree. Start from commit `4de1834`.
Do not redesign or touch files outside the two listed below.

Fix all five High findings in
`docs/handoff/CODEX-LEAD-REPAIR-20260824/review-codex.md`:

1. Replace read-then-unregister with registry-locked compare-and-delete using the captured session/PID ownership; unreadable or mismatched ownership must never delete.
2. Make registrar output/status parsing explicitly non-fatal under inherited `errexit`/`pipefail`.
3. Put fallback workspace identity in global signal/EXIT cleanup immediately after creation, then disarm only after normal disposal.
4. Correct the rollback contract. Do not claim byte-for-byte rollback for unrelated behavior; use truthful independent controls/comments.
5. Replace grep-only fallback assertions with isolated subprocess integration fixtures in a temporary Git repo and stub Codex/GLM/registry launchers. Exercise success, nonzero, timeout/signal cleanup, and foreign-owner refusal. Never call a real provider or canonical registry.

Keep the known unrelated legacy timing failures out of scope. Run `bash -n`, the focused test, and only bounded fixture tests. Commit both files and finish clean.

acceptance:
  surface: review_gate
  observable: All five reviewed High findings are fixed in a clean commit and isolated executable fixtures pass without a real provider or canonical registry.
  authored_at: 2026-08-24T20:57:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh
