# SPAWN-GATE-AND-MODEL-GUARD-DEADLOCK-01 — report

Row `bd9c35163b33`, worktree `bd9c35163b33`, base `40327a32`.

## Verdict up front

The composition described in the brief is **no longer a deadlock**: the
intersection of spawns both `leadv2-model-inherit-guard.sh` and
`leadv2-spawn-arbiter-gate.sh` accept is **non-empty**, because a prior lane
(`BUILTIN-AGENT-SPAWN-DEADLOCK-01`, commit `55d40e29`, 2026-09-10 — same day
as this brief's reproduction) already closed the arbiter side of it. What
remained was (a) zero automated test coverage of the two hooks running in
sequence, the way a real spawn actually hits them, and (b) one real leftover
documentation hole in the gate's own DENY text, fixed below.

## 1. Reproduce all three refusals, on the CURRENT code

Harness: same stubbed quota/freepool/journal fixture the existing
`test-spawn-arbiter-gate.sh` suite uses (`ROUTE_TEST_QUOTA` healthy, fresh
`LEADV2_ROUTE_ARBITER_DECISIONS_FILE`). Real hook scripts, not mocks.

### Repro 1 — `subagent_type=Explore, model=haiku`, empty journal

Brief's claim: "arbiter gate DENIED (no decision on record for that
model)". **Does not reproduce today**:

```
--- hook: model-inherit-guard ---
(silent, rc=0 — explicit non-opus model always passes)

--- hook: spawn-arbiter-gate ---
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow",
 "additionalContext": "[leadv2-spawn-arbiter-gate] arbiter decision on record: kind=recon
 arm=haiku model=haiku tier=standard reason=explicit_requested_capable
 recorded=2026-09-15T00:46:23Z -- spawn honours this decision."}}
```

The gate's `BUILTIN-AGENT-SPAWN-DEADLOCK-01` auto-consult (added five days
before this brief's own reproduction note, same lane) now consults the
arbiter itself on absence of a record and re-tests the same predicate —
first attempt passes.

### Repro 2 — `subagent_type=Explore`, no model

Brief's claim: "model-guard DENY". **Still reproduces, correctly and
intentionally** — this is the guard doing its job, not the deadlock:

```
--- hook: model-inherit-guard ---
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
 "permissionDecisionReason":"model-guard DENY: subagent_type=Explore has no explicit
 model= -> it inherits the caller (opus) = double burn, zero savings. Re-spawn with
 model=haiku (reads/discovery/fan-out) or model=sonnet (code/verify). Pass model= on
 EVERY built-in Agent call."}}

--- hook: spawn-arbiter-gate (same event, run independently) ---
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow",
 "additionalContext": "... arm=haiku model=haiku ... reason=cheapest_capable ..."}}
```

The gate alone would allow (it owns no opinion on "no model" for built-ins —
that is explicitly the sibling guard's contract, confirmed in
`test-spawn-arbiter-gate.sh` case 3). The COMBINED verdict a real spawn
experiences is deny, correctly, because Claude Code fires every matching
`PreToolUse` hook and denies if any one denies.

### Repro 3 — recorded decision names a model the tool refuses (`freepool-default`)

Brief's claim: "the recorded decision names a model the tool refuses".
**Does not reproduce through the gate** (the gate always hands the arbiter
`speakable_models`), but **does reproduce if the arbiter is consulted
directly, without that filter** — which is exactly what a human following
the gate's own pre-2026-09-10-shaped "way forward" text would have done:

```
$ bash leadv2-route-arbiter.sh worker '{"work_kind":"recon","size":"standard",
    "subtype":"Explore","task":"repro3-no-speakable-filter"}'
arm=freepool kind=recon model=freepool-default tier=standard ...
```

