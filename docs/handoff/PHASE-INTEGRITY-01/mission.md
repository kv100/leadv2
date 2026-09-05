# PHASE-INTEGRITY-01 — a phase counts only if it actually ran

**Canonical. This lands once and binds persona-engine, m3-market and respiro-ios.** The founder
asked for this at the plugin level explicitly: lead discipline does not scale, because the next
lead in the next repo repeats the same shortcut.

## What actually happened, 2026-08-29, in one session

The lead ran a whole session — one opening task plus several added mid-session — and **never
classified a single task.** No `class:` was ever written to any `docs/leadv2/tasks/<id>/STATE.md`.
Phase 1 did not happen, and nothing stopped it.

Two mechanisms let that through, and both are in this repo:

### Hole 1 — the silent class fallback

Every dispatch this session journalled `task_class=Heavy route=phases source=fallback`. With no
classification recorded, the dispatcher **invents** one rather than refusing. A silent default is
what made skipping Phase 1 free: the task still moved. The result is the worst combination —
Heavy's ceremony on paper, Trivial's rigour in fact.

### Hole 2 — self-certifiable phase proof

`leadv2-phase-record.sh record <sig> plan --artifact <path>` accepts any file that exists. The
lead hand-wrote `context.yaml` and `.gate1-passed`, recorded `diverge`, `plan` and `gate1` against
its own files, and the admission guard passed. **The party being checked writes the evidence.**

The lead did this on six separate dispatches. It is not an accident of one run; it is the cheapest
path through the gate, so it will always be taken.

## What that cost, measured

One task (POST-COUNTER-BLIND-TO-CHAINS-01) consumed five dispatches and four rounds before an
opus review returned FAIL with 4 High: a census covering 6 of ~23 call sites; a false premise
("PostgREST cannot express this OR across a jsonb array") asserted by the lead and built on by the
worker; five COUNT queries turned into unbounded fetches; and a test that stays green when the fix
is reverted. A real Phase 2 exists precisely to catch these before a worker starts.

Worse: to satisfy the `plan` proof, the lead copied a 26KB architect prepass **from six days
earlier** into three fresh handoff dirs. It contradicted the mission, and three codex workers
correctly stopped without implementing. This repo's own code already names that failure — the
prepass invalidation logic exists because a stale artifact "killed rounds 2-3 of
dispatch-16fbe872".

## Build this

**A phase is satisfied only by evidence that the phase ran as a distinct process.**

1. **No silent class default.** An unclassified task is REFUSED with a message naming what to do,
   never defaulted to Heavy (or anything else). If a caller genuinely wants to declare a class,
   the explicit flag remains the way — but absence must stop the dispatch, not pick for it.
2. **`plan` proof must be machine-attributable to a planner run** — a journal record of the
   planner actually executing (arm, run id, timestamp), not merely a file on disk. A document the
   lead authored seconds earlier must stop counting.
3. **`gate1` proof must trace to a real decision** — an answered question in the control-plane
   question store, or a journalled `gate1_auto_accepted` with its rc. Not a hand-written sentinel.
4. **`skipped` becomes a first-class recorded state** with a reason, distinct from `done`.
   Deliberately skipping diverge on a Light task is legitimate; recording it as *done* is not.
5. **Staleness is fatal, not advisory.** A plan/prepass artifact older than the lane's base commit,
   or predating the current mission revision, does not satisfy the phase.

Follow the code. Where these five statements conflict with what the code actually does, the code
wins and you say so in your report.

## Out of scope — do not decide it here

*Which* planning mechanism Standard+ should use (the Phase-2 triad, the in-dispatch
`architect_prepass`, cost, model, trigger predicate) is a separate open question the founder has
not settled — he raised a specific objection that reviving `architect_prepass` reintroduces a
"fast single architect → worker → many review rounds" shape and the quota burn that got it
disabled on 2026-08-25 (`LEADV2_DISPATCH_ARCHITECT_GATE=0`, commit `b9c235ee4`). A Codex design
pass is running on it separately. **This task makes phase evidence honest; it does not choose the
planner.**

## Prove it — evidence, not a diff

1. **A test that reproduces the exact 2026-08-29 bypass:** hand-write a `context.yaml` and a
   `.gate1-passed`, record `plan` and `gate1` against them, attempt a dispatch. It must be refused.
   Show it passing today (the bypass works — red) and refused after your change (green).
2. **A test for the unclassified path:** dispatch with no class recorded → refused, with the
   message naming the remedy. Show both directions.
3. **A test that a legitimate flow still works** — a real planner run satisfies `plan`, a real
   answered gate satisfies `gate1`, a `Light` task legitimately skipping diverge dispatches fine.
   If this suite is not green, the fix is a wall, not a gate, and it will be turned off within a
   week exactly like the prepass was.
4. The repo's own suite — name the command, and report the count as a **delta**, not an absolute:
   `plugins/leadv2/scripts/tests/run-core-offline.sh` currently has **11 pre-existing failures in
   LANE-PLACEMENT-01 on untouched `main`** (verified 2026-08-29). Do not attribute those to
   yourself, and do not let them hide a new one.
5. `git diff --stat`.

Report to `docs/handoff/dispatch-<task>/developer.md`.

## Scope

`plugins/leadv2/scripts/leadv2-dispatch-code.sh`, `plugins/leadv2/scripts/leadv2-phase-record.sh`,
and tests under `plugins/leadv2/scripts/tests/`.
