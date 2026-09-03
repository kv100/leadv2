# Orchestration doctrine: how a lead dispatches today

This is the operating page for a new lead session. It describes the current
dispatch path, not an aspirational routing design. Every rule below names the
implementation that enforces it.

## 1. Lane lifecycle

1. Dispatch through `leadv2-dispatch-code.sh`; it resolves a candidate chain,
   reserves a ledger slot, and launches only the confirmed candidate
   (`plugins/leadv2/scripts/leadv2-dispatch-code.sh:6189-6249`,
   `plugins/leadv2/scripts/leadv2-dispatch-code.sh:6436-6464`).
2. The worker owns its scoped work and returns evidence; a launch handle alone
   is not completion. For ambiguous handles, inspect provider status and then a
   durable receipt or commit before considering a retry
   (`persona-engine/docs/leadv2/single-lead-mode.md:25-29`,
   `persona-engine/docs/leadv2/single-lead-mode.md:68-75`).
3. The close path resolves an author-excluding reviewer pool, then asks the
   arbiter to select only an available non-self reviewer
   (`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:414-465`).
4. A passing review does not mean `landed`: an isolated lane must merge to the
   default branch and pass ancestry verification before that terminal state is
   written (`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:3048-3069`).
   The lead personally verifies the receipt, commit ancestry, and live ladder;
   missing evidence means the task remains at the lower proven rung
   (`persona-engine/docs/leadv2/single-lead-mode.md:54-64`).

## 2. The arbiter

Run the arbiter before every worker spawn and every reviewer selection. The
worker integration calls `route_arbiter worker` before adopting the spawn chain
(`plugins/leadv2/scripts/leadv2-dispatch-code.sh:6189-6233`); the review
integration calls `route_arbiter reviewer` before replacing the available
reviewer (`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:433-460`).

The arbiter makes one `leadv2-quota-live.sh json` read for GLM, Codex, and
Claude windows, separately invokes the freepool gate, and feeds both results to
its policy process (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:15-27`).
It derives utilization from the relevant live windows; a broken or unknown
GLM/Codex/Claude probe is capped pessimistically, while freepool is capped when
its gate refuses (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:60-82`).

It filters the capability matrix by kind, size, and protected status; applies
`work_pct` to workers and `review_pct` to reviewers; and picks the
lowest-relative-cost capable arm under its ceiling
(`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:83-108`,
`plugins/leadv2/config/leadv2-routing.yaml:38-67`). When equal-cost choices
exist, it skips the last selected arm if another equal-cost arm is available;
the selected arm is moved to the head of the emitted chain
(`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:112-131`).

Journal the routing evidence, not just the chosen model: `route_resolved
by=arbiter` carries role, selected arm, task, reason, and `util_*`; routing
headroom is also recorded as `route_headroom_chosen`
(`plugins/leadv2/scripts/leadv2-dispatch-code.sh:6231-6236`,
`plugins/leadv2/scripts/leadv2-dispatch-code.sh:6378-6378`). An all-capped
arbiter result is a refusal; missing, malformed, or non-dispatchable arbiter
output falls back to the legacy ladder and is journaled as `arbiter_broken`
(`plugins/leadv2/scripts/leadv2-dispatch-code.sh:6234-6249`).

## 3. Arms

| Arm | Current capability | Ceiling | Hard exclusion / admission |
| --- | --- | --- | --- |
| GLM | Standard/heavy/bulk code, docs, and audit; build-only. | work 80%, review 90%. | No protected cells and no review cell in the arbiter matrix; resolver routes protected work through the safety exception. (`plugins/leadv2/config/leadv2-routing.yaml:38-67`, `plugins/leadv2/config/leadv2-routing.yaml:252-279`) |
| Codex | Code, docs, review, plan, and audit; standard through heavy tiers. | work 90%, review 95%. | Eligible for protected work; reviewer selection still excludes the author. (`plugins/leadv2/config/leadv2-routing.yaml:38-67`, `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:443-452`) |
| Sonnet | Standard/heavy code, docs, review, plan, and audit. | Claude work 95%, review 95%. | Used by the resolver’s safety/protected exception and remains subject to reviewer availability and self-review exclusion. (`plugins/leadv2/config/leadv2-routing.yaml:38-67`, `plugins/leadv2/config/leadv2-routing.yaml:271-279`) |
| Opus | Review, plan, audit, and safety; no auto-build cell. | Claude work 95%, review 95%. | Review-only dispatch-ladder entry; the close path chooses it only from an available reviewer pool. (`plugins/leadv2/config/leadv2-routing.yaml:65-67`, `plugins/leadv2/config/leadv2-routing.yaml:235-241`) |
| Freepool | Standard/bulk code and docs; build-only. | Health gate, plus no capability cell once the gate refuses. | Never review; `untrusted: true` removes it from protected/safety chains; only standard/bulk are eligible. (`plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:41-61`, `plugins/leadv2/config/leadv2-routing.yaml:198-222`) |

