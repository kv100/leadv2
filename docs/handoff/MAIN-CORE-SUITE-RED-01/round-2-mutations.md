# Mutation-pair (negative control) catalog for MAIN-CORE-SUITE-RED-01 round 2.
# Each entry: suite fixed this round, the exact mutation that proves the
# suite's assertion has teeth, and the observed red/green result.

- suite: plugins/leadv2/scripts/tests/test-idle-lead-guard.sh
  case: "case 10: hooks.json registration assertion"
  mutation: >
    Re-add "leadv2-idle-lead-guard.sh" to hooks.json's Stop hooks array
    (the retired standalone hook ONE-LANE-WATCH-01 removed).
  expect_red: "case 10: registration assertion failed"
  expect_green_after_revert: "case 10: idle-lead-guard retired; promise-guard kept; lane-watch-v2 armed on both events"
  verified: true

- suite: plugins/leadv2/scripts/tests/test-injector-dedup.sh
  case: "multisession negative control (4th session cap)"
  mutation: >
    perl -0pi anchor "(others = [sess for sess in s[^\]]*\])" -> "${1}[:3]"
    on a copy of leadv2-user-prompt-context.sh, reintroducing the 3-session
    cap that drops a 4th session's blocked_by note. Anchor updated to match
    the multi-line comprehension TERMINAL-LANES-STILL-READ-AS-LIVE-01
    rewrote it into; a grep -q '\[:3\]' guard after the perl call now fails
    loudly if the anchor ever stops matching again.
  expect_red: "multisession negative-control red (cap reintroduced => 4th session lost)"
  expect_green_after_revert: "multisession: 4th session (note+blocked_by) reaches output"
  verified: true

- suite: plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh
  case: "C5-registered-arm-silent"
  mutation: >
    Suite's own built-in red-first pass: `git archive HEAD` of the
    committed (pre-fix) leadv2-dispatch-product-close.sh, run as pass 2/2.
  expect_red: "[TEST][pre-fix] FAIL C5-registered-arm-silent"
  expect_green_after_revert: "[TEST][post-fix] PASS C5-registered-arm-silent"
  verified: true

- suite: plugins/leadv2/scripts/tests/test-phase-precondition.sh
  case: "G3: REQUIRE_PHASES=0 no warn and spawns"
  mutation: >
    sed on the fixed glm-stub.sh fixture: printf '%s\n' "$handle" ->
    printf '%s/%s%s\n' "$RUNS" "$handle" "$handle" (reintroduces the
    doubled/prefixed launch envelope the stub used to emit).
  expect_red: "FAIL: G3: dispatch should exit 0 (got 4)"
  expect_green_after_revert: "pass=82 fail=0"
  verified: true
