# RECOVER-TWELVE-CONFLICTED-BRANCHES-01 — отчёт о слиянии 12 конфликтных веток

Worktree: `.claude/worktrees/RECOVER-TWELVE-CONFLICTED-BRANCHES-01` (ветка
`worktree-RECOVER-TWELVE-CONFLICTED-BRANCHES-01`). Возобновление после падения
предыдущего прогона: 6 веток были слиты до падения, 6 слиты этим прогоном.

## Сводка (13 строк таблицы брифа; 12 веток + PLUGIN-PAPERCUTS из примечания)

| Ветка | Исход | Коммит слияния |
|---|---|---|
| SMART-ARBITER-01 | слита (прошлый прогон) | b718c1ec |
| 6409fada | слита (прошлый прогон) | 06fbefa9 |
| ARBITER-ESTIMATES-BLIND-01 | слита (прошлый прогон) | e434a4c9 |
| 66d6209a | слита (прошлый прогон) | 1af7279e |
| 7c9da953 | слита (прошлый прогон) | 9496c0dc |
| DISPATCH-PHASE-DEADLOCK-01 | слита (прошлый прогон) | 3786789e |
| DARK-SUITES-UNREACHABLE-BY-RUNNER-01 | слита | 768796cc |
| agent-a4be34650195f2188 | слита (дифф пуст — см. ниже) | d131633a |
| CI-SUITES-ARE-MACOS-ONLY-01 | слита | 5187b58e |
| CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01 | слита | 5f2b02b0 |
| PHASE-BOOTSTRAP-ADMIT-02 | слита | (см. ниже) |
| PLUGIN-PAPERCUTS-01 | см. ниже | — |
| 5fa969ac | см. ниже | — |

(строки заполняются по мере завершения прогонов)

## Проверка симлинков

Восемь отслеживаемых симлинков `docs/leadv2/` (`.bus-offsets .bus.lock
.merge.lock active.yaml.lock bus.jsonl merge-queue.jsonl open-threads.md
questions`) проверены `-L` после КАЖДОГО слияния этого прогона; все OK.

## Детали разрешений (этот прогон)

## Codex effort wiring probe (dispatch-b7cc018f, 2026-09-05)

Findings — how effort reaches Codex on this tree (both paths verified in source):

1. **Worker arm** (dispatch-code → codex-task.sh): arbiter resolves effort from
   `router_v2.effort_matrix` (EFFORT-IS-NOT-WIRED-01, SMART-ARBITER-01),
   forwarded as `--effort` alongside `--tier`
   (`leadv2-dispatch-code.sh:5986-5990`). Wired.
2. **Lead session** (fanout → codex-session-runner): fanout exports
   `LEADV2_LEAD_EFFORT` from the classifier's `lead_effort`
   (`leadv2-fanout.sh:1194,1303`); the runner pins it as
   `-c model_reasoning_effort="$EFFORT"` on both fresh and resume
   (`leadv2-codex-session-runner.sh:474,492`). Wired. Unlike GLM
   (`_glm_effort_for_class`), codex has NO class→effort map — it rides the
   classifier default `medium` unless the arbiter's effort matrix feeds it.

Suite evidence (foreground runs):

- `test-glm-effort-wiring.sh`: was rc=1 (3 FAIL) — stale grep: the assertion
  demanded `effort=X mechanism=flag` contiguous, but DEEPTHINK-MODE-IS-NOT-
  WIRED-01 added `think=/think_source=` columns between them. Fixed the
  pattern (tail-anchored). Now **28/0, rc=0**.
- `test-codex-session-runner.sh`: was rc=1 (all runner cases red) —
  non-hermetic: `codex_spawn_gate` check 3 reads the HOST's real
  `~/.claude/state/leadv2/quota-cache/` when `LEADV2_QUOTA_LIVE/_CACHE_DIR/
  _CEILINGS` are unset (the lib's own comment says tests MUST set them).
  Reproduced live: `reason=threshold used=live` at codex 92%. Added the
  hermetic trio (same fixture pattern as test-codex-quota-guardrails.sh).
  Now **23/0, rc=0**.
- `test-effort-routing.sh`: rc=1 (7 PASS / 4 FAIL) — **pre-existing red on
  origin/main too** (A/B run in a detached main worktree: 4 PASS / ≥4 FAIL,
  incl. arbiter-level case 1 failing there). The 4 dispatch-level reds
  (codex/sonnet argv not captured, glm effort-drop premise obsolete after
  GLM-EFFICIENCY-01, decision-line shape) are suite-expectation drift, not a
  regression from this branch's merges — the merges actually fixed 3 of
  main's reds. Left as-is (separate repair task).

A/B main worktree removed after the run.


### PLUGIN-PAPERCUTS-01 Resolution

After analyzing the code and the deliberate design choice documented in the commit history, I conclude that **main is correct**: an unknown-reader pass must never stop the beat loop.

**Why Main's Decision is Correct**

The commit message explicitly states:
> "That removal was deliberate: a loop that dies on reader-error passes goes quiet, and the silence this loop exists to prevent comes back. So `P1` asserts a contract that main removed on purpose."

The fundamental purpose of the single-lead beat loop is to prevent founder-blindness - ensuring that when at least one lane is live, the founder receives regular status updates via `founder-status.md`.

If the loop were to stop on reader errors (when the heartbeat script fails to execute or returns unparseable output), we would create exactly the failure mode the loop is designed to prevent:
- Monitor becomes blind (heartbeat errors)
- Loop stops beating 
- No updates to `founder-status.md`
- Founder sees no new data and assumes everything is fine
- Founder's blindness persists and worsens

This is precisely what fix-round H4 sought to address, and why the `LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX` stop was intentionally removed.

**Addressing Resource Concerns**

While the lane's concern about unbounded loops in test/dead environments is valid, main's version already includes appropriate bounds:
1. **Hard lifetime cap** (`LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S`, default 24 hours)
2. **Project root monitoring** (exits if project root disappears)
3. **Owner-based self-reap** from WATCHER-LIFECYCLE-LEAK-01 (when explicitly configured)

These bounds ensure that even in permanently broken environments, the loop will not run indefinitely - it will either:
- Exit when the project root is removed (test fixture teardown)
- Self-reap when an owner process dies (if owner is explicitly set)
- Hit the 24-hour lifetime cap as a final safety net

The 24-hour cap is a reasonable balance: long enough to avoid prematurely stopping during transient monitor issues, but short enough to prevent permanent resource leaks in abandoned test environments.

**The Flaw in P1's Assumption**

Test case P1 assumes that the loop should stop after `LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX` consecutive reader-error passes. This assumption is incorrect because:
- It confuses "reader error" (temporary monitor blindness) with "permanently dead environment"
- Implementing this stop would re-introduce the founder-blindness failure
- The existing lifetime cap and project-root monitoring already provide sufficient bounds for test scenarios

**Test Replacement Strategy**

Since P1 tests a retired contract, it must be replaced with a test case that validates main's actual contract:
> "The loop stops on ZERO_MAX consecutive REAL zeros (where zero means heartbeat successfully parsed and reported zero live lanes), and does NOT stop on reader errors."

The replacement test will:
1. Verify the loop stops when presented with ZERO_MAX consecutive real zero lane counts
2. Verify the loop continues running when presented with reader errors (unknown passes)
3. Demonstrate that mutating the zero-stop rule (e.g., setting ZERO_MAX=0 or removing zero-stop logic) causes the test to fail

This approach maintains the backlog's purpose of preventing regressions while aligning with main's correct design decision.