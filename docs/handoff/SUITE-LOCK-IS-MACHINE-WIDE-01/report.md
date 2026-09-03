# SUITE-LOCK-IS-MACHINE-WIDE-01 — round 3 report

## 1. Case 7 diagnosis: which lying-green shape it was

**Shape: the scenario never reached the locking path at all.**

The round-2 control (salvaged as `852b959`, `test-suite-lock-scope.sh` case 7) was
**structural, not behavioral**: under the mutation it only re-derived both fixture
roots' lock paths and asserted the two strings collide on the machine-wide literal,
then reverted. It never executed the locking scenario (holder in root A, contender
in root B) under the mutation — the `run-core-offline.sh` lock path itself was never
reached by any mutated-body execution. A control over path *derivation* is insensitive
to whether any *scenario* depends on the scoping, which is why it stayed green while
proving nothing. (The sibling lane's `25a6295` commit message records the same
diagnosis independently.)

Round 3's control runs the exact case-1 scenario under the mutation and requires it
to FAIL (`FATAL lock_timeout`, rc=2), then re-runs it after revert and requires rc=0
— so the RED means something.

## 2. Production changes (`plugins/leadv2/scripts/tests/run-core-offline.sh`)

- `LEADV2_SUITE_LOCK_WAIT_S` now **defaults to 600** — the wait is bounded by
  default; expiry exits 2 with `FATAL lock_timeout file=... wait_s=... holder=...`.
- The lock is no longer held on an inherited fd 9 (`exec 9<>` + `flock 9`). The
  whole rest of the script is handed to `flock -x -n -E 99 -o <lockfile> env
  _LV2_CORE_OFFLINE_LOCK_HELD=1 bash <self>`: `flock -o` closes its lock fd before
  exec, so the re-exec'd script and everything it forks never holds the fd — no
  orphaned child can keep the lock past its parent's death (the fd-inheritance
  mechanism behind the 47 launchd-reparented `sleep 900` pile-up).
- `LEADV2_SUITE_LOCK_FILE` precedence untouched: explicit env var > derived
  per-REPO_ROOT path (the documented one-step rollback still works — case 6).
- Test-only hook `LEADV2_SUITE_LOCK_ORPHAN_TEST_SLEEP_S` (never set by real
  callers) simulates the incident shape for case 3/8.
- Probe on this box first: Homebrew `flock 0.4.0` supports `-n -w -x -E 99 -o`
  (live probe: contended `-w 1 -E 99 -o` ⇒ exit 99).

## 3. Suite: `plugins/leadv2/scripts/tests/test-suite-lock-scope.sh` — pass=12 fail=0

12 checks over cases 1–7, incl. case 3 (orphan child survives, fresh run acquires
immediately), case 4 (bounded wait expires loudly naming file+holder), case 6
(env override wins), case 7 (behavioral mutation control: RED rc=2 under mutation,
GREEN rc=0 after revert). Full transcript in the session log; summary line:
`[LOCK-SCOPE] pass=12 fail=0`.

## 4. Case 2 live demo — two real concurrent runs, one root

Both runs observed `file=/tmp/leadv2-core-offline--private-tmp-lv2-concurrent-demo2-cvsNkn.lock`;
run B printed `waiting for lock file=... (held by a concurrent run)` then
`lock-probe acquired` once A released. Same root ⇒ same file ⇒ serialises.

## 5. Falsification set

- `bash -n` on `run-core-offline.sh`, `test-suite-lock-scope.sh`, `run-all.sh`: OK.
- Mutation kill: suite green (12/0) ⇒ applied the machine-wide-literal mutation to
  the production body ⇒ **suite alone red: `pass=9 fail=3`, rc=1** (case 1 both
  checks + case-7 GREEN checks fail) ⇒ reverted byte-identical (`diff` clean) ⇒
  green again (12/0).
- Changed-scope selection + full self-check: `tests/run-all.sh --scope changed` —
  `run-core-offline:plugins/leadv2/scripts/tests/test-suite-lock-scope.sh` added to
  `EXTRA_SUITE_MAP` so the suite is selected; `[RUN]` line and result in the
  session log.

## 6. Acceptance mapping

- Control fires (red under mutation, green after revert): case 7 ✓
- Env override still wins: case 6 ✓
- Two runs in one root serialise: case 2 + live demo ✓
- Bounded wait expires loudly naming holder: case 4 ✓
- Child cannot outlive parent holding the lock: case 3 + `flock -o` design ✓
- Suite selection proven with `--scope changed`: EXTRA_SUITE_MAP row ✓
