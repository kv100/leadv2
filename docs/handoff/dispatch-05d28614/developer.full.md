verdict: APPROVE
next_action: review_round_2

# PPC-G8: fix the integration test harness timeout

## Root cause

`plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh` is the phase-8 wrapper that runs the
canonical integration/e2e entrypoint (`tests/run-all.sh --scope changed`, resolved via
`leadv2-e2e-entrypoint.sh`) before writing the sentinel `leadv2-phase8-assert.sh`'s A7 check
reads. The invocation at the old line 173:

```bash
{ printf 'e2e-root: %s\n' "${_p8_e2e_root}"; ( cd "${_p8_e2e_root}" && bash -c "${e2e_cmd} --scope changed" ); } > "$LOG" 2>&1 || rc=$?
```

ran the whole integration suite with **no deadline**. `tests/run-all.sh` itself (read in
full) also has no per-suite timeout — each `bash "${suite}"` inside its loop runs unbounded.
A hung suite therefore blocked this gate script forever, and since the gate holds an
`flock` on `/tmp/leadv2-e2e-gate-<task_id>.lock` for its whole run, a hang here also
permanently starved any other invocation for the same task_id.

This matches the repo's own memory note that `tests/run-all.sh --scope changed` for
core-offline alone already runs >10min in the worst case — a suite regression pushing it to
"never returns" was one incident away.

## Fix

`plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh` (committed 26c121f):

1. Sources `lib/leadv2-builder-selfcheck.sh` for its already-tested, portable
   `_lv2_selfcheck_timeout_run <timeout_s> <logfile> -- <cmd...>` helper (gtimeout, else
   timeout(1), else a background sleep+kill process-group watcher that reports rc=124 like
   timeout(1) would — stock macOS ships neither `gtimeout` nor `timeout`). Reused verbatim
   rather than reimplemented, per repo convention (this exact wrapper already backs
   `leadv2-builder-selfcheck.sh`'s three call sites).
2. Wraps the e2e run:
   ```bash
   E2E_TIMEOUT_S="${LEADV2_PHASE8_E2E_TIMEOUT_S:-900}"
   { printf 'e2e-root: %s\n' "${_p8_e2e_root}"; ( cd "${_p8_e2e_root}" && _lv2_selfcheck_timeout_run "${E2E_TIMEOUT_S}" /dev/stdout -- bash -c "${e2e_cmd} --scope changed" ); } > "$LOG" 2>&1 || rc=$?
   if [[ $rc -eq 124 ]]; then
     echo "leadv2-phase8-e2e-gate: e2e suite TIMED OUT after ${E2E_TIMEOUT_S}s" >> "$LOG"
   fi
   ```
   Default 900s (matches `LEADV2_BUILDER_SELFCHECK_TIMEOUT_S`'s existing default),
   overridable via `LEADV2_PHASE8_E2E_TIMEOUT_S`. rc=124 falls through the existing FAIL
   path unchanged (sentinel removed, decision journaled, tail of log echoed) — no new
   control-flow branch needed since the existing `[[ $rc -eq 0 ]]` / foreign-failure /
   fail-closed logic already treats any non-zero rc correctly; the added `if` only makes
   the timeout cause visible in the log rather than looking like an ordinary suite failure.

## Verification

- `bash -n plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh` → SYNTAX_OK.
- Isolated smoke test of the sourced helper: `_lv2_selfcheck_timeout_run 2 /dev/stdout -- bash -c 'sleep 10; echo done'` returned `rc=124` in 2.03s wall time (would have been 10s+ without the wrapper). Confirms the deadline actually fires and does not wait for the full hung command.
- `plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh` (the only suite that exercises
  this script): reds both on my changed file and on `git show HEAD:...` restored to a temp
  copy and run standalone — identical failure signature (`offending=.claude/commands/leadv2.md`,
  rc=5 everywhere) on both. This is a pre-existing red driven by the worktree's own ambient
  dirty state (`.claude/commands/` untracked, `docs/leadv2/*` modified — present before this
  session started, per initial `git status`), not a regression introduced by this change.
  Confirmed by running the baseline (unmodified `leadv2-phase8-e2e-gate.sh`) through the same
  test and getting the same 1 passed / 10 failed breakdown.

## What I deliberately left alone

- `tests/run-all.sh` itself still has no per-suite timeout in its own loop
  (`for suite in "${SUITES[@]}"; do ... bash "${suite}" ...`). The mission's timeout symptom
  is specifically the phase8 e2e *gate* hanging, and that is now bounded regardless of which
  suite inside `run-all.sh` misbehaves. Adding a nested per-suite timeout inside
  `run-all.sh` too would be a second, independent change outside this mission's scope —
  flagging it as a possible follow-up, not doing it.
- Did not touch `test-e2e-foreign-failure.sh`'s pre-existing red; per repo policy, an
  environment-sensitive failure is a finding, not a test bug to silently fix under this task.

DELIVERABLE_COMPLETE
