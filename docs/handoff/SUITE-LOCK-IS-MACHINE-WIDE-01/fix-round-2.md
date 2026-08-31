# SUITE-LOCK-IS-MACHINE-WIDE-01 — round 2: scoping landed, the orphan hole and the unbounded wait did not

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SUITE-LOCK-IS-MACHINE-WIDE-01`

LANE_WRITES: plugins/leadv2/scripts/tests/run-core-offline.sh,plugins/leadv2/scripts/tests/test-suite-lock-scope.sh,tests/run-all.sh,docs/handoff/SUITE-LOCK-IS-MACHINE-WIDE-01/

**Round 1 is merged as `57aa62a` and stays.** Rebase onto current main first.

I verified round 1 myself on the live machine — the scoping is correct and I am not asking you to
redo it:

```
/Users/.../Projects/leadv2                     -> /tmp/leadv2-core-offline--Users-...-leadv2.lock
.../worktrees/SUITE-LOCK-IS-MACHINE-WIDE-01    -> /tmp/leadv2-core-offline--Users-...-SUITE-LOCK-....lock
.../worktrees/LANE-LIVENESS-PROVE-03           -> /tmp/leadv2-core-offline--Users-...-LANE-LIVENESS-....lock
```

Three worktrees, three distinct lock files; the same root maps to the same file. The `9<>` instead
of `9>` and the holder diagnostic written into the file are both right. Do not weaken any of it.

Two things from the round-1 brief did not land, and one of them is the mechanism that actually
killed lanes today.

## [Critical] the lock fd is still inherited by children — orphans hold it

`exec 9<>"$LOCK"` leaves fd 9 inheritable, so every child gets it. A child that outlives its run
keeps the flock alive, because the lock belongs to the open file description that all of them share.

Measured on this machine during the incident:

```
$ lsof -t /tmp/leadv2-core-offline.lock | wc -l      # then: 47 orphans
$ ps -o pid=,ppid=,etime= -p <pid>
  53461  1  01:41   sleep 900
  74652  1  01:13   sleep 900
```

`ppid=1` — reparented to launchd, holding the lock of a run that no longer existed, for up to 15
minutes each. That is self-sustaining: a lane dies, its orphan holds the lock, the next lanes wait
on a corpse, they time out, they leave their own orphans.

Per-root scoping narrows the blast radius but does not close this: two runs in the *same* root
still deadlock behind a corpse, and that is the common case for repeated dispatches of one lane.

Set `FD_CLOEXEC` on the lock fd, or hold the lock in a process whose exit is guaranteed to release
it. Say in `report.md` which you chose and why.

## [Critical] the default wait is still unbounded

```bash
else
  flock 9      # no -w
fi
```

`LEADV2_SUITE_LOCK_WAIT_S` is unset by default, so a blocked run waits forever, prints one line,
and is killed from outside with no reason recorded anywhere. That is precisely why six lanes today
read as "died silently" when they were in fact queuing.

Give it a bounded default and make the timeout refusal loud: exit non-zero, name the lock file, the
holder line, and the holder's age. Round 1 already writes the holder diagnostic into the file —
use it.

## [Critical] there is still no suite

Round 1 shipped a production change with no test at all, so nothing stops the machine-wide literal
from coming back. Build `test-suite-lock-scope.sh` against fixture roots and a fixture lock dir —
never `/tmp/leadv2-core-offline*.lock`, never a real lane:

1. two runs in **different** roots ⇒ both proceed, neither waits;
2. two runs in the **same** root ⇒ the second waits (or fails with the explicit reason);
3. a run whose child outlives it ⇒ the next run acquires **immediately** (the orphan case: start a
   run that spawns a long-lived child, kill the run, prove the lock is free);
4. a run that cannot acquire within the budget ⇒ non-zero exit naming lock file, holder and age;
5. `LEADV2_SUITE_LOCK_DISABLE=1` ⇒ no lock taken (regression guard);
6. `LEADV2_SUITE_LOCK_FILE` still overrides the path (regression guard);
7. restoring the hardcoded machine-wide path ⇒ case 1 fails.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body, RED, revert, GREEN, clean `git diff --stat`. Restoring the
  machine-wide literal path must turn this suite red — that is the required negative control.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

An orphaned child can no longer hold the lock, a run that cannot acquire it fails loudly within a
bounded wait, and restoring the machine-wide path turns the new suite red with the exit code
following.
