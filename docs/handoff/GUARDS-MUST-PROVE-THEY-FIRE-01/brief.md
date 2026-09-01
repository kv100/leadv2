# GUARDS-MUST-PROVE-THEY-FIRE-01 — 92 guards, 2 of them observable, and the founder finds the dead ones by hand

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GUARDS-MUST-PROVE-THEY-FIRE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-guard-census.sh,plugins/leadv2/hooks/lib/leadv2-guard-verdict.sh,plugins/leadv2/scripts/tests/test-guard-census.sh,plugins/leadv2/scripts/tests/fixtures/guards/,tests/run-all.sh,docs/handoff/GUARDS-MUST-PROVE-THEY-FIRE-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## The founder's complaint, and why every audit so far has missed it

> "все вот эти гарды/хуки — что-то работает, а что-то нет, и хрен пойми как жить с этим; пока за
> руку не поймаю, ни аудиты, ни проверки особо не помогают"

He is right, and it is measurable. Measured on this tree, 2026-09-01:

```
92 hook scripts
12 have a mode flag at all
 2 leave a journal you can read to see whether they ever ran
```

Of those 12: **7 are OFF by default** (`pulse-enforcer`, `lead-edit-guard`, `bandit-preflight`,
`lead-prose-guard`, `broken-signal-gate`, `workflow-bypass-guard`, `workflow-sentinel-touch`),
**2 are log-only** (`promise-guard`, `compact-trigger`), 3 are on.

Two guards were caught inert THIS session, both by hand:

- `leadv2-promise-guard.sh` — 702 lines, correctly wired, journal shows **423 "would have blocked"
  across 1868 turns and zero actual blocks**, because it ships log-only;
- `leadv2-idle-lead-guard.sh` — supposed to refuse a turn end when work is queued and no lane is
  live. That state held all night and it never fired once. Its block condition requires
  `lane-liveness.sh --all` to answer `availability=authoritative`, and that script was hanging for
  240s+ on a Codex call (fixed separately in `afb6641`) — so the guard timed out and failed open,
  silently.

Existing audits check that a guard is *installed*. Both of these were installed. Installation is not
the property that matters; **the ability to fire is**.

## [Critical] 0 — the anti-silence guard stands on a liveness source that answers "nothing is alive", always

Measured 2026-09-01, while one lane was demonstrably writing files seven minutes earlier:

```
leadv2-lane-liveness.sh --all
  total rows   231
  alive rows     0
```

Every row is `dead:*`. And the three lanes dispatched to the **codex** arm that afternoon
(`faee3fc5`, `a605eb2a`, `cf05539d`) do not appear in the output **at all** — not alive, not dead,
absent. Only the GLM lane had a row, and that row said `dead:sentinel_finalized` while its worker
was running.

`leadv2-idle-lead-guard.sh` — the guard whose entire job is to refuse a turn end when work is queued
and no lane is live — consults exactly this. So its input is a constant: "no lane is live". A guard
whose predicate never varies is not a guard, and this is why it never fired once through a night in
which the founder repeatedly caught silence by hand.

This is the same blindness class the lead just fixed in his own session watchdog: it watched
`~/.claude/cache/glm-runs` only, so three codex lanes sat idle for 49-153 minutes while it reported
nothing. The founder's question — "do our anti-silence guards repeat the same mistake, do they see
ALL the work?" — is answered by the numbers above: no, they do not.

What this lane must establish:

1. **Why every row is dead.** Determine it from the runtime — a stale sentinel, a log-artifact path
   that no longer matches, a registry that is written but never updated. Name the cause in
   `report.md` before changing anything.
2. **Provider coverage is part of correctness.** A liveness answer that structurally cannot include
   codex lanes is wrong even when its GLM rows are right. Whatever signal replaces it must be one
   that every arm necessarily produces — the lead's own fix used mtimes inside the lane worktree,
   which no provider can avoid touching while working. Evaluate that or something better, and say
   why.
