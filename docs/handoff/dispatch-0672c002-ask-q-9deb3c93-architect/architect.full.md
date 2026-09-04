# architect — blocked-question decision (dispatch-0672c002)

## Question
Wire complexity/duration_class into the LIVE `route_arbiter()` mechanism (a), or implement
only the brief's originally-named `resolve_arm` / `resolve_v2_dispatch` sites, which the lane
census showed are behind `LEADV2_ROUTER_V2` and not on the live path (b)?

## Evidence checked (this session, worktree COMPLEXITY-ESTIMATOR-IS-OFF-01)
```
$ ls -l plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
-rw-r--r--  1 kostiantyn.vlasenko  staff  14144 Aug 31 14:01 .../leadv2-route-arbiter.sh

$ grep -n "route_arbiter" plugins/leadv2/scripts/leadv2-dispatch-code.sh | head
10:# route_arbiter-gated at exactly FOUR sites, all in this file: cmd_resolve's initial ...
6943:  if declare -F route_arbiter >/dev/null 2>&1; then
6974:    _arb_out="$(route_arbiter worker "${_arb_desc}")"; _arb_rc=$?
7091: ... 7394: ... 7708: (three further spawn sites, same shape)

$ grep -n "LEADV2_ROUTER_V2" plugins/leadv2/scripts/leadv2-dispatch-code.sh | head
2697:  estimate="$(... LEADV2_ROUTER_V2=1 bash "$judge" --mission-file ...)"
2702:  out="$(... LEADV2_ROUTER_V2=1 bash "$bandit" sample ...)"
```
The arbiter is invoked at four spawn sites guarded only by `declare -F` (i.e. unconditionally
once the lib is sourced), while the router-v2/judge chain the brief names is reached only under
its own env gate. That corroborates the lane's census: the arbiter is the first
candidate-chain source and is what emitted `reason=cheapest_capable`.

## DECISION_OPTION: a
## RATIONALE: the arbiter is the unconditional live candidate-chain source, so only wiring complexity there changes real routing; option (b) ships dead code and leaves the reported defect intact.

## Why (a), in full
1. **The brief's intent, not its coordinates, is binding.** D1 makes the brief the plan
   *because* it was authored from live evidence. The lane then falsified one of those
   evidence claims with better evidence from the same file. Honouring the stale file:line
   over the corrected mechanism would satisfy the letter of D1 while defeating the reason
   D1 exists. The lane title — "complexity estimator is off" — is a statement about live
   arm selection, and (b) provably does not touch live arm selection.
2. **(b) is not a smaller-risk option, it is a zero-value one.** It produces a diff that
   passes its own tests inside a shadow path and closes the lane with the defect live. That
   is the worse failure mode: the backlog records the bug as fixed.
3. **(a) stays inside the reversibility envelope the brief demanded.** Additive-only:
   the judge estimate is computed unconditionally, complexity feeds candidate-chain
   reordering / a floor in the arbiter, the decision line names complexity, `cost-estimate.sh`
   is invoked. Rollback is via the same `routing.yaml` capability_matrix / env knobs that
   already govern the arbiter — no `LEADV2_ROUTER_V2` flip, no new gate, no schema or
   migration surface.

## Constraints binding the implementing lane (not a re-scope — guardrails on (a))
- **Env naming:** any new knob must be `LEADV2_*` (e.g. `LEADV2_ARBITER_COMPLEXITY=…`),
  cross-checked against the `env` block in `.claude/settings.json` before use. No
  `LEAD_V2_*` spelling.
- **Default must preserve today's selection** when the judge is unavailable or returns an
  unparseable estimate — the arbiter falls back to the current static `cost` ordering.
  A judge failure must never fail a dispatch.
- **Cost of the unconditional judge call:** `leadv2-task-judge.sh` now runs on every
  arbiter decision including the three non-initial spawn sites (bench-fallback 7091,
  exit76 7394, advisory 7708). Compute the estimate ONCE per dispatch and reuse it at
  those sites; a per-site re-invocation is a 4× latency regression.
- **Mutation control:** per D1, the proof must be a mutation inside the arbiter body on the
  real call path — flipping complexity must visibly change the emitted decision line.
  A fixture-only mutation does not discharge this.
- **Write scope:** `leadv2-route-arbiter.sh`, its tests, `routing.yaml` capability_matrix.
  If the wiring turns out to require editing `leadv2-dispatch-code.sh` beyond passing the
  estimate through, that is a scope question back to lead, not a silent expansion.

## Risks
| Risk | Mitigation |
|---|---|
| Judge latency/failure on the hot dispatch path | Compute once per dispatch, cache, fail-open to current static ordering |
| Complexity floor starves cheap arms → cost regression | Floor expressed in `routing.yaml`, tunable/removable without a code change |
| Divergence between arbiter decision and the still-present shadow router-v2 chain | Out of scope here; record as a follow-up backlog item, do not delete the shadow path in this lane |
| Four call sites drift apart | Single helper resolving the estimate; all four sites consume it |

## Out of scope for the implementing agent
- Removing, refactoring or re-enabling `resolve_arm` / `resolve_v2_dispatch` or the
  `LEADV2_ROUTER_V2` gate.
- Any change to `leadv2-task-judge.sh`'s own estimation logic.
- Correcting the brief's prose retroactively; the corrected census belongs in the lane's
  full deliverable.

DELIVERABLE_COMPLETE
