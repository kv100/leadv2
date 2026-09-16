# ARM-SELECTION-DECISION-FIXTURES-01 — the frozen baseline instrument

Lane: `worktree-ff1a631b18fa`. Date: 2026-09-16. Founder order: apply
`docs/reference/arm-selection-proposal-2026-09-16.md`. That proposal's §7 requires
freezing the baseline decisions FIRST, before any policy change shows its outcomes.
This lane is that freeze. **It changes no policy** — not one line of
`plugins/leadv2/config/leadv2-routing.yaml` or
`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` is modified (proof under
"Write set").

## What was built

A hermetic decision harness that drives the live arbiter through its existing
test seam — the same one `docs/handoff/WEEKLY-ALLOCATES-FIVE-HOUR-ONLY-ADMITS-01/probe.sh`
uses — with fixed inputs and records its decision:

- `plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh` —
  the harness + test suite. Modes: default (full acceptance), `--record DIR`
  (regenerate recordings), `--verify DIR` (fresh recordings diffed against DIR).
- `docs/handoff/ARM-SELECTION-DECISION-FIXTURES-01/baseline/case01..case13*.txt` —
  the frozen baseline recordings (committed with `git add -f`; `.gitignore`
  drops `docs/handoff/*/*` except `*.md`).
- this report.

Per decision the recording captures: the full stdout decision line (winning arm,
model, tier, effort, `reason=`, `chain=`, `arm_excluded=` with per-stage reasons,
`fit_mode=`, `complexity=`, `req_eff=`, `fit_bucket=` per candidate, `cost_src=`,
`cost_actuals=`, `reset_urgency=`, headroom tokens) AND the structured
`LEADV2_ROUTE_ARBITER_DECISIONS_FILE` record (winner + `candidate_set` with
per-candidate `capability`/`fit_bucket`/`effective_cost`, `arm_excluded` map,
`req_eff`, `fit_mode`, `complexity`, `arb_rev`, `matrix_rev`). "Which comparator
was decisive" is readable off the line: `reason=` (cheapest_capable /
capability_fit / complexity_penalty / explicit_requested_capable) plus
`fit_pick=`/`fit_differs=` (whether the fit key overrode the pure-cost order).

The seam (all hermetic, no network, no live quota, no spend):

```
env LEADV2_ROUTE_ARBITER_ROUTING_YAML=<fixture> \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE=<stub cat'ing a fixed json> \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE=<stub exit 1> \
    LEADV2_ROUTE_ARBITER_STATE_FILE=<per-invocation temp> \
    LEADV2_ROUTE_ARBITER_DECISIONS_FILE=<per-invocation temp> \
    LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL=<fixture journal> \
    LEADV2_ROUTE_ARBITER_FAILURE_LEDGER=<empty fixture> \
    LEADV2_ROUTE_ARBITER_MODEL_CAPABILITY_YAML=/dev/null \
    LEADV2_ARBITER_SPEND_FORECAST=0 \
    bash plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh worker '<descriptor>'
```

Run under `bash`, never `zsh` (no `BASH_SOURCE` in zsh; the probe pattern in the
mission brief says the same). Each scenario's fixture yaml mirrors the live
config's `router_v2` block (cost keys incl. the two `null`s, `capability_fit`
on, the retained `+100` complexity_penalty rule, live ceilings) with a
scenario-specific `capability_matrix`. Pinning `MODEL_CAPABILITY_YAML=/dev/null`
keeps effort projections hermetic.

## Scenario count

The mission text says "the twelve that are decision-shaped (1-13 excluding
14)". §6 of the proposal lists fourteen cases; 1–13 are thirteen, all
decision-shaped (case 14 is the documentation task, already done by the lead).
All thirteen are frozen. Dropping one because the brief miscounted would have
left a policy lane without its yardstick for that case.

## The frozen baseline (13 scenarios, 21 invocations)

