# PREPASS-PROVIDER-FALLBACK-01-R5

Bounded review fix. Start from commit `9c2e753` from worktree
`PREPASS-PROVIDER-FALLBACK-01-R4` (cherry-pick it into this lane). Do not repeat
the earlier discovery and do not run broad legacy suites.

Fix all four High findings in
`docs/handoff/CODEX-LEAD-REPAIR-20260824/review-codex.md`:

1. Architect fallback must not run code-capable launchers in the shared main
   checkout. Use a disposable isolated git workspace or an existing
   launcher-enforced architect/read-only mode; extract only a validated design
   artifact and clean the isolation resource on every terminal path.
2. Pre-registration cleanup must be owner-safe. A concurrent retry must never
   unregister another dispatcher/worker row. Use a unique ownership identity
   tied to this dispatcher process/attempt and verify it before release.
3. Every proven no-worker terminal exit, including the reviewer census, must
   release only its own pre-registration. Prefer a single disarmable EXIT trap
   plus explicit worker-spawn handoff rather than scattered unsafe calls.
4. Decision-driving provider/launcher contracts must have evidence. Add focused
   fixture tests for auth/rate/quota classification and Codex/GLM launcher
   result parsing; tag any remaining external assumption `UNVERIFIED` and do
   not enable behavior that depends solely on it.

Exact write boundary:

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
- `plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh`

Run only the new focused test plus:

- `bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh`
- `bash plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh`
- `bash plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh`
- `bash plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh`
- `bash plugins/leadv2/scripts/tests/test-active-registry-update-phase.sh`

Do not run ledger/partial-close/core-offline suites: they are known to escape
fixtures and spawn real workers. Commit the cherry-picked base plus the bounded
fix and report raw tests.

acceptance:
  surface: review_gate
  observable: All four Codex High findings are fixed with isolated prepass fallback, owner-safe all-exit slot release, evidence-backed provider contracts, focused tests, and no spawned fixture workers.
  authored_at: 2026-08-24T19:36:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh
