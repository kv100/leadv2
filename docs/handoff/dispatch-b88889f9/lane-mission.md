# Design brief — a real estimator, a real arbiter, a real balancer

Founder order, 2026-09-07: *«пусть они спроектируют… мне надо чтобы это работало до старта WAVES»*.
Two arms get this brief **independently** — fable and codex/astra — and produce two designs that will
be compared. Do not coordinate; divergence is the point.

**Deliverable is a design document, not code.** It lands under
`docs/handoff/SMART-ARBITER-DESIGN-20260907/design-<arm>.md`.

## What is broken, in facts you may rely on

All measured 2026-09-07 on this machine. Do not re-derive; do challenge if you think a number is wrong.

1. **The cost column was never measured.** `plugins/leadv2/config/leadv2-routing.yaml`
   `router_v2.capability_matrix` carries hand-assigned integers — glm-flash 0.33, glm 1, freepool 1,
   haiku 2, codex 3/4/7, sonnet 5, fable 8, opus 9 — and the config's own comment says `cost: 0.33`
   is *"a STATIC preference note, not a quota model"*. `capability` beside it is likewise a
   hand-written 2/3/4.
2. **Nothing can attribute burn to an arm.** The only burn log,
   `~/.claude/state/leadv2/quota-weighting-log.jsonl` (295 lines), records aggregate Claude
   five-hour / seven-day percentages with **no arm or model field at all**.
3. **Quota is a cliff, not a gradient.** `over_ceiling()` in
   `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` drops a provider once its binding window
   passes a ceiling (glm 80/90, codex 95/98, claude 95/95 work/review). Below the ceiling the
   remaining headroom does **not** affect selection — it is only a tie-break, second key in
   `_cost_key=(ecost, u[provider], arm, tier)`. The config has a `headroom_weights` key for exactly
   this and the arbiter **never reads it** (`grep -c headroom` in the arbiter = 0, against a
   non-zero control for `quota_ceilings`).
4. **So the fleet is effectively one arm.** Over 73 deduplicated live `route_resolved` decisions
   (2026-09-06/07): glm 55 (75.3%), glm-flash 9, sonnet 6, codex 2, refuse 1, and **opus, fable,
   freepool: zero**. 68 of 73 decisions are `cheapest_capable`. The arbiter is not malfunctioning —
   the rule executes exactly as written and one answer dominates it.
5. **Unused quota expires.** Windows are 5-hour and weekly/7-day and reset on a clock, so headroom
   left unspent is destroyed, not banked. Current state: glm weekly **74%** against an 80 ceiling
   (six points from exclusion), codex weekly 15%, claude max_20x 5h 9% / 7d 50%, claude team max_5x
   5h 21% / 7d 14%.
6. **The cheap arm is about to hit its ceiling and the fallbacks are unproven.** When glm crosses
   80, work moves to arms with almost no live history — and codex, the largest of them, has 80
   interrupted turns in 253 rollouts with an unidentified cancel source, where each interruption
   currently buys the whole arm a one-hour standdown.

## A seventh fact, found while dispatching this very brief

There is **no way to say "any of these arms" on a real dispatch.** Only two things exist:

- `--requested-arm <arm>` — which does not add a preference, it *filters the candidate set down to
  that single arm* (`leadv2-route-arbiter.sh:724-742`, `ok=[c for c in ok if
  c.get('arm')==requested_arm]`) and stamps `reason=explicit_requested_capable` unconditionally
  (`:1062`). A pin, not a constraint.
- nothing at all — and then `cheapest_capable` picks, which in practice means glm.

`allowed_arms`, the field the arbiter itself accepts and which is the only mechanism by which fable
or opus can legitimately win, is reachable **only from a direct `route_arbiter worker` call**. On the
dispatch path it is synthesised in `_build_candidate_chain` from the already-resolved arm plus
whatever follows it in `dispatch_ladder` (`leadv2-dispatch-code.sh:8517-8518`); no CLI flag and no
mission directive feeds it (`--allowed-arms`, `--arm-pool`, `LANE_ALLOWED_ARMS` — all absent).

So the operator's vocabulary is "exactly this one" or "whatever is cheapest". **"Any of these three,
pick well" cannot be expressed at all** — which is a large part of why fable, opus and freepool sit
at zero live decisions: short of a pin, there is no way for work to reach them, and a pin is not a
decision the arbiter made.

Treat this as part of the problem to solve, not trivia: a balancer that cannot be handed a pool has
no surface to act on. Say in your design what the dispatch-side vocabulary should be, and whether a
pin should remain a filter or become a strong preference that the arbiter may still overrule when the
pinned arm is capped or incapable.

