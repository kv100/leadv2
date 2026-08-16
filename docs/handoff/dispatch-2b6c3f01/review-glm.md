⚠ claude.ai connectors are disabled because ANTHROPIC_API_KEY or another auth source is set and takes precedence over your claude.ai login · Unset it to load your organization's connectors
"glm-5.2" is not a model this version of Claude Code recognizes, so auto-compact will keep this session within 200k tokens (the context window it assumes). If the model accepts more, append [1m] to the model name for 1M, or set CLAUDE_CODE_MAX_CONTEXT_TOKENS to its real window; to make it recognized, map it in the modelOverrides setting or update Claude Code; CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1 restores the previous wait-for-the-API behavior.
[claude-code:unrecognized_model] {"model":"glm-5.2","query_source":"sdk"}
REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=1 medium=1 low=1

FINDING: severity=High file=plugins/leadv2/scripts/tests/test-broad-status-duty.sh line=184 dimension=correctness desc=`timeout N loop_env ...` tries to exec a shell FUNCTION (`loop_env`) as a binary → rc 127 instantly; the loop never runs in T3/T4/T7, those assertions fail, and T6 (kill-switch) passes vacuously — the suite ships red (15/24) and its central claims (dispatch-before-report, session-death survival, cron-skip visibility, rollback-whole) are untested.

FINDING: severity=High file=plugins/leadv2/scripts/leadv2-supervise-loop.sh line=160 dimension=correctness desc=New "beat-cron install skipped: crontab unavailable" log line is unreachable in any fresh checkout: `leadv2-supervise-watchdog.sh` is committed 100644 (non-exec), so `_install_beat_cron` returns at `[[ -x "$WATCHDOG_SH" ]]` (line 154) before the crontab check — the "visible gap, not a silent one" claim is false in practice, and T7 can never pass even after fixing the timeout bug. (Pre-existing 644 mode on main, but this diff builds a visibility guarantee on top of the dead path.)

## Detail

**High #1 — test harness cannot run the loop.** `loop_env` is a bash function; `timeout` (external binary) execs it by name → "failed to run command" rc 127, swallowed by `|| true`. Affected call sites: `test-broad-status-duty.sh:184` (T3), `:206` (T4 loop), `:215` (T4 `--ensure`), `:223` (T4 watchdog), `:247` (T6), `:259` (T7). Proof: `timeout 10 foo_env` → `timeout: failed to run command` rc=127; identical one-cycle fixture run via `timeout N env ...` succeeds. Consequences: suite exits 1 as committed; T6's "no beat, no ready-line" pass is vacuous (nothing ran), so the kill-switch/"rollback cannot half-work" property the diff's comments lean on is unverified by the suite. Fix: invoke as `loop_env timeout N bash "$LOOP_SH"` (function wraps timeout) or have `loop_env` use a plain `env` executable and prefix with `timeout` only via that.

**High #2 — cron-skip visibility built on a dead branch.** Verified: `git ls-files -s` → watchdog mode `100644` (also on `main`); in this checkout `[[ -x ]]` is false, so `_install_beat_cron` returns before line 160 ever executes. My reproduction with `CRONTAB_BIN=/nonexistent-crontab` produced no skip line in the log. Either commit the watchdog +x or reorder/log the `-x` guard failure too.

**Medium (counted in header):** the diff's own header claims test 4 is "the demonstration, not a claim" of session-death survival — nothing of the sort runs, and 9 assertions of a newly added suite fail on `main`-clean code. False coverage claims are worse than no coverage in a mutation-gated repo.

**Low:** the loop now appends the pump's full stderr (`check complete: …`) to `supervise-loop.log` every beat — log noise only (no `URGENT` substring, so no spurious founder wake).

## What is verified GOOD (production code)

I reproduced the full beat path end-to-end in a hermetic fixture (stubbed collector/claude/pump, `MAX_CYCLES=1`, `PULSE_ON_START=1`): pump ran before `founder-status.md` was written; block header carries `dispatched=2`; exactly one `[SUPERVISE-URGENT] BROAD_STATUS_READY … rows=0 dispatched=2` line passes a real `grep URGENT`; dedupe semantics correct against the actual `leadv2-alarm-dedupe.sh` (`leadv2_alarm_transition` 0=fire/1=suppress, verified same-beat suppression, new-beat fire, lib-absent pass-through — T1/T2/T5/T8 pass live); `dispatched` parsing matches the real pump's stderr line format (`[leadv2-backlog-pump] check complete: … dispatched=N`); degraded paths emit `degraded=1` rather than silence; kill-switch logic confirmed by code read (beat and ready-line share one branch). Docs/hooks wording surfaces are consistent (T8 passes). No pre-existing test references broad-status, so no regression surface there.

**Report:** reviewed `/tmp/pulse.diff` only; no files changed, nothing staged or committed (review-only session — NOT-COMMITTED by design). Test evidence: new suite run — 15 passed / 9 failed (output above); my independent fixture run of the same production path — all green.
