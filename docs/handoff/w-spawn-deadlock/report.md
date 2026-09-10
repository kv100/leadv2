# BUILTIN-AGENT-SPAWN-DEADLOCK-01 — report

Row `10ee163f7a3e`, worker lane, 2026-09-10. Brief: `docs/handoff/w-spawn-deadlock/brief.md`.

## What was broken

The spawn arbiter gate and the model-inherit guard formed a lock with no key:
`Explore` + `model=haiku` was denied for having no arbiter decision, `Explore`
without a model was denied for inheriting opus, and the arbiter — consulted as
the gate's own way-forward text instructed — answered `model=freepool-default`,
a value the built-in Agent tool cannot pronounce (`sonnet|opus|haiku|fable`).
Zero `verdict=allow` lines in the policy's lifetime: the nested-agent
mechanism never fired once.

## The fix (third thing, both guards standing)

Both guards are untouched in their semantics. What changed is the seam between
the gate and the arbiter:

1. **The gate declares the speakable set once** (`SPEAKABLE_MODELS="sonnet opus
   haiku fable"`, `leadv2-spawn-arbiter-gate.sh`) and passes it to the arbiter
   as `speakable_models` in the same descriptor request the gate already used.
   No second yaml, no arm-name list in the gate.
2. **The arbiter ranks inside the pool** (`leadv2-route-arbiter.sh`,
   `_pool_contains`): under `speakable_models` an arm enters the default
   auction only with a cell whose model is speakable (pool_default still
   applies). freepool drops out by itself — `freepool-default` is in nobody's
   speakable set — the right reason, not a hardcoded exclusion.
3. **The gate consults once itself** (the extra round is gone): on absence of
   a record the gate runs ONE arbiter consult (`kind=recon` — named in every
   denial as the gate's assumption for a bare read-only spawn) pinning the
   spawn's own model via the new `requested_model` descriptor field (resolved
   to an arm through the matrix, then the existing requested_arm machinery:
   honoured or refused honestly, never substituted). The SAME (subtype, model)
   predicate re-runs; a match passes the spawn on the FIRST attempt.
4. **Empty pool / unknown model / broken arbiter are loud**: the arbiter's
   existing `pool_empty_all_excluded` refusal names the emptiness arm by arm;
   a model no arm carries refuses as `requested_model_unknown` (journalled);
   a garbage or missing arbiter yields a denial naming "no decision line
   (rc=N)" / the re-install path — never a pass, never a silent fallback model.
5. **Kill switches**: `LEADV2_ROUTE_ENFORCE=0` (gate, pre-existing) and
   `LEADV2_SPAWN_GATE_AUTO_CONSULT=0` (new: revert to deny-without-consulting),
   both named in every refusal.

Work kind note: the auto-consult assumes `recon` and says so; when the work is
NOT recon the denial keeps the one-line true-kind consult (`work_kind:
build|review|plan`) and the retry then matches the record. The recon round —
the one measured 4/4 — needs no second step at all.

## Files changed

- `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` — `speakable_models`
  + `requested_model` descriptor inputs (opt-in; absent = byte-identical
  behaviour), speakable-aware pin shortcut, `requested_model_unknown` refusal.
- `plugins/leadv2/hooks/leadv2-spawn-arbiter-gate.sh` — `SPEAKABLE_MODELS`
  constant, `lookup_decision()` factored (same predicate re-run), one-call
  auto-consult, denial carries the arbiter's line verbatim.
- `plugins/leadv2/scripts/tests/test-spawn-speakable-pool.sh` — NEW suite,
  registered by the same `# run-all-triggers:` self-select header as its
  neighbours (`leadv2-spawn-arbiter-gate leadv2-route-arbiter`).
- `plugins/leadv2/scripts/tests/test-spawn-arbiter-gate.sh` — contract updates
  (auto-consult cases) + de-brittled two pre-existing reds (the decided
  arm/model is read from the consult line, not hardcoded; fresh subtypes for
  the no-record cases; deterministic kimi-pin refusal instead of the
  quota-stub shape that stopped refusing). Was 20 pass / 5 fail on pristine
  main before this lane; 28/0 after.
- `docs/handoff/w-spawn-deadlock/report.md` — this file.

`leadv2-model-inherit-guard.sh` NOT touched (the reproducer already passes it;
its no-model denial for built-ins is unchanged and still stands).
`leadv2-dispatch-code.sh`, `config/direct-spawn-gate.yaml` untouched, per brief.

## Acceptance evidence

(filled below as each probe runs)
