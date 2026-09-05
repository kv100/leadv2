# DISPATCH-FAILS-OPEN-ON-NO-CAPABLE-CELL-01

**The fail-open stays. It stops being silent.** Commit `d7942a83`.

## 1. How often, measured before anything was touched

Lane journals in this repo (`docs/leadv2/tasks/*/journal.md`; persona-engine
keeps its own — the store is not shared, checked).

| class | all time | dates |
|---|---|---|
| `rc=68 fail_open_to_ladder` — the `no_capable_cell` case | **4** | all 2026-09-04T19:58 … 09-05T00:33 |
| `rc=65 fail_open_to_ladder` | 11 | 08-26…08-28, none since |
| `rc=127 missing_fail_open_to_ladder` (arbiter not callable at all) | 14 | 13 on 08-26, **1 on 09-05** |
| `bench_fallback` rc=65 | 3 | 08-26 |

Denominator: 132 dispatches on 09-04, 25 on 09-05 → **4 of ~157 in that window
(~2.5%), 4 of 444 all-time (0.9%)**.

**Those 4 are one task, not four.** All in `dispatch-b5abfcfd`, retries of the
same lane; two never reached a spawn (`dispatch_refused
reason=duplicate_task_signature`). Real spawns through a fail-open: **two**.

**And they landed where the arbiter wanted anyway.** All four continue
`candidate_chain arms=glm,codex,sonnet` → glm, and the isolated arbiter on the
same yaml also picks glm. The *path* was wrong; the *outcome* was not. No cost
is measurable in what is recorded — the row's premise that this "spends money
and time every time it fires" is not supported, and was retracted.

## 2. What is actually broken: the event cannot be counted

The arbiter prints its reason:

```
arm=refuse model=none tier=none reason=no_capable_cell kind=code chain= ...
```

The dispatcher had already parsed it into `_arb_reason` — it uses that value two
lines above for `rc=3` — and then journalled the rc alone:

```
arbiter_broken task=<sig> rc=68 reason=fail_open_to_ladder
```

Which capability was missing is recorded nowhere. Worse, the route that follows
is an ordinary-looking `route_resolved by=router`, indistinguishable from a
normal v1 route, so the *share* of work taking this path could not be counted at
all. That is the measured defect — not the downgrade.

**Five sites discarded it the same way**, not one: `:8144` (this one), `:8218`
(bench fallback), `:8539` (exit76), `:8877` (arm advance), and
`leadv2-dispatch-product-close.sh:503` (reviewer). `:8131` is deliberately left
alone — there the arbiter *succeeded* and the fault is ours, already named by
its own `note=chain_not_dispatchable`.

## 3. Why not a hard refusal

`leadv2-dispatch-code.sh:8141` decided on purpose that a routing-config
vocabulary gap is never a hard refusal, and that is right: `no_capable_cell` is
born from a typo in a config vocabulary — this repo has had one (`sonnet` vs
`claude-sonnet` across two tables). A hard refusal converts a rare quiet
mis-route into **a total stop for every dispatch of that kind**. Trading a
measured zero for an unmeasured large is a bad deal. "Refuse with an explicit
downgrade" is what the fail-open already is, minus the name.

## 4. What changed

* `_arb_fault_detail` in `lib/leadv2-route-arbiter.sh` — the lib **both**
  scripts already source (`dispatch-code.sh:587`, `product-close.sh:33`). One
  owner, five readers, instead of a fifth copy of the same three-line parse.
  Unparsable or empty input yields `arb_reason=unparsed`, never an empty token,
  so the line shape stays fixed for anything grepping it.
* The resulting route carries ` after=fail_open arb_rc=<rc> arb_reason=<r>`.
  `_ROUTE_FAIL_OPEN` is empty by default, so an untouched dispatch emits
  **byte-for-byte** the line it emitted before.

### The reader census that chose the key's name

20 readers of `route_resolved`; every one greps a substring or `key=value`; none
anchors to end-of-line; none counts fields. So the key is **appended**, nothing
renamed or reordered.

