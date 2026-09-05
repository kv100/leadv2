# SELECTOR-DESIGN-01 — What the work selector should actually be

Design only. No code written, nothing committed. Repo: `/Users/kostiantyn.vlasenko/Projects/leadv2`.
Canonical tree read: `plugins/leadv2/` (the `.claude/scripts/` copies are per-file symlinks to it).

---

## §0. Premise correction — read this first

The mission's stated facts were checked against the tree. **Two of the stated defects are already
fixed on disk**, and the correction changes the shape of the work. Do not implement against the
mission text; implement against this section.

| Mission claim | On disk | Verdict |
|---|---|---|
| Judge emits `work_kind`/`duration_class`/`complexity` (3 dims) | Prompt template emits **6**: `complexity`, `subsystems_touched`, `needs_live_verification`, `risk_class`, `duration_class`, `work_kind` — `leadv2-task-judge-prompt.tmpl:5` | **Stale.** 6 dims, not 3. |
| Judge prompt is arm/model/provider/quota-free | Confirmed. No arm vocabulary; enforced by `tests/test-leadv2-task-judge.sh::test_lexicon_grep_on_prompt_template` | **Holds. Keep this invariant.** |
| Whole chain behind `LEADV2_ROUTER_V2` default 0, so every live dispatch is `cheapest_capable` with no notion of difficulty | The **v2 chain** (`resolve_v2_dispatch`, `leadv2-dispatch-code.sh:2812`) is indeed flag-gated shadow. But the **live** path is `route_arbiter()` (`lib/leadv2-route-arbiter.sh`), consulted **unconditionally**, and since COMPLEXITY-ESTIMATOR-IS-OFF-01 it **does** receive a difficulty estimate: `_dispatch_complexity_estimate()` (`leadv2-dispatch-code.sh:2861`) calls the judge on **every** dispatch and rides `complexity`/`duration_class` into the arbiter descriptor (`:7411`). `router_v2.complexity_penalty` then penalises cheap/mechanical/bulk/background cells by +100 when `complexity=complex`. | **Stale.** `reason=cheapest_capable` is a literal string in the arbiter's `print()` (`leadv2-route-arbiter.sh:280`), emitted on **every** successful pick regardless of which penalties fired. It is a label, not evidence that difficulty was ignored. |
| Bandit collapses dimensions into binary `work_kind:short\|long` | Already three-segment: `work_kind + ":" + duration_class + ":" + complexity` (`leadv2-dispatch-code.sh:2836`) | **Stale — fixed.** |
| `effort` never read or passed (0 occurrences) | Arbiter resolves it from the winning cell via `router_v2.effort_matrix` and prints `effort=` (`leadv2-route-arbiter.sh:262-274, 280`); dispatcher parses it into `RESOLVED_EFFORT` (`:7464`) and passes `--effort` to sonnet (`:5359`) and codex (`:5462`). | **Stale.** But see D-3: it is dropped for glm/glm-flash/freepool with `effort_dropped … reason=no_effort_control` (`:5179,:5243,:5293`), and **nothing re-ranks when the winner cannot take the effort the matrix said it needed.** |

**So the honest problem statement is not "turn on the flag."** The estimator exists, runs on every
dispatch, and two of its six dimensions already move the routing decision. The real defects are
different, and worse.

**D-1 (Critical, live, measured).** `util()` in `leadv2-route-arbiter.sh:103` returns
`(100.0, True)` — "maximally capped" — whenever a provider's quota probe reports
`status != 'ok'`. A provider whose *probe* is broken is therefore indistinguishable from one that
is genuinely exhausted, and both produce a hard `SystemExit(3)` / `all_arms_capped` / dispatch
`exit 4`. This is exactly the founder's complaint. The journal records it verbatim:

```
docs/leadv2/cache/summaries/30ac5beeff9d.md:5
  route_resolved by=arbiter role=worker arm=refuse task=26c4cec3 reason=all_arms_capped
  util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0
```

`unknown_capped` is the arbiter naming its own defect. And the same repo contains the *opposite*
policy for the same quota truth: `leadv2-router-v2.py:15` documents
`usable_now is None -> ELIGIBLE reason=unknown_headroom_failopen` — "an unknown read is never
treated as exhausted." **Two readers of one quota source with contradictory unknown-semantics.**
The fail-closed one is the one that runs live.

Measured blast radius, from `docs/leadv2/` journals: `model_select_telemetry` has 298 rows, of
which **24 are `terminal=fail`** (19 `all_arms_capped`, 5 `all_arms_unavailable`) =
**8.1% of dispatches hard-refuse**.

**D-2 (High).** Four of the six estimated dimensions never reach the live arbiter.
`work_kind`, `risk_class`, `subsystems_touched`, `needs_live_verification` are computed,
journalled, and discarded on the routing path. `work_kind` is even read into `DC_WORK_KIND`
(`leadv2-dispatch-code.sh:6785`) and then never referenced again — the arbiter's `kind` comes from
the caller's `--kind` flag, not from the estimate. `risk_class` and `subsystems_touched` are used
only by `leadv2_admission_map_class` (`lib/leadv2-admission-class.sh:46-68`) to pick a task class.
`needs_live_verification` has **zero readers anywhere**.

**D-3 (High).** `effort` is resolved from the winning cell *after* the winner is chosen, and the
winner is chosen with no knowledge of whether it can honour an effort level. When `effort_matrix`
says `high` and the cost sort picked glm-flash, the dispatcher emits
`effort_dropped … reason=no_effort_control` and spawns at provider default. The routing decision
and the effort decision are sequenced in the wrong order.

**D-4 (High).** The bandit has never learned because **`route-outcomes.jsonl` has no writer.**
`leadv2-route-bandit.sh` is the only file in the repo that mentions the path (`:13,:225,:475`), and
it only ever *reads* it. `route-estimates.jsonl` is likewise written only under
`LEADV2_ROUTER_V2=1` (`leadv2-task-judge.sh:_journal`), which is off — the file does not exist on
disk. No `route-bandit-state*` file exists anywhere in the tree. The classic
"column with no writer lies zero": the bandit is not badly tuned, it is **unfed**.

**D-5 (Medium, concurrency).** The arbiter's anti-stickiness state is a single global path,
`${TMPDIR}/leadv2-route-arbiter-last-arm` (`leadv2-route-arbiter.sh:40`), read-modify-written by
every lane. With WIP=2 lanes plus unlimited concurrent `/leadv2` sessions
(CONCURRENCY-2-LANES-01), two lanes routing in the same second both read the same `last` and both
rotate to the same alternative — anti-stickiness silently inverts under concurrency. The write is
atomic (`os.replace`); the read-modify-write is not.

