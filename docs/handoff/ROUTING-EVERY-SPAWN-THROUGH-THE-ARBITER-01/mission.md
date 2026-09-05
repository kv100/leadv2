ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01 — every agent spawn, in every repo carrying the lead
plugin, must pass through the arbiter. No exceptions, no name lists, no carve-outs.

FOUNDER DECISION 2026-09-04, and it supersedes the earlier draft of this work
(`ROUTING-HAS-NO-ENFORCING-LAYER-01`, superseded before any code was written):

> "мой кол в том чтобы всегда во всех репо где есть плагин лида агенты спавнились через диспатч
> и арбитра, все. а мы уже сделаем так чтобы арбитр был умным."

Shared plugin tree, so it holds for every consumer of the plugin and every repo on this machine.

THE TWO THINGS THAT ARE NOT THE SAME, and the whole design rests on the distinction:

- The **arbiter** picks arm + model, accounts quota, and RECORDS the decision. Sub-second,
  in-process, no files. → **EVERY spawn, always.**
- The **dispatcher** additionally creates a worktree, a registry row, gates and phases. Tens of
  seconds, files on disk. → **lane work only.**

Routing recon through the dispatcher would be wrong three ways, all measured 2026-09-04: every
registered lane gets a twin registry row that blocks the NEXT dispatch (this halted all work for
two hours today); a five-second haiku read becomes half a minute with a worktree; and when the
dispatcher is broken — it refused eight consecutive times today — we would lose the ability to
diagnose it, because the diagnosis would go through it too.

THE DEFECT AS IT STANDS, measured, file and line:
- `plugins/leadv2/hooks/leadv2-codex-first-nudge.sh:113` hardcodes
  `'permissionDecision': 'allow'`. It is structurally incapable of refusing; it can only print.
- `leadv2-router.sh` is a calculator that prints a recommendation.
- The shoulder table in `extensions.md` is a document.
A direct `Agent(subagent_type=developer, model=sonnet)` walks past all three. It happened
2026-08-27 and again 2026-09-04, and both times the nudge fired and was ignored, because being
ignored is all it can do.

## Part 1 — the arbiter must be able to route EVERYTHING (do this FIRST)

`lib/leadv2-route-arbiter.sh` decides well for build work. Enforcement cannot be switched on
before it can also answer for the other kinds, or recon gets denied with nowhere to go.

Teach it `work_kind` at minimum: `build`, `recon` (read-only exploration), `review`, `plan`.
Existing callers pass `work_kind` already — check what they send before inventing names.

Routing intent, as config rows, not code branches: recon is cheap and high-volume → the cheapest
capable arm (haiku / freepool where healthy); review → per the repo's existing table, never the
same arm that authored the diff; plan and safety judgment → the pinned expensive models, which is
already recorded doctrine. Do not silently change existing build routing.

Part 1 is done when the arbiter returns a sensible arm for all four kinds and the decision line
names the kind. Show all four.

## Part 2 — enforcement (only after Part 1 is proven)

A spawn with no arbiter decision is DENIED. The predicate is the ABSENCE OF A RECORDED DECISION —
**no model name, no provider name, no subtype name may appear in it.**

Two independent reviewers each found a name-list hole in the earlier draft of this mission before
a line was written: first "gate developer/frontend-developer/postgres-pro" (bypassed by
`general-purpose` and `claude`, both write-capable catch-alls), then "gate write-capable spawns on
Claude models" (bypassed by freepool, glm, kimi — the founder's own objection). Assume there is a
third hole and that it is in whatever you are about to enumerate. Enumerate nothing.

The refusal must name the way forward: consult the arbiter (for a plain spawn) or route through
`leadv2-dispatch-code.sh` (for lane work). Verify both paths exist before printing them — a
refusal pointing at a script that is not there is worse than no refusal.

There must be a kill switch — one environment variable that disables enforcement — and its name
must appear in the refusal text. This ships to three repos at once; if it is wrong, the founder
must be able to turn it off in one step without editing a file.

## ACCEPTANCE

Part 1: the arbiter answers for `build`, `recon`, `review`, `plan` — four decision lines, verbatim,
each naming the kind and a sensible arm.

Part 2, six cases:
1. A spawn with no arbiter decision → DENIED, with the way forward in the text. Verbatim.
2. The same spawn after consulting the arbiter → passes, and the decision is readable back where
   you claim it is written. Show the read-back.
3. `Agent(subagent_type="general-purpose")` write-capable → DENIED.
4. A spawn on a NON-Claude arm — freepool, glm, kimi → DENIED. The door nobody names.
5. Recon → routed, NOT denied: it consults the arbiter, gets a cheap arm, and proceeds. If recon
   is denied, Part 1 is incomplete and enforcement must not ship.
6. Kill switch set → everything passes, verbatim proof.

NEGATIVE CONTROL, mandatory: restore `permissionDecision: 'allow'` inside the function body,
re-run case 1, show it passes; restore the fix, show denied. Both outputs verbatim. An inert guard
and a working guard are indistinguishable by silence — that exact class was caught four separate
times on 2026-09-04.

## DEPLOYMENT — the step that decides whether any of this changes behaviour

Hooks load from the plugin CACHE, not the tree you edit. Editing the file changes nothing by
itself. Copy the hook into the cache, and state plainly whether the hook ROSTER (`hooks.json`)
changed — if it did, a session restart is required and you must SAY SO rather than claim the fix
is live. `claude plugin update` no-ops for directory-source marketplaces when content changed but
the version did not. A "fixed" file with unchanged behaviour is the lying-green disease this task
exists to end.

## CONSTRAINTS

Shared plugin tree feeding three repositories; the founder authorised this explicitly. Land Part 1
and Part 2 as separate commits so enforcement can be reverted without losing the routing work.
Never `git add -A`. Do not push to origin. `tests/known-red-suites.txt` and
`tests/known-failures.txt` may only shrink. The suite carries a `# run-all-triggers:` header naming
the hook and the arbiter lib; prove CI selection with `tests/run-all.sh --scope changed`. Report
the suite's final count line verbatim; if it prints none, say so. If the close gate returns
`e2e_regression`, run the named suites on main WITHOUT your commit before believing it — a verdict
is not evidence.
