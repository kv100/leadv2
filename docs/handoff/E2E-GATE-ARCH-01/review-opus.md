LABEL=critic-dispatch-E2E-GATE-ARCH-01-review-1786622764 SESSION_ID=aea2b5fb-d395-4614-ac7c-9261edfccff4
--- body from: docs/handoff/dispatch-E2E-GATE-ARCH-01-review/critic.full.md ---
# critic — E2E-GATE-ARCH-01 build-attempt-2.diff

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=1 high=2 medium=3 low=3

FINDING: severity=Critical file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=1650 dimension=correctness desc=flock branch never closes fd 9, so the global gate lock is held through e2e-ownership + the entire review engine (line 1703) until process exit — a second concurrent lane always times out and is blocked as false e2e_infra
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=1666 dimension=correctness desc=fd 9 is inherited by the suite subshell and every descendant; any lingering background child keeps the flock's open file description alive and wedges the global lock after the owning lane exits
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh line=1639 dimension=correctness desc=mkdir stale-lock reclaim is a TOCTOU — a waiter can rm/rmdir a lock dir that a third process legitimately re-acquired between the pid read and the rmdir, granting the lock to two lanes at once

Diff line numbers below are given as `diff:<n>` (build-attempt-2.diff) plus the resulting
line in `leadv2-dispatch-product-close.sh` (target file, pre-image starts at 1599).

Environment facts verified, not assumed:
- `leadv2-dispatch-product-close.sh` uses `set -uo pipefail` (line 13) — **no `-e`**, so
  `exec 9>… || return 2` is reachable rather than fatal (verified empirically:
  `bash -c 'set -uo pipefail; f(){ exec 9>"/nonexistent-dir-xyz/lock" || return 2; }; f; echo rc=$?'`
  → `rc=2`, shell survives). The acquire's `return 2` path is sound.
- The diff is NOT applied to the working tree; the gate block at 1599 is still the
  one-liner. Review is of the proposed patch.

---

## Critical

### C1 — the flock is never released; it is held across the whole review phase
`diff:50-55` → product-close ~1650 (`_lv2_e2e_release_lock`)

```bash
_lv2_e2e_release_lock() {
  if [[ "${_lv2_e2e_lock_kind}" == "mkdir" ]]; then
    rm -f -- "${_lv2_e2e_lock_dir}/pid" ...
    rmdir "${_lv2_e2e_lock_dir}" ...
  fi
}
```

There is no `flock` arm. The lock is an fd-based flock held on fd 9 opened by
`exec 9>"${_lv2_e2e_lock}"` (`diff:60`) in the **main shell**, not a subshell — so it lives
until `leadv2-dispatch-product-close.sh` exits.

What runs after the gate block, in the same process, still holding the global lock
(verified by grep on the target file):

| line | work |
|---|---|
| 1629 | `leadv2-e2e-ownership.sh` — differential suite **re-runs** |
| 1703 | `leadv2-review-run.sh` — the full multi-model review engine |
| 1808 | `sleep 5` retry loops |

The review engine is minutes-to-tens-of-minutes of LLM work. The lock timeout is 300s
with exactly one jittered retry (`diff:98-110`). So with two concurrent lanes the second
lane's outcome is not "waits its turn" — it is deterministically:

`300s wait → park → jitter → immediate retry → still held → _lv2_e2e_infra e2e_gate_lock_timeout → exit 4`.

The change intended to make concurrent lanes safe. As written it makes the **second
concurrent lane always fail**, and fail as a `blocked/e2e_infra` park — precisely the
"gate produced nothing" failure class this task exists to eliminate. That is worse than
the flake it replaces, because it is deterministic rather than probabilistic.

Required fix — release symmetrically, and only around the suite run:

```bash
_lv2_e2e_release_lock() {
  case "${_lv2_e2e_lock_kind}" in
    mkdir) rm -f -- "${_lv2_e2e_lock_dir}/pid" 2>/dev/null || true
           rmdir "${_lv2_e2e_lock_dir}" 2>/dev/null || true ;;
    flock) exec 9>&- ;;
  esac
  _lv2_e2e_lock_kind=""
}
```

