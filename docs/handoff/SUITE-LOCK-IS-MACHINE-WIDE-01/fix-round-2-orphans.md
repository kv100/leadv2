# SUITE-LOCK-IS-MACHINE-WIDE-01 — round 2 report (lane SUITE-LOCK-ORPHAN-FD-04)

Branch: `worktree-SUITE-LOCK-ORPHAN-FD-04`, rebased onto current main (`10fe3d6`).
Round-1 scoping (`57aa62a`) is preserved unchanged — no lock slug, `9<>`-era
comment, or diagnostic was weakened; round 2 only closes the two holes the
round-1 brief named.

## Files changed

- `plugins/leadv2/scripts/tests/run-core-offline.sh` — lock section rewritten:
  orphan-proof holder + bounded default wait + loud timeout refusal.
- `plugins/leadv2/scripts/tests/test-suite-lock-scope.sh` — NEW, 7 cases /
  12 checks (see below).
- `tests/run-all.sh` — `EXTRA_SUITE_MAP` row
  `run-core-offline.sh:plugins/leadv2/scripts/tests/test-suite-lock-scope.sh`
  (merged with main's new lane-liveness/lanes-snapshot rows during the rebase).

## [Critical 1] orphan-proof lock — what was chosen and why

**Chosen: hold the lock in a dedicated `flock` process, not `FD_CLOEXEC`.**

`FD_CLOEXEC` was rejected on the merits, not convenience: bash 3.2 has no
builtin to set close-on-exec on a manually opened fd (`exec 9<>"$LOCK"` leaves
fd 9 inheritable forever, and `set -o` offers nothing; the only escape hatches
are re-exec self-tricks that are harder to reason about than the alternative).
Instead the script hands its entire body to `flock -x -n -E 99 -o <lockfile>
env _LV2_CORE_OFFLINE_LOCK_HELD=1 bash <self>`:

- `flock`'s own `-o/--close` closes its lock fd **before exec'ing** the body,
  so the body and everything it ever forks never sees the fd — there is
  nothing left for an orphan to inherit, which is strictly stronger than
  close-on-exec (no inheritance path exists at all).
- The lock is then held solely by the `flock` process, and killing that
  process — however it dies — releases the lock immediately and
  unconditionally. That is exactly the brief's "process whose exit is
  guaranteed to release it".
- `-E 99` is an exit code no suite-body outcome can produce (bodies exit
  0/1/2), so "could not acquire" is unambiguous against a legitimate body
  exit propagated through `flock`.

Verified live (test case 3): a run whose `sleep 20` child survived it as an
orphan (checked `kill -0`) held no lock — a fresh run acquired immediately.

## [Critical 2] bounded default wait

`LEADV2_SUITE_LOCK_WAIT_S` defaults to **600s**. The first attempt is
non-blocking (`-n`); on `99` it prints the lock file + holder stamp and makes
one bounded `-w "$LEADV2_SUITE_LOCK_WAIT_S"` attempt. Budget exhausted ⇒
`[CORE-OFFLINE] FATAL lock_timeout file=... wait_s=... holder=pid=... since=...`
on stderr and **exit 2** — file, holder, and the holder's `since=` stamp (the
age is derivable from it and is also shown) all named, using the holder
diagnostic round 1 already writes into the file.

## [Critical 3] the suite (test-suite-lock-scope.sh)

Fixture roots are throwaway `git init`'d mktemp dirs symlinking the real
runner; every lock path is fixture-derived. Never touches
`/tmp/leadv2-core-offline*.lock` or a real lane. Cases:

1. different roots ⇒ different resolved lock files; a run in root B proceeds
   immediately while root A's file is held (no wait);
2. same root ⇒ second run waits, then proceeds (rc 0);
3. **orphan case**: a run forks a long-lived child and exits; child verified
   still alive (`kill -0`); a fresh run acquires immediately — also proves
   `lsof`-free equivalent: nothing holds the lock;
4. exhausted budget ⇒ non-zero exit + `FATAL lock_timeout` naming file,
   `holder=pid=`, `since=` (age);
5. `LEADV2_SUITE_LOCK_DISABLE=1` ⇒ bypasses a held lock (regression guard);
6. `LEADV2_SUITE_LOCK_FILE` override still wins (regression guard);
7. **negative control**: the machine-wide literal
   `/tmp/leadv2-core-offline.lock` is sed'd back into the production line
   (trap-guarded byte-for-byte restore), and the case-1 scenario is *run*
   under the mutation and proven to FAIL (non-zero, `FATAL lock_timeout`),
   then reverted and proven to pass again.

Selection is proven via `--scope changed`: the `EXTRA_SUITE_MAP` row fires on
stem `run-core-offline` and selects `test-suite-lock-scope.sh` (line 82 of
`tests/run-all.sh` also runs the full core runner on every invocation, which
is how the whole 83-suite core suite got re-verified under the new lock).

## Falsification set (raw output)

```
$ bash -n plugins/leadv2/scripts/tests/run-core-offline.sh && \
  bash -n plugins/leadv2/scripts/tests/test-suite-lock-scope.sh && \
  bash -n tests/run-all.sh
ALL-SYNTAX-OK
$ flock --help | grep -E 'close|-E|wait'
 -o --close      Close file descriptor before running command   (all flags present)

$ bash plugins/leadv2/scripts/tests/test-suite-lock-scope.sh          # GREEN
[LOCK-SCOPE] pass=12 fail=0   rc=0

# RED: machine-wide literal restored into the production default line
$ sed 's#..._core_offline_lock_slug...#LEADV2_SUITE_LOCK_FILE="${...:-/tmp/leadv2-core-offline.lock}"#'
LEADV2_SUITE_LOCK_FILE="${LEADV2_SUITE_LOCK_FILE:-/tmp/leadv2-core-offline.lock}"
$ bash plugins/leadv2/scripts/tests/test-suite-lock-scope.sh
[LOCK-SCOPE]   case1: two different fixture roots resolve to two different lock files FAILED
[LOCK-SCOPE]   case1: root B proceeds immediately while root A's file is held FAILED
[LOCK-SCOPE]   case7 GREEN: reverted -- two different roots resolve to two different files again FAILED
[LOCK-SCOPE] pass=9 fail=3    rc=1
# revert (cp -p from pre-mutation backup) → GREEN again: pass=12 fail=0, rc=0
$ git diff --stat -- plugins/leadv2/scripts/tests/run-core-offline.sh   # empty: byte-identical restore
```

Full-suite in-suite control also shows `case7 RED: ... the case-1 scenario
FAILS (rc=2) OK` on every green run.

Changed-scope runner: `bash tests/run-all.sh --scope changed` — result
recorded in the lane journal/report addendum (full 83-suite core run plus
`test-suite-lock-scope.sh`).
