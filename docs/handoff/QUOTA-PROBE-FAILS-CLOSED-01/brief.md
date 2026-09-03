# QUOTA-PROBE-FAILS-CLOSED-01 — an unreadable quota probe is treated as an exhausted arm

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will ever reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 900`.
- Nested agents allowed for bulk reads — **synchronously only**, never `isolation:"worktree"`.
- **Commit after every step.**

**Class:** Standard. **Repo:** leadv2 plugin.

## The defect, verified on live code 2026-09-02
`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:102`

```python
if x.get('status')!='ok': return (100.0, True)
```

A **failed probe** of an arm's quota returns utilisation `100.0` — "exhausted" — flagged unknown. Not
"unknown, rank it lower"; literally capped. The rendered decision line is
`util_%s=unknown_capped` (same file, line 139).

Live consequence the same day: the lane `DRIFT-GUARDS-TO-CANON-01` was refused with

```
route_resolved arm=refuse reason=all_arms_capped util_glm=6 util_codex=100 util_claude=unknown_capped util_freepool=0
```

— refused "for lack of arms" while GLM sat **94% free**. `all_arms_capped` appears **28 times** across
task journals.

Worse, the repo holds two contradictory policies for the same quantity: `leadv2-router-v2.py` documents
**fail-open** for the same data. One of them is wrong and both are shipped.

## Deliver
1. **Unknown is not capped.** A failed probe yields "unknown". An arm with unknown quota ranks below a
   known-free arm but stays eligible. Keep the existing behaviour for a probe that *succeeds* and reports
   a real 100% — that arm is genuinely capped.
2. **The `last_resort` invariant: a quota-caused refusal must be structurally impossible while any arm is
   below its threshold.** If every arm is unknown, pick the cheapest and journal the decision as
   `last_resort` with the reason. A router that answers "no arms" while an arm is 94% free is answering
   wrongly, not conservatively.
3. **One policy, one place.** Reconcile with `leadv2-router-v2.py`'s fail-open. Say in the report which
   policy won and why; do not leave two.
4. Keep the decision line honest: it must distinguish `unknown` from `capped` in its own text, because a
   reader today cannot.

## Prove it
- **The regression case:** feed the arbiter the exact 2026-09-02 state — `codex=100` (real),
  `claude` probe fails, `glm=6`, `freepool` excluded — and show it resolves to **glm**, not `refuse`.
  Paste the run.
- **Negative control:** restore `return (100.0, True)` in a mktemp FULL copy of the tree (including
  `lib/`) whose baseline is proven green → the case must go red. Paste baseline and mutant runs. Insert
  the mutation INSIDE the function body; a top-level insert makes everything red for the wrong reason and
  reads as a pass.
- **The genuinely-capped case still refuses correctly:** all arms report a real 100% → refusal, with a
  reason naming that it is real and not a probe failure. Paste it.
- `tests/run-all.sh --scope changed` from the LANE ROOT (path is `tests/run-all.sh` at the repo root, NOT
  `plugins/leadv2/scripts/tests/run-all.sh` — that path does not exist). FOREGROUND, `timeout 1800`.
  Paste the real tail. A placeholder token where run output belongs fails this round outright.
- `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Out of scope
Turning on `LEADV2_ROUTER_V2`, changing the task judge, touching the bandit. This round fixes quota
reading and the refusal invariant, nothing else.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only. Tree clean, `main` merged.

## Done when
The regression case resolves to glm with pasted output; the negative control is red against a green
baseline; a real all-capped state still refuses with a distinguishable reason; one policy remains and the
report names it.
