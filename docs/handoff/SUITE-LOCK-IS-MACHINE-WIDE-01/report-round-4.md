# SUITE-LOCK-IS-MACHINE-WIDE-01 — round 4 report (lane SUITE-LOCK-ORPHAN-FD-04)

Branch `worktree-SUITE-LOCK-ORPHAN-FD-04`, base `25a6295`. Round 4 re-measured
the suite's 4-failures/exit-0 report. Finding, in one line: **the production
code was never wrong, and the exit code was never broken — the round-4
measurement ran the suite with `LEADV2_SUITE_LOCK_DISABLE=1` in its
environment, and that kill-switch disables the very mechanism the suite
asserts.** The fix this round makes the suite hermetic against that misuse.

## Files changed

- `plugins/leadv2/scripts/tests/test-suite-lock-scope.sh` — two changes:
  1. **Inherited-lock-knob scrub** (new, after `set -euo pipefail`): if
     `LEADV2_SUITE_LOCK_DISABLE` / `_WAIT_S` / `_FILE` are inherited, print a
     loud `NOTE: scrubbing inherited lock knobs` line to stderr and `unset`
     them. Case 5 still re-applies the kill-switch per-run via `env`, so the
     kill-switch contract stays covered. (`run-core-offline.sh` already
     scrubs `LEADV2_*` for its inner suites; this guard covers direct
     invocation — exactly how the round-4 measurement was burned.)
  2. **Explicit exit contract** (replaces the bare trailing
     `(( fail == 0 ))`): `(( fail == 0 )) || exit 1; exit 0`.

## [Critical 1] "exit code must follow the counter" — already did; artifact

The committed script already exited non-zero on fail>0 (the trailing
`(( fail == 0 ))` under `set -e`). Re-measured verbatim at `25a6295`:

```
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-suite-lock-scope.sh; echo TRUEEXIT=$?
[LOCK-SCOPE] pass=8 fail=4
TRUEEXIT=1
```

The round-4 brief's `EXIT=0` was a measurement artifact of the observing
shell: piping the suite (e.g. `... | tail`) puts the *pipe tail's* status in
`$?`. Under zsh, `$PIPESTATUS` is also empty (bash's name; zsh uses
`$pipestatus`), so a bash-style "recover the real rc" recipe silently yields
"" / 0. The lead's own harness reproduced this exact failure mode on the
first attempt (`PIPEEXIT=` came back empty).

Post-fix, the contract is explicit AND proven by an induced failure (a
copy of the suite with one `check "INDUCED-FAILURE exit-code proof" 0`
injected; copy placed in `tests/` so `RUNNER_REAL` resolution works):

```
INDUCED-FAIL EXIT=1
[LOCK-SCOPE]   INDUCED-FAILURE exit-code proof FAILED
[LOCK-SCOPE] pass=12 fail=1
```

A printed FAILED line can no longer coexist with `$?` = 0.

## [Critical 2] "the negative control does not fire" — it fires; the env was the cause

With the kill-switch inherited, the mutated case-7 run also bypasses the
lock, so `rc_mut=0` and RED cannot fire — the brief's exact observation.
Clean environment, same commit, no code change:

```
[LOCK-SCOPE]   case7 RED-pre: under the mutation, two different roots collide on one file OK
[LOCK-SCOPE]   case7 RED: with the machine-wide literal restored, the case-1 scenario FAILS (rc=2) OK
[LOCK-SCOPE]   case7 GREEN: reverted -- two different roots resolve to two different files again OK
[LOCK-SCOPE]   case7 GREEN: reverted -- the case-1 scenario passes again (rc=0) OK
```

RED half: under the mutation, root B's run of the case-1 scenario times out
against the externally held colliding file (rc=2, `FATAL lock_timeout`).
GREEN half: after byte-for-byte revert, the same scenario acquires (rc=0).
Case 1 therefore does depend on the per-root slug behaviour — the negative
control is real. (Both halves also re-verified post-fix, in the
lock-knob-scrubbed run: same four lines, rc=2 / rc=0.)

## [Critical 3] case 4 and case 6 — correct assertions; red only under the kill-switch

Diagnosis from the runtime, not from source-grepping: `run-core-offline.sh`
guards its entire lock section with
`if [[ "$LEADV2_SUITE_LOCK_DISABLE" != "1" ... ]]` — with the kill-switch
set, no lock is ever acquired, so:

- case 4 (budget exhausted ⇒ `FATAL lock_timeout` + rc≠0): can never fire —
  no wait happens. Pre-fix DISABLE=1 log: `case4 ... FAILED`, rc=0.
