P6a — PHASES-ARE-NOT-SCALED-BY-COMPLEXITY-01, part A: a REAL complexity estimate, in a new file.
Row `f33ff575078f`. This is a founder gate item before WAVES, restated by him today verbatim:
«судья оценивает сложность и дальше она через N фаз проходит в зависимости от сложности, на каждую
задачу арбитр выбирает того, кто будет делать работу. Без постоянного выполнения этого нельзя
стартовать WAVES.»

REPO: ~/Projects/leadv2 (the plugin repo is the single source; edit there, never a copy in a project).
Design context: `~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/PLAN.md` §8.

## What already exists — this is NOT a rebuild, read §8 before designing anything

Two layers are already live and must be preserved:
- The phase list is already class-scaled. Real dispatches today emit
  `brain_decision class=Heavy phases=classify,diverge,plan,gate1,build,test,review,live_verify,e2e,close reason=declared_floor`
  and `brain_decision class=Standard phases=classify,plan,gate1,build,test,review,deploy,live_verify,close`.
- GATE-DEPTH-MUST-SCALE-WITH-COMPLEXITY-01 (commit `b9a40609`) already emits
  `complexity_gate_applied task=… complexity=… complexity_source=… pipeline_route=… forced_plan=… review_rounds=…`
  at `leadv2-dispatch-code.sh:4536`, with `plan_first|brief_direct` at `:4352` and review rounds 1/2/3
  at `:4355-4357`, consumed in `leadv2-dispatch-product-close.sh:1906`.

## The measured gap — the branch is real, the INPUT is not

Every `complexity_gate_applied` row that exists in the lane journals — nine of them, the entire
population — reads `pipeline_route=plan_first`. **`brief_direct` has never once been taken.**
`review_rounds` is only ever 2 or 3, never 1. Provenance: `complexity_source=flag` in six rows,
`heuristic` in two, `judge` in one.

So the class is mostly DECLARED by the caller (`reason=declared_floor`), the heuristic resolves the
whole fleet to `standard`, and the judge is reached once. **A condition that only ever evaluates one
way is a constant with a branch drawn around it.** It will pass every test written against it and
still not do the thing it was built for. Your job is the missing input, not a new branch.

## What to build — a new, standalone, testable estimator

`plugins/leadv2/scripts/lib/leadv2-complexity-estimate.py` (NEW), plus a CLI entry so a shell caller
and a test can both use it without importing Python. Given a mission text and its declared metadata
(kind, declared class, write-set size and paths, subsystem count), it returns a complexity verdict,
the `pipeline_route` and `review_rounds` implied by it, and — decisively — the RANKED SOURCE that
produced the answer, so `complexity_source` stops being `flag` by default.

Three rules that are not negotiable:

1. **Rank the sources and log which one won.** `flag` must become the exception an operator explicitly
   asked for, never the default path. The estimator must be able to say `complexity_source=estimate`
   with a reason a human can read.
2. **Asymmetry, and it points one way.** Unknown or low-confidence provenance resolves DEEPER, never
   shallower. A wrong-deep task costs tokens; a wrong-shallow one ships an unreviewed diff. Encode
   this as an explicit rule with its own test, not as an accident of thresholds.
3. **The easy half must be reachable.** `brief_direct` with `review_rounds=1` must be a verdict the
   estimator actually returns for a trivial or simple task. Until that happens end to end at least
   once, "easy task → brief and go" is a code path, not a behaviour. Prove it with a fixture whose
   input is a genuinely trivial mission (a one-line docs edit) and whose output is
   `pipeline_route=brief_direct review_rounds=1`.

## Scope boundary — the wiring is part B, not yours

`leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`, `lib/leadv2-glm-policy-resolve.py`,
`config/leadv2-routing.yaml` and `tests/run-all.sh` are held by live lanes. Do NOT touch them; READ
them freely (you need `:4352-4357` and `:4536` to match the existing verdict vocabulary EXACTLY —
your output strings must be the ones the existing consumer already understands). If the work seems to
require editing one, STOP and report which line and why.

Do not add the `EXTRA_SUITE_MAP` row. Instead, state in your report the exact row part B must add, and
say plainly that until it exists **CI does not select the new suite**.

## Acceptance
acceptance:
  surface: log_line
  observable: The estimator, run over a trivial mission, returns `pipeline_route=brief_direct` with
    `review_rounds=1` and a `complexity_source` that is not `flag`; run over a heavy multi-subsystem
    mission it returns a deeper route. Both verdicts use the same vocabulary the existing
    `complexity_gate_applied` consumer already parses.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the estimator's route-selection body, force `brief_direct` for the complex fixture. The
   suite must go red. **A suite that only asserts a `plan_first` row is not a control — it is the
   constant.** The control must assert the EASY case too.
2. Inside the source-ranking body, make every verdict report `complexity_source=flag`. The suite must
   go red.
Insert each mutation INSIDE the function body, never at top level — a top-level insert makes every
suite red for the wrong reason and reads as a pass.

## Constraints
- Never `git add -A`; name every path, and `git commit -- <the same paths>`.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim in the report carries its artifact: a diff hunk, a probe line, a suite output.
  "Unverified" is said out loud; "should work" is never said.

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-complexity-estimate.py, plugins/leadv2/scripts/tests/test-complexity-estimate-easy-half.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-a0b9aa86" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.