`freepool-default` is not in `sonnet|opus|haiku|fable` — the Agent tool
cannot pronounce it. This is the live remnant of the original bug: it no
longer fires through the gate's own auto-consult (filtered), but it still
fires through the gate's own **suggested manual command**, which — before
this lane's fix — omitted `speakable_models`. See §3.

## 2. The intersection (read from code, not guessed)

Model-inherit-guard passes a spawn when: (a) an explicit non-opus model is
given (any subtype, no exceptions — `leadv2-model-inherit-guard.sh:49-52`),
or (b) `model=opus` and the subtype is on the allowlist
(architect/critic/security-auditor + `leadv2:` variants), or (c) no model is
given AND the subtype is a custom agent whose definition pins a frontmatter
`model:`. It denies only: opus for a non-allowlisted subtype, or no model at
all for a frontmatter-less built-in (`Explore`/`general-purpose`/`claude`).

Spawn-arbiter-gate passes a spawn when a fresh, non-refused arbiter decision
is on record for that `(subtype, model)` pair — including one it just
produced via its own one-shot auto-consult, pinning the caller's requested
model when one was given.

**Intersection, in plain terms:** any subagent spawn that carries an
explicit non-opus model the arbiter is willing to honour for that subtype
right now (or `model=opus` on an allowlisted subtype, likewise honoured), OR
a model-less spawn of a custom agent whose definition frontmatter already
pins a model. This is not a narrow accidental gap — it is the entire normal
happy path (a caller states a model and the arbiter either grants exactly
that model or refuses by name; nothing is ever silently substituted). The
set is **non-empty**, so per the brief's own framing this is a
documentation/coverage finding, not a code deadlock.

## 3. The fix (must not weaken either guard)

**Mechanism, one sentence:** the gate already declares the Agent tool's
speakable model pool once (`SPEAKABLE_MODELS`) and hands it to the arbiter
as `speakable_models` on its own auto-consult; the one remaining place the
gate talks to the arbiter — the DENY message's suggested manual CLI
fallback for a spawn whose true `work_kind` the recon auto-consult couldn't
guess — did not carry that same pool, so this lane threads it through
there too (`SPEAKABLE_JSON`, built once from the same constant, one text
edit).

```diff
-  bash $ARBITER_CLI worker '{\"work_kind\":\"build|recon|review|plan\",\"size\":\"standard\",\"subtype\":\"$SUBTYPE\",\"task\":\"one line\"}'"
+  bash $ARBITER_CLI worker '{\"work_kind\":\"build|recon|review|plan\",\"size\":\"standard\",\"subtype\":\"$SUBTYPE\",\"task\":\"one line\",\"speakable_models\":$SPEAKABLE_JSON}'"
```

No arm is hardcoded out of routing: `speakable_models` is the exact same
opt-in descriptor field `leadv2-route-arbiter.sh` already implements
(`_pool_contains`, from the prior lane) — quota, task and complexity still
decide inside that pool. **Route arbiter decision logic, capability matrix,
and cost ordering are untouched** (off-limits honoured; only
`leadv2-spawn-arbiter-gate.sh` text changed).

Files changed:
- `plugins/leadv2/hooks/leadv2-spawn-arbiter-gate.sh` — `SPEAKABLE_JSON`
  var + one DENY-text edit.
- `plugins/leadv2/scripts/tests/test-spawn-gate-composition.sh` — new
  composition suite (below).

`leadv2-model-inherit-guard.sh` and `leadv2-route-arbiter.sh`: **not
touched** (per off-limits and because the reproduction shows their
semantics are already correct).

## 4. Composition test — both hooks in sequence

`plugins/leadv2/scripts/tests/test-spawn-gate-composition.sh` (new,
self-registered via `# run-all-triggers: leadv2-spawn-arbiter-gate
leadv2-model-inherit-guard leadv2-route-arbiter`). Runs
`leadv2-model-inherit-guard.sh` and `leadv2-spawn-arbiter-gate.sh` against
the SAME payload and computes a combined verdict (deny if either denies —
matching how Claude Code actually evaluates multiple `PreToolUse` hooks),
never letting one hook's pass stand in for the pair:

- **A** — Explore+haiku, fresh journal: both hooks allow individually,
  combined allow, journal names the decided arm/model.
- **B** — the still-refused cases stay refused in combination: (b1) built-in
  with no model — guard denies even though the gate alone would allow via
  its own consult; (b2) non-allowlisted subtype + opus — guard denies.
- **C** — the two-attempt happy path: attempt 1 (no model) denies overall
  but the gate's own auto-consult (which ran regardless, since both hooks
  fire on the same event) already journaled a decision; attempt 2, with
  that exact model, combined-allows. Proves the retry the DENY text
  recommends actually terminates in one retry, not a loop.
- **D** — frontmatter-pinned custom agent (`developer`, real
  `.claude/agents/developer.md`, `model: claude-sonnet-5`), no model on the
  call: both hooks pass, no deadlock for the common lane-worker shape.
- **E** — both kill switches together (`LEADV2_ROUTE_ENFORCE=0` + explicit
  model) still allow.
- **F** — the DENY's manual way-forward names `speakable_models` with the
  full pool (this lane's fix, tested directly).

```
== A: the reproducer, live -- Explore+haiku through BOTH hooks, first attempt ==
PASS: A1 model-inherit-guard: explicit non-opus model always passes
PASS: A2 spawn-arbiter-gate: auto-consult grants a fresh decision
PASS: A3 COMBINED (both hooks, same event) -> allow
PASS: A4 journal line names the decided arm: [leadv2-spawn-arbiter-gate] arbiter decision on record: kind=recon arm=haiku model=haiku tier=standard reason=explicit_requested_capable recorded=2026-09-15T00:49:36Z -- spawn honours this decision.
== B: the still-refused cases must STAY refused ==
PASS: B1 built-in, no model -> model-inherit-guard still denies
PASS: B2 denial names the inheritance reason
PASS: B3 COMBINED still denies
PASS: B4 non-allowlisted subtype + opus -> model-inherit-guard denies
PASS: B5 denial names the opus allowlist reason
PASS: B6 COMBINED denies
== C: the two-attempt happy path resolves in exactly 2, never loops ==
PASS: C1 attempt 1 denied, but a decision was already recorded (model=haiku) for the retry
PASS: C2 attempt 2 (model=haiku, matching the recorded decision) -> COMBINED allow
== D: frontmatter-pinned custom agent, no model on the call ==
PASS: D1 developer.md pins model: -> model-inherit-guard allows model-less
PASS: D2 spawn-arbiter-gate allows via consult (binds subtype only)
PASS: D3 COMBINED allow
== E: kill switches on both hooks together still allow ==
PASS: E1 LEADV2_ROUTE_ENFORCE=0 (gate) + explicit model (guard) -> both allow
== F: the DENY's own manual-CLI way-forward must carry speakable_models ==
PASS: F1 manual way-forward command names speakable_models
PASS: F2 the suggested JSON carries the full speakable pool, not a partial list
SUMMARY: pass=16 fail=0        (+4 mutation-control cases below, 20/20 total)
```

## 5. Negative controls — one per independent property, both RUN

Ran via the shared `leadv2-mutation-control.sh` (WORKER-DOD-GATE-01), a
scratch-copy mutant proven applied and proven to bite — not asserted prose.

### Control 1 — revert the boundary translation (this lane's fix)

Patch reverts the `speakable_models` field out of the DENY's manual-CLI
suggestion:

```
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-spawn-gate-composition.sh
  file=plugins/leadv2/hooks/leadv2-spawn-arbiter-gate.sh
  red_line=FAIL: F1 way-forward missing speakable_models: [leadv2-spawn-arbiter-gate]
    DENIED: no route-arbiter decision is on record for this spawn (subagent_type=Explore
    model=haiku). FOUNDER 2026-09-04: every agent spawn goes through the arbiter.
  diff_hash=3f17abb17f850a91d155e0d70d69711e03302d30ff350e14f08cd05b1f5b17ce
  lane_diff_hash=7522fd099afe31e0a757f275269a15a72a3d15dd60a0a7179610ff75b6dca1b8
```

(A first run against the pre-fixup wording of F1 produced a weaker red on
F2 only, because F1's own check named the word "speakable_models" in prose
too and passed for the wrong reason — caught live, F1 tightened to check
the literal `"speakable_models":[` field emission, see the fixup commit.)

### Control 2 — remove the still-refused case's check

Patch collapses `leadv2-model-inherit-guard.sh`'s opus allowlist `case` to
a catch-all `*)`, i.e. opus becomes allowed for every subtype:

```
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-spawn-gate-composition.sh
  file=plugins/leadv2/hooks/leadv2-model-inherit-guard.sh
  red_line=FAIL: B4 guard=allow
  diff_hash=ed52772806432a17e05a401d4efd470a7d95d03a2beef2607767695750abb8d6
  lane_diff_hash=7522fd099afe31e0a757f275269a15a72a3d15dd60a0a7179610ff75b6dca1b8
```

Artifacts: `docs/handoff/SPAWN-GATE-AND-MODEL-GUARD-DEADLOCK-01/mutation-control/20260915T010254Z-58749.txt` (control 1, first/weak run), `20260915T010341Z-81660.txt` (control 1, corrected), `20260915T010401Z-85991.txt` (control 2).

## 6. Falsification set

```
$ bash -n plugins/leadv2/hooks/leadv2-spawn-arbiter-gate.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-spawn-gate-composition.sh && echo OK
OK
```

No `.py` files changed (no `py_compile` needed).

## 7. Suite results

```
plugins/leadv2/scripts/tests/test-spawn-gate-composition.sh   pass=20 fail=0   (new)
plugins/leadv2/scripts/tests/test-spawn-speakable-pool.sh     pass=26 fail=0   (untouched, unaffected)
plugins/leadv2/scripts/tests/test-spawn-arbiter-gate.sh       pass=27 fail=1   (pre-existing on unmodified HEAD — see below)
```

`test-spawn-arbiter-gate.sh` case "refusal not recorded" fails **identically
on unmodified HEAD** (verified by swapping the hook file back to
`git show HEAD:...`, running the suite, then restoring my diff via `git
apply` and confirming `bash -n` still passes) — an environment-sensitive
arbiter/kimi-capability drift unrelated to this lane's one-line DENY-text
change. Not touched, per "never weaken a fixture to get green."

`tests/run-all.sh --scope changed`: 5 passed, 2 failed —
`test-spawn-arbiter-gate.sh` (above, pre-existing) and
`run-core-offline.sh`. The latter does not reference either hook file
(`grep` confirms zero hits) and is documented elsewhere in this repo's
memory as an always-on, environment/concurrency-sensitive suite (multiple
other `/leadv2` sessions were live in this same environment during this
run — `dispatch-8a0d9618`, `6445c953e793`, `PLUGIN-PREPASS-PHANTOM-DESIGN-01`,
`PLUGIN-MARK-FINISHED-NO-RELEASE-01` all showed active in the session
banner). Not investigated further given this row's scope (hook boundary
only); flagging as a pre-existing/environment finding, not fixed here.

## 8. Off-limits — honoured

- Route arbiter decision logic, capability matrix, cost ordering: untouched.
- `.claude/hooks/leadv2-glm-first-agent-gate.sh` in persona-engine: not
  touched, not needed — this fix stayed entirely inside
  `~/Projects/leadv2/plugins/leadv2/hooks/`.
- No shared tree outside `plugins/leadv2/hooks/` (and the new test under
  `plugins/leadv2/scripts/tests/`) touched.

DELIVERABLE_COMPLETE