**D-6 (Medium, config).** The quota ceilings have **three** readers with **two** different values:
`plugins/leadv2/config/leadv2-routing.yaml` `router_v2.quota_ceilings`,
`plugins/leadv2/config/leadv2-quota-ceilings.sh` (mirror), and
`lib/leadv2-glm-policy-resolve.py` `DEFAULT_BUILD_THRESHOLD_PCT = 80.0` for **codex** BUILD where
the yaml declares 90. The divergence is documented and deliberately unfixed. Any new selector must
read the yaml and only the yaml, or the divergence becomes four-way.

**Baseline numbers this design is measured against** (all from `docs/leadv2/` journals,
2026-08-09 → 2026-09-02):

| Metric | Value | Source |
|---|---|---|
| `route_resolved` lines (lifetime) | 1160 | `grep -rh "route_resolved" docs/leadv2/ \| wc -l` |
| Dispatch rate, last 4 days | 85–187/day | date histogram of the same grep |
| Escalation rate (`fallback_depth > 0`) | **88 / 298 = 29.5%** | `model_select_telemetry` |
| Hard-refusal rate (`terminal=fail`) | **24 / 298 = 8.1%** | `model_select_telemetry` |
| Terminal outcomes (lifetime) | 947 | `dispatch_terminal task=` |
| Landed share of decided lanes | **454 / 749 = 60.6%** (landed ÷ landed+dead+pass_unlanded) | same |

`terminal=win cause=worker_spawned` (274 of 298) is **not** a quality signal — "win" means a
process started. Do not use it as the reward. This is a lying-green metric already in the journal.

---

## §1. What the estimator should measure

Rule applied: a dimension survives only if I can name a real dispatch shape in this repo whose
`(arm, effort)` would differ. Everything else is cost without benefit.

### 1.1 Keep — 5 dimensions

| Dim | Values | Who reads it | The dispatch that routes differently |
|---|---|---|---|
| `complexity` | trivial\|simple\|standard\|complex | L4 cost penalty | **Already proven.** `router_v2.complexity_penalty` adds +100 to `[cheap,mechanical,bulk,background]` when `complex`. Without it, glm-flash (`cost: 0.4`) wins every `kind=code size=standard` auction — it is the cheapest cell in the matrix by 2.5×. Journal shows 90 `arm=glm-flash` picks; the penalty is what keeps hard ones off it. |
| `duration_class` | short\|medium\|long | L4 penalty (**new rule**) + bandit ctx key | Rides into the descriptor today and `complexity_penalty` supports a `duration_classes:` key — but **no rule uses it**, so it is inert on the routing path. Earn it: a `long` task on a `sizes:[standard]`-only cell (glm-flash) has no heavy fallback below it. The 23 `fallback_depth=5` rows are this shape — a cheap arm taken for long work, cascading to the end of the ladder. Rule: `duration_classes:[long]` penalises `[cheap]` by 100. |
| `risk_class` | none\|data\|safety_publish_payments | class map (today) + L4 penalty (**new**) | `safety_publish_payments` already escalates the *class* to Heavy. `data` does **nothing** today — a migration-writing task with `complexity=standard` and no `--protected` flag is `kind=code size=standard`, and glm-flash wins it. Standing rule `feedback_migration_review_must_apply` demands a dry-run apply. Rule: `risk_classes:[data,safety_publish_payments]` penalises `[cheap,mechanical]` by 100. |
| `subsystems_touched` | int 0-10 | class map (`>=4 → Heavy`) | Already changes the outcome: Heavy → `SIZE_MAP` `heavy` → glm-flash and freepool are structurally out of the capable set (`sizes:[standard]` / `[standard,bulk]`). Cheap, already wired. Keep. |
| `context_bytes` | int (**new, deterministic**) | L1 hard filter (**new**) | **The one hard capability constraint nobody measures.** `model-capability.yaml` carries `context_k` per arm (opus/kimi 1000, sonnet/haiku 200, glm/codex `null`). A mission whose text + `reads:` exceeds an arm's window cannot be done by that arm at any effort — a *capability* fact, not a preference, so it belongs in the hard filter alongside `kinds`/`sizes`, not in the cost sort. This is the honest mechanism behind the 29 `fallback_depth >= 3` rows: the cascade you get when an arm is picked that structurally could not hold the task. **Computed in bash from `wc -c` on the mission file plus the declared `reads:` — no LLM call, no judge involvement.** |

### 1.2 Move out of routing — 1 dimension

`needs_live_verification` — **zero readers today.** It does not and should not change the arm: no
arm is better at SSH. It changes the **phase contract** (does this task need a live-verify gate
before close?). Keep the field, move its consumer to §4. If §4 is not implemented, **cut the
field** — an unread field in a schema is a lie about what the system considers.

### 1.3 Reclassify — 1 dimension

`work_kind` (build\|review\|diagnose\|docs) is estimated and discarded because the arbiter's `kind`
comes from the caller's `--kind` flag. Two options; recommend (b):

- **(a) Let `work_kind` override `kind`.** Rejected: `--kind` carries lane vocabulary the caller
  knows and the judge cannot (`fanout-class-funnel`, `backlog-pump`), and letting a haiku estimate
  overwrite a caller's explicit contract is a silent authority transfer.
- **(b) `work_kind` becomes a required-tag signal, never a `kind` override.** `diagnose` requires
  the winning cell to carry a reasoning tag (`adversarial`/`integration`), because root-causing is
  the one work kind where a cheap mechanical arm reliably produces a confident wrong answer
  (memory `feedback_diagnosis_read_error_first`; `DIAGNOSE_KEYWORDS` already exist in the judge's
  fallback estimator, `leadv2-task-judge.sh:120`). `docs` requires nothing and unlocks `[cheap]`.
  `build`/`review` are neutral.
  **The dispatch that routes differently:** a `bug:`-prefixed mission dispatched with
  `--kind code` (the default) — today glm-flash; under (b) glm-flash lacks a reasoning tag and is
  filtered, codex/sonnet wins.

### 1.4 Explicitly rejected — do not add

