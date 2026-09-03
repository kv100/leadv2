# DISPATCH-PHASE-DEADLOCK-01 — a new lane cannot start, because the gate wants proofs only a started lane makes

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PHASE-DEADLOCK-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-phase-record.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh,tests/run-all.sh,docs/handoff/DISPATCH-PHASE-DEADLOCK-01/

Main is `720fba1` in `~/Projects/leadv2`. Branch from it.

## The defect, with today's cost

Every brand-new lane is refused:

```
[leadv2-dispatch-code] phase_precondition_refused task=<sig8> class=Standard missing=diverge,plan,gate1
[leadv2-dispatch-code] ERROR: dispatch refused: missing mandatory phases: diverge,plan,gate1
[leadv2-dispatch-code] ERROR:   remedy: leadv2-phase-record.sh record <sig8> plan --artifact <path>
```

The remedy does not work. `_verify_artifact` (`leadv2-phase-record.sh:410-430`) requires
concrete files that do not exist before a worker has ever run:

- `plan` → `docs/handoff/dispatch-<sig8>/context.yaml` containing `decisions`, or a non-empty
  `architect-prepass.md`;
- `gate1` → a non-empty `docs/handoff/dispatch-<sig8>/.gate1-passed`.

Recording a phase whose artifact fails that check stamps `proof=unverified` and prints
`assert will refuse` — so the remedy line points at a command that cannot satisfy the gate it
is offered for. The only way through is to hand-write those files, which is what I did eight
times today.

Measured cost on 2026-08-31: four dispatch attempts lost on `CODEX-DETACH-01`, one each on
`ANTI-SILENCE-ONE-MECHANISM-01`, `COMPLEXITY-ESTIMATOR-IS-OFF-01` and
`PULSE-BEATS-IN-IDLE-REPOS-01` — plus, now, a **red test on main**: `test-effort-routing.sh`
fails `sonnet argv=<no argv captured>` because its fixture dispatch trips this same refusal.

## [Critical] distinguish "phases were skipped" from "this lane has never started"

A lane with no phase record at all is at bootstrap, not in violation. The gate must let the
first dispatch through and hold its teeth for every subsequent one — a lane that HAS a phase
history and is missing a mandatory phase is still refused exactly as today.

## [Critical] a lead-authored brief plus an explicit gate decision must be admissible proof

When the lead has written the plan and taken gate 1, that is a real plan and a real gate — it
just does not live in `context.yaml`. Make `_verify_artifact` accept a brief the dispatch was
launched with (`@docs/handoff/<task>/brief.md` or a `fix-round-N.md`) as plan evidence, and an
explicit recorded gate decision as gate1 evidence, and mark the proof honestly — `attested`,
not `verified`, so the distinction from a machine-checked artifact is not lost.

Do not simply drop the requirement: a Standard/Heavy lane that skipped planning must still be
caught. Say in `report.md` what still gets refused after your change.

## [Medium] the remedy line must be actionable

If a refusal prints a remedy, running that remedy must clear the refusal. Today it does not.
Either make it sufficient, or print what the artifact must contain.

## Acceptance

Build `test-phase-precondition-bootstrap.sh` against fixture handoff trees — never a real lane,
never a real state root — covering:

1. a lane with no phase record ⇒ first dispatch admitted;
2. the same lane on a later dispatch, missing a mandatory phase ⇒ refused as today;
3. a lane whose plan evidence is only a lead-authored brief ⇒ admitted, proof recorded as
   `attested`;
4. running the printed remedy for a refusal ⇒ the next dispatch is admitted;
5. a Standard lane that genuinely skipped planning ⇒ still refused.

Add the `EXTRA_SUITE_MAP` rows and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production function body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`.
- A kill counts only if **this suite alone** goes red.
- A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion, and neither is a `FAIL:` line
  that leaves `$?` at 0.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Never run the suite against the real repo or the real dispatch ledger.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A first dispatch of a new lane succeeds with no hand-written files, a lane that skipped a
mandatory phase is still refused, `test-effort-routing.sh` goes green on main, and a mutation
collapsing bootstrap back into violation turns the suite red with the exit code following.
