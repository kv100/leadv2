# SUITE-LOCK-IS-MACHINE-WIDE-01 — every lane's test gate queues on one machine-wide lock

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SUITE-LOCK-IS-MACHINE-WIDE-01`

LANE_WRITES: plugins/leadv2/scripts/tests/run-core-offline.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-suite-lock-scope.sh,tests/run-all.sh,docs/handoff/SUITE-LOCK-IS-MACHINE-WIDE-01/

Main is `de44cc7` in `~/Projects/leadv2`. Branch from it. **Run this lane with
`LEADV2_SUITE_LOCK_DISABLE=1` in your environment**, or you will queue behind the very lock you are
fixing.

## The defect — this is why lanes die silently

`run-core-offline.sh:57-66`:

```bash
LEADV2_SUITE_LOCK_FILE="${LEADV2_SUITE_LOCK_FILE:-/tmp/leadv2-core-offline.lock}"
exec 9>"$LEADV2_SUITE_LOCK_FILE"
if ! flock -n 9; then
  printf -- '[CORE-OFFLINE] waiting for lock file=%s (held by a concurrent run)\n' ...
```

The lock file is a **single machine-wide path**. Every lane's e2e gate calls this script. So N
concurrent lanes do not run concurrently — one runs, N-1 block, and the blocked ones are eventually
killed by their own timeouts.

Measured on 2026-08-31, do not re-derive:

- `grep -rl 'waiting for lock file=/tmp/leadv2-core-offline.lock' docs/handoff/*/e2e-gate.log | wc -l`
  → **45**. This is a standing condition, not today's accident.
- `LEAD-WORKER-CHANNEL-01`'s `e2e-gate.log` ends on that exact waiting line, and its stream's last
  events are `task_updated {"status":"killed"}` then `status:"stopped"`. The lane produced nothing
  and left only its anchor commit — indistinguishable, from outside, from a lane that simply failed.
- Of six lanes dispatched in one window, four were dead within the hour with anchor-only commits.

The cost is not just throughput. It corrupts every estimate the lead makes, because the lead sizes
work assuming lanes run in parallel when they are in fact a queue of one.

## [Critical] the lock must be scoped to what it actually protects

Find out what the lock exists to protect — say it in `report.md`, from the code, not from a guess.
If it guards a shared *path* (a fixture dir, a temp file, a state root), the lock belongs to that
path and two lanes with separate worktrees must not contend. If it guards a genuinely global
resource (a fixed port, a shared cache), then say which, and scope the lock to that resource alone
rather than to the whole suite run.

Default expectation: derive the lock file from the **lane worktree**, so lanes with distinct
worktrees never contend, while two runs in the *same* worktree still serialise. Do not simply
delete the lock — find out what breaks without it first, and write that down.

## [Critical] a lane that loses the lock race must fail loudly, not silently

Today a blocked lane prints one line to `e2e-gate.log` and is later killed with no diagnosis
reaching anyone. Whatever the scoping outcome, a lane that cannot obtain its lock within its
budget must terminate with an explicit, greppable reason that names the lock and the holder — and
the dispatcher must surface it as a distinct terminal cause, not as a generic death.

## [Medium] the dispatcher should not launch lanes it knows will queue

If the lock remains global for some subset of work, the dispatcher must account for it when
admitting lanes rather than starting N and letting N-1 die. Say in `report.md` what you did here;
"nothing, because the lock is now per-lane" is an acceptable answer if that is true.

## Acceptance

Build `test-suite-lock-scope.sh` against fixture worktrees and a fixture lock dir — never
`/tmp/leadv2-core-offline.lock`, never a real lane:

1. two runs in **different** worktrees ⇒ both proceed, neither waits;
2. two runs in the **same** worktree ⇒ the second waits (or fails with the explicit reason),
   proving the lock still does its job;
3. a run that cannot get its lock within the budget ⇒ non-zero exit with a message naming the lock
   file and the holder;
4. `LEADV2_SUITE_LOCK_DISABLE=1` ⇒ no lock is taken at all (regression guard for the existing
   escape hatch);
5. `LEADV2_SUITE_LOCK_FILE` still overrides the path (regression guard);
6. the dispatcher surfaces the lock-timeout cause distinctly from an ordinary worker death.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Restoring the machine-wide literal path must turn the suite red.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence. A printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Never take the real `/tmp/leadv2-core-offline.lock` from a test.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

Two lanes in different worktrees run their gates at the same time, a lane that loses a lock race
says so in one greppable line instead of dying quietly, and restoring the machine-wide lock path
turns the suite red with the exit code following.

## Addendum — the lead read the lock rationale; naive per-worktree scoping is WRONG

`run-core-offline.sh:44-55` says why the lock exists, and it is not what I assumed when I wrote
the [Critical] section above. Two concurrent runs share `/tmp` fixtures **and the same real repo
working tree**: the hermeticity post-condition diffs `git status -- docs/leadv2` in the REAL repo
around every suite, so a second run mutating that tree mid-diff manufactures a false
HERMETIC-VIOLATION.

So the coupling is not the worktree — it is that the suite reaches OUT of its lane into shared
state. Keying the lock on the lane worktree would let two lanes run at once and silently corrupt
each other's hermeticity verdicts. That is a half-fix that looks green and poisons every later
result, which is worse than the queue.

Therefore the real task is one level down: **make the suite hermetic to its own lane** — the /tmp
fixture paths and the hermeticity diff must both be lane-scoped — and only then narrow the lock.
If you cannot make it lane-local, say so plainly in `report.md` and leave the lock global; do NOT
narrow the lock while the shared-tree diff remains.

Second measured fact: `LEADV2_SUITE_LOCK_WAIT_S` is unset by default, so the wait is
**unbounded**. That is the precise silent-death mechanism — a blocked lane waits forever, prints
one line, and is later killed from outside with no reason recorded. Even if the scoping question
ends in "leave it global", a bounded default wait plus a loud failure is still required.

## Addendum 2 — the lock is held by ORPHANED processes, which is the real cycle

Measured on the live machine while lanes were dying:

```
lsof /tmp/leadv2-core-offline.lock ->
  sleep 53461 ... 9w REG ... /private/tmp/leadv2-core-offline.lock
  sleep 74652 ... 9w REG ... /private/tmp/leadv2-core-offline.lock
ps -> pid=53461 ppid=1 etime=01:41 cmd=sleep 900
      pid=74652 ppid=1 etime=01:13 cmd=sleep 900
```

`:61` does `exec 9>"$LOCK"` in the shell, so **every child inherits fd 9**. When the run dies, its
`sleep 900` survives, is reparented to launchd, and keeps holding the flock for up to 15 minutes
after the run that took it ceased to exist.

So the failure is self-sustaining: a lane dies -> its orphan holds the lock -> the next lanes wait
on a corpse -> they are killed on timeout -> they leave their own orphans. Every restart feeds the
cycle. This, not the global path alone, is why the death rate stayed near half all day.

Three requirements follow, and they are not optional:

1. **the lock fd must be close-on-exec**, so no child ever inherits it;
2. **the flock must be held by a process whose exit releases it** — a holder that cannot outlive
   its own run;
3. **the wait must be bounded and the refusal loud**, naming the holder pid and its age, so a
   corpse-held lock is diagnosable in one line instead of by `lsof` archaeology.

Acceptance gains one case: a run whose child outlives it must NOT leave the lock held — assert by
starting a run that spawns a long child, killing the run, and proving the next run acquires
immediately.

## Addendum 3 — measured precisely, with one correction

`lsof` on the lock file lists processes with the fd OPEN, which is not the same as holding the
flock. But it matters here anyway: an inherited fd shares the same open file description, so the
flock stays held until EVERY inherited copy is closed. A single orphan is enough to hold it.

Decisive test (do this, not lsof-counting):

```
( exec 9>/tmp/leadv2-core-offline.lock; flock -n 9 && echo FREE || echo HELD )
```

After sweeping orphans the lock came back HELD — by exactly one live `flock 9` belonging to a
running lane. That is correct behaviour. The pathology is only the orphan case.

Also found while measuring, and worth its own row: **11 orphaned `leadv2-single-lead-beat-loop.sh`
processes, ppid=1, some running 22+ hours**, in worktrees of long-merged lanes AND inside test
fixture directories (`repo-glm`, `repo-codex`, `target`). Killing them did not reduce the count —
they respawn. Leaked beat loops in fixture dirs are a plausible source of the foreign-repo pulses
the founder saw. Do not fix that here; file it separately as BEAT-LOOP-ORPHANS-01.
