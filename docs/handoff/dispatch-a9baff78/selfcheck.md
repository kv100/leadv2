# builder selfcheck — dispatch-a9baff78
generated_at: 2026-09-03T20:09:27Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SD-MAIN-CORE-SUITE-RED-01
diff_hash: fd111e7e94adb9036e3c8ef6d225de5170e4ad3f3a1abc87de8aa817d94af6d8
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SD-MAIN-CORE-SUITE-RED-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
