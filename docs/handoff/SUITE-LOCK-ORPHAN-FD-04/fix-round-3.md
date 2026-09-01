# SUITE-LOCK round 3 — four named failures, and the control must be fixed FIRST

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SUITE-LOCK-IS-MACHINE-WIDE-01`

Round 2 landed the per-repo lock scoping (`57aa62a`) and that part is proven on live paths: three
worktrees produced three distinct lock files. Round 2's own suite, however, finished `pass=8 fail=4`,
and **one of the four failures is its negative control**. A suite whose control does not fire is not
evidence of anything, so nothing else in this round counts until case 7 is fixed.

Do these in the order given. Do not start case 6 before case 7 is green.

## 1 — case 7: the negative control does not fire (fix this FIRST)

The control restores the old machine-wide literal lock path inside the production body and expects
the scenario to go red. It stays green. That means the scenario under it does not actually depend on
the scoping — it would pass with or without the fix, which is exactly the lying-green shape this
whole task exists to remove.

Find out why the scenario is insensitive to the mutation and make it sensitive. The likely shapes:
the scenario never reaches the locking path at all, or it runs both halves inside one repo root so
scoped and unscoped resolve to the same file. Say in `report.md` which it was.

**A green control is a failed round.** Show the run output: control applied ⇒ red, reverted ⇒ green.

## 2 — case 6: `LEADV2_SUITE_LOCK_FILE` override is ignored

The env override must still win over the derived per-root path — that is the documented one-step
rollback for this whole change. If the derivation now runs unconditionally, the rollback does not
exist. Restore the precedence: explicit env var > derived per-root path > default.

## 3 — case 2: two runs in the SAME repo root must still serialise

Per-repo scoping is correct only if it still excludes concurrent runs *within* one root. Round 2's
comment at `run-core-offline.sh:44-55` is the reason this matters: the lock guards a hermeticity
post-condition that runs `git status -- docs/leadv2` against the real shared tree, so two runs in one
root genuinely conflict. Same root ⇒ same lock file ⇒ second run waits or refuses. Prove it with two
concurrent runs and their observed lock paths, not by reading the derivation.

## 4 — case 4: a bounded wait must fail LOUDLY

`LEADV2_SUITE_LOCK_WAIT_S` exists but the default path still calls bare `flock 9` — an **unbounded**
wait. That is what produced the day's worst failure: up to 47 orphaned `sleep 900` processes,
reparented to launchd, each holding the lock through an inherited fd, so every new lane blocked
forever and looked like a dead worker.

Two requirements:

- **a bounded wait that expires must exit non-zero with a message naming the lock file and the pid
  holding it** — never fall through silently and never wait forever by default;
- **the fd must not be inherited by children.** Set `FD_CLOEXEC` on the lock fd (or close it
  explicitly across every spawn). This is the actual mechanism behind the orphan pile-up: the child
  shares the parent's open file description, so the parent can exit while the child keeps the lock
  held. Prove it: spawn a child, exit the parent, show the lock is released.

## Acceptance

The existing suite goes `pass=12 fail=0`, with case 7 demonstrated as a real control (red under
mutation, green after revert), plus:

8. an inherited-fd scenario: parent takes the lock, spawns a child, parent exits ⇒ lock is free;
9. a bounded wait that expires ⇒ non-zero exit and a message naming lock file + holder pid.

Prove suite selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`.
- A kill counts only if this suite alone goes red, **and only if the suite was green first** — this
  is the rule round 2 broke.
- Never `flock` a path outside the fixture tree from a test; never kill a process outside it.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

The control fires, the env override still wins, two runs in one root still serialise, a bounded wait
expires loudly naming the holder, and a child cannot outlive its parent holding the lock.
