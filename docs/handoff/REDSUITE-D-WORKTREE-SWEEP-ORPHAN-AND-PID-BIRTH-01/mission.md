# REDSUITE-D-WORKTREE-SWEEP-ORPHAN-AND-PID-BIRTH-01

Row `f43a661f5ece`. One red suite, three failing cases, subject `leadv2-worktree-cleanup.sh`.

**Read `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md` first and follow it.**

## What was measured, by the lead, on main, before this lane existed
macOS Darwin 25.6.0, run alone at a 400s ceiling, 2026-09-15: `test-worktree-lane-safety.sh rc=1
wall=56s`. Three cases fail:

```
FAIL: P6-orphan-swept-and-journaled(hook) -- post-fix rc=2, expected 0
FAIL: P6-orphan-swept-and-journaled(dead) -- post-fix rc=2, expected 0
FAIL: P14-pid-birth-lib-absent-degrades
```

The rest of the suite is green, and several cases record a genuine `RED-then-GREEN` transition
(`P8-malformed-env-degrades(dead)`, `P11-age-from-gitdir-not-dirmtime(dead)` — both `pre_rc=1 ->
post_rc=0`). So the harness works and these three are real.

One case is explicitly labelled `GREEN-PRE-FIX: P12-min-age-s-precedence(dead) -- also passed
pre-fix; a safety invariant, not evidence of this fix`. Respect that distinction in your report:
a case that was already green is not evidence your change did anything.

## The detail that should shape your diagnosis
P6 fails with **rc=2, not rc=1**. In this codebase 2 is a refusal — the sweeper declining to act —
while a failed sweep would surface differently. So the likely story is not "the sweep is wrong" but
"the sweep never ran, because something refused it". Find what returns 2 on that path and what
condition it is guarding, and say whether the guard is right and the fixture is wrong, or the
reverse. That decision is the substance of this lane; the diff is small either way.

Both P6 variants (`hook` and `dead`) fail identically, which is evidence for a single shared cause
upstream of both rather than two bugs. Prove that rather than assuming it: if one mutation moves
both variants, say so; if it takes two, you had two causes.

P14 is a degrade path: the pid-birth library is absent and the code is asserted to degrade
gracefully. Degrade paths fail silently by nature, so read the assertion carefully before deciding
whether the subject or the assertion is wrong.

## Write-set note
Your declared write set names `plugins/leadv2/scripts/leadv2-worktree-cleanup.sh` and the suite. If
P14's real owner turns out to be the pid-birth library itself, **you cannot write it** — the write
set is fixed at dispatch. In that case fix what you can, leave P14 red, and name the exact file you
needed in the report. That is the correct outcome, not a failure.

## Deliverables
- Fixes with one negative control per independent claim.
- `docs/handoff/REDSUITE-D-WORKTREE-SWEEP-ORPHAN-AND-PID-BIRTH-01/report.md` per `lane-rules.md`.

## Acceptance
```
cd ~/Projects/leadv2 && bash plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh >/dev/null 2>&1
```
Red today (rc=1).
