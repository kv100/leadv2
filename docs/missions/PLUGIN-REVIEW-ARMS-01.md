# MISSION — PLUGIN-REVIEW-ARMS-01 (every lane in the plugin's own repo ends unreviewed)

Work in `~/Projects/leadv2`.

## The defect

A lane dispatched inside the plugin repo itself gets no review. Today `4c9ddb05` — a real,
substantial change to the review gate — finished, committed, and the gate returned:

```
status: no_reviewer
author: glm
refusal: all_review_arms_unavailable
pool:
```

The pool is empty because this repo has no `routing.yaml`; the dispatcher logged
`route_resolved … rule=none reason=no_routing_yaml` on the way in, too. So the plugin repo — the
one repo whose bugs propagate to every consuming project simultaneously — is the only one where
nothing is ever reviewed. The lead had to review it by hand, and a lead reviewing his own
dispatch is exactly the arrangement the review gate exists to replace.

## What to build

Give this repo a working reviewer pool. Look at how a consuming repo configures it
(`~/Projects/persona-engine/.claude/leadv2-overrides/` is a live example) and give the plugin repo
the equivalent, adjusted for what actually makes sense here — this repo is bash and markdown, not
a product, so the arm mix and the protected-path list should reflect that.

Two things to get right:

- **Author-excluding must still work.** If glm wrote the diff, glm must not review it. Verify this
  holds with the config you add, do not assume.
- **A missing or broken config must fail loudly, not silently.** Today the absence of
  `routing.yaml` produced `rule=none` and a shrug. If the pool cannot be resolved, that should be
  a visible failure with a reason, not an empty `pool:` line.

While you are here: the plugin repo's dispatcher also warns
`phase_precondition_warn … missing=plan,gate1,build,test,review,live_verify,close` on every single
dispatch, and `leadv2-phase-record.sh` does not exist here at all (exit 127). Say whether that is
load-bearing or noise. If it is noise, silence it; if it is load-bearing, it means no phase is
ever recorded for plugin work and that is a second finding.

## Hard constraints
- Plugin repo only.
- Do not disable a gate to make it stop complaining.

## Evidence required
Dispatch a throwaway lane in this repo and show it resolving a real reviewer pool and producing a
verdict. Report to `docs/missions/PLUGIN-REVIEW-ARMS-01.report.md`. End with DELIVERABLE_COMPLETE.
