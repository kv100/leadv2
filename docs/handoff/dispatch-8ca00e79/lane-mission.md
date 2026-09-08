POOL-IS-COMPUTED-AFTER-THE-ARM-IS-CHOSEN-01 — build the eligible set before anything resolves, so a pool is a pool and a pin is honoured or honestly refused.

REPO: ~/Projects/leadv2 (plugin repo is the single source).
Design this implements: ~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/PLAN.md
section P2, merged from design-fable.md §6 and design-codex.md §2. Read the plan first.

## The mechanism, measured 2026-09-07

A live dispatch with `--kind plan --task-class heavy --requested-arm fable` produced:

```
route_resolved by=arbiter role=worker arm=refuse reason=requested_arm_incapable requested_arm=fable
  arm_excluded=fable:not_allowed,opus:not_allowed
```

The pin never got a chance to apply, and the reason string is a lie: fable was not incapable, it was
never in the room. The chain:

- `leadv2-dispatch-code.sh:2475-2489` — `_build_candidate_chain(arm, sig8)` walks `dispatch_ladder`
  from the position of an ALREADY-RESOLVED arm (here glm, from the legacy resolver) and takes only
  what follows it in that branch. An unknown id falls back to sonnet.
- `:8517-8519` — those survivors become the arbiter's `allowed_arms`.
- `lib/leadv2-route-arbiter.sh:479-501` — everything outside that set is marked `not_allowed` in a
  two-valued `_arm_excluded` map.
- `:724-742` — the `requested_arm` filter runs AFTER that intersection, against a set that no longer
  contains the pinned arm, and reports `requested_arm_incapable`.

Second, independent cause of the same symptom: `config/leadv2-routing.yaml:519-530` — the haiku and
opus ladder rows carry `dispatch: false`, so `_filter_ladder_to_dispatchable` (`:8457-8460`) removes
them from `_LADDER_IDS` before the walk. Position is irrelevant for those two; they are never in the
array at all.

Consequence for the evidence, and this matters for anyone reading the numbers: fable and opus at
ZERO of 73 live arbiter decisions is not a statement about their cost or capability. There is no
path to them. A design that reads that zero as an economic judgement is reading the wrong signal.

## What to build

### Order of operations
`validate descriptor → intersect explicit pool with policy/trust/kind/size and launchable tuples →
apply failure-memory and health exclusions → inspect budgets → score → launch exact tuple.`
Never reconstruct eligibility from an ordered suffix.

`_arb_allowed_csv` (`:8517`) is built from the capability matrix ∩ kind/size/trust ∩ what is actually
launchable — NOT from `_build_candidate_chain "${arm}"` (`:8460`). After the arbiter answers,
`candidate_arms := arbiter chain (price-ranked) ++ ladder arms not already present`. The ladder
becomes the FALLBACK ORDER after the winner, never the bound on the pool. `_select_base_arm`
(`:2265-2297`) survives only as the crash fallback when the arbiter itself fails.

### Two words, not three
| Input | Meaning |
|---|---|
| no arm option | every enabled, launchable matrix cell for this kind/role is a candidate |
| `--arm-pool a,b,c` | hard candidate set. Unknown names, an empty pool, or a CLI/mission conflict are errors BEFORE anything launches. Persist the canonical set so resume and arm-advance keep it. |
| `--pin-arm x` (alias `--requested-arm`, keep it working) | hard filter, singleton pool. Never overruled, never silently substituted. It does not waive safety, capability, trust or budget — it either runs or refuses honestly. |

Deliberately NOT building a soft `--prefer-arm`: a caller who accepts substitutions supplies a pool.
Two words cover every case we have; the third was in one of the two designs and was rejected on the
merge.

### Typed exclusion stages
Replace the two-valued `_arm_excluded` map (`:497-502`) with an ordered stage list, one entry per
matrix arm that fits kind/size, in evaluation order:
`arm_excluded=fable:not_in_pool+not_launchable, freepool:untrusted, glm:capped`
Stages: `not_in_pool, not_launchable, untrusted, capped, failure_memory, price_ratio`.
`requested_arm_incapable` is RESERVED for the one case where it is true — no matrix cell fits
kind/size — and is retired as a catch-all everywhere else. An operator reading a refusal must be
able to tell "never eligible" from "never tested" from "tested and lost".

`dispatch: false` on the haiku/opus ladder rows must stop bounding the pool. Replace it with a
matrix-cell `pool_default: false` on OPUS ONLY (opus shares the lead's own account window and lead
starvation is worse than any routing gain) — opus reachable by explicit pool or pin, never by the
default auction. haiku: `pool_default: true`.

## Coordination
A sibling lane (ARMS-CANNOT-LAUNCH-THEMSELVES-01) is building the launch-capability registry that
answers "is this tuple launchable". Do not build your own. Consume it behind a small interface and,
if it has not landed when you need it, stub that one predicate as "the current DISPATCHABLE_*_ARMS
sets" and leave a single named seam for it — do not fork a second registry.

## Acceptance
acceptance:
  surface: log_line
  observable: A dispatch pinned to an arm that the legacy ladder branch did not contain either runs
    on that arm or refuses with a reason naming the exact stage that removed it — the operator can
    read, from one line, which of "not in the pool", "not launchable", "untrusted", "over ceiling"
    or "lost on price" actually happened, and `requested_arm_incapable` no longer appears for an arm
    that is perfectly capable.
  authored_at: 2026-09-07T18:30:00Z

## Negative controls (E2E-KILLRATE-01 — run them, show them red)
1. Inside the pool-construction body, restore `_build_candidate_chain` as the source of
   `allowed_arms`. The pin-reachability suite must go red.
2. Inside the exclusion-stage builder, collapse two distinct stages back into one `not_allowed`
   value. The reason-precision suite must go red.
3. Inside the pin handler, allow a silent substitution when the pinned arm is capped. That suite
   must go red.
Insert each mutation INSIDE the function body, never at top level.

Add the `EXTRA_SUITE_MAP` rows so the new suites are SELECTED, and prove it with `--scope changed`.

## Constraints
- Never `git add -A`; name every path. Never `reset --hard`, `clean`, `stash`, `worktree prune`.
- Never push to origin.
- Every claim in your report carries its artifact.

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh, plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py, plugins/leadv2/config/leadv2-routing.yaml, plugins/leadv2/tests/test-arm-pool-reachability.sh, plugins/leadv2/tests/test-exclusion-stages.sh, plugins/leadv2/scripts/leadv2-run-all.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-8ca00e79" "<question>" \
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