| reader | how it reads | verdict |
|---|---|---|
| `leadv2-skill-telemetry-collect.sh:126` | matches the **event name** only (`PHASE_PREFIX_MAP`) | cannot see it |
| `test-leadv2-router-v2-toggle.sh:43,79,156` | substring of a **prefix** | safe |
| `test-effort-routing.sh:371` | needs a token *after* `effort=` | safe (`task=` already follows) |
| `test-freepool-gets-work.sh:178,179` | `[[:space:]]reason=cheapest_capable` | safe — **and it named the key** |
| 16 others (`lock-busy-reresolve`, `kimi-dispatch-spill`, `route-arbiter`, `model-select-telemetry`, `freepool-capability-floor`, `arm-capability-honoured`, `plugin-papercuts`, `dispatch-outcome-ledger`, `dispatch-ledger-partial-close`, `lockout-failure-class`) | substring / `key=value` | safe |

The field is `arb_reason=`, not `reason=`, precisely because of that fourth row:
a second bare `reason=` token would have collided with an existing assertion.
The name was chosen by measurement, not taste.

## 5. Coverage

Case **(g)** in `test-route-arbiter.sh`, whose triggers already name both changed
files (`leadv2-route-arbiter leadv2-routing.yaml leadv2-dispatch-code.sh`).

A **real** rc=68 is forced by cutting `capability_matrix` to a single
non-dispatchable cell, so the intersection with the dispatcher's ladder is empty
**by construction**, not by a coincidence of today's config. Assertions are on
**presence**: the line must appear and must name the missing thing.

The negative control **(g-red)** lives inside the suite, so it runs on every CI
selection rather than once by hand — and it refuses to pass when the green half
did not hold, printing `control NOT EVALUATED`.

| run | result |
|---|---|
| first | 11/3 |
| after the anti-tautology guard | **10/4** — the extra red *is* the control refusing over a dead fixture |
| after all four fixture defects closed | **13/1** |

The remaining 1 is case (e), red on main from both cwds and absent from
`known-red-suites.txt` — filed separately, not touched here.

CI selection proven by changing a production file
(`lib/leadv2-route-arbiter.sh`, marker reverted):
`[SELECT] …/test-route-arbiter.sh`, `run-all: 154 selected, scope=changed`.

## 6. Four defects in my own fixture, each visible only after the previous closed

Recorded because the *order* is the lesson.

1. **cwd outside the fixture.** The foreign-root guard
   (`FOREIGN-PROJECT-ROOT-GUARD-01`) compared env-root against the cwd-derived
   git root and re-rooted to the real checkout — so the dispatch read the real
   routing yaml. It printed `WARN: foreign project root detected`; the evidence
   was on screen and unread.
2. **A tautological green control.** `(g-red)` passed while `(g)` failed: with a
   dead fixture nothing was present in the unmutated run either, so "it
   disappeared" was true for the wrong reason. Fixed by a green-half flag, not a
   stricter assertion — an unevaluated control must be **red**, because in any
   summary a skipped control is indistinguishable from a satisfied one.
3. **`--writes src/x.py` into a shared namespace.** Refused as
   `dispatch_refused reason=writeset_overlap blocked_by=dispatch-c4c38811`
   *before routing was reached*. `c4c38811` is case (e)'s own deterministic
   signature — a row it left behind blocked a standalone probe minutes later, so
   the trace outlives the run. Each call now claims its own path.
4. **The fixture yaml was inert.** `leadv2-route-arbiter.sh:52` reads the
   **plugin's** `config/leadv2-routing.yaml` and never
   `$PROJECT_ROOT/.claude/ref/leadv2-routing.yaml` — that per-repo file is the
   *dispatcher's ladder* source. Two readers, two files, one filename. Filed
   separately as a product finding. `LEADV2_ROUTE_ARBITER_ROUTING_YAML` is the
   seam and is now pinned.

Defect 4 prompted a check of an already-closed lane: `test-effort-routing.sh`
uses the same one-arm-matrix trick, and its seam **is** pinned at all four
dispatches (`:45`, `:209`, `:293`, `:337`), so its presence proof stands. A
closed lane is a reason to look, not a reason not to.

None of the four would have been visible if the control had stayed tautological
— it would still be green over a completely inert fixture.
