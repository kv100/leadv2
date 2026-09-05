# builder selfcheck — dispatch-74658fef
generated_at: 2026-08-21T05:02:49Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/74658fef
diff_hash: f97c6a9eee9fa7e0a3140e4d17ab49e2c17e551db39d8f274e8ac72132b69ef8
checks: 8   failed: 3   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-core-offline-lock-01.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-core-offline-shards-01.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-core-offline-tmpdir-01.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/74658fef/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-core-offline-lock-01.sh | FAIL (falsification_missing) |
| falsification | plugins/leadv2/scripts/tests/test-core-offline-shards-01.sh | FAIL (falsification_missing) |
| falsification | plugins/leadv2/scripts/tests/test-core-offline-tmpdir-01.sh | FAIL (falsification_missing) |

## raw — plugins/leadv2/scripts/tests/test-core-offline-lock-01.sh (falsification proof) (rc=0)
[LOCK-01] case (a)/(b): held lock -> bounded wait times out
[LOCK-01]   (a)/(b) bounded wait times out with journaled lines ✓
[LOCK-01] case (c): wait long enough to outlast the holder
[LOCK-01]   (c) waited then acquired ✓ (elapsed 1s)
[LOCK-01] case (d): kill-switch bypasses a held lock
[LOCK-01]   (d) kill-switch bypassed the held lock ✓
[LOCK-01] pass=3 fail=0

## raw — plugins/leadv2/scripts/tests/test-core-offline-shards-01.sh (falsification proof) (rc=0)
[SHARDS-01] total suites in SUITE_DEFS = 60
[SHARDS-01]   shards=1: 60 lines, 60 unique indices, no out-of-range shard ✓
[SHARDS-01]   shards=2: 60 lines, 60 unique indices, no out-of-range shard ✓
[SHARDS-01]   shards=3: 60 lines, 60 unique indices, no out-of-range shard ✓
[SHARDS-01]   shards=4: 60 lines, 60 unique indices, no out-of-range shard ✓
[SHARDS-01]   shards=5: 60 lines, 60 unique indices, no out-of-range shard ✓
[SHARDS-01]   shards=7: 60 lines, 60 unique indices, no out-of-range shard ✓
[SHARDS-01] case: default shard count is sane (1..4)
[SHARDS-01]   default resolves to 4 shards ✓
[SHARDS-01] pass=8 fail=0

## raw — plugins/leadv2/scripts/tests/test-core-offline-tmpdir-01.sh (falsification proof) (rc=0)
[TMPDIR-01] case: two suites each see a distinct, private TMPDIR
[TMPDIR-01]   distinct private TMPDIRs: seen1=/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//lv2-caller-tmp.Y6Y4Lr/core-offline-run.5xxt8k/suite.rtE53V seen2=/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//lv2-caller-tmp.Y6Y4Lr/core-offline-run.5xxt8k/suite.0CsFOk ✓
[TMPDIR-01] pass=1 fail=0

verdict: RED