### And an eighth, worse than the seventh — a pin does not guarantee reachability

Measured while dispatching this brief to fable, `--kind plan --task-class heavy --requested-arm fable`:

```
route_resolved by=arbiter role=worker arm=refuse reason=requested_arm_incapable requested_arm=fable
  arm_excluded=fable:not_allowed,opus:not_allowed
  util_glm=74 util_codex=15 util_claude=50 util_freepool=0
```

The pin never got a chance to apply. `allowed_arms` is computed first, and on the dispatch path it is
`_build_candidate_chain(arm, sig8)` (`leadv2-dispatch-code.sh:2475-2484`) walking `dispatch_ladder`
from the position of the **already-resolved** arm — here `glm` (`arm_resolved job=build arm=glm
reason=none`) — and taking only what follows it in that branch. fable and opus are not in that
branch, so `leadv2-route-arbiter.sh:501` marks them `not_allowed`, and the `requested_arm` filter
(`:724-742`) then runs against a set that no longer contains the pinned arm. Result: `arm=refuse`,
and the work does not run at all.

So the operator's vocabulary is poorer than fact 7 said. It is not merely that "any of these three"
cannot be expressed — **"this one, definitely" cannot be honoured either**, unless the arm happens to
sit downstream of whatever the legacy resolver picked first. The ladder branch, chosen before anyone
expressed a preference, silently bounds what any preference can reach.

Note what this does to the evidence in fact 4: fable and opus at zero of 73 live decisions is not a
statement about their cost or their capability. **There is no path to them.** A design that assumes
the zero reflects an economic judgement is reading the wrong signal.

Also visible in the same line: an arm can be dropped as `arm_not_capable_for_size` in the same
breath, so exclusion reasons stack and the journal reports one of them. Any redesign should make the
losing reason unambiguous — an operator reading `requested_arm_incapable` would reasonably conclude
fable is incapable of the work, which is false; it was simply never in the room.

## The problem to solve

Design the three pieces and how they fit. Treat them as one system; a good answer may reshape the
boundaries between them.

**A. Estimator — what an arm actually costs.**
What to instrument, at which seam, and in what unit. The unit must be comparable across providers
whose meters differ (percentage of a rolling window vs tokens vs requests). State what a "unit of
work" is, so cost-per-unit means something when one arm needs three rounds and another needs one.
Say what is recorded per completed lane and where it is written.

**B. Arbiter — how to choose.**
Given measured cost, capability, and live headroom, how is the arm picked? Headroom must act as a
gradient rather than a cliff, without inverting into "always spread" — spending a scarce expensive
arm on work a cheap arm does well is a real loss, and the founder's own framing is *"кто что лучше
делает и как оптимальнее"*, not equal shares. Be explicit about how capability and cost trade off
when they disagree.

**C. Balancer — keeping fallbacks warm and expiring quota used.**
Some deliberate exploration is necessary or arms stay unmeasured forever and their first real use is
an emergency. How much, chosen how, and on which work — exploration on a safety-critical lane is not
acceptable, exploration on a docs lane is nearly free.

## The hard constraint — read this before proposing anything

**Four of seven arms have no burn data and cannot get any without being run**, and the traffic that
would produce it is WAVES itself, which is gated behind this work. Any design that begins "first
collect N samples per arm" has not engaged with the problem.

So state plainly, as a separate section:
- what can be built and switched on **before** any new traffic,
- what needs traffic and how the system behaves **while still ignorant** — a cold-start policy that
  is safe, not a placeholder,
- how a measured number **replaces** a hand-written one incrementally, per arm, without a flag day.

This is an explore/exploit problem under a hard budget with non-transferable currencies. Say so if
that framing helps, and name the mechanism you are choosing rather than gesturing at a family of
them. The repo already has bandit machinery for content decisions — reuse it only if it genuinely
fits, and say why if it does not.

## Ground rules

- **Design only. No production edits.** Write your document; touch nothing under
  `plugins/leadv2/scripts/` or `config/`.
- **Every claim about current behaviour carries a file:line or a command.** Anything you assert about
  how the code works today must be checkable. If you could not verify something, say "not verified"
  — an honest gap outranks a confident guess here, and a claim that turns out to be invented
  discredits the whole document.
- **Name what you would NOT do**, and what you would delete. A design that only adds is usually
  avoiding a decision.
- **Give a rollback for each piece.** One step, one flag.
- **Say what would falsify your design** — the observation that would prove it wrong after two days
  of WAVES traffic. A design with no failure condition is not a design.
- Length is yours to choose; density beats volume. No summary of this brief back at us.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b88889f9" "<question>" \
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