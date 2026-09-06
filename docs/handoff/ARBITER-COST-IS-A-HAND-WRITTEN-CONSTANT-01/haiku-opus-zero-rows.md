# Why haiku and opus have zero rows in model-select-telemetry.csv

Follow-up to `cost-ladder-census.md`. Question: instrument or behavior? Answer: **behavior for
both, on the path this telemetry covers — but there's a second, real instrument gap underneath
opus's answer that the first answer alone would have hidden.**

## The filter that actually decides it

`plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:55,60`:

```python
DISPATCHABLE_BUILD_ARMS = {"glm", "glm-flash", "codex", "sonnet", "freepool"}
DISPATCHABLE_PLAN_ARMS  = {"codex", "sonnet", "opus", "fable"}
```

`model-select-telemetry.csv`'s `role` column is 100% `worker` (checked: no other value exists in
692 rows) and its `work_kind` column has exactly 4 values — `build`, `diagnose`, `docs`, `review`
(checked: zero `plan` rows exist, ever). That means **this file only ever observes the
`DISPATCHABLE_BUILD_ARMS` path.**

- **haiku is in neither set.** It cannot appear in this telemetry no matter how it behaves,
  because it is never a dispatchable worker OR plan arm at all. Its only real usage is as a
  synchronous classifier (`leadv2-task-judge.sh`, referenced in `leadv2-dispatch-code.sh:4222` as
  "the ALREADY-AVAILABLE judge... haiku + code-only") — a fixed-role call, not a competing choice
  in the arbiter's ranking, and that script has zero references to
  `model-select-telemetry.csv`/`model_select_telemetry` (checked directly). **Verdict: behavior.**
  Haiku isn't silently winning and going unlogged — it structurally cannot compete for a build-path
  worker slot, by the same explicit filter that also blocks opus (`leadv2-dispatch-code.sh:8300-8302`:
  "the arbiter's own matrix can list haiku/opus as capable-and-uncapped, but neither is safe to
  auto-spawn").

- **opus is in `DISPATCHABLE_BUILD_ARMS`'s exclusion (same as haiku) for the WORKER path** — same
  citation, same reason: capable-on-paper, filtered before spawn. `leadv2-dispatch-code.sh` says
  outright: "arm=opus is never spawned (lead judgment, opus arms are reported but NOT
  auto-dispatched — those stay lead judgment)" and routes opus through
  `atomic_dispatch_reserve_confirm_opus()` — reserve-and-confirm, no process spawn, nothing for a
  worker-spawn telemetry line to describe. **Verdict for the build path: behavior**, and a
  deliberate one — opus escalation is meant to stay a human/lead judgment call, not an autonomous
  spawn.

  **But opus IS in `DISPATCHABLE_PLAN_ARMS`** — for planning work, opus (and fable) are real
  candidates, not filtered out. And this telemetry file has never recorded a single `plan`
  work_kind row, of any arm, ever. So opus's zero here is not fully explained by "opus never
  spawns" — for the plan path specifically, whatever chooses between codex/sonnet/opus/fable for
  planning work does not write to `model-select-telemetry.csv` at all. **That is a genuine
  instrument gap**, layered underneath the behavior answer: if I had stopped at "opus never spawns,
  behavior, done," I would have missed that plan-job routing (where opus is a live candidate) is
  simply invisible to this file, full stop, for every arm, not just opus.

## Answer

Not a single "it's behavior" or "it's an instrument gap" — both, cleanly separated by path:

| arm | build/worker path (what this CSV covers) | plan path |
|---|---|---|
| haiku | never dispatchable (behavior) | never dispatchable (behavior) |
| opus | never spawns, reserve-confirm only (behavior) | dispatchable, but **unmeasured — this telemetry file has zero plan-job rows for any arm** (instrument gap) |

If the founder or anyone wants to know whether opus is actually a good or bad choice when the
arbiter DOES pick it, this file cannot answer that — not because opus performs badly, but because
the file was never wired to record plan-job outcomes at all. That gap sits on the plan-routing
mechanism, wherever it lives (not yet located in this pass — would need tracing whatever calls
`leadv2-codex-planner.sh`/the plan workflow's own arm choice, which is out of this follow-up's
scope unless you want it pulled next).