| Candidate | Why rejected |
|---|---|
| `reversibility` | Every case I could construct is already covered by `risk_class` plus the `--protected`/`safety`/`publish` lane flags. No dispatch routes differently. |
| `novelty` / prior-art hit | `leadv2-cost-estimate.sh` reads `prior-art.yaml`, so the data exists — but I could not name a cell whose selection flips on it, and it costs a file read per dispatch. **Deferred, not designed.** Revisit only if the §3 ledger shows a first-pass-rate gap between repeat and novel missions. |
| `estimated_lines_changed` | The judge cannot know this before the work; asking produces a confident ungrounded number. `subsystems_touched` already covers breadth. |
| `retry_round` / prior failure | **Not an estimator dimension.** It is live state, not task shape. Putting it in the judge would break the arm-blindness invariant (a judge that knows "glm failed twice" is a router). It belongs in §2 as an input to the decision function. |

### 1.5 Cost of the estimate

Unchanged: one cached haiku call per unique mission signature. Note for the implementer — **the
judge is currently invoked twice per dispatch**, once by `_admission_classify`
(`leadv2-dispatch-code.sh:3888`) and once by `_dispatch_complexity_estimate` (`:2871`). Both key on
the same `sig8`, so the second is a cache hit and costs a process spawn, not a model call. Do not
"fix" this by removing one — they serve different consumers. Do fold them into one call returning
both, if touching that code anyway.

---

## §2. The decision function

An explicit ordered procedure. Replaces the body of `route_arbiter()` in
`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`. Same function name, same single-line
`key=value` output contract, same "non-zero means caller fails open to the ladder" contract — so
`leadv2-dispatch-code.sh` needs only the additions in §2.9.

### 2.0 Inputs

```
E  estimate    : complexity, duration_class, work_kind, risk_class,
                 subsystems_touched, context_bytes        (§1)
S  live state  : util[provider], util_status[provider] in {ok, unknown}
                 freepool_gate_rc
                 provider_lockout[provider]               (quota-lockout-<p>.json)
                 operator_kill[arm]                       (~/.claude/leadv2-excluded-arms)
                 failed_arms[task]                        (this task's prior rounds)
                 round_n                                  (1 = first attempt)
L  lane        : kind, task_class, protected, safety, publish, ui_judgment,
                 allowed_arms, role in {worker, reviewer}
C  config      : router_v2.{capability_matrix, quota_ceilings, effort_matrix,
                 cost_penalties, last_resort}             (leadv2-routing.yaml, sole source)
```

### 2.1 STEP 1 — Hard capability filter (L1). Never traded back by a score.

For each cell `c` in `capability_matrix`, keep `c` iff **all** hold:

1. `L.kind` is in `c.kinds` (with the existing out-of-vocabulary → `code` normalisation).
2. `SIZE_MAP(L.task_class)` is in `c.sizes` (existing map, unchanged).
3. `require_trusted` implies `c.protected`, where
   `require_trusted = (safety OR publish OR ui_judgment) OR (protected AND kind not in {review,audit,plan})`.
   Unchanged from today (ARMS-ADMISSION-01).