- case 6 (override file wins ⇒ `waiting for lock file=<override>`): same —
  no wait line is ever printed.

Both assertions state the intended contract and both pass without the
kill-switch (see GREEN below). The assertions were **not** touched. The
production code was **not** touched. What changed is the suite refusing to
inherit an environment that contradicts its own subject:

```
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-suite-lock-scope.sh   # post-fix
[LOCK-SCOPE] NOTE: scrubbing inherited lock knobs (DISABLE=1 WAIT_S= FILE=) -- cases set their own per-run
[LOCK-SCOPE] pass=12 fail=0
EXIT=0
```

## RED → GREEN, both outputs

RED (pre-fix, the brief's exact reproduction — a real reason: the lock is
disabled, so four lock-holding assertions honestly fail, and the suite
honestly exits 1):

```
[LOCK-SCOPE]   case2: same root -- second run waits for the holder, then proceeds FAILED
[LOCK-SCOPE]   case4: budget exhausted -> non-zero exit naming file, holder and age FAILED
[LOCK-SCOPE]   case6: LEADV2_SUITE_LOCK_FILE override still wins over the default FAILED
[LOCK-SCOPE]   case7 RED: with the machine-wide literal restored, the case-1 scenario FAILS (rc=0) FAILED
[LOCK-SCOPE] pass=8 fail=4
TRUEEXIT=1
```

GREEN (post-fix, same command — the kill-switch is scrubbed with a loud
NOTE, cases set their own knobs):

```
[LOCK-SCOPE] NOTE: scrubbing inherited lock knobs (DISABLE=1 WAIT_S= FILE=) -- cases set their own per-run
[LOCK-SCOPE] pass=12 fail=0
EXIT=0
```

And post-fix clean environment (no knobs inherited): `pass=12 fail=0`,
`EXIT=0`, case7 mutation halves rc=2 / rc=0 as above.

## Falsification set (raw output)

```
$ bash -n plugins/leadv2/scripts/tests/test-suite-lock-scope.sh
SYNTAX-OK
$ # induced-failure exit-code proof (see Critical 1)
INDUCED-FAIL EXIT=1
$ timeout 300 bash plugins/leadv2/scripts/tests/test-suite-lock-scope.sh   # clean
CLEAN EXIT=0 / [LOCK-SCOPE] pass=12 fail=0
$ LEADV2_SUITE_LOCK_DISABLE=1 timeout 300 bash plugins/leadv2/scripts/tests/test-suite-lock-scope.sh
DISABLED-ENV EXIT=0 / [LOCK-SCOPE] pass=12 fail=0
```

No Python files changed (none in scope). Changed-scope runner
(`timeout 900 tests/run-all.sh --scope changed`): the stem-based scope
matcher does **not** select this lane's changed file (a test-file change
maps to no suite row in `EXTRA_SUITE_MAP`), so `test-suite-lock-scope.sh`
does not appear in its log — its four direct runs above are the suite's
verification. The runner did execute suites whose bytes this lane's diff
does not touch; several came back red in the sharded run and were
re-verified standalone:

```
[CORE-OFFLINE] SHARD_RESULT idx=1 pass=17 fail=3 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=2 pass=13 fail=3 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=3 pass=16 fail=2 missing=0
```

Example, the lock-relevant one (`test-core-offline-lock-01.sh`, red inside
the shard run as `LOCK-01 pass=1 fail=2`, both files byte-identical to HEAD
per `git diff --quiet`):

```
$ bash plugins/leadv2/scripts/tests/test-core-offline-lock-01.sh
[LOCK-01] pass=3 fail=0   EXIT=0
```

Diagnosis: shard-parallel suite execution on a machine with five other
active leadv2 lanes (e2e/build phases live during this run) contends for
the same fixtures/locks — a reds-attribution hazard for `--scope changed`
itself, not a regression of this lane (no file this diff touches is in the
failing set).

## Constraint compliance

- No grep-against-source as an assertion anywhere; the case-7 mutation
  pre-check (`grep -q '_core_offline_lock_slug ...'`) is a mutation-apply
  guard, not an assertion, and is unchanged from round 2.
- Bash 3.2 only: no `mapfile`; every `${arr[@]}` use remains guarded under
  `set -u` (the one array, `cleanup_items`, is expanded as
  `"${cleanup_items[@]:-}"`).
- Suite is trap-guarded: a crash mid-mutation still restores the production
  runner byte-for-byte (post-run `git status` shows only the suite modified).
