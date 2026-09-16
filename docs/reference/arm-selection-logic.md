# How an arm is chosen — the full picture

Written 2026-09-16 for the founder, who asked how glm and glm-flash rank against everything else and
whether flash is under-used. Every number below was measured, not recalled; where a number is stale
or unmeasured it says so. Source of truth for the config is
`plugins/leadv2/config/leadv2-routing.yaml`; the live decisions are the `route_resolved` and
`model_select_telemetry` lines in `~/.claude/leadv2-state/*/tasks/dispatch-*/journal.md`.

This document describes what the system DOES today. Corrections go in `§9`.

---

## 1. The short version

Five filters run in order. An arm must survive all five.

| # | Filter | Where | Removes |
|---|---|---|---|
| 1 | **Role eligibility** — does this arm do this KIND of work at all? | `capability_matrix[].kinds` | opus from every build (it has no `code`) |
| 2 | **Size eligibility** — standard / heavy / bulk | `capability_matrix[].sizes` | haiku and codex/luna from anything above `standard` |
| 3 | **Ladder window** — which classes the dispatcher will even offer it | `dispatch_ladder[].when` | freepool from `heavy`/`strategic` |
| 4 | **Protected-path gate** | `protected:` + `protected_path_patterns` | `protected: false` arms from safety/publish/payments |
| 5 | **Arbiter economics** — `ecost` = price ÷ (headroom × reset-urgency), plus penalties | `router_v2.cost`, `complexity_penalty` | **this is where flash actually dies** |

Filters 1–4 are policy and are easy to read off the yaml. Filter 5 is where the surprises live.

---

## 2. The capability ladder

`capability` is a hand-assigned integer. **It is not derived from any benchmark** — there is no
reference to livebench, artificialanalysis, arena or any external source anywhere in the routing
config. It encodes our own judgement, entered by hand, and last touched 2026-09-14.

| capability | arms |
|---|---|
| 6 | fable, astra |
| 5 | opus, sol |
| 4 | glm, sonnet, codex/terra |
| 3 | codex/luna |
| 2 | haiku, **glm-flash**, freepool |

A task carries a required-effort number (`req_eff`, visible in every `route_resolved` line). An arm
below that number is not "slightly short" — it is out.

**This is the single most consequential table in the system and the least evidence-backed.**
glm-flash sits at 2, level with haiku, while glm sits at 4. That one integer is what decides most of
what follows.

---

## 3. Price — and the hole in it

`router_v2.cost` is keyed by PROVIDER, not by arm, with one exception:

```yaml
glm-flash: 0.33   # Z.AI credit-weight ratio, GLM-EFFICIENCY-01
glm:       1.0    # the unit
codex:     null
anthropic: null
freepool:  1.0
```

`null` means **fall back to the matrix median, which is 1.0**.

The consequence is blunt and worth stating plainly: **haiku, sonnet, opus, fable, codex/luna,
codex/terra, astra and sol all cost exactly the same number to the arbiter.** The
`cheapest_capable` rule cannot separate any of them. When sonnet beats opus, or luna beats astra, it
is never because it was cheaper — it is because of capability and role eligibility alone.

So the question "why don't we use sonnet where opus isn't needed" has a mechanical answer: the
arbiter is not able to ask it. Only the GLM family carries real prices, which is exactly why the
GLM family is the only place where price visibly moves decisions.

---

## 4. Why opus never builds

`opus` has `kinds: [review, plan, audit, safety]`. There is no `code`. It is also
`pool_default: false`, so it is not in the default review auction either — it must be reached
deliberately. `sonnet` has the full set `[code, docs, review, plan, audit, fanout-class-funnel,
backlog-pump]`.

Measured over 2026-09-06 → 2026-09-16: opus appears in `arm_excluded` 77 times, of which
**67 are `not_in_pool`**. It is not losing an economic contest; it is not entering one.

---

## 5. glm-flash: what actually stops it

The founder already removed the policy blocks himself
(`GLM-FLASH-DOES-ANY-WORK-01`, 2026-09-10): the ladder entry is now `when: [all]` with no
`untrusted:`, and the matrix row is `protected: true`, `sizes: [standard, heavy, bulk]`. Nothing in
filters 1–4 stops it any more.

That unlock is visible in the data. glm-flash exclusion reasons, dated either side of 09-10:

| reason | before 09-10 | on/after |
|---|---|---|
| `untrusted` | 49 | 13 (residual) |
| `price_ratio` | 16 | **175** |
| `forecast` | — | 63 |
| `capped` | — | 62 |
| `not_launchable` | 1 | 21 |

The old gate went away and a new one took its place. **`price_ratio` is now the dominant reason
glm-flash does not run.** The cheapest arm in the fleet, at a third of glm's price, is being
excluded on price — because the ratio is capability-adjusted, and `capability: 2` cancels the
discount.

