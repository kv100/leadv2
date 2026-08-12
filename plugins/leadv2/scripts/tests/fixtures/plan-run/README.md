# plan-run test fixtures

Shared stub scripts for `test-plan-run-*.sh` suites.

- `stub-architect.sh` — emits a valid `PLAN_YAML:` fenced block with all
  required judgment fields (decisions, off_limits, plan.steps, acceptance,
  risk). Used as `LEADV2_DISPATCH_ARCHITECT_BIN`.
- `stub-codex-disabled.sh` — simulates `codex_enabled=false` by emitting
  `codex_skipped_by_policy` on stdout+stderr with exit 0.
- `stub-quota-ok.sh` — stub `--quota-live` reader that always returns
  `{"status":"ok"}`.
