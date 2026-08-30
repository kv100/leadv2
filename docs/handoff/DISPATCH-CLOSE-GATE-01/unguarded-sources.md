# Unguarded `lib/` source census — DISPATCH-CLOSE-GATE-01

Generated from `rg -n --glob '*.sh' '^[[:space:]]*(source|\.)[[:space:]].*(/|\.)lib/' plugins/leadv2/scripts plugins/leadv2/hooks` on this lane. “Guarded” means the source has a local-or-canonical fallback in its immediate loading block. This lane fixed every unguarded production source in its write set; the remaining entries are outside `LANE_WRITES` and are an explicit baseline for `test-lib-source-guarded.sh`.

## Guarded in this lane

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh:687` — guarded with canonical fallback.
- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:2051` — guarded with canonical fallback.
- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:2884` — guarded with canonical fallback.

## Unguarded outside this lane’s write set

- `plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh:74`
- `plugins/leadv2/hooks/leadv2-stale-pid-sweep.sh:12`
- `plugins/leadv2/scripts/leadv2-codex-session-runner.sh:23`
- `plugins/leadv2/scripts/leadv2-session-runner.sh:265`
- `plugins/leadv2/scripts/leadv2-review-run.sh:1251`
- `plugins/leadv2/scripts/leadv2-backlog-pump.sh:169`
- `plugins/leadv2/scripts/leadv2-backlog-pump.sh:581`
- `plugins/leadv2/scripts/leadv2-kimi-session-runner.sh:118`
- `plugins/leadv2/scripts/leadv2-glm-session-runner.sh:100`
- `plugins/leadv2/scripts/leadv2-codex-lockout.sh:30`
- `plugins/leadv2/scripts/codex-task.sh:122`
- `plugins/leadv2/scripts/codex-task.sh:124`
- `plugins/leadv2/scripts/codex-task.sh:126`
- `plugins/leadv2/scripts/leadv2-glm-quota-gate.sh:36`
- `plugins/leadv2/scripts/claude-subsession.sh:387`
- `plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh:53`
- `plugins/leadv2/scripts/leadv2-gate1-prompt.sh:162`
- `plugins/leadv2/scripts/leadv2-lane-outcome.sh:40`
- `plugins/leadv2/scripts/leadv2-lane-worktree.sh:167`
- `plugins/leadv2/scripts/leadv2-worktree-cleanup.sh:21`
- `plugins/leadv2/scripts/tests/test-codex-lockout-agreement.sh:63`
- `plugins/leadv2/scripts/tests/test-admission-class.sh:19`
- `plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh:93`
- `plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh:99`
- `plugins/leadv2/scripts/tests/test-close-chain.sh:262`
- `plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh:104`
- `plugins/leadv2/scripts/tests/test-mission-writeset.sh:15`
- `plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh:48`
- `plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh:116`
- `plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh:151`
- `plugins/leadv2/scripts/tests/test-red-first-baseline.sh:7`
- `plugins/leadv2/scripts/tests/test-parked-worker-resume.sh:18`
- `plugins/leadv2/scripts/tests/test-parked-worker-resume.sh:60`
- `plugins/leadv2/scripts/tests/test-provider-quota-gate.sh:284`
- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:3341`
