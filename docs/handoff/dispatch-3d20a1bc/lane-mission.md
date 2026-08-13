# ARM-LADDER-HAS-NO-QUOTA-PRECHECK-01 — plugin repo `~/Projects/leadv2`

All edits in the plugin repo, NOT persona-engine. Do not rebase. Subject:
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` and `plugins/leadv2/config/leadv2-routing.yaml`.
Baselines to preserve: `plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh` 8/8 from BOTH
the repo root and inside a lane worktree; `test-phase-precondition.sh` 79/0;
`run-core-offline.sh` 40 passed / 1 failed (the 1 is `Codex full-cycle runner`, quota-locked —
it fails on untouched main too, leave it).

## The problem, as observed in live use

**P1 — the ladder is hardcoded, so the config is decorative.** The arm ladder
(glm → codex → sonnet) lives in the script, not in `leadv2-routing.yaml`. The config's `arms:`
list at `config/leadv2-routing.yaml:44-53` already carries a 2026-08-02 note saying it is NOT what
the dispatcher selects from: `claude-haiku` and `claude-opus` are declared and UNREACHABLE, `fable`
is undeclared yet reachable (`workflows/leadv2-plan.js:31`, `ARCH_MODEL = HEAVY ? 'fable' : 'opus'`),
and every provider has more than one model the format cannot express. Someone editing the config to
change routing changes nothing — the classic dead-knob shape.

**P2 — no quota precheck: the ladder discovers exhaustion by failing.** On 2026-08-05 two lanes sat
"live" for 51 minutes while both Codex jobs had already returned `failed` instantly with
"You've hit your usage limit… try again at Aug 8th". The ladder had no way to know Codex was locked
out before spawning into it. A precheck that reads each provider's known lockout state (Codex
prints a reset timestamp in its own failure; GLM and Claude expose usage) and skips a locked arm
would have routed correctly on the first try.

**P3 — dispatch from inside the plugin repo routes blind.** Running the dispatcher with cwd =
`~/Projects/leadv2` logs `route_resolved ... rule=none reason=no_routing_yaml`: the routing config is
resolved relative to the CONSUMING project, so plugin self-hosting work always falls to the default
arm with no policy applied. Resolve the plugin's own config as the fallback when the cwd repo has
none.

## Required shape

1. **Move the ladder into `leadv2-routing.yaml`** as an ordered list with a per-entry policy —
   at minimum `provider`, `model`, `when` (task kinds / classes it is eligible for) and `effort`.
   The script reads the list; it must not carry a hardcoded fallback order any more. Express the
   models that exist today, including the ones the current format cannot (multiple models per
   provider, and `fable` for the Heavy architect path).
2. **Add a quota precheck** before spawning an arm. Persist a per-provider lockout record
   (provider, locked_until, source of the timestamp) and skip any arm whose lockout has not
   expired, journalling the skip with the reason so a lead reading the journal sees WHY an arm was
   passed over. A missing or unreadable record must mean "not locked" — never fail closed on an
   arm we could have used.
3. **Fix the config resolution** so a dispatch launched from the plugin repo finds the plugin's own
   routing config instead of logging `no_routing_yaml`.
4. **Never hardcode an arm exclusion.** Eligibility is decided by quota + task kind + class, never
   by a hand-kept list of banned arms. This is a standing founder rule and the review will check it.

## Tests
Add cases to `plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh`:
- the ladder order actually comes from the yaml (change the yaml in a fixture → the resolved arm
  changes);
- a provider marked locked-until-future is skipped and the next arm is chosen, with the skip
  journalled;
- a lockout in the past is ignored;
- an absent lockout record does not block anything;
- dispatch with cwd = the plugin repo resolves a routing config rather than logging
  `no_routing_yaml`.

Each new test MUST fail against the current HEAD of `~/Projects/leadv2` main and pass after your
change. Run the suite both ways and paste both outputs. A test that passes in both directions is
treated as absent.

## Do NOT
Do not touch the phase-record contract (`leadv2-phase-record.sh`) — separate, already landed. Do not
change which arm any existing task type resolves to today except where the quota precheck skips a
genuinely locked arm. Do not rebase.

## Return
`PASS|FAIL|BLOCKED` + commit sha + all three suite runs verbatim + the before/after run of each new
test. Commit in the lane before you finish.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-3d20a1bc" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.