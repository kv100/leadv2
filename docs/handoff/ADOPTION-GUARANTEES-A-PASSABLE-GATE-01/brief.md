# ADOPTION-GUARANTEES-A-PASSABLE-GATE-01 — every repo must get a passable phase gate, not just the two I fixed by hand

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ADOPTION-GUARANTEES-A-PASSABLE-GATE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-repo-install.sh,plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh,tests/run-all.sh,docs/handoff/ADOPTION-GUARANTEES-A-PASSABLE-GATE-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Why this exists

The phase gate (`leadv2-phase-record.sh`) requires three artifacts to exist in a lane worktree:
`docs/handoff/dispatch-<sig8>/context.yaml`, `architect-prepass.md`, `.gate1-passed`. A lane
worktree only ever contains what is **committed**. In repos whose `.gitignore` blankets
`docs/handoff/*/*` or `docs/handoff/dispatch-*/*`, those paths can never be committed — so an
honest gate passage is physically impossible and the lead bypasses the gate instead. That is
exactly what happened on 2026-08-31 across a full day of dispatches.

I fixed it by hand in two repos (`leadv2` `6f6b55b`, `persona-engine` `833e4926e`). That is the
defect this lane exists to remove: a hand-applied fix is not a fix. Audited today:

```
dota-coach            ok
getmany-followup-bot  GATE UNPASSABLE (artifacts ignored)
platform              ok
respiro-ios           ok
tg-airwatch           ok
leadv2 / persona-engine  ok (hand-fixed today)
```

One repo is still broken, and every repo adopted in the future starts broken by default.

## [Critical] adoption must guarantee the invariant, in every repo, forever

`leadv2-repo-install.sh` already runs on every `/leadv2` invocation and is idempotent. Make it
also guarantee that the gate's required artifacts are committable in that repo.

Requirements on the implementation:

- **Idempotent and silent when already satisfied.** It runs on every invocation; it must print
  nothing and change nothing when the repo is already correct.
- **Additive, never destructive.** Append the needed negations; never rewrite, reorder or remove
  existing `.gitignore` lines. A repo's own ignore rules are the repo's business.
- **Verify by asking git, not by pattern-matching the file.** The check must be
  `git check-ignore` on the three concrete paths — the only thing that reflects what git will
  actually do. Grepping `.gitignore` for a string is how a negation that is present but overridden
  by a later rule reads as "fixed" when it is not.
- **Report honestly.** If it cannot make the paths committable (unusual ignore layering, a global
  ignore file, no `.gitignore` at all), say so loudly rather than leaving a repo that looks adopted
  and silently cannot pass its gate.

Do not special-case any repo by name.

## [Critical] the same guarantee for round-N briefs

`fix-round-N.md` was also ignored in `leadv2` until today, so round-2 instructions never reached
the worker that needed them. Whatever set of paths you guarantee, include the brief and round
files the dispatcher reads — determine that set from the dispatcher, and name it in `report.md`.

## [Medium] make the audit re-runnable

Provide a way to check every adopted repo at once (a `--check` mode is already the convention in
this script). The founder must be able to answer "is every project fine?" with one command, not by
opening seven repos. Say in `report.md` what the command is.

## Acceptance

Build `test-adoption-gate-passable.sh` against fixture repositories — never a real repo, never the
real `~/.claude`:

1. a fixture repo with a blanket `docs/handoff/*/*` ignore ⇒ after adoption, all three gate
   artifacts are committable (`git check-ignore` says no);
2. the same for a `docs/handoff/dispatch-*/*` blanket (persona-engine's shape — a different rule,
   same disease);
3. a repo already correct ⇒ adoption changes nothing and prints nothing;
4. running adoption twice ⇒ no duplicate lines added;
5. existing unrelated `.gitignore` lines survive byte-identically;
6. a repo where the paths cannot be made committable ⇒ loud, explicit failure;
7. round-N brief paths are committable too.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Removing the guarantee must turn this suite red.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion. Assert with `git check-ignore`, not by
  reading `.gitignore`.
- Never modify a real repository's `.gitignore` from a test.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

Adopting any repo — including a brand-new one — leaves its phase gate honestly passable, the
check is re-runnable across every adopted repo with one command, and removing the guarantee turns
the suite red with the exit code following.