4. `L.allowed_arms` is null, or `c.arm` is in it. Unchanged.
5. **NEW — context fit.** `context_k(c)` from `model-capability.yaml`. If `context_k` is null or
   the file is unreadable → **pass** (fail open, journal `context_fit=unknown`). Else keep iff
   `E.context_bytes / 3.5 < context_k * 1000 * 0.6` (chars→tokens ≈ 3.5; the 0.6 leaves room for
   the agent's own tool output).
6. **NEW — work-kind tag requirement.** If `E.work_kind == diagnose`, keep iff `c.tags` intersects
   `{adversarial, integration}`. All other work kinds impose nothing.

`capable = [c ...]`. **If `capable` is empty this is a config-vocabulary gap, not a refusal.** Emit
`reason=no_capable_cell`, `exit 68`, caller falls open to the ladder. Unchanged from today
(T17 C1) and correct — keep it.

### 2.2 STEP 2 — Quota classification. Three states, never two. *(fixes D-1)*

For each provider `p` in `{glm, codex, claude, freepool}` compute a **pair** `(util, status)`:

```
freepool : status = ok always;  util = 0 if freepool_gate_rc == 0 else 100
                                (its gate IS a real observation, not a probe)
others   : if quota probe status != 'ok'  -> (null, UNKNOWN)     <- the change
           else                            -> (measured_pct, OK)
```

Then:

```
state(p) = OVER    if status == OK   and util >= ceiling(p, L.role)
           UNDER   if status == OK   and util <  ceiling(p, L.role)
           UNKNOWN if status == UNKNOWN
```

`ceiling(p, role)` reads `router_v2.quota_ceilings[p].{review_pct|work_pct}` from
`leadv2-routing.yaml` — **the yaml only** (see D-6). Never the `.sh` mirror, never
`leadv2-glm-policy-resolve.py`.

The current `return (100.0, True)` for a failed probe is **deleted**. `unknown_capped` as a concept
ceases to exist. `ufmt()` renders `util_glm=unknown` (not `unknown_capped`) — a wording change that
is itself part of the fix, because the old token asserted a fact about the world that was never
observed.

### 2.3 STEP 3 — Eligibility. The invariant.

```
eligible = [c in capable : state(c.provider) != OVER
                           and not provider_lockout[c.provider]
                           and not operator_kill[c.arm]]
```

UNKNOWN is **eligible**. It is penalised in §2.4, never excluded here. This alone removes 19 of the
24 measured hard refusals.

**The last-resort invariant — `all_arms_capped` becomes structurally impossible.**
`leadv2-routing.yaml` gains:

```yaml
router_v2:
  last_resort:
    arm: sonnet          # must be a `protected: true` cell, so it is legal for any lane
    never_capped: true   # quota may DEMOTE it in the sort; quota may never REMOVE it
```

If `eligible` is empty after the filter above:

- **3a.** If the last-resort arm survived STEP 1 (it is capable) and is **not** operator-killed and
  **not** provider-locked-out → select it. `reason=last_resort_over_ceiling`. Journal at WARN and
  fire the founder notification channel: routing is running on fumes and a human should know.
  This is a **degraded success**, not a refusal.
- **3b.** Only if the last-resort arm is itself operator-killed or provider-locked-out → refuse,
  `reason=all_arms_operator_excluded`, `exit 3`. **A quota number can no longer produce a refusal.
  Only a human decision can.** That is the "impossible by construction" the mission asks for, and
  it is testable: no path from a `util` value to `exit 3` exists in the control-flow graph.

`all_arms_capped` is retired as a reason code. The dispatcher's `elif` at
`leadv2-dispatch-code.sh:7470` matches that literal and must be updated to
`all_arms_operator_excluded` in the same change, or the refusal branch becomes unreachable and
falls into the generic `arbiter_broken` fail-open. (That would be *safe* but would silently lose
the `exit 4` contract. Change both.)

### 2.4 STEP 4 — Effective cost. One number, additive, config-driven.

```
ecost(c) = c.cost
         + freepool_floor_penalty(c)          # existing, unchanged, +100
         + sum(cost_penalties(c, E))          # §2.5, generalised complexity_penalty
         + unknown_penalty(c)                 # NEW: +20 if state(provider) == UNKNOWN
         + retry_penalty(c)                   # NEW: +1000 if c.arm in failed_arms[task]
```

Magnitudes are chosen so the ordering is unambiguous, not by feel:

- Real `cost` range is `0.4 .. 9` (glm-flash → opus).
- `unknown_penalty = 20` — an arm with an unreadable probe sorts **after every known-healthy arm**
  but **before** any capability-mismatched one. It stays a live candidate; it is never preferred.
- `complexity`/`risk`/`duration` penalties `= 100` — clears the whole real cost range, so a
  penalised cheap cell sorts behind opus. Matches the existing freepool floor magnitude.
- `retry_penalty = 1000` — clears everything including stacked 100s, so **round N never re-picks an
  arm that already failed this task**. Escalation becomes automatic and monotone, with no
  `if round == 2` branch anywhere.

### 2.5 The penalty table (`router_v2.cost_penalties`)

Generalises today's `complexity_penalty` — same match-on-`tags` mechanism, more match keys. An
empty list reproduces today's behaviour byte-for-byte. **Never names an arm.**

```yaml
router_v2:
  cost_penalties:
    - complexities:  [complex]
      penalize_tags: [cheap, mechanical, bulk, background]
      penalty: 100                       # existing rule, unchanged
    - duration_classes: [long]
      penalize_tags:    [cheap]
      penalty: 100                       # NEW — §1.1 duration row
    - risk_classes:  [data, safety_publish_payments]
      penalize_tags: [cheap, mechanical, bulk, background]
      penalty: 100                       # NEW — §1.1 risk row
```

Match semantics, unchanged from the current implementation: an **absent** key matches everything; a
**present** key must intersect; all present keys must match (AND); penalties from matching rules
**sum**.

### 2.6 STEP 5 — Sort and rotate

```
sort eligible by (ecost, util_or_+inf_if_unknown, arm, tier)
chain        = dedup([c.arm for c in sorted])
price        = ecost(sorted[0])
alternatives = [c for c in sorted if ecost(c) == price and c.arm != last_arm]
winner       = alternatives[0] if alternatives else sorted[0]
```

Unchanged except: the secondary sort key must treat UNKNOWN as `+inf`, not as `100.0` — otherwise
an unknown arm ties with a genuinely-at-100% arm.

**D-5 fix, same change:** scope the anti-sticky state file per lane, not globally.
`ROUTE_ARBITER_STATE_FILE` default becomes
`${TMPDIR}/leadv2-route-arbiter-last-arm.$(repo_slug)`, and the read-modify-write is wrapped in
`flock` on `<file>.lock` — the pattern `leadv2-task-judge.sh:_journal` already uses for
`route-estimates.jsonl`. Without this, two concurrent lanes rotate to the *same* alternative and
anti-stickiness is worse than absent.

### 2.7 STEP 6 — Effort, and the re-rank that makes it real *(fixes D-3)*

```
6a. effort = first matching row of router_v2.effort_matrix against winner.{tags,kind,protected}
             (existing logic, unchanged; default 'medium')
6b. if round_n >= 2:  effort = bump_one_level(effort)          # medium -> high -> high
6c. if effort == 'high' AND winner.arm has no effort control:
        candidates = [c in eligible : c.effort_control]
        if candidates non-empty AND ecost(candidates[0]) - ecost(winner) <= effort_swap_budget:
            winner = candidates[0];  reason = 'effort_capable_swap'
        else:
            emit effort_unavailable arm=<winner> wanted=high   # NOT silently dropped
```

`effort_control` is a **new per-cell boolean** in `capability_matrix`, not a hardcoded arm list:
`true` on the sonnet/haiku/opus/codex cells, `false` on glm/glm-flash/freepool. This must be config,
not an `if arm ==` branch — the same anti-hardcoding property `effort_matrix` already has.

`effort_swap_budget` (config, propose `5`) bounds how much extra cost a high-effort requirement may
buy. Without a bound, every `protected: true` lane (which `effort_matrix` maps to `high`) would
swap off glm and the cost policy collapses. **This number is a genuine unknown — see §6 R2.**

### 2.8 STEP 7 — Emit

One line, a superset of today's, so existing `sed -n` parsers keep working:

```
arm=<a> model=<m> tier=<t> effort=<e> reason=<r> chain=<a1,a2,...>
util_glm=<n|unknown> util_codex=... util_claude=... util_freepool=...
complexity=<c> duration_class=<d> work_kind=<w> risk_class=<rc> context_fit=<ok|unknown|filtered>
penalties=<arm:points,...> last_resort=<0|1> effort_control=<0|1>
```

`reason` vocabulary: `cheapest_capable` | `effort_capable_swap` | `last_resort_over_ceiling` |
`no_capable_cell` | `all_arms_operator_excluded`.

### 2.9 What `leadv2-dispatch-code.sh` must change

| Site | Change |
|---|---|
| `:7411` descriptor | add `work_kind`, `risk_class`, `subsystems_touched`, `context_bytes`, `round_n`, `failed_arms` |
| `:6786` | `_dispatch_complexity_estimate` returns 6 fields, not 3 |
| `:7470` | `all_arms_capped` → `all_arms_operator_excluded` |
| new, before `:7385` | compute `context_bytes` = `wc -c` of mission file + declared `reads:` |
| `:5179,:5243,:5293` | keep `effort_dropped`, but it should now be rare — it is the §5 canary |

---

## §3. The feedback loop — the honest answer is: **kill the bandit, keep the ledger**

### 3.1 Why the bandit cannot learn at our volume

Three independent reasons, any one sufficient:

1. **It is unfed.** `route-outcomes.jsonl` has no writer anywhere in the repo (D-4). No
   `route-bandit-state*` file exists. The bandit has literally never updated a posterior. It is not
   a badly-tuned learner; it is a learner with no input. "Has never demonstrably learned"
   understates it.
2. **The context space is ~60x the data.** Even if fed: the context key is
   `work_kind(4) x duration_class(3) x complexity(4) = 48` contexts x ~6 arms = **288 arm-in-context
   cells.** Lifetime terminal outcomes: **947.** That is ~3.3 observations per cell. A
   Beta-Binomial needs on the order of 30+ per cell to separate a 0.50 arm from a 0.65 arm with any
   confidence. We are ~10x short, and the space grows if §1 adds `risk_class` to the key.
3. **The samples are not exchangeable.** The arbiter picks by cost, not randomly, so the bandit only
   ever observes outcomes for the *cheap* arms — sonnet and opus have near-zero coverage in most
   contexts. And the arm population is non-stationary: glm-5.2 → glm-5.3 (2026-08-25), glm-flash
   added 2026-08-26. A posterior accumulated over that window averages over different models
   wearing the same name. Discounting old data to handle drift makes reason (2) strictly worse.

**Verdict: the bandit is unlearnable at our volume and should not gate routing.** An unlearnable
bandit is worse than a table — it adds variance, a circuit-breaker, a state file, and a cooldown
path, in exchange for noise. Recommend `LEADV2_ROUTE_BANDIT=0` permanently and the §2.5 table as
the decision mechanism.

### 3.2 What IS learnable — one number per arm, not 288

Marginalise the context away. **6 arms x 947 observations ≈ 150 per arm.** That is enough to
estimate one quantity per arm with useful precision:

> **`P(escalation | arm)` — the probability that a lane routed to this arm needed a fallback,
> a re-dispatch, or died.**

At n=150 and p≈0.30 the 95% CI half-width is ≈ ±7pp. Enough to detect a 15pp gap between arms; not
enough to detect 5pp. That is an honest, stated resolution limit — and it is exactly the
granularity the §2.5 penalty table needs, because the table's job is to answer "is this cell too
cheap for this shape of work", which is a per-arm question.

### 3.3 The outcome signal — definition

Rejected candidates and why:

- **Wall time** — dominated by queueing, human review latency, and founder availability. Not a
  routing property.
- **Cost / tokens** — we already optimise cost in `ecost`. Rewarding it again double-counts and
  drives everything to glm-flash.
- **`terminal=win cause=worker_spawned`** — the existing telemetry's "win". Means a process
  started. 274/298 = 92% "win rate" while 29.5% of dispatches escalate. This is the lying-green
  metric; do not reuse it.

**Adopted — a 3-value outcome, computable entirely from signals already on disk:**

| Outcome | Definition | Reward |
|---|---|---|
| `clean` | `terminal=landed` AND `fallback_depth == 0` AND review round-1 Critical+High == 0 | 1.0 |
| `escalated` | `terminal=landed` AND (`fallback_depth > 0` OR a round-2+ fix was needed) | 0.3 |
| `failed` | `terminal` in `{dead, dead_with_unlanded_work, pass_unlanded}` | 0.0 |

`terminal` in `{no_work, parked, refused}` → **excluded, not scored.** These are not routing
outcomes (93 + 54 + 45 = 192 of 947 lifetime rows). Scoring them would punish an arm for a lane the
founder parked.

Primary headline metric: **first-pass rate = `clean` / (`clean` + `escalated` + `failed`)**.
The baseline is derivable but not yet measured — deriving it is implementation step 1 of §5.

### 3.4 Where it is recorded

**`docs/leadv2/route-outcomes.jsonl`** — the path the bandit already expects. One row per scored
lane, append-only, `flock`-guarded (multiple lanes close concurrently — reuse the
`leadv2-task-judge.sh:_journal` flock pattern verbatim).

```json
{"ts":"2026-09-02T14:03:11Z","task_id":"SELECTOR-DESIGN-01","estimate_id":"a1b2c3d4",
 "arm":"glm-flash","model":"glm-5.3-flash","tier":"standard","effort":"low",
 "reason":"cheapest_capable","ecost":0.4,"penalties":"",
 "complexity":"simple","duration_class":"short","work_kind":"build",
 "risk_class":"none","subsystems_touched":2,
 "terminal":"landed","fallback_depth":0,"review_critical":0,"review_high":0,
 "outcome":"clean","reward":1.0}
```

**Writer: exactly one.** `leadv2-phase8-close.sh`, at the point where `$OUTCOME` is already in
scope (`:459`, next to the existing ledger emit). That is the one place in the system where a
lane's terminal state is known. The routing fields come from the `route_resolved` journal line for
that task — which already carries every one of them after §2.8.

**Companion:** `docs/leadv2/route-estimates.jsonl`. Un-gate the existing writer in
`leadv2-task-judge.sh:_journal` — drop the `LEADV2_ROUTER_V2 == 1` condition so it writes on every
dispatch. Joined to outcomes on `estimate_id` + `task_id`, it is what makes
`leadv2-route-bandit.sh judge-audit` (which already exists, `:464-490`) able to answer
"is the judge's `complexity` predictive of anything?" — the question that decides whether the
estimator is worth its haiku call at all.

### 3.5 How a bad arm choice becomes a changed answer

Not by a posterior update in a running process. By a **monthly human-reviewed table adjustment**,
with the ledger as evidence. Concretely:

1. `scripts/leadv2-route-audit.sh` (new, ~40 lines of python) reads both jsonl files and prints
   per-arm and per-(arm x complexity) first-pass rate with n and CI half-width.
2. **Alarm rule, automatable:** if for some arm `a` and some `complexity` value `x`, `n >= 30`
   **and** the first-pass rate is more than 15pp below that arm's own overall rate, emit a
   `route_drift` line naming a proposed `cost_penalties` rule.
3. A human adds the rule to `leadv2-routing.yaml`. Config-only, no script change — the §2.5 table
   is specifically designed so a rule is a yaml edit.
4. The rule's effect is measurable in the same ledger over the following 100 dispatches.

That is a closed loop with a ~2-week cycle, human in the loop, evidence on disk. It is slower than
a bandit and it is the one that will actually work at ~100 dispatches/day with a delayed,
non-stationary, non-randomised reward.

**The `route_drift` alarm is the deliverable that makes this real.** Without it this degenerates
into "someone should look at the numbers sometime," which is how the bandit got here.

---

## §4. The contract with the phases

### 4.1 What exists

`leadv2_admission_map_class` (`lib/leadv2-admission-class.sh:46-68`) already maps the estimate to a
class, and `_admission_classify` (`leadv2-dispatch-code.sh:3839-3897`) already sets
`ADMISSION_ROUTE` in `{phases, dispatch}`. **The Phase-1 contract is half-built.** Current mapping:

```
complexity == complex  OR  risk == safety_publish_payments  OR  subsystems >= 4   -> Heavy
complexity == standard                                                            -> Standard
complexity in {trivial, simple}                                                   -> Light
```

Explicit `--task-class` is **escalate-only** (`leadv2_admission_class:80-92`): the flag wins unless
the estimate ranks higher. Keep that; it is the right asymmetry.

### 4.2 The mapping — make it explicit and complete

Add the missing rows. `Strategic` is in the class vocabulary and `SIZE_MAP`, but
`leadv2_admission_map_class` **can never produce it** — it is reachable only from an explicit flag
or a task record. Either give it a rule or state that it is flag-only. I recommend flag-only and
documenting that, because "strategic" is a founder judgment about *importance*, not a property of
the mission text — a judge cannot see it.

| Class | Estimate condition | Phase route | Planning | Triad (architect+critic+security) | Gate-1 | Live-verify gate |
|---|---|---|---|---|---|---|
| **Light** | `complexity` in {trivial,simple} AND `risk == none` AND `subsystems <= 3` | `dispatch` | **skip** | **skip** | skip | only if `needs_live_verification` |
| **Standard** | `complexity == standard` AND `risk != safety_publish_payments` | `phases` | required | critic only | skip | if `needs_live_verification` |
| **Heavy** | `complexity == complex` OR `subsystems >= 4` OR `risk == data` | `phases` | required | architect + critic | **required** | if `needs_live_verification` |
| **Strategic** | flag / task-record only — never estimated | `phases` | required | full triad | **required** | **always** |
| *any* | `risk == safety_publish_payments` | `phases` | required | **+ security-auditor, unconditional** | **required** | **always** |

Two deltas from today, both deliberate:

- `risk_class == data` currently contributes to Heavy only via the `safety_publish_payments`
  branch — `data` alone maps nowhere. This table routes `data` (migrations, schema) to Heavy +
  Gate-1, which is what the standing rule `feedback_migration_review_must_apply` ("apply to scratch
  PG 2x") requires. Today a migration with `complexity=standard` gets Standard and no Gate-1.
- `needs_live_verification` gains its **first reader**: it selects the live-verify gate. This is
  the justification for keeping the field at all (§1.2).

### 4.3 What the estimator must output for the phase machinery to consume it

The existing `TaskEstimate` v1 schema plus `context_bytes`, bumped to `estimate_v: 2`. Validation
lives in `leadv2-task-judge.sh:_validate_estimate` and must gain the new field.

```json
{
  "estimate_v": 2,
  "complexity": "trivial|simple|standard|complex",
  "duration_class": "short|medium|long",
  "work_kind": "build|review|diagnose|docs",
  "risk_class": "none|data|safety_publish_payments",
  "subsystems_touched": 0,
  "needs_live_verification": false,
  "context_bytes": 0,
  "estimate_id": "<sig8>",
  "estimate_source": "judge|fallback"
}
```

**Backward compatibility (hard requirement).** `_validate_estimate` currently rejects
`estimate_v != 1`. It must accept `1` **or** `2`, defaulting `context_bytes` to `0` on a v1
document — otherwise every cached estimate under `docs/leadv2/judge-cache/` becomes invalid on
deploy and every dispatch in flight re-pays the judge call. `context_bytes: 0` must mean
"unmeasured → skip the STEP-1.5 context filter", never "zero bytes → filter everything".

`context_bytes` is **computed by the caller in bash**, not asked of the model. The prompt template
gains **no new field** and no new vocabulary — the arm-blindness invariant and
`test_lexicon_grep_on_prompt_template` are untouched.

---

## §5. The migration

No flag day. Four stages, each with a number that ends it.

### 5.1 Stage 0 — measure the baseline (no behaviour change)

Ship only the **writers**: un-gate `route-estimates.jsonl`, add the `route-outcomes.jsonl` writer
to `leadv2-phase8-close.sh`, add `leadv2-route-audit.sh`. Zero routing change.

**Exit condition: 200 scored outcome rows.** At 85–187 dispatches/day and a landed+dead rate of
~79% of dispatches, that is **~2–3 days**. Publish the baseline first-pass rate. **Everything after
this stage is compared against that number**; until it exists, "better" is unmeasurable and no
further stage may ship.

### 5.2 Stage 1 — shadow

The new selector runs as a **second, side-by-side call** in `route_arbiter`'s caller. It spawns
nothing. Both picks are journalled:

```
route_shadow task=<sig8> live_arm=<a> live_effort=<e> live_reason=<r>
             shadow_arm=<a2> shadow_effort=<e2> shadow_reason=<r2>
             agree=<0|1> divergence_kind=<same|cheaper|dearer|refuse_avoided|refuse_added>
```

`LEADV2_SELECTOR_MODE=off|shadow|enforce`, default `off`. **Naming note (self-check item 1):** this
deliberately breaks the repo's `0|1` env convention (`LEADV2_ROUTER_V2=0`) because a three-state
rollout needs three states, and encoding it as two booleans is how you get an `on-but-shadow`
ambiguity. There is precedent for value-shaped `LEADV2_*` vars (`LEADV2_CLAUDE_PERMISSION_MODE`,
`LEADV2_BOT_MODE`). Grepped `plugins/leadv2/`: no existing `LEADV2_SELECTOR*` var, so no collision.

**Exit condition: 200 shadow rows** (~2–3 days). The comparison that proves it is better — all
three must hold:

| # | Claim | Test on the shadow rows | Pass bar |
|---|---|---|---|
| C1 | It refuses less | `divergence_kind == refuse_avoided` count vs live `terminal=fail` count | **`refuse_added == 0`** and `refuse_avoided >= 15` (baseline 24 refusals / 298 = 8.1%) |
| C2 | It does not just get expensive | mean `ecost(shadow) - ecost(live)` | **<= +1.0** cost units |
| C3 | Divergences are explainable | every `agree=0` row carries a non-empty `penalties=`, or `last_resort=1`, or `context_fit=filtered` | **100%** — a divergence with no named cause is a bug, not a decision |

C3 is the one that matters. A selector that diverges for reasons it cannot name is the same
`cheapest_capable`-label problem in a new coat.

### 5.3 Stage 2 — enforce, with a live comparison window

`LEADV2_SELECTOR_MODE=enforce`. Rollback is one env flip back to `shadow`; the old arbiter body
stays in the file for one full cycle, not deleted.

**The exact number that says revert** — evaluated on a rolling 100-dispatch window, any one trips:

| Metric | Baseline (§0) | **REVERT if** |
|---|---|---|
| Escalation rate (`fallback_depth > 0`) | 29.5% | **> 34.5%** (baseline + 5pp) |
| Hard-refusal rate (`terminal=fail`) | 8.1% | **> 0.0%** — after §2.3 the only legal refusal is `all_arms_operator_excluded`; a single quota-caused refusal means the invariant is broken |
| First-pass rate | Stage-0 baseline `B` | **< B - 5pp** |
| `effort_dropped` rate | measure at Stage 0 | **> Stage-0 rate** — §2.7 exists to reduce it; an increase means the swap logic inverted |

100 dispatches is about one day at current volume, so a bad enforce is caught within a day, not a
week.

### 5.4 Negative control — mandatory, and it must be run

Per the standing E2E doctrine (E2E-KILLRATE-01), a green suite that has not been shown to go red
proves nothing. Note: `tests/mutations/catalog.yaml` **does not exist in this repo** (it is
persona-engine's) — so this ships as a documented mutation procedure in the new suite's header,
applied by hand in a scratch worktree, with the red run pasted into the close.

New suite: `plugins/leadv2/scripts/tests/test-selector-quota-invariant.sh`, selected by CI on any
change to `lib/leadv2-route-arbiter.sh` or `config/leadv2-routing.yaml` — **add the
`EXTRA_SUITE_MAP` row and prove selection with `--scope changed`**, or the suite is worthless (this
is the exact failure mode `tests/contract/publish-end-to-end.sh` had for weeks).

Three mutations, each applied **inside the function body**, each of which the suite must kill:

| # | Mutation | Where | Reintroduces |
|---|---|---|---|
| **M1** | In STEP 3, change `state(p) != OVER` to `state(p) == UNDER` | eligibility filter body | **D-1 exactly.** All-unknown probes → empty eligible → refusal. This is the 2026-09-01 journal line. |
| **M2** | In `ecost`, set `unknown_penalty` from 20 to 0 | cost function body | An unknown-quota arm ties with a known-healthy one and can win on the alphabetical arm tiebreak. |
| **M3** | Delete the `last_resort` branch (3a) | eligibility body | A genuinely over-ceiling fleet hard-refuses instead of degrading. |

The suite must go **red on each**, and green with all three reverted. If M1 does not turn it red,
the suite is testing something other than the invariant the founder asked to be made impossible.

Positive assertion, stated as the closing sentence of the change:
> *"Mutation M1 is killed by `test-selector-quota-invariant.sh`, which CI selects on a change to
> `lib/leadv2-route-arbiter.sh`"* — with the red run output attached. Nothing weaker.

---

## §6. Risks, and what I am not sure about

| # | Risk | Mitigation |
|---|---|---|
| R1 | `last_resort: sonnet` makes the Anthropic bucket the shock absorber for every quota gap. If glm and codex are both genuinely exhausted, sonnet takes the whole load and hits its own 95% ceiling. | It is still `never_capped` and still succeeds — but the WARN + founder notification in §2.3-3a is load-bearing, not decorative. Consider `last_resort` as an ordered *list* (sonnet, then codex-volume) rather than a single arm. **Not designed here.** |
| R2 | `effort_swap_budget` has no empirical basis. | Ship it at `5` behind config, measure `effort_capable_swap` frequency and its first-pass rate in the §3 ledger, tune at the first monthly review. Named as a guess in the config comment. |
| R3 | `context_bytes / 3.5` is a chars-per-token constant for English prose; code and JSON run denser. | The `x 0.6` safety factor absorbs the error in the conservative direction. Fails toward *excluding* a small-context arm, which cascades to a bigger one — the safe failure. |
| R4 | Retiring `all_arms_capped` breaks `leadv2-dispatch-code.sh:7470`, `tests/test-route-arbiter.sh:37`, and `tests/test-model-select-telemetry.sh:504-510`. | All three are named. Update in the same commit. `test-model-select-telemetry.sh` case (g5) asserts the old cause string and **will go red** — that is correct, it is asserting the defect. |
| R5 | `estimate_v: 2` invalidates every cached estimate if `_validate_estimate` is not made version-tolerant. | Explicit backward-compat requirement in §4.3. This is the highest-probability implementation mistake in the whole design. |
| R6 | Adding `risk_class` to the bandit context key would make §3.1(2) worse. | §3 removes the bandit from the routing path entirely, so the key stops mattering. If the bandit is kept for any reason, **do not** widen its key. |
| R7 | The judge runs twice per dispatch (§1.5). Adding `context_bytes` in bash means the two call sites can disagree if only one computes it. | Compute `context_bytes` once in the dispatcher and inject it into the estimate JSON after the judge returns — never inside `leadv2-task-judge.sh`, which has two entry points. |

### Things I could not determine

1. **What fraction of the 24 hard refusals were probe failures vs genuine exhaustion.** The journal
   shows `unknown_capped` on the rows I sampled, but I did not enumerate all 24. If a material
   share were genuine exhaustion, R1 gets sharper. **Measure this in Stage 0 before Stage 2.**
2. **Whether `context_bytes` would actually have changed any of the 29 `fallback_depth >= 3` rows.**
   I argued the mechanism; I did not verify it against those specific lanes, because the journal
   does not record mission size. **This is the weakest justification in §1** — if Stage-1 shadow
   shows `context_fit=filtered` firing on ~0% of dispatches, cut the dimension.
3. **Whether `leadv2-cost-estimate.sh` / `prior-art.yaml` already carries a usable novelty signal.**
   Not read (discovery budget). Deferred in §1.4 rather than designed on a guess.
4. **`terminal=refused` (45 rows) vs `model_select_telemetry terminal=fail` (24 rows)** — these two
   counts should describe overlapping populations and I did not reconcile them. Do so before
   quoting 8.1% as the headline baseline; the real refusal rate may be higher.

---

## §7. Out of scope — the implementing agent should ignore all of this

- `LEADV2_ROUTER_V2` / `resolve_v2_dispatch` / `leadv2-router-v2.{sh,py}`. It is a parallel shadow
  path the live dispatch does not use. **Do not turn it on, do not extend it, do not delete it** in
  this change. Its `unknown_headroom_failopen` policy is cited in §0 only as evidence that the
  correct semantics were already written down once.
- `leadv2-route-bandit.sh` and `leadv2-route-bandit-py.py`. §3 removes them from the routing path;
  it does **not** delete them, and the `judge-audit` subcommand is reused. No edits.
- The judge prompt template. Zero changes. The arm-blindness invariant and its grep test are the
  one thing in this subsystem that is correct and load-bearing.
- The quota-ceiling three-reader divergence (D-6). Documented as a hazard; **do not fix it here** —
  the fix is a separate task and mixing it in makes the §5.3 revert numbers uninterpretable. The
  only requirement is that the new selector reads `leadv2-routing.yaml` and nothing else.
- `_admission_classify`'s explicit-flag escalate-only semantics. Correct as-is.
- Anything under `.claude/worktrees/`. Stale per-lane copies.
- Deleting the old arbiter body. It stays in-file for one full cycle after Stage 2.

---

## §8. Mandatory constraint checklist

1. **Env var naming** — `LEADV2_SELECTOR_MODE` follows the `LEADV2_*` prefix. Grepped
   `plugins/leadv2/`: no existing `LEADV2_SELECTOR*` var. The deliberate divergence from the `0|1`
   convention is stated and justified in §5.2. **PASS.**
2. **File paths** — every path cited was existence-checked. All 15 source/config/test paths `OK`.
   `docs/handoff/SELECTOR-DESIGN-01/` created. **To-create:**
   `plugins/leadv2/scripts/tests/test-selector-quota-invariant.sh`,
   `scripts/leadv2-route-audit.sh`, `docs/leadv2/route-outcomes.jsonl`,
   `docs/leadv2/route-estimates.jsonl`. **Confirmed absent:** `tests/mutations/catalog.yaml`
   (persona-engine's, not this repo's) — §5.4 adjusted accordingly rather than citing a file that
   is not there. **PASS.**
3. **`claude -p` commands** — this design adds no new `claude -p` invocation. The existing judge
   call (`leadv2-task-judge.sh:_invoke_judge`) already carries `--max-turns 3`,
   `--permission-mode bypassPermissions`, `--output-format json`. **PASS, verified not assumed.**
4. **Concurrent access** — two race surfaces named, both given a mitigation:
   (a) `route-outcomes.jsonl`, written by `leadv2-phase8-close.sh` from concurrently-closing lanes
   → `flock`, reusing the pattern already in `leadv2-task-judge.sh:_journal`;
   (b) **the pre-existing D-5 race** on the global anti-sticky state file
   `${TMPDIR}/leadv2-route-arbiter-last-arm` — per-repo scoping plus `flock` on the
   read-modify-write, §2.6. **PASS.**
5. **Config contradiction check** — one found and escalated: **D-6**, quota ceilings declared in
   three places with two values (`leadv2-routing.yaml` codex work 90 vs
   `lib/leadv2-glm-policy-resolve.py` `DEFAULT_BUILD_THRESHOLD_PCT` 80). Pre-existing and
   documented in `config/leadv2-quota-ceilings.sh`'s own header. **Not introduced by this design**;
   a constraint is added (§7) that the selector read the yaml only, so it does not become
   four-way. **FLAGGED, not fixed — deliberate.**

### Pre-finalize contradiction scan

- Env-var names vs settings: **none.** No collision, no shadowing.
- Flag semantics vs other usages: **one, benign.** `LEADV2_SELECTOR_MODE`'s tri-state shape differs
  from `LEADV2_ROUTER_V2`'s boolean. Justified §5.2; precedent exists.
- Path existence: **clean.** All cited paths verified; all new paths marked to-create; the one
  assumed-existing path that turned out absent (`tests/mutations/catalog.yaml`) was caught and §5.4
  rewritten rather than shipping a reference to a file that is not there.
- **Mission-premise contradiction: 2 of the stated defects are already fixed on disk** (§0). This is
  the largest finding in the document. An implementer working from the mission text alone would
  have re-fixed the bandit context key and re-wired `effort` — both of which landed under
  COMPLEXITY-ESTIMATOR-IS-OFF-01 and EFFORT-IS-NOT-WIRED-01 — and would have left D-1, the defect
  actually causing the founder-visible symptom, untouched.

DELIVERABLE_COMPLETE

## ДОПОЛНЕНИЕ 2026-09-02 (замечание основателя): диапазон армов для сборки отрезан с обоих концов

Живая лестница, `config/leadv2-routing.yaml` -> `router.dispatch_ladder`:

| арм | when |
|---|---|
| glm | all |
| glm-flash | trivial, light, standard |
| kimi | all (снят распоряжением основателя) |
| codex | all |
| sonnet | all |
| freepool | light, standard, bulk |
| **haiku** | **review** |
| **opus** | **review** |
| fable | architect, heavy |

**Следствие, которое объясняет «воркер всегда sonnet»:** opus и haiku допущены только к ревью, то
есть трудную сборку нельзя отдать опусу, а механическую правку в одну строку нельзя отдать хайку —
оба конца диапазона отрезаны конфигом. Для сборки остаются четыре арма. Sonnet выигрывает не как
лучший писатель кода, а как единственный оставшийся сверху.

Fable формально допущен к heavy, но за 35 диспатчей 2026-09-02 не выбран ни разу. Отдельно проверить,
достижим ли он вообще или его срезает сортировка по цене — недостижимая ветка это то же самое, что
её отсутствие (ср. GLM-FAILED-TWICE-UNREACHABLE-01).

**Тиры Codex не являются решением маршрутизатора.** В матрице способностей есть `codex-standard` и
`codex-top`, в лестнице — один `codex`. Тир задаётся человеком через `--tier top --reason`, машина о
ручке не знает. То же и с усилием: пара «модель + усилие» сейчас распадается на решение машины
плюс привычку человека.

**Требование к проекту селектора:** он выбирает не арм, а пару (модель, тир/усилие). Множество
допустимых моделей для сборки определяется оценённой сложностью задачи, а не статическим списком
`when:`, написанным на глаз. Каждое исключение модели из сборки должно иметь причину, выраженную
через способность или квоту, и быть проверяемым — «opus только для ревью» такой причины не имеет.

Негативный контроль: задача, оценённая как самая трудная, обязана иметь opus в множестве кандидатов;
задача, оценённая как механическая правка, обязана иметь haiku. Вернуть статический `when:` -> обе
пробы краснеют.
