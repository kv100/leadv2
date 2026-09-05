# builder selfcheck — dispatch-168e6ff1
generated_at: 2026-09-01T19:10:29Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PLUGIN-PAPERCUTS-01
diff_hash: fad0f9d15b3a9878afe2bf2860152b12dd6b11606c97d05e676a037bd9d71df2
checks: 2   failed: 1   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-phase-precondition.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PLUGIN-PAPERCUTS-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition.sh | FAIL (test_failed:rc=143) |

## raw — plugins/leadv2/scripts/tests/test-phase-precondition.sh (falsification proof) (rc=143)
test: Standard missing plan/gate1
test: waiver review refused
test: waiver close refused
test: waiver empty reason
test: phases.yaml version 2 rejected
test: phases.yaml removal key rejected
test: phases.yaml union adds e2e to Light
test: waiver plan accepted
missing=classify,gate1,build,test,review,live_verify,close
test: waiver plan not allowed
test: no phases.yaml → base table

test: G1 REQUIRE_PHASES unset warns and spawns
  FAIL: G1: journal should contain phase_precondition_warn
test: G2 REQUIRE_PHASES=1 refuses and does not spawn
  FAIL: G2: dispatch should exit 3 (got 0)
  FAIL: G2: spawn sentinel should NOT exist
  FAIL: G2: journal should contain phase_precondition_refused
test: G3 REQUIRE_PHASES=0 no warn and spawns
test: G4 phase-waiver review refused in modes unset/1 (0 proceeds, see G8)
test: G5 forged review diff_hash rejected
test: G6 artifact integrity rejected
test: G7 review provenance — de-self-attestation
test: G8 REQUIRE_PHASES=0 proceeds despite broken phases.yaml + refused waiver

verdict: RED
