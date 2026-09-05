# builder selfcheck — dispatch-fe034e50
generated_at: 2026-08-24T16:17:58Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/fe034e50
diff_hash: af695c410dd46c5871315b60f1d186a57269dfa69ab80c30c268b504fbbef027
checks: 7   failed: 1   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh | 0 |
| bash -n | /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/leadv2-fanout.sh | 0 |
| bash -n | /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh | 0 |
| bash -n | /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh | 0 |
| suites | - | SKIP (no_matching_suite) |
| falsification | /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh | ADVISORY (no_falsification_marker) |
| falsification | /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh | FAIL (test_failed:rc=1) |

## raw — /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh (falsification proof) (rc=1)
PASS: (a) park row written before sonnet fallback worker spawn (ordering holds)
PASS: (a) poison fence held
PASS: (b) glm-deferred --list prints the parked sig8
PASS: (b) glm-deferred --list prints 'no deferred glm tasks' when empty
PASS: (c) two credit-empty computations within 24h emit exactly ONE journal line
PASS: (c) a third computation after the stamp ages past 24h emits a second journal line
FAIL: (d) expected sonnet-fallback line missing from rendered artifact -- content=2026-08-20T00:00:00Z [BROAD_STATUS] dispatched=1
⚠ ДОСКА ПУСТА — ничего не выполняется, 0 мин

16:17 · посты н/д · комменты н/д · реплаи н/д

| Линия | Что делает | Состояние |
|---|---|---|
| (живых линий нет) | — | — |

С прошлого удара: +0 линии подняты, 0 закрыто.
Решений не ждёт.
(скрыто: 6 строк очереди — docs/leadv2/founder-status-full.md)
[BROAD_STATUS_END]
PASS: (d) a day with no fallback renders no sonnet-fallback line
PASS: (e) shared-cache double refusal: count=2, both distinct sig8s recorded
PASS: (e) park queue holds a row for both distinct sig8s
PASS: (e) run 2's park row carries reason=glm_refused_quota_precheck (benched, never attempted)
PASS: (e2) a repeat bump for an already-present sig8 is a no-op (count stays 1)
PASS: (g) a parked row whose sig8 already landed is reaped, not retried
PASS: (h) a parked row with no usable mission is skipped and stays in the queue (H3)
PASS: (i) a failed retry dispatch leaves the row pending
PASS: (f) real retry-all: new dispatch observed (marker file), 'retried as=', old sig8 reaped from --list
PASS: poison fence held across the suite

================================================
  glm-deferred-ladder suite: FAIL=1
================================================

verdict: RED
