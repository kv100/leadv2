# Verify: flock fd 9 never released

Finding: `_lv2_e2e_release_lock` only releases the mkdir-fallback lock; the flock path leaks fd 9.

## Evidence (docs/handoff/E2E-GATE-ARCH-01/build-attempt-2.diff)

- `_lv2_e2e_acquire_lock` (diff +56..+65) runs `exec 9>"${_lv2_e2e_lock}"` in the *current* shell
  (plain function, no subshell), then `flock -x -w "${_wait}" 9`, setting `_lv2_e2e_lock_kind="flock"`.
- `_lv2_e2e_release_lock` (diff +50..+55) has its entire body guarded by
  `if [[ "${_lv2_e2e_lock_kind}" == "mkdir" ]]`. There is no `exec 9>&-`, no `flock -u 9`,
  and no `else` arm. For `kind=flock` the function is a no-op.
- No `exec 9>&-` exists anywhere in the new hunk. The only `9>&-` in the file is the pre-existing
  ledger call at `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:81`, unrelated and
  predating this change.
- The exclusive lock lives on the open file description behind fd 9, and fd 9 stays open for the
  life of the top-level `product-close.sh` process. So the global gate lock is held past the e2e
  run: e2e-ownership stamping, then the review engine invocation at
  `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1703`
  (`bash "${_ENGINE_BIN}" --task ...`), through `exit ${_engine_rc}`.
- Consequence matches the claim: a second concurrent lane's `flock -x -w 300` waits on a lock held
  through the entire review, hits the timeout path, and is classified by
  `_lv2_e2e_infra e2e_gate_lock_timeout` — a false `e2e_infra` park rather than genuine gate contention.

## Refutation attempts, all failed

1. *"`exec 9>` inside a function only affects a subshell"* — false. `_lv2_e2e_acquire_lock` is
   invoked as a plain command in the main shell (`if _lv2_e2e_acquire_lock ...; then`), so the
   redirect mutates the script's own fd table. The `>> log 2>&1` at the call site redirects fd 1/2 only.
2. *"the process exits right after the e2e run"* — false. The gate branch falls through to
   ownership stamping and then the review engine, ~100 lines later.
3. *"the lock is released when the suite subshell closes the file"* — false. The child inherits a
   duplicate descriptor pointing at the same open file description; the parent's copy keeps the lock.

Required fix: give `_lv2_e2e_release_lock` a flock arm —
`[[ "${_lv2_e2e_lock_kind}" == "flock" ]] && exec 9>&-` — reset `_lv2_e2e_lock_kind=""` in both
arms, and add a regression case asserting a second acquisition succeeds immediately after release.

VERIFY_VERDICT: upheld

DELIVERABLE_COMPLETE