Both call sites (`diff:92`, `diff:105`) already invoke it; the `_lv2_e2e_infra` exits do
not, but process exit closes fd 9 there — except under H1 below.

---

## High

### H1 — fd 9 leaks into the suite (and the review engine), so the lock outlives the lane
`diff:66-69` → product-close ~1666 (`_lv2_e2e_run`), and the post-gate body

A POSIX/BSD `flock` lock belongs to the **open file description**, not to the process.
`exec 9>` in the main shell means fd 9 is inherited by:
- the `( cd … && bash -c "${e2e_cmd} --scope changed" )` subshell and every suite it runs;
- after C1 is fixed but the leak is not: `leadv2-e2e-ownership.sh` (1629) and
  `leadv2-review-run.sh` (1703).

Any suite that leaves a background process alive (a dev server, a `&`-spawned poller — the
normal shape of an e2e suite) keeps that open file description, and therefore the global
lock, **after `product-close` has exited**. Every subsequent gate on that machine then
burns 300s and parks as `e2e_infra` until that orphan dies. There is no reaper and no
stale detection on the flock path (the pid-marker recovery exists only for the mkdir path).

Note the author already knows this hazard: `_dl_note` at line 81 of the target file passes
`9>&-` to the ledger call. The new code does not apply the same discipline to the far more
dangerous callee.

Required fix: close fd 9 in every child that does not need it —

```bash
_lv2_e2e_run() {
  printf 'e2e-root: %s\n' "${_lv2_e2e_root}"
  ( cd "${_lv2_e2e_root}" && bash -c "${e2e_cmd} --scope changed" ) 9>&-
}
```

and, once C1's `exec 9>&-` is in place, the post-gate calls are already safe.

### H2 — mkdir stale reclaim is a TOCTOU that can hand the lock to two lanes
`diff:37-44` → product-close ~1639

```bash
if [[ -f "${_lv2_e2e_lock_dir}/pid" ]]; then
  IFS= read -r _pid < "${_lv2_e2e_lock_dir}/pid" || _pid=""
  if [[ "${_pid}" =~ ^[0-9]+$ ]] && ! kill -0 "${_pid}" 2>/dev/null; then
    rm -f -- "${_lv2_e2e_lock_dir}/pid" ...
    rmdir "${_lv2_e2e_lock_dir}" ...
```

Failure scenario (three lanes, A/C waiting, X the crashed owner):
1. A reads `pid` → X, `kill -0 X` fails → A decides the lock is stale.
2. Before A's `rm`, C runs the same detection, wins, `rmdir`s, `mkdir`s the dir afresh and
   writes **its own** pid. C now legitimately owns the lock and starts its suite.
3. A proceeds with its stale decision: `rm -f .../pid` deletes **C's** pid marker,
   `rmdir` removes **C's** lock dir, `continue` → A's next `mkdir` succeeds.
4. A and C run the e2e gate concurrently — the exact interleaving this task forbids, now
   with no pid marker for C, so a fourth lane sees a marker-less dir and can never reclaim.

The window is small but this path is only ever exercised under contention after a crash,
i.e. exactly the SD-E2E-GATE-LOAD-FLAKE-01 conditions. Two lanes silently sharing the gate
reproduces the original flake while the journal reports clean serialization.

Required fix: make the reclaim atomic — only the process that wins the rename may remove:

```bash
_stale_dir="${_lv2_e2e_lock_dir}.stale.$$"
if mv "${_lv2_e2e_lock_dir}" "${_stale_dir}" 2>/dev/null; then
  # re-verify we moved the dir we inspected, then discard it
  rm -rf -- "${_stale_dir}" 2>/dev/null || true
fi
continue
```

`mv` of the directory is atomic w.r.t. other reclaimers: the loser's `mv` fails because the
source is gone, and it simply re-loops. A fresh owner that `mkdir`s in between is untouched
because its dir is a different inode… so also re-read and compare the pid immediately
before the `mv` to avoid moving a legitimately-new owner's dir.

---

## Medium

### M1 — no test covers flock release; the suite is green while C1 ships
`test-e2e-gate-arch-01.sh` `diff:383-389` (case c), `diff:349-364` (case b)

