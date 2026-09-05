# builder selfcheck — dispatch-9204345e
generated_at: 2026-09-02T23:24:23Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HOOKS-PARITY-ACROSS-REPOS-01
diff_hash: 650358ea2a141b4fd5250db6f9969cbd77f1c916bd304a55791eb579326cec2a
checks: 21   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/hooks/leadv2-lead-delegation-nudge.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-pulse-json.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-hook-fork-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-watch-v2.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-hook-fork-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-lead-delegation-nudge.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-loop-detect.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-pulse-json.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh | 0 |
| bash -n | tests/ci-gate.sh | 0 |
| bash -n | tests/known-red-guard.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| py_compile | plugins/leadv2/scripts/leadv2-loop-detect.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HOOKS-PARITY-ACROSS-REPOS-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-hook-fork-guard.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-lead-delegation-nudge.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-loop-detect.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-pulse-json.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
