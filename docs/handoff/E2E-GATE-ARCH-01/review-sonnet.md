LABEL=critic-dispatch-E2E-GATE-ARCH-01-review-1786622340 SESSION_ID=2df0831d-c45a-4168-8f80-2c04ae200b37
--- body from: docs/handoff/dispatch-E2E-GATE-ARCH-01-review/critic.full.md ---
REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=1 high=0 medium=1 low=1
FINDING: severity=Critical file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=1642 dimension=correctness desc=_lv2_e2e_release_lock only releases the mkdir-fallback lock; for the flock path it does nothing, so fd 9 (held via `exec 9>"${_lv2_e2e_lock}"` at line 1652, locked at line 1653) stays open and locked for the rest of the top-level product-close.sh process, not just for the duration of the e2e run

## Review scope
Diff reviewed: docs/handoff/E2E-GATE-ARCH-01/build-attempt-2.diff (not yet applied to working tree; line numbers below computed by walking the diff hunks against the stated `+` target line of `@@ -1599,7 +1599,108 @@`).

Two hunks:
1. plugins/leadv2/scripts/leadv2-dispatch-product-close.sh — adds a global flock/mkdir lock around the e2e gate invocation.
2. plugins/leadv2/scripts/tests/test-e2e-gate-arch-01.sh (new) — 5 behavioural cases (a–e).

## Critical

**file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=1642 (function def), triggered from call sites at line=1684 and line=1697**

```
1642 +  _lv2_e2e_release_lock() {
1643 +    if [[ "${_lv2_e2e_lock_kind}" == "mkdir" ]]; then
1644 +      rm -f -- "${_lv2_e2e_lock_dir}/pid" 2>/dev/null || true
1645 +      rmdir "${_lv2_e2e_lock_dir}" 2>/dev/null || true
1646 +    fi
1647 +  }
```

`_lv2_e2e_acquire_lock` (line 1648) takes the flock path via:
```
1652 +      exec 9>"${_lv2_e2e_lock}" || return 2
1653 +      flock -x -w "${_wait}" 9 && { _lv2_e2e_lock_kind="flock"; return 0; }
```
`exec 9>...` is run directly in the top-level script (these are ordinary function calls, not command substitutions or subshells), so fd 9 and its flock persist in the *calling process* — i.e. the rest of `leadv2-dispatch-product-close.sh`, not a subshell scoped to the gate. `_lv2_e2e_release_lock` never does `exec 9>&-` or `flock -u 9` for the `flock` kind — it is a complete no-op in that branch. The lock is therefore held until the whole dispatch-product-close.sh process exits, not released when the e2e run finishes.

**Failure scenario:** this script is `leadv2-dispatch-product-close.sh` — it keeps doing work after the e2e gate block (ledger writes, ownership/ ownership-ledger/deploy-adjacent logic per the surrounding "GATE-FOREIGN-FAILURE-01" comment visible right after this hunk). On a machine with `flock` available (Linux dev/CI boxes, and any macOS box with flock installed — the fallback only triggers when flock is genuinely absent), every lane that successfully acquires the lock will hold it for its *entire remaining dispatch-close run*, not just for the e2e suite window. A second lane's gate will then queue for that whole duration and can hit the 300s `LEADV2_E2E_GATE_LOCK_TIMEOUT`, park as `e2e_infra`/`e2e_gate_lock_timeout`, and require a manual/automatic retry — i.e. the fix reduces true e2e/e2e contention flakes but introduces a new, larger class of false `e2e_infra` parks under any real multi-lane load, directly working against the stated goal ("only one gate runs at a time... A gate must never run unlocked", comment at top of the hunk, not "only one dispatch pipeline runs at a time").

**Why the test suite (case b) doesn't catch it:** case (b) runs two full `product-close.sh` invocations back-to-back with almost no post-gate work, so both processes exit (releasing fd 9 implicitly) within roughly one second of the gate finishing. The test can't distinguish "released after gate" from "released at process exit" because in the test harness those two events are nearly simultaneous. In production, with real deploy/close work after the gate, the two diverge — that gap is exactly the untested behavior that breaks.

**Required fix:** in `_lv2_e2e_release_lock`, add an `elif`/second branch for `_lv2_e2e_lock_kind == "flock"` that does `exec 9>&- 2>/dev/null || true` (and reset `_lv2_e2e_lock_kind=""`). Then extend test case (b), or add a new case, to assert the lock is actually free (e.g. a third `flock -n` probe or a fresh gate invocation with a short timeout) immediately after the first gate's e2e run completes but before the first gate's *process* exits — the current test cannot observe this because it never checks lock state before process exit.

## Medium

**file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=1684/1697, dimension=design**
Because `_lv2_e2e_release_lock` is a no-op for the flock case (see Critical above), the two call sites at lines 1684 and 1697 give a false impression that the lock is being explicitly managed per-gate-run. This is a direct downstream symptom of the Critical finding but worth calling out separately: reviewers reading only the call sites (not the function body) would reasonably assume release is symmetric with acquire for both lock kinds.

## Low

**file=plugins/leadv2/scripts/tests/test-e2e-gate-arch-01.sh line≈373 (NOFLOCK_BIN allowlist), dimension=design**
The allowlist of binaries symlinked into `NOFLOCK_BIN` (`env bash dirname mkdir rm date git sed awk head sort stat ps sleep cat grep cut tr wc find basename ln touch rmdir mv readlink uname python3 mktemp`) is a manually maintained list that must stay in sync with whatever `leadv2-e2e-entrypoint.sh` / `run-all.sh` / the product-close script needs. If the script grows a new dependency (e.g. `curl`, `jq`), this test will silently start failing for unrelated reasons rather than testing the no-flock fallback specifically. Not blocking — advisory since it's test-only code — but worth a comment noting the list must be kept in sync, or building it by copying non-flock entries from the real `$PATH` instead of hand-enumerating.

## Verdict
FAIL — the Critical finding is a real regression risk that inverts part of the intended fix (serialization scope silently balloons from "gate execution window" to "rest of the dispatch process"), and it is not covered by the new test suite despite the suite explicitly claiming to prove flock serialization (case b) and lock-timeout classification (case d/e). Do not merge until `_lv2_e2e_release_lock` explicitly releases the flock case and a test proves release happens before process exit.

DELIVERABLE_COMPLETE
