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
- `plugins/leadv2/scripts/tests/test-quota-reset-arbiter.sh` — case (d) made
  deterministic (pre-existing red on pristine main, same anthropic-stub drift
  class: the bare all_arms_capped refusal stopped firing; now a pinned capped
  arm refuses through the same prints). 8/1 -> 9/0.
- `docs/handoff/w-spawn-deadlock/mutation-control/` — two control artifacts.
- `docs/handoff/w-spawn-deadlock/report.md` — this file.

`leadv2-model-inherit-guard.sh` NOT touched (the reproducer already passes it;
its no-model denial for built-ins is unchanged and still stands).
`leadv2-dispatch-code.sh`, `config/direct-spawn-gate.yaml` untouched, per brief.

## Acceptance evidence

### The real spawn through both hooks (half the acceptance)

The EXACT reproducer payload, real hooks, real arbiter, live journal — first
`verdict=allow` in the policy's lifetime (only the quota probe is stubbed to a
healthy anthropic window; the live window is honestly forecast-blocked today,
see the next block):

```
PAYLOAD='{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"haiku","prompt":"map the auth flow"}}'
=== hook 1: model-inherit-guard ===   rc=0 (silence + rc0 = pass)
=== hook 2: spawn-arbiter-gate ===
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow",
 "additionalContext": "[leadv2-spawn-arbiter-gate] arbiter decision on record:
 kind=recon arm=haiku model=haiku tier=standard reason=explicit_requested_capable
 recorded=2026-09-10T11:39:36Z -- spawn honours this decision."}}
VERDICT-LINE: verdict=allow
=== live journal tail ===
{'subtype': 'Explore', 'work_kind': 'recon', 'arm': 'haiku', 'model': 'haiku',
 'tier': 'standard', 'reason': 'explicit_requested_capable', 'ts': '2026-09-10T11:39:36Z'}
```

### Fully live run (no stubs at all), same payload, same minute

The live anthropic window is forecast-blocked, so the honest live answer today
is a NAMED, current refusal — not the historical deadlock (the arbiter no
longer answers freepool-default; freepool drops itself as not_in_pool):

```
permissionDecision: "deny"
Gate consult (one call ...; speakable pool: sonnet opus haiku fable):
  arm=refuse model=none tier=none reason=requested_arm_forecast kind=recon
  requested_arm=haiku chain= util_glm=22 util_codex=47 util_claude=64
  util_freepool=0 reset_claude=34.36h_live
  arm_excluded=freepool:not_in_pool,haiku:forecast
journal: {'arm': 'refuse', 'reason': 'requested_arm_forecast', 'subtype': 'Explore', ...}
```

This is the system working: the first live `verdict=allow` on a bare spawn
arrives when the anthropic window has headroom; the mechanism no longer
depends on anything unpronounceable. NOTE for the founder: under
`kind=recon` the speakable pool has exactly one arm (haiku; freepool is
excluded by founder order 2026-09-09), so a bare recon spawn is only as
available as the anthropic window. If bare recons should survive an
anthropic forecast block, that is a matrix/policy row (add a speakable recon
cell), not a gate change.

### Falsification set

`bash -n` over every changed shell — all OK:

```
OK  bash -n plugins/leadv2/hooks/leadv2-spawn-arbiter-gate.sh
OK  bash -n plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
OK  bash -n plugins/leadv2/scripts/tests/test-spawn-arbiter-gate.sh
OK  bash -n plugins/leadv2/scripts/tests/test-spawn-speakable-pool.sh
OK  bash -n plugins/leadv2/scripts/tests/test-quota-reset-arbiter.sh
```

No standalone Python files changed (the arbiter's python is embedded and is
exercised by every suite run above).

### Suites

New suite `test-spawn-speakable-pool.sh` — 26/26, including the brief's
acceptance pairs (A: Explore+decided model passes on attempt one, exactly one
consult; B: undecided models keep the same refusal opening — freepool-default
as not_in_pool, kimi-k2 as requested_model_unknown; C: model-less custom
agent passes + pre-existing-record path untouched; D: emptied pool refuses
pool_empty_all_excluded naming every arm+stage; E: garbage/missing arbiter ->
named refusal; F: auto-consult kill switch; G: kind assumption named and
escapable; H: mutation bites — strip the speakable branch and the arbiter
answers freepool again).

```
SUMMARY: pass=26 fail=0        # test-spawn-speakable-pool.sh
SUMMARY: pass=28 fail=0        # test-spawn-arbiter-gate.sh (was 20/5 on pristine main)
SUMMARY: pass=9 fail=0         # test-quota-reset-arbiter.sh (was 8/1 on pristine main)
```

Neighbour regression sweep (worktree, post-change):

```
test-route-arbiter.sh                  rc=0 0 fails
test-route-arbiter-loud-refusal.sh     rc=0 0 fails
test-route-arbiter-failure-memory.sh   rc=0 0 fails
test-route-arbiter-spend-forecast.sh   rc=0 0 fails
test-quota-reset-arbiter.sh            rc=0 (after case-(d) repair)
test-think-through-arbiter.sh          rc=0 0 fails
test-arbiter-seam-plugin-kind.sh       rc=0 PASS=14 FAIL=0
```

### Mutation controls (leadv2-mutation-control.sh artifacts)

```
MUTATION-CONTROL ok suite=.../test-spawn-speakable-pool.sh
  file=.../leadv2-route-arbiter.sh sed='s/if speakable is not None:/if False:/'
  red_line=AssertionError: {}          # H0: the auction answered freepool
MUTATION-CONTROL ok suite=.../test-spawn-speakable-pool.sh
  file=.../leadv2-spawn-arbiter-gate.sh sed='s/^SPEAKABLE_MODELS="sonnet opus haiku fable"/SPEAKABLE_MODELS=""/'
  red_line=FAIL: A1 verdict=deny       # emptied pool -> loud refusal -> reproducer reds
lane_diff_hash=ac28c8696e1230825792dc8f72d3926e34f5ceefd58ec9c9e0e506efba2a98ae
```

Artifacts: `mutation-control/20260910T114324Z-18921.txt`,
`mutation-control/20260910T114353Z-51524.txt`.

### Changed-scope runner

`tbd — appended when the background run completes`
