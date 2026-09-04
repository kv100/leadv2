# ARBITER-ESTIMATES-BLIND-01 — round 2 report

## Census correction retained

The original brief named `resolve_arm` / `resolve_v2_dispatch`, but the live
selection path is the unconditional `route_arbiter()` call in
`leadv2-dispatch-code.sh`. The shadow v2 gate was therefore not changed as a
substitute for the live fix. The arbiter now receives the task judge's
complexity and duration estimate on every dispatch; an unavailable estimate
falls open as `unknown` and does not refuse the task.

## Routing rule

This implementation chooses a **config-driven reordering**, not an arm floor.
`router_v2.complexity_penalty` adds an effective-cost penalty to matching cell
tags. A complex estimate therefore demotes cheap/mechanical/bulk/background
cells without hard-coding an arm. No estimate or no matching rule leaves the
pure static-cost ordering unchanged. The decision line names
`complexity`, `duration_class`, `complexity_policy`, and (when active)
`reason=complexity_penalty`.

`leadv2-cost-estimate.sh` remains non-routing telemetry because it has no
per-arm live-provider price input. It now runs before arm selection, alongside
the judge; missing helper/output is a logged non-fatal degrade.

## Focused proof

```text
STANDARD_TRIVIAL:
arm=glm-flash ... reason=cheapest_capable ... complexity=trivial duration_class=short complexity_policy=none
STANDARD_CROSS_SUBSYSTEM:
arm=codex ... reason=complexity_penalty ... complexity=complex duration_class=long complexity_policy=penalty
ESTIMATE_ABSENT:
arm=glm-flash ... reason=cheapest_capable ... complexity=unknown duration_class=unknown complexity_policy=none
ESTIMATE_UNKNOWN:
arm=glm-flash ... reason=cheapest_capable ... complexity=unknown duration_class=unknown complexity_policy=none
MUTANT_BASELINE_TRIVIAL: arm=glm-flash
MUTANT_BASELINE_COMPLEX: arm=codex
MUTANT_TRIVIAL: arm=glm-flash
MUTANT_COMPLEX: arm=glm-flash
```

The mutant is a full temporary copy of `leadv2-route-arbiter.sh`; it replaces
the descriptor reads for `complexity` and `duration_class` inside
`route_arbiter()` with `unknown`. The baseline differs and the mutant
collapses, so the proof is sensitive to the live function body.

Focused suite after the fix:

```text
SUMMARY: pass=12 fail=0
FOCUSED_RC=0
```