3. **A guard that depends on liveness must fail LOUD, not open.** `idle-lead-guard` times out and
   silently permits the turn. Any guard that cannot obtain its input must say so where it can be
   seen, per §3 below.

Acceptance case: a lane that is provably working (its worktree changed within the last minute) ⇒
liveness reports it alive, whichever arm it runs on. That single case would have caught this.

## [Critical] 1 — one honest state per guard

Every guard must land in exactly one of these, and the state must be derived, never declared:

| state | meaning |
|---|---|
| `not-wired` | not in `hooks.json` for any event |
| `never-ran` | wired, but no evidence it has ever executed |
| `ran-never-fired` | executes, but has never reached its own fire path |
| `fires-log-only` | reaches the fire path, does not block (the promise-guard case) |
| `blocking` | reaches the fire path and blocks |
| `disabled` | wired but its default flag is off (the seven above) |

`never-ran` and `ran-never-fired` are the two states nothing can see today, and they are where the
failures live. Decide from the runtime what evidence distinguishes them and say so in `report.md`.

## [Critical] 2 — a guard proves it CAN fire, or it does not count

This is the whole task, and it is the same doctrine as mutation-testing a suite: a guard that has
never been shown to fire is exactly as trustworthy as a test that has never been shown to go red.

Each guard ships a fixture that drives it into its fire path, and the census **runs those fixtures**
and reports which guards are provably capable of firing today. A guard whose fixture no longer makes
it fire is a REGRESSION and must be reported as loudly as a failing test — that is the signal that
would have caught `idle-lead-guard` the moment `lane-liveness` started hanging.

You will not write 92 fixtures in one lane. Do the shared mechanism plus fixtures for the guards
that actually gate work — the Stop-event guards and the PreToolUse guards that can block — and
report the coverage number honestly in `report.md`. A partial census that says "37 of 92 proven,
here are the other 55" is worth far more than a full one that assumes.

## [Critical] 3 — make "did not run" impossible to miss

A guard that cannot complete must not fail open silently. When a guard bails — timeout, missing
dependency, unreadable input — that fact is recorded with the reason. `idle-lead-guard` failing open
for hours with nobody knowing is the exact defect.

Keep it cheap: this runs on every relevant event, so the recording must not itself become the fork
pressure that `FORK-STORM-KILLS-HOOKS-01` is removing. Say in `report.md` what one record costs.

## [Medium] 4 — one table, read not diagnosed

One command prints: guard · event · state · last ran · last fired · fixture proven?. Sorted so the
dead ones are at the top. The founder must never again need to grep a hook to learn it was switched
off at the source.

## Out of scope

Do NOT flip any guard's default on or off in this lane. Making them observable and changing what
they do are two different decisions, and mixing them means a regression cannot be attributed.
`promise-guard`'s flip has its own lane (`PROMISE-GUARD-TURN-IT-ON-01`).

## Acceptance

Build `test-guard-census.sh` against fixture guards and a fixture `hooks.json` — never the real
`~/.claude`, never the real hook tree:

1. a guard wired and firing ⇒ `blocking`;
2. a guard wired whose flag defaults off ⇒ `disabled`, never `blocking`;
3. a guard that journals but never blocks ⇒ `fires-log-only` (the promise-guard shape);
4. a guard wired that never executes ⇒ `never-ran`, distinct from `ran-never-fired`;
5. a guard whose fixture no longer makes it fire ⇒ reported as a regression, non-zero exit;
6. a guard that bails on a timeout ⇒ recorded with its reason, not silently absent;
7. a guard absent from `hooks.json` ⇒ `not-wired`;
8. the census never mutates the real hook tree or the real journals.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Removing the fixture-proof step must turn case 5 red.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- Never reorder a hook array. Never write to the real guard journals from a test.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion. A census that reads source text to decide
  a guard "works" is the same lie in a new place — decide from behaviour.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

Every guard has a derived state, the ones that gate work carry a fixture proving they can still
fire, a guard that stops being able to fire reports as a regression instead of going quiet, and the
founder reads one table instead of catching a dead guard by hand.
