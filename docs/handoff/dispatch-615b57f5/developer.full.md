# BURN-GOVERNOR-01 fix-round-1 — developer report

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b` (branch `worktree-b22dc98b`).
Commit: `3d4d575` — "fix(b22dc98b): BURN-GOVERNOR-01 fix-round-1 — hermetic tests, warn text, bounded sqlite read". 53 files changed, 252 insertions(+), 3 deletions(-).

Implemented the architect prepass's mechanism-closed design verbatim (§2.1–§2.3), not the mission's original under-described framing, since the design explicitly wins on conflict.

## What changed

**Finding 1 (test hermeticity).** Added `export LEADV2_BURN_GOVERNOR=0` (with the design's 2-line comment) right after the `set -uo pipefail` line in all 51 named test files under `plugins/leadv2/scripts/tests/`. `export`, not a bare assignment, per the design's §0.2 finding that `test-glm-deferred-ladder.sh` subtest (f) triggers the burn gate in a **grandchild** process (`glm-deferred --retry-all` → child dispatch → `cmd_resolve` → `_burn_gate`). `test-burn-governor.sh` was correctly excluded and left untouched. Verified all 51 files now carry the export and remain `bash -n` clean.

**Finding 2 (compact-trigger warn text).** `plugins/leadv2/hooks/leadv2-compact-trigger.sh:329`, `emergency)` arm's `MSG` now reads:
```
[COMPACT_NOW] Сессия ПРЕВЫСИЛА аварийный порог контекста: ~${EST_K}K токенов (порог ${EMERG_T} токенов, файл ${KB}KB${TASK_NOTE}). Каждый следующий ход стоит ${EST_K}K input. Авто-/compact сейчас НЕ включён (по умолчанию OFF): чтобы хук сам блокировал ход и вызывал /compact, экспортируй LEADV2_COMPACT_INTERACTIVE_BLOCK=1. Скажи фаундеру одной строкой: 'Нужен /compact — контекст ${EST_K}K токенов.' Потом жди.
```
Confirmed `EMERG_T` is in scope (assigned unconditionally at line 228, `${LEADV2_COMPACT_EMERGENCY_TOKENS:-650000}`). No change to `LEADV2_COMPACT_INTERACTIVE_BLOCK` default (stays `${…:-0}`, i.e. OFF).

**Finding 3 (bounded sqlite read).** `plugins/leadv2/scripts/leadv2-burn-governor.sh`: added `_LBG_SQL_TIMEOUT_S=5` and `_lbg_bounded_sqlite()` (gtimeout → timeout → portable detached-watcher fallback, mirroring `lib/leadv2-builder-selfcheck.sh:_lv2_selfcheck_timeout_run`'s documented fix for the watcher-inherits-the-pipe trap). Replaced the direct `sqlite3 -cmd '.timeout 2000' …` call with `_lbg_bounded_sqlite "${db}" "…"`. On timeout the helper discards the partial output and returns rc 124; `burn24h` ends up empty and falls through the **existing** `no_telemetry` guard — no new branch, no new exit code, no change to the stdout contract that the two independent `sed` parsers (in `leadv2-dispatch-code.sh` C1 and C2) depend on.

## Verification (raw output)

`bash -n` on every touched file — clean:
```
FAIL=0
```
(one file, `test-router-v2-retired-arm.sh`, initially failed `bash -n` — see "Census correction" below; clean after that fix.)

`test-burn-governor.sh` — 25/25, unchanged:
```
=== 25 passed, 0 failed ===
```

`test-glm-deferred-ladder.sh` — subtest (f) now clean:
```
PASS: (f) real retry-all: new dispatch observed (marker file), 'retried as=', old sig8 reaped from --list
```
Full suite: `FAIL=1`, but the only failure is subtest (d)'s first assertion (`expected sonnet-fallback line missing from rendered artifact`), which fails **identically on an unmodified copy of the test file run against HEAD** (verified by running `git show HEAD:...test-glm-deferred-ladder.sh` standalone before any of my edits — same content mismatch, tied to a hardcoded fixture date `2026-08-20T00:00:00Z` now in the past relative to today `2026-08-23`). Not touched — out of the three-finding scope and not something these fixes could affect either way. On the baseline (no export) run, subtest (f) instead fails with:
```
FAIL: (f) retry-all did not spawn a new dispatch for the parked mission -- out=retry_failed ffffffff rc=6 [leadv2-dispatch-code] ⛔ BURN GATE: 24h burn 1968472385 >= hard cap 1300000000 — lane refused, task parked
```
confirming the fix.

## Census correction (PREPASS-MECHANISM-CLOSURE-01)

Two things the architect's census did not anticipate, found while implementing:

1. **`test-router-v2-retired-arm.sh` had a pre-existing, unrelated `bash -n` failure on HEAD.** Line 339 (a `pass` message) ended `')"`  instead of `')'` — an unclosed single quote. Confirmed present before any of my changes (`git show HEAD:...` piped to `bash -n` fails identically). This is one of the 51 files LANE_WRITES already scopes me to touch (for finding 1), and the repo's commit hook runs `bash -n` on staged files and blocks the commit until it's clean. I fixed the one-character quoting bug (`"` → `'`) rather than work around the hook, since: (a) it's a trivial, unambiguous correctness fix restoring what the message clearly intended, (b) it's within a file I already write to, (c) `--no-verify` is disallowed absent explicit request. Diff is exactly one character.

2. **Fixing that syntax error let `test-router-v2-retired-arm.sh` run further than it ever has, and it now fails a NEW assertion: "poison fence".** Before finding 1's export, every T1–T4 subtest in this suite died early on the real burn gate's hard-cap refusal (`rc=6`, same class of failure as (f)) — so the suite's poison-fence check (asserting no real, un-stubbed provider binary was invoked) never actually got exercised end-to-end. With the burn gate disabled for tests, T1–T5 all now pass, but the terminal poison-fence assertion fails:
   ```
   FAIL: poison fence -- a POISON marker appears in captured output -- a real provider bin was invoked
   ```
   This means the suite's stub/poison harness has an incomplete fence — a real provider binary is reachable in at least one of T1–T5's code paths once dispatch is allowed to proceed past the burn gate. This is a **pre-existing test-fixture gap that finding 1 exposes rather than causes** — it was always there, just unreachable because the burn gate always failed first on this host. I did **not** attempt to fix it: it is not one of the three named findings, fixing it would mean auditing this suite's stub wiring (scope creep explicitly forbidden by the mission), and I have no visibility into whether the intended fix is "add another poison stub" or "the test's provider-selection setup itself is wrong" without deeper investigation. Flagging for lead/review triage — this may warrant its own follow-up task.

No other census mismatches found. `test-plan-run-contract.sh` and `test-status-surface.sh` both contain the string `env -i` (design claimed no dispatch-invoking file in the 51 had one) — checked both: `test-status-surface.sh`'s hit is inside a comment, not a real invocation; `test-plan-run-contract.sh`'s two real `env -i` calls invoke `leadv2-plan-run.sh` in `--mode plan`/`--mode prepass`, never `leadv2-dispatch-code.sh` (that file's only reference to `leadv2-dispatch-code.sh` is a comment, not an execution) — so the export's non-propagation into that `env -i` child is irrelevant; no gap.

## Non-goals honored

Findings 4/5 (`cmd_glm_deferred` retry-all TOCTOU, `founder_task_id` drop) untouched. `LEADV2_COMPACT_INTERACTIVE_BLOCK` default untouched (still `0`). `run-core-offline.sh` untouched. No shared test preamble introduced. No change to the governor's stdout contract, thresholds, or always-exit-0 property. No files under `docs/` touched by this task's own scope (aside from this handoff).

## Files changed (53)

`plugins/leadv2/scripts/leadv2-burn-governor.sh`, `plugins/leadv2/hooks/leadv2-compact-trigger.sh`, all 51 test files listed in the design's §3 (including `test-router-v2-retired-arm.sh`, which also carries the one-character census-correction fix).

DELIVERABLE_COMPLETE