- Case (c) asserts release (`[[ ! -d "${TMP}/case-c.lock.d" ]]`) — but only on the **mkdir**
  path (`PATH=${NOFLOCK_BIN}`).
- Case (b) asserts non-overlap of two windows. C1 does not break non-overlap — holding the
  lock *longer* still serializes — so case (b) passes with the bug present.
- Cases (d) and (e) also run on `NOFLOCK_BIN`.

Net: on a machine with `flock`, no case in this file exercises the flock release path at
all. The header's mutation-gate table claims red/green coverage for (b)–(e), but there is
no mutation whose revert is detected on the flock branch.

Required: add case (f) — with real `flock` on PATH, run gate 1 to completion, then assert a
second gate acquires the same lock **immediately** (well under the timeout), and assert
`lsof`/`/dev/fd` shows fd 9 closed after `_lv2_e2e_release_lock`. Cheaper equivalent: run
gate 1 with `LEADV2_E2E_CMD` set to a no-op, then `flock -n -w 0` the same lock file from
the test after gate 1 exits **but with a suite-spawned background child still alive** — must
succeed. That single case fails on both C1 and H1.

### M2 — the 300s timeout is calibrated against the wrong critical section
`diff:17`, `diff:98-110`

With C1 fixed the held window is the suite run; 300s is plausible. As shipped the window is
suite + ownership + full review, and no timeout value would be correct. Land the fix in C1
before tuning; also state in the comment that the lock covers the suite run **only**, so a
later editor does not move work inside it.

### M3 — a `mkdir_fallback` journal `emit decision` fires on every gate on stock macOS
`diff:86-89`

`flock` is absent from stock macOS — the primary dev platform for this repo. This is not an
exception path there, it is every run, so every lane now writes an extra `decision` row
recording a permanent property of the OS. Keep the `>> e2e-gate.log` line; drop the `emit`
(or emit once per host, guarded by a marker file under the cache dir).

---

## Low

### L1 — no EXIT trap releases the mkdir lock
`diff:50-55`. A lane killed with SIGTERM/SIGINT mid-suite leaves `${lock}.d` behind. It is
recoverable only through the stale-pid path, which H2 shows is itself racy. Add
`trap '_lv2_e2e_release_lock' EXIT` scoped around the gate (composing with any existing
EXIT trap — `_pc_exit_handler` is already installed, so append rather than overwrite).

### L2 — `kill -0` liveness is pid-recycling-sensitive
`diff:39`. An unrelated process that inherits the recycled pid makes a dead owner look
alive forever; the lock then never reclaims and every lane parks. Store `pid` plus a start
marker (e.g. `ps -o lstart= -p`) or the lock dir's own mtime, and treat a lock older than
`2 × timeout` with a live-but-unmatched pid as stale.

### L3 — `LEADV2_E2E_GATE_LOCK_JITTER` is unvalidated
`diff:102`. Unlike `_lv2_e2e_lock_timeout` (`diff:18`), the jitter value is passed straight
to `sleep`. A non-numeric value makes `sleep` error to the log and fall through (harmless
without `set -e`, but silently defeats the jitter that spreads the retry). Apply the same
`^[0-9]+$` guard.

---

## What is correct

Stated only because it bounds the findings above, not as praise:
- `$?` capture in the `else` arms (`diff:94`, `diff:107`) does read the condition's status —
  correct bash.
- The `return 2` / infra-classification split (`diff:70-85`, case (e)) is the right shape:
  a lock-infrastructure fault becomes `blocked/e2e_infra`, not a false `e2e_regression`.
- Timeout validation `diff:18` and the `_wait=0` second attempt terminate (mkdir loop
  returns 1 immediately at `SECONDS - _started >= 0`).

## Verdict

**BLOCK.** C1 alone converts a probabilistic flake into a deterministic failure of the
second concurrent lane. C1 + H1 + H2 must land together with the M1 test case, otherwise
the suite stays green over the defect.

Type-check evidence: N/A — no Python/TypeScript in this diff. Shell-level evidence is the
empirical `exec`-redirect check and the post-gate call-site grep, both quoted above. The
new suite was **not executed** (the diff is unapplied in this tree); the coverage gap in M1
is derived from the test source, not from a run.

DELIVERABLE_COMPLETE
