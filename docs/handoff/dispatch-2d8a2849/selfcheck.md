# builder selfcheck — dispatch-2d8a2849
generated_at: 2026-08-23T06:22:13Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2d8a2849
diff_hash: 6b5b8f63c03b8a760382a7070301d59d5849a11fc58f7d9dece478ca3016be7c
checks: 7   failed: 2   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2d8a2849/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh (falsification proof) (rc=1)
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: Case 1: exits 5 (falls through to the existing empty_diff terminal)
[TEST] PASS: Case 1: absent stream is NOT classified as arm_produced_nothing
[TEST] PASS: Case 1: ledger row is no_work/empty_diff (existing path, not the silent-arm path)
[TEST] PASS: Case 1: no arm_advance decision for an absent stream
[TEST] PASS: Case 2: review-gate.md not arm_produced_nothing (assistant events present)
[TEST] FAIL: Case 2: expected landed, got -- {"ts":"2026-08-23T06:22:07Z","task_sig":"c2c2c2c2","founder_task_id":"","task_id":"","terminal":"refused","cause":"unscoped_lane_work","evidence":"lane_root=lane dirty=1 offending=newfile.txt","commit":"none","deliverable":"unknown","attempt":"c2c2c2c2-1787466127-70170"} (rc=5, out=[leadv2-dispatch-product-close] product_close task=c2c2c2c2 worker_liveness=unknown author=glm handle=- action=proceed_legacy
[leadv2-dispatch-product-close] review_gate task=c2c2c2c2 status=blocked reason=unscoped_lane_work terminal=refused cause=unscoped_lane_work offending=newfile.txt)
[TEST] PASS: Case 3: fresh (within growth window) stream falls through as NOT silent
[TEST] PASS: Case 3: existing empty-diff path still produces reason: no_work
[TEST] PASS: Case 4: stale stream + clean worktree classified as silent
[TEST] PASS: Case 5: no arm_produced_nothing when arm not registered (empty_diff path owns it)
[TEST] PASS: Case 5: no arm_advance decision without arm registration

[TEST] 11 passed, 1 failed
FAIL: Case 2: expected landed, got -- {"ts":"2026-08-23T06:22:07Z","task_sig":"c2c2c2c2","founder_task_id":"","task_id":"","terminal":"refused","cause":"unscoped_lane_work","evidence":"lane_root=lane dirty=1 offending=newfile.txt","commit":"none","deliverable":"unknown","attempt":"c2c2c2c2-1787466127-70170"} (rc=5, out=[leadv2-dispatch-product-close] product_close task=c2c2c2c2 worker_liveness=unknown author=glm handle=- action=proceed_legacy
[leadv2-dispatch-product-close] review_gate task=c2c2c2c2 status=blocked reason=unscoped_lane_work terminal=refused cause=unscoped_lane_work offending=newfile.txt)

## raw — plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh (falsification proof) (rc=1)
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] FAIL: Case A: a lane with a commit ahead of base was classified arm_produced_nothing -- out=[leadv2-dispatch-product-close] product_close task=caaaaaaa worker_liveness=unknown author=glm handle=- action=proceed_legacy
[leadv2-dispatch-product-close] review_gate task=caaaaaaa status=blocked reason=arm_produced_nothing terminal=no_work cause=arm_produced_nothing arm=glm
[leadv2-dispatch-product-close] arm_advance_skipped task=caaaaaaa arm=glm reason=kill_switch
[TEST] FAIL: Case A: arm_advance decision emitted for a lane that produced a commit -- out=[leadv2-dispatch-product-close] product_close task=caaaaaaa worker_liveness=unknown author=glm handle=- action=proceed_legacy
[leadv2-dispatch-product-close] review_gate task=caaaaaaa status=blocked reason=arm_produced_nothing terminal=no_work cause=arm_produced_nothing arm=glm
[leadv2-dispatch-product-close] arm_advance_skipped task=caaaaaaa arm=glm reason=kill_switch
[TEST] PASS: Case B: absent stream is NOT classified arm_produced_nothing
[TEST] PASS: Case C: fresh stream is NOT classified arm_produced_nothing
[TEST] PASS: Case D: genuinely silent arm still classified arm_produced_nothing
[TEST] PASS: Case D: ledger row is no_work/arm_produced_nothing
[TEST] PASS: Case D: exactly one arm_advance decision line
[TEST] PASS: Case D: .arm-advanced-glm marker present

[TEST] 7 passed, 2 failed
FAIL: Case A: a lane with a commit ahead of base was classified arm_produced_nothing -- out=[leadv2-dispatch-product-close] product_close task=caaaaaaa worker_liveness=unknown author=glm handle=- action=proceed_legacy
[leadv2-dispatch-product-close] review_gate task=caaaaaaa status=blocked reason=arm_produced_nothing terminal=no_work cause=arm_produced_nothing arm=glm
[leadv2-dispatch-product-close] arm_advance_skipped task=caaaaaaa arm=glm reason=kill_switch
FAIL: Case A: arm_advance decision emitted for a lane that produced a commit -- out=[leadv2-dispatch-product-close] product_close task=caaaaaaa worker_liveness=unknown author=glm handle=- action=proceed_legacy
[leadv2-dispatch-product-close] review_gate task=caaaaaaa status=blocked reason=arm_produced_nothing terminal=no_work cause=arm_produced_nothing arm=glm
[leadv2-dispatch-product-close] arm_advance_skipped task=caaaaaaa arm=glm reason=kill_switch

verdict: RED
