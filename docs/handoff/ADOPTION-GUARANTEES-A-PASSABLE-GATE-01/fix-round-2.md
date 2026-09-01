# ADOPTION round 2 — the healer always exits 2, and one guarded path is still ignored

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ADOPTION-GUARANTEES-A-PASSABLE-GATE-01`

Round 1 (`c10c9df`) landed the shape of the fix and a real 17-case suite. Measured on the lane
commit, `LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh`
gives **PASS=7 FAIL=10**. Do not add features this round — make these ten green.

## 1 — `rc=2` on every path (fix this FIRST; it causes 4 of the 10)

```
FAIL: blanket */*: adoption exits 0 (rc=2)
FAIL: blanket dispatch-*: adoption exits 0 (rc=2)
FAIL: already-correct: re-adoption exits 0 (rc=2)
FAIL: second adoption exits 0 (rc=2)
```

The healer returns 2 even on the already-correct repo, which is the path that must be a silent
no-op. Find out what sets 2 — from the runtime, not by reading — and say in `report.md` what it
was. Exit codes must be: 0 = satisfied or healed, non-zero **only** when the repo genuinely cannot
be made committable.

## 2 — the guarantee does not actually hold

```
FAIL: blanket */*: all gate artifacts committable after adoption (git check-ignore still ignores a guarded path)
FAIL: blanket dispatch-*: all gate artifacts committable after adoption
FAIL: blanket */*: round-N brief paths still ignored (0/2 committable)
```

After adoption, `git check-ignore` still ignores at least one guarded path, and **neither**
round-N brief path is committable. This is the whole point of the task: an ignored
`fix-round-N.md` is why round-2 instructions never reached a worker in the first place. Assert with
`git check-ignore`, never by reading `.gitignore` — a negation that is present but overridden by a
later rule reads as fixed when it is not.

## 3 — idempotency and silence

```
FAIL: already-correct: re-adoption printed output (out=0B err=1173B)
FAIL: idempotency: guarantee block appears 0 times
```

An already-correct repo must print **nothing** — 1173 bytes on stderr is not silence, and stderr
counts. And the guarantee block appears **zero** times after adoption, which means the write did
not happen at all: the earlier "committable" failures are probably the same defect seen from
another angle. Fix the write first, then re-measure before touching anything else.

## 4 — the unfixable path must report

```
FAIL: unfixable: no UNFIXABLE report in output
```

The exit code is already right here; the message is missing. A repo that cannot be healed must say
so loudly and name the path it could not free — a repo that looks adopted but silently cannot pass
its gate is exactly the failure this task exists to remove.

## Acceptance

`PASS=17 FAIL=0`, plus the negative control: remove the guarantee from the production body ⇒ suite
red; revert ⇒ green; `git diff --stat` clean. Prove suite selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path. A kill counts only if this suite alone
  goes red, **and only if the suite was green first**.
- Never modify a real repository's `.gitignore` from a test.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

Adoption exits 0 when it heals or when there is nothing to do, prints nothing when the repo is
already correct, leaves every gate artifact **and** both round-N brief paths committable by
`git check-ignore`, and says loudly when it cannot.
