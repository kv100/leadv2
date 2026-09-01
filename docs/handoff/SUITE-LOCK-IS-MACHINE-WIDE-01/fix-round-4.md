# SUITE-LOCK round 4 — the suite reports 4 failures and exits 0

Measured by the lead on lane `SUITE-LOCK-ORPHAN-FD-04` at commit `25a6295`,
2026-09-01, with `LEADV2_SUITE_LOCK_DISABLE=1`:

```
[LOCK-SCOPE] pass=8 fail=4
EXIT=0
```

**That exit code is the headline defect.** A suite that prints `FAILED` four times and then hands
CI a zero is worse than no suite: CI selects it, CI goes green, and the lock bug ships. This is the
exact `SUITE-THAT-CANNOT-FAIL-01` disease, now inside the suite that was meant to prove the lock fix.

## [Critical] 1 — the exit code must follow the counter

`fail>0` ⇒ non-zero exit. Nothing else in this round matters until this is fixed, because until it
is, every other result in this file is unverifiable by CI.

## [Critical] 2 — the negative control does not fire

```
case7 RED-pre: under the mutation, two different roots collide on one file        OK
case7 RED: with the machine-wide literal restored, the case-1 scenario FAILS      FAILED (rc=0)
```

The mutation IS applied — `RED-pre` proves the two roots collide — and the case-1 scenario still
returns 0 under it. So case 1 does not depend on the behaviour the mutation removes: it passes with
and without the fix, which means **case 1 proves nothing today**. Make case 1 genuinely sensitive to
the machine-wide literal, then re-run case 7 and show both halves in `report.md`.

## [Critical] 3 — the two other failures

```
case4: budget exhausted -> non-zero exit naming file, holder and age   FAILED
case6: LEADV2_SUITE_LOCK_FILE override still wins over the default     FAILED
```

Diagnose each from the runtime before changing anything. If a case asserts the wrong contract, say
so in `report.md` and change the assertion deliberately, with the reason — never tweak until green.
If the production code is wrong, fix the production code.

## Rules

Unchanged from the earlier rounds, plus:

- The suite must be shown RED once for a real reason and GREEN after, with both outputs in
  `report.md`. `pass=N fail=0` with a zero exit, or it is not done.
- No `grep` against script source as an assertion; a printed `FAILED` line that leaves `$?` at 0 is
  precisely what this round exists to remove.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop, even if partial.