The second brake is `complexity_penalty`:

```yaml
complexities: [complex]
penalize_tags: [cheap, mechanical]   # +100 ecost
```

glm-flash carries `tags: [cheap, mechanical]`; glm carries `tags: [bulk, background]` and is not
penalised. A `+100` penalty against a 3× price advantage is not a tilt, it is an exclusion.

How often does that fire? Measured over all journals:

| complexity | count |
|---|---|
| standard | 1159 |
| **complex** | **1000** |
| simple | 455 |
| trivial | 206 |
| unknown | 89 |

A third of all classified work is `complex`, and flash cannot win any of it.

---

## 6. What actually ran

563 `route_resolved` lines carrying an arm, 2026-09-06T09:51Z → 2026-09-16T13:43Z.

| arm | count | share |
|---|---|---|
| glm | 236 | 41.9% |
| codex | 145 | 25.7% |
| sonnet | 114 | 20.2% |
| glm-flash | 19 | 3.4% |
| fable | 19 | 3.4% |
| (refused) | 15 | 2.7% |
| astra | 10 | 1.8% |
| freepool | 3 | 0.5% |
| sol | 1 | 0.2% |
| haiku | 1 | 0.2% |

By role: worker 500 of the 563 (glm 220, codex 115, sonnet 110, glm-flash 19); reviewer 63
(codex 30, glm 16, fable 13, sonnet 4).

By class, from `model_select_telemetry` (465 lines):

- **light**: glm-flash 9, codex 6, glm 5, freepool 1
- **standard**: glm 100, codex 85, sonnet 39, freepool 3, fable 3, glm-flash 2
- **heavy**: glm 58, codex 58, sonnet 41, astra 4, fable 1
- **strategic**: sonnet 20, codex 11, astra 4, glm 1

The shape of the problem is in that list. glm-flash wins where the work is trivial — and `light` is
a rounding error on this board. In `standard`, which is the single biggest bucket, flash took
**2 of ~232**. In `heavy` and `strategic` it took none.

All 19 of its wins came with `reason=cheapest_capable` (18) or `explicit_requested_capable` (1), so
when it is genuinely allowed to compete on price, it wins. It is almost never allowed to.

---

## 7. The honest summary

The founder's impression — "glm is used everywhere, and there is a large class of work where flash
would be as good for less" — is consistent with everything measured here. What the data adds:

1. **The block is no longer policy, it is arithmetic.** Unlocking the ladder again would change
   nothing; `price_ratio` and `capability: 2` are doing the work now.
2. **The capability integers are the weakest link.** They are hand-set, benchmark-free, and one of
   them (flash = 2) is responsible for most of the imbalance.
3. **Half the fleet is unpriced.** With codex and anthropic at a default 1.0, the arbiter is blind
   to the sonnet-vs-opus and luna-vs-astra tradeoffs entirely. The founder's guess that the same
   problem affects codex tiers is correct, and it is the same root cause.

## 8. What would actually move it — unstarted, listed for the founder's call

- **A. Price codex and anthropic for real.** Until then `cheapest_capable` is a two-arm rule wearing
  a fleet-wide name. Biggest single win, and it costs nothing at runtime.
- **B. Re-derive `capability` from evidence instead of judgement.** We already record
  `cost_actual_recorded` with `rounds=` per lane — rounds-to-PASS per arm per class is a measurement
  we are already collecting and not using. External boards (livebench, artificialanalysis, arena)
  can seed the priors; our own rounds data should settle it.
- **C. Decide whether `complex` is over-assigned.** 1000 of 2909 classified tasks is a lot for a
  label that hard-excludes the cheap tier. Worth sampling by hand before changing the penalty.
- **D. Trial flash on `standard`.** The cheapest honest experiment: let flash compete on a bounded
  slice of standard work, and compare rounds-to-PASS against glm on the same slice. That answers
  "is it actually no worse" with our own numbers rather than anyone's leaderboard.

None of these are started. They are written here so the founder can pick, not as a plan of record.

## 9. Known defects in the documentation itself

- `leadv2-routing.yaml:251` states that glm-flash and freepool "remain `protected: false`" and are
  marked `untrusted: true` in the ladder. **Both halves are false in the live file**: the matrix row
  is `protected: true`, and `untrusted:` was removed by `GLM-FLASH-DOES-ANY-WORK-01`. The comment
  survived the change it describes. It should be corrected or deleted.
- One measurement in this document is missing: "who wins `standard` on and after the unlock" — the
  aggregation returned empty because of a mis-parsed field order, which is a broken query, not a
  zero. The per-class table in §6 covers the whole window instead.
