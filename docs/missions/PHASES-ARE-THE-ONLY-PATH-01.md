# PHASES-ARE-THE-ONLY-PATH-01 — build (plugin repo ~/Projects/leadv2)

## Outcome
No work reaches a worker outside the phase pipeline, and the phase a lane is in is a fact that
one script writes and everything else reads.

## Read first — the design is DONE, do not redesign
`~/Projects/persona-engine/docs/handoff/DISPATCH-KILLED-BY-FG-TIMEOUT-01/c4-design.md` (§1-§4,
§2b, §2c). Also `C4-founder-ruling.md` and `observability-findings.md` in the same directory.
Every "where / what / which class / which seam" question is already answered there with file:line.
Your job is to implement it, not to re-open it. If you believe a design decision is wrong, STOP and
report BLOCKED with the reason — do not silently substitute your own.

## Repo / base
Work in `~/Projects/leadv2`. **First action: `git fetch origin`, then bring the lane up to date with origin/main by
REBASE (`git rebase origin/main`) — an --ff-only merge fails once the lane has its own commits,
which already bit round 1 of the guard lane. Record the resulting SHA.** A stale lane base makes every later diff unreadable (it already
happened on lane 40241035 today, where a 333-line change read as 1628 deletions).

## Write set (allowed paths ONLY)
- `plugins/leadv2/scripts/leadv2-phase-record.sh` (new — the ONE writer)
- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (precondition guard + stamp sites)
- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` (review/e2e records)
- `plugins/leadv2/scripts/leadv2-phase8-close.sh` (close record)
- `plugins/leadv2/scripts/leadv2-status-surface.sh` (`lane_phase()` reads the record)
- `plugins/leadv2/docs/phases.md` (CX-03 removal, see below)
- `plugins/leadv2/scripts/tests/` (new tests)

## Requirements

**R1 — the precondition guard.** New `_phase_precondition_guard` in `cmd_resolve()`, at the same
structural slot as the existing `_lane_writes_guard` and `_acceptance_guard`, plus
`cmd_advance_arm`. Not a hook: 3 of 5 call sites are subprocess-internal and a PreToolUse hook
cannot see them, and hooks fail open by convention.

**R2 — one phase record, one writer.** `docs/handoff/dispatch-<sig8>/phases.d/<phase>.yaml`,
written ONLY by `leadv2-phase-record.sh`. Schema carries `status` (running|done|n/a|waived),
`handle`, `started_at`, `ended_at`, and a pointer to the phase's own artifact plus its sha256.
The artifact is the proof; the record is an index. An empty file satisfies nothing.

**R3 — the surface reads the record, never infers.** Rewrite `lane_phase()` (it is at
`leadv2-status-surface.sh:3035-3050`, called at :3138 and :3198 — NOT 987-1001, that range is
flat_yaml/journal_mtime/close_dir_mtime). Delete the directory-existence inference. `status: running`
is intent, not fact: corroborate it against `LANE_LIVENESS_BIN` using the record's handle; a dead
probe with an empty `ended_at` renders `review (stalled, started <age> ago)`, never `review`.

**R4 — active.yaml / pulse.json `phase` becomes a derived mirror.** Keep the slot; it has a working
writer chain (`leadv2_active_update_phase` at `active-registry.sh:577-593`). It reads empty only
because the dispatcher never registers an active.yaml session row (`backlog-pump.sh:253`) and
`_stamp_active_phase` swallows the failure (`>/dev/null 2>&1 || true` at dispatch-code.sh:353).
**Registering the dispatch lane in active.yaml is IN SCOPE.** phase-record.sh writes the record
first, then calls `leadv2_active_update_phase`, so mirror and record cannot disagree.

**R5 — class→phase table** per design §3. Mandatory in every class: classify, build, review, close.
Shrinking only via `--phase-waiver <phase>=<reason>` and only for phases listed in the project's
`waivers_allowed`; review and close are hard-excluded in plugin code.

**R6 — the override seam:** `.claude/leadv2-overrides/phases.yaml`, single plugin reader,
`class_overrides` add-only (removals rejected at parse), `steps:` on the fixed hook points, and
`waivers_allowed`. Absent file ⇒ today's behaviour unchanged.

**R7 — remove CX-03.** `plugins/leadv2/docs/phases.md:270` sets `model=skip` for light_low_risk,
which is review skipped by omission. The founder ruled 2026-08-05 that review is mandatory in every
class. Remove it and adjust the router path that consumed it.

**R8 — migration.** Ship gated on `LEADV2_REQUIRE_PHASES`, default **`warn`**. In warn mode the
guard journals `phase_precondition_warn` and proceeds. Fail-closed on day one would refuse every
in-flight lane and stall backlog-pump. Rollback is `LEADV2_REQUIRE_PHASES=0`, byte-identical to
today's behaviour, same convention as :384/:410/:416. The flip to enforce is ledgered separately as
`SD-PHASE-ENFORCE-01` — do not flip it here.

## R9 — `setsid` is not a valid backgrounding signal on macOS
The guard hook shipped in `69ad929` accepts `setsid` as proof a command is backgrounded, but
`setsid` does not exist on macOS (verified: `command not found`). A lead writing
`setsid bash .../leadv2-dispatch-code.sh ...` gets a command that never runs at all, while the
guard stays silent. Drop `setsid` from the backgrounded test, or gate it on
`command -v setsid`. Small, but it is a lie in a guard whose whole job is to not lie.

## Non-goals
Do NOT bind anything to `.claude/leadv2-overrides/gate1.sh` — it exists in persona-engine and has
zero readers in the plugin; it is an orphan and adopting it is a separate deliberate decision.
Do not change arm resolution, quota gates, or routing.

## Acceptance
- A dispatch for a Standard task with no plan/gate record journals `phase_precondition_warn` naming
  the missing phases; with `LEADV2_REQUIRE_PHASES=1` the same call is refused.
- `--phase-waiver review=<any>` is refused in every class.
- `--phase-waiver plan=<reason>` succeeds only when `plan` is in `waivers_allowed`, and the waiver
  is recorded in `phases.d/plan.yaml` with `status: waived` and the reason.
- A `phases.yaml` whose `class_overrides` REMOVES a phase is rejected at parse with a clear error.
- `lane_phase()` renders `review (stalled, ...)` for a record with `status: running`, an empty
  `ended_at`, and a dead liveness probe. Fixture test, no live lane needed.
- With no `phases.yaml` present and `LEADV2_REQUIRE_PHASES=0`, the existing test suite is green from
  the freshly-ff'd base.

## Rollback
`LEADV2_REQUIRE_PHASES=0`. Name it in your report.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw test output. Do not edit boards or plans.