Protected, safety, and publish work must never be dispatched to GLM or
freepool. The enforceable layers are: the resolver’s protected-path exception,
the dispatcher’s protected/safety chain filter for untrusted arms, and the
arbiter matrix’s `protected: false` cells for GLM/freepool
(`plugins/leadv2/config/leadv2-routing.yaml:60-67`,
`plugins/leadv2/config/leadv2-routing.yaml:198-222`,
`plugins/leadv2/config/leadv2-routing.yaml:252-279`). The freepool gate is an
additional availability guard—not a protected-path policy guard—because it
checks liveness, pin drift, and rolling error/latency health only
(`plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh:4-16`,
`plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh:135-157`).

## 4. Burn governor

The pre-arm 24-hour burn governor defaults to a soft threshold of 800M and a
hard threshold of 1.3B tokens (`plugins/leadv2/scripts/leadv2-burn-governor.sh:14-25`).
Soft is a warning and dispatch continues; hard refuses and parks the task. Only
`LEADV2_BURN_OVERRIDE=1` bypasses the hard refusal, and that override is
journaled; `--force` does not bypass it
(`plugins/leadv2/scripts/leadv2-dispatch-code.sh:1464-1503`).

## 5. Failure paths

- **Quota lockout:** treat a provider lockout as a skip before spawn, retain the
  journal reason, and use the next admitted arm; the lockout record includes a
  provider, expiry, class, source, and escalating strike count
  (`plugins/leadv2/scripts/leadv2-dispatch-code.sh:6252-6257`,
  `plugins/leadv2/scripts/leadv2-dispatch-code.sh:2263-2295`).
- **Exit 76:** freepool’s fallback sentinel represents timeout or an
  incoherent/error result; it is a request for the caller to take the Sonnet
  fallback, while the diagnostic outcome remains in its run records
  (`plugins/leadv2/scripts/freepool-coder.sh:36-52`). Inspect the worker receipt
  before retrying or rerouting; an ambiguous handle is not permission to launch
  a duplicate (`persona-engine/docs/leadv2/single-lead-mode.md:68-75`).
- **`gate_broken`:** when the freepool rolling error-rate or latency threshold
  breaches, the gate emits `LEADV2_DISPATCH_REFUSED: gate_broken`; do not work
  around it with an un-gated freepool launch
  (`plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh:73-105`,
  `plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh:143-156`).
- **Codex interruption / vanished job:** only a positively parsed `No job
  found` result or a `turn_aborted` event marks the worker dead; the dispatcher
  records a Codex lockout strike and spills to the next arm. Other status errors
  remain unknown rather than being treated as proof of death
  (`plugins/leadv2/scripts/leadv2-dispatch-code.sh:5123-5171`,
  `plugins/leadv2/scripts/leadv2-dispatch-code.sh:5298-5309`).

## 6. Lead invariants

- Never call a lane landed on a terminal marker alone: verify the in-scope diff,
  tests, review verdict, merge ancestry, and, when relevant, the live probe
  (`persona-engine/docs/leadv2/single-lead-mode.md:54-64`,
  `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:3048-3069`).
- Keep one execution watcher and one journal path per lane; do not add a second
  watcher that can independently reclassify or relaunch an already-owned job.
  The dispatch contract records one channel+handle and one evidence/next state
  per task (`persona-engine/docs/leadv2/single-lead-mode.md:20-21`,
  `persona-engine/docs/leadv2/single-lead-mode.md:68-75`).
- Keep execution WIP at one across every channel, including review and fix
  rounds. Start the next task only after the active task is accepted, rolled
  back, or explicitly parked with a ledger row
  (`persona-engine/docs/leadv2/single-lead-mode.md:14-18`).