| case | frozen decision (first invocation unless noted) |
|---|---|
| 01 flash-admitted-standard | `arm=glm … reason=capability_fit fit_pick=glm fit_differs=1 fit_bucket=glm:0,codex:0,sonnet:0,glm-flash:1`; flash in `candidate_set`, labelled `price_ratio` (loser, not refusal) |
| 02 flash-exhausted-alternative | `arm=sonnet`, `arm_excluded glm:capped,glm-flash:capped` (one provider window caps both glm arms), rc=0 — no loop, no bypass |
| 03 complex-risk-strong-route | `arm=astra` (capability 6) wins heavy+complex+safety; unprotected `scout` excluded `untrusted` — the safety gate stays intact |
| 04 fit-mode-on-off | two invocations, same fixture: `fit_mode=on`/`complexity_policy=capability_fit` vs `fit_mode=off`/`complexity_policy=penalty`; flash `effective_cost` differs by exactly +100.0 between them (asserted in-suite) |
| 05 rotation-keeps-fit | equal-ecost arms, buckets `alpha:0,beta:1`, state file seeds alpha as last pick → **`arm=beta`**: rotation picked the WORSE-fit arm (finding, below) |
| 06 null-price-unknown | (a) glm capped → sonnet wins `cost_src=anthropic:median`; (b) glm healthy → `cost_src=glm:measured` — null stays visibly median, measured never labelled fallback |
| 07 observed-rounds-once | `cost_actuals=standard/glm:n=3,avg_rounds=2.00`, glm `effective_cost` == exactly 2× codex's (multiplier applied once); codex sub-min_rows stays un-repriced; class-less + malformed journal rows invent nothing |
| 08 same-provider-models-effort | one codex provider, luna(volume/cap3/standard-only)/terra(standard/cap4)/sol(top/cap5/heavy): complex-heavy → `model=gpt-5.6-terra effort=high` (luna kept out by size, sol loses the auction); simple-standard → `model=gpt-5.6-terra effort=medium` (tier tie-break) |
| 09 opus-identity | (a) `requested_arm=opus` → `arm=opus kind=review model=opus reason=explicit_requested_capable` (pin reaches `pool_default: false`); (b) `requested_model=claude-opus-4-8` → rc=69 `reason=requested_model_unknown` — no silent alias substitution |
| 10 fable-scoped-weekly | (a) scoped 98%/general 0% → `arm=sonnet`, `fable:capped` on its OWN window — scoped exhaustion does not block sonnet; (b) scoped 0%/general 97% → **`arm=fable`** admitted while the general weekly is exhausted (finding, below); (c) scoped stale (`hours_to_reset=0`) → no `reset_urgency` fabricated for claude/fable |
| 11 weekly-preservation | codex 5h bucket 0.2h from reset + weekly 45% vs glm weekly 40% → `arm=glm`; `reset_urgency=codex:1.223[weekly],glm:1.243[weekly]` — urgency priced from WEEKLY only, the expiring 5h bucket did not buy preference |
| 12 account-identity-mismatch | active-flagged account can't answer (`status unknown`), different ok account carries 20%/30% → `arm=sonnet util_claude=30 claude_priced_from=measured` — real numbers, not fabricated zeros |
| 13 direct-fallback-same-checks | (a) healthy pin → `arm=sonnet reason=explicit_requested_capable`; (b) same pin with anthropic capped → rc=70 `reason=requested_arm_capped`; (c) fallback auction on the same state → `arm=glm` — pin and auction face the same capped check |

## Fields normalized away, and why

1. decision-record `ts` / `ts_epoch` — wall clock of the record write; not an
   input to the decision.
2. the rotation state file is deleted before every invocation — the arbiter
   writes each winner into it and a leftover would rotate the next run's
   equal-ecost pick — except case05, where the seeded state file IS the fixture
   input under test.

Nothing else is touched. `arb_rev`/`matrix_rev` (content hashes of the arbiter
and the fixture yaml) are KEPT — they are what lets a diff name the exact bytes
behind a moved decision. `PYTHONHASHSEED` is deliberately left randomized: each
invocation is a fresh python with a fresh seed, so the twice-run diff (21+21
independent seed draws agreeing) is real evidence that no set-iteration order
leaks into a decision, not an artifact of a pinned seed.

## Evidence: determinism (twice-run diff)

```
== 1. record all scenarios twice ==
recorded 13 scenario recordings into /private/tmp/arm-sel-fixtures.XXXX/run1
recorded 13 scenario recordings into /private/tmp/arm-sel-fixtures.XXXX/run2
PASS: scenarios recorded: 13 (proposal §6 cases 1-13; case 14 is documentation)
== 2. twice-run determinism ==
PASS: twice-run diff empty (recordings deterministic)
```

## Evidence: negative control (moves it, then restores it)

The control mutates one input that MUST move a decision: case01's winning-arm
capability in the fixture yaml, 4 → 2.

```
== 5. negative control: move it, then restore it ==
PASS: mutation (case01 glm capability 4->2) changed the recording
PASS: mutation moved the decision (arm=glm -> arm=codex)
PASS: reverting the mutation restored the baseline byte-for-byte
```

The winner moved glm → codex (with glm at bucket 1 alongside flash, the
bucket-0 codex/sonnet pair sorts ahead under `_fit_key`, and codex wins the
equal-ecost tie) — a real decision movement, not just a hash change; the
reverted re-record is byte-identical to the committed baseline.

## Evidence: full acceptance run

`bash plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh` →

```
== 3. baseline pins ==
… (44 assertions across the 13 scenarios: winners, exclusions, fit buckets,
   cost_src provenance, the +100 isolation, the once-only rounds multiplier,
   refusal codes 69/70, the two baseline findings) …
== 4. committed baseline byte-identity ==
PASS: fresh recordings byte-identical to committed baseline (…/docs/handoff/ARM-SELECTION-DECISION-FIXTURES-01/baseline)
SUMMARY pass=44 fail=0
```

## Evidence: falsification set

```
$ bash -n plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh
bash -n: OK (rc=0)
```

No Python files were added by this lane (the in-suite python is heredoc-internal
and exercised by every green assertion above).

Changed-scope runner (`bash tests/run-all.sh --scope changed`, core-offline
always-on + stem-selected suites):

```
[PASS] …/plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh
run-all: 5 passed, 0 failed, scope=changed
```

## Baseline findings (frozen, not fixed — the following lanes own them)

1. **case05 — anti-stickiness can rotate to a worse fit bucket** (proposal §4.4
   verification item). At equal effective cost with state-file `last=alpha`,
   `alternatives=[c for c in ok if ecost(c)==price and arm!=last]` picks `beta`
   (bucket 1) over `alpha` (bucket 0); the line even records the contradiction:
   `arm=beta … fit_pick=alpha … fit_bucket=alpha:0,beta:1`. Rotation preserves
   price equality but not fit ordering. Owner: the arbiter-policy lane.
2. **case10 — a scoped weekly window REPLACES the general weekly, not sums it**
   (proposal §2.5/§4.3). With `weekly_scoped.Fable=0%` and `seven_day=97%`,
   fable is admitted (`arm=fable`, `util_claude=97 util_claude_Fable=10`):
   `leadv2-route-arbiter.sh` pops `seven_day` when a scoped hit exists, so
   general-weekly exhaustion cannot refuse a scoped arm. Founder says Fable
   burns BOTH windows. Owner: the arbiter-policy lane.
3. **case01 — the decisive comparator today is the fit key, not price.** The
   frozen line reads `reason=capability_fit fit_pick=glm fit_differs=1`: under
   pure cost, flash (0.33) would have won the standard task; the fit bucket
   (flash 1 vs glm 0 at req_eff 3.0) overrode it. Exactly the lever the
   capability-band lane intends to move — when it moves, this recording is the
   before-picture.

## Scope boundary (honest limits of the instrument)

- The arbiter seam emits the ALIAS `model=opus`. Effective identity resolution
  lives downstream: `plugins/leadv2/config/model-capability.yaml:84-87` maps
  `opus → model_id: claude-opus-5, underlying_model: claude-opus-5` (read-only
  fact; no 4.8 route exists there). Case09 freezes that no-arm-carries-4-8
  refuses by name (rc=69) — no silent alias downgrade — but "the launched
  process was opus-5" is a launcher-side check this harness cannot see.
- Case12 freezes the QUOTA half of the identity question (no mislabeled quota
  from an unanswered active account). Profile-UUID enforcement at launch is
  downstream of this seam.
- Case08's model-choice-survives-launcher-resolution is likewise downstream;
  the recording pins the model token the launcher must preserve.

## Protocol for the two policy lanes

1. Implement the policy change in this worktree's successors (config lane:
   `config/leadv2-routing.yaml`; arbiter lane: `scripts/lib/leadv2-route-arbiter.sh`).
2. `bash plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh`
   — it will go RED at "committed baseline byte-identity" (and at any pin whose
   decision moved). That red is the instrument working.
3. `bash …test-arm-selection-decision-fixtures-01.sh --record /tmp/after`
   then `diff -r docs/handoff/ARM-SELECTION-DECISION-FIXTURES-01/baseline /tmp/after`.
   Every recording that differs names its case; `arb_rev`/`matrix_rev` in the
   record heads say WHICH bytes moved. A decision that moved without an
   intended cause, or an intended decision that did NOT move, is exactly what
   this diff exists to catch.
4. Update the pins you intended to move and re-freeze the baseline in the same
   commit, with the diff and the reason in your lane's report.

## Write set

Exactly (staged set at commit time, `git status --porcelain`):

```
A  docs/handoff/ARM-SELECTION-DECISION-FIXTURES-01/baseline/case01-flash-admitted-standard.txt
… (13 baseline recordings, git add -f)
A  plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh
A  docs/handoff/ARM-SELECTION-DECISION-FIXTURES-01/report.md      (this file, *.md not gitignored)
```

No modification to `config/leadv2-routing.yaml`, `scripts/lib/leadv2-route-arbiter.sh`,
or any existing test. No runtime-state paths (`docs/leadv2/`, `docs/LEAD_V2_STATE.md`,
`docs/handoff/dispatch-nw*`) in the diff. The suite is registered: tracked
(git-added → discovery-admitted), self-selecting path convention
(`plugins/leadv2/scripts/tests/test-*.sh`), and carries
`# run-all-triggers: leadv2-route-arbiter` for changed-scope selection — proven
by its `[PASS]` row in the `--scope changed` run above.
