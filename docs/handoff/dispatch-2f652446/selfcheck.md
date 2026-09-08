# builder selfcheck — dispatch-2f652446
generated_at: 2026-09-08T01:19:01Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2f652446
diff_hash: 1e57bb475fe56e7fd1865e9f53c835b38dc035b17e53ea109988d2671dee9cba
checks: 5   failed: 1   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-codex-config-prune.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-worktree.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-config-prune.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2f652446/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-codex-config-prune.sh | FAIL (test_failed:rc=1;file_new_in_diff) |

## raw — plugins/leadv2/scripts/tests/test-codex-config-prune.sh (falsification proof) (rc=1)
PASS: dry-run does not write
PASS: dead-path surviving table count
PASS: reported count matches observed drop
PASS: backup preserves original bytes and permissions
PASS: live bytes and all comments retained
PASS: second prune is a byte-identical no-op
FAIL: identical live aliases collapse to physical entry 
PASS: conflicting live policies untouched
PASS: first write registers one canonical path
PASS: second-write table count
PASS: writer leaves existing alias policy untouched
PASS: concurrent writers produce one table
PASS: writer escapes TOML path keys
PASS: multiline strings and nested tables
PASS: invalid input fails without changing config
PASS: unsupported inline layout fails without changing config
test-codex-config-prune: 15 passed, 1 failed

verdict: RED
