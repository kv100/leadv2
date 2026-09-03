# SMART-ARBITER-01 — an arbiter that knows the windows, the model, the task and the load

Author: architect (Opus). Date: 2026-09-03. Repo: leadv2 plugin. Status: design brief — no code.

Builds on, and does not re-derive: `docs/handoff/SELECTOR-DESIGN-01/design.md` (decision-function
skeleton, three-state quota, last-resort invariant, founder addendum 2026-09-02 — **not landed**: the
arbiter still carries `unknown_capped`), `docs/handoff/ARBITER-ESTIMATES-BLIND-01/` (**landed**,
`14d1990d`/`baf559e8`: estimates are journaled), `docs/handoff/ARM-CAPABILITY-FROM-OUTCOMES-01/brief.md`
(**not landed**: `leadv2-arm-capability.sh` absent), `docs/handoff/QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01/brief.md`
(in flight: `rate_limit_history`).

The bar, verbatim (founder): «убедись что арбитр умный и понимает квоту недельную, 5 часовую,
возможности модели, сложность задачи, пропускную способность, уровень эффорта для задачи, верно
оценивает сложность и тип задачи и тд ... а если этого нет то это угадывание».

Every number below is from a re-runnable command on the tree at `79db6c62` (2026-09-03) or from a live
probe run at 18:1x UTC. Numbers I could not measure are in §9, not disguised as estimates.

---

## §0. Premise corrections — what actually routes today (measured, read this first)

### 0.1 The coordinator's "1773 refusals" counted the sandbox, not the lanes

Two journals exist and they disagree:

| Source | What it is | `all_arms_capped` lines | util tokens on those lines |
|---|---|---|---|
| `docs/handoff/dispatch-*/` (814 dirs) | handoff artifacts **including `e2e-gate.log`** — the plugin's own product gate running *nested sandbox dispatches* | **1737** — 1729 in `e2e-gate.log`, 6+2 in `developer.stream.jsonl` (workers running the test suite) | 1729/1729 `util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped` |
| `docs/leadv2/tasks/dispatch-*/journal.md` (849 dirs) | the **real lane journals** written by `emit decision` | **20** | 18 all-three-unknown, 2 with glm/codex numeric and claude unknown |

```
grep -rHoE 'arm=refuse task=[^ ]+ reason=all_arms_capped util_glm=[^ ]+ util_codex=[^ ]+ util_claude=[^ ]+' docs/handoff/dispatch-*/ | sed -E 's#^docs/handoff/dispatch-[^/]+/([^:]+):.*util_glm=([^ ]+) util_codex=([^ ]+) util_claude=([^ ]+)#\1 glm=\2 codex=\3 claude=\4#; s/=([0-9]+)( |$)/=NUM\2/g' | sort | uniq -c
grep -rhoE 'route_resolved by=arbiter role=[a-z]+ arm=[a-z-]+' docs/leadv2/tasks/ | sort | uniq -c
```

Real-journal census of the arbiter's own decisions (`route_resolved by=arbiter`):

| arm | picks |
|---|---|
| codex | 161 (+3 as reviewer) |
| glm-flash | 108 |
| sonnet | 86 |
| freepool | 35 |
| **refuse** | **20** |
| glm | 20 |

**The arbiter answers in 430 of 450 real dispatches (95.6 %).** It is the live first-pick router. The
coordinator's ordering rule ("first make it answer, then make it smart") is right as a principle and
wrong as a diagnosis: the component is executing; its *inputs* are what lie (§0.4). The 20 real
refusals (08-26 ×5, 08-31 ×1, 09-01 ×12, 09-02 ×2) are still a defect and D1 removes them.

### 0.2 D0 answer: why `capped()` says "all arms capped" at 13 % — it is the probe, not the ceilings file

- `capped()` (`lib/leadv2-route-arbiter.sh:147-151`) reads ceilings from **`router_v2.quota_ceilings` in
  `config/leadv2-routing.yaml`** (`:146`), default 100 when the key is absent. It never opens
  `~/.claude/config/leadv2-quota-ceilings.sh`. The missing ceilings file (until the 20:04 symlink) could
  not produce a single arbiter refusal. It affected the three *gates*, and those fail **open**
  (`leadv2-glm-quota-gate.sh:39-40` → default 80; `leadv2-provider-quota-gate.sh:20` → `exit 0`).
- The refusal mechanism is `util()` (`:86-111`): **`if x.get('status')!='ok': return (100.0, True)`
  (`:102`)** — a dead probe is scored as 100 % used, so every cell on that provider is "capped". With
  all three probes dead and the freepool gate down, `ok` is empty → `reason=all_arms_capped`, `exit 3`
  (`:169-172`) → the dispatcher **does not fall open to the ladder on rc=3**: it exits 4
  (`leadv2-dispatch-code.sh:7671-7675`). Only rc≠3 falls open (`:7676-7680`). The coordinator's "after
  a refusal the ladder picks" is wrong for exactly the refusal reason he counted.
- Why probes die: the sandbox (e2e-gate) has no credentials, and a headless real session can lack
  `~/.claude/secrets/zai.env` (`leadv2-quota-read.py:167` → `unknown`), the Codex refresh token
  (**live today: `codex: unknown refresh http 401`**), or the `rate_limit_anthropic` kv row.

### 0.3 "The arbiter never picks GLM" — partly wrong, and the real reason is not the sort key

The arbiter picked `glm-flash` 108× and `glm` 20×. What removes the GLM family is not
`ok.sort(...)` at `:212`; it is three upstream mechanisms, all measured:

| mechanism | evidence | effect |
|---|---|---|
| **Prose "safety" classifier** — `grep -qiE 'safety[_-]?gate|\bpublish\b|\bpayments?\b'` over the whole mission text (`leadv2-dispatch-code.sh:7577-7580`) sets `_arb_safety=1` → `require_trusted` (`arbiter:76-80`) → only `protected: true` cells survive (`:165`); the ladder strips untrusted arms the same way (`:2330-2352`) | `arm_excluded by=router arm=glm-flash reason=protected_path` **183**, `arm=freepool` **196** (real journals) | ~40 % of dispatches are "protected" by prose; cheapest *trusted* code cell is codex-volume (cost 3), then sonnet (5). glm-5.3 has `protected: false` (`routing.yaml:60`) |
| **Class → complexity → penalty chain** — `_fallback_estimate` maps `class_hint Heavy → complex/long` (`leadv2-task-judge.sh:96-100`); `complexity_penalty` adds +100 to any cell tagged `cheap/mechanical/bulk/background` when `complex` (`routing.yaml:118-121`, `arbiter:189-211`); glm-5.3 is tagged `[bulk, background]` (`:60`) | telemetry: `class=heavy → codex 72, sonnet 50`; `estimate_source=fallback` **416** vs `judge` **47** | **Heavy ≡ not-GLM by construction**: 90 % of estimates are the line-count fallback, and the class hint alone makes them `complex` |
| **Post-pick reroute** — `glm-quota-gate` benches glm on `max(5h, weekly) ≥ 80` *or* **peak hours 06:00–10:00 UTC** (`leadv2-glm-quota-gate.sh:79-84,165-172`) and the arbiter re-runs over the remaining arms (`dispatch-code:7737-7751`) | `route_headroom_chosen after=glm_quota_gate → sonnet 43, codex 11`; `after=primary_arm_benched → sonnet 11, codex 2` | with GLM at 1 %/13 % (live), every peak-hour pick still lands on sonnet/codex |

Final arm actually run (`model_select_telemetry … terminal=win`, real journals, role=worker):

| arm | final wins | arbiter picks | delta |
|---|---|---|---|
| sonnet | **160** | 86 | +74 — sonnet is the sink of every post-pick failure |
| codex | 95 | 161 | −66 (codex probe 401 → `unknown_capped` → benched) |
| glm-flash | 52 | 108 | −56 (peak hours, quota gate) |
| freepool | 25 (+4 fail) | 35 | −10 |
| glm | 5 (+1 fail) | 20 | −15 |
| refuse | 15 fail | 20 | |

So the honest sentence is: **the arbiter picks cheap-first, and everything after the pick pushes the
work to sonnet.** A design that only touches the sort key changes 0 of these three mechanisms.

### 0.4 The seven inputs — where each one stands today

| founder input | exists? | what the decision actually sees | verdict |
|---|---|---|---|
| weekly window | yes, per provider (`quota-live json`) | folded into one number `max(5h, weekly)` (`arbiter:103,110`), compared to a *weekly* ceiling (`routing.yaml:33`) | half-blind: 5h and weekly are indistinguishable |
| 5-hour window | yes | same fold; a 5h burst at 96 % reads OVER on a 95 weekly ceiling, a weekly 79 % with 5h 0 % reads fine | half-blind |
| model capability | asserted in `capability_matrix` (`routing.yaml:59-84`) | hard filter kinds/sizes/protected; static `cost` | asserted, never measured (ARM-CAPABILITY-FROM-OUTCOMES-01 not landed) |
| task complexity | judge output, 90 % fallback = **mission line count** (`task-judge.sh:102-108`) | one rule: `complex` → +100 on cheap tags; nothing else | present but mostly fabricated from length + class hint |
| throughput | **does not exist** | nothing | §4 |
| effort | `effort_matrix` on the winning cell's tags (`arbiter:232-247`) | high/low/medium from tags; complexity never enters | present, blind to the task |
| task type | `kind` (CLI, almost always `code`), judge `work_kind`, prose regex, fallback substring list `('payment','publish','safety gate','safety-gate')` (`task-judge.sh:109-112`) | prose decides "protected", which decides the arm family | founder-measured 18/19 false positives, 1/1 false negative; the substring `publish` matches "publishes", the bare token `safety` is absent from every pattern |
| Claude account (two buckets) | `quota-live` returns both accounts (live: max_20x 5h 52/7d 49 active; max_5x 5h 54/7d 26) | arbiter reads **only the `active` one** (`arbiter:109`); `active_account: max_20x` is *pinned* in yaml (`routing.yaml:10`), live `account_resolution=pinned_unresolved`; the real account is chosen later by `leadv2-claude-profile-select.sh` inside `claude-subsession.sh:440-496` (lowest worst-window utilisation, registry has 2 entries) | two decisions, arbiter blind to the second; after 09-15 the pinned label is wrong |

---

## §1. Order of work — answer to "first answer, then answer smartly"

Agreed on principle; the measured premise differs, so the order is:

1. **D0 measure** (done in part above; the rest in §6) — every number that feeds a rule gets a command.
2. **D1 truthful inputs** — a dead probe is UNKNOWN, never 100 %; every input carries its source; the
   emitted line says what was guessed. *This* is "make it answer": it removes the 20 refusals and the
   `exit 4`s, and it stops the codex-401 → sonnet slide.
3. **D2 window model** — 5h and weekly as separate states per *bucket*, two Claude buckets by
   `account_key`, pressure from `rate_limit_history`.
4. **D3 decision function** — the ecost below; peak hours and the post-pick gates folded into the one
   decision so there is one pick, not pick-then-bench-then-repick.
5. **D4 task-type truth** — prose never removes arms; paths and flags do; the diff is checked at review.
6. **D5 effort/tier pair** — complexity enters effort and codex tier; `--tier` becomes an override.
7. **D6 throughput ledger** — measured before it steers; weight 0 until n ≥ 10 per cell.
8. **D7 shadow → enforce.**

A "smart" sort on top of D0-unfixed inputs is the guessing the founder describes, only with more
decimals. That is why D1/D2/D4 precede D3.

---

## §2. The decision model — the function, readable and contestable

### 2.0 Inputs (each with a `source`; an input without a source is UNKNOWN, never a default number)

```
L  lane      kind, role∈{worker,reviewer}, task_class_raw, flags{protected,safety,publish,ui_judgment}
             + flag_source∈{cli,path,judge_risk,prose}, allowed_arms, test_only, failed_arms[task], round_n
E  estimate  complexity∈{trivial,simple,standard,complex}, duration_class∈{short,medium,long},
             work_kind∈{build,review,diagnose,docs}, risk_class, subsystems_touched, estimate_source∈{judge,fallback}
Q  quota     per bucket b ∈ {glm, codex, claude:<account_key>…, freepool}
             per window w ∈ {five_hour, seven_day}: pct, reset_epoch, status∈{ok,stale,unknown},
             rate_pct_per_h (from rate_limit_history, else null), ceiling(b,role,w)
C  config    capability_matrix (+cell.bucket_class), quota_ceilings (+5h keys), cost_penalties,
             last_resort, time_windows (peak), effort_rules, unknown_policy
T  throughput per (arm,class): n, median_build_min, inflight(provider)   — absent until D6 ships
```

### 2.1 Hard rules (never traded against price) — in order

| # | rule | source of truth |
|---|---|---|
| H1 | capability filter: `kind ∈ cell.kinds`, `SIZE_MAP(task_class) ∈ cell.sizes`, `require_trusted ⇒ cell.protected`, `allowed_arms` | unchanged from `arbiter:165` + SELECTOR-DESIGN §2.1 |
| H2 | `require_trusted` is computed from **flags and paths only** (`flag_source ∈ {cli, path}`); `prose` and `judge_risk` can raise effort and reviewer rank, never remove a cell | D4 |
| H3 | bucket state OVER on **either** window ⇒ every cell on that bucket is ineligible for this role; ceilings are per window and per role | D2 |
| H4 | provider lockout / operator kill / `arm ∈ failed_arms[task]` ⇒ ineligible (retry is +1000, effectively hard, keeps the chain non-empty) | SELECTOR-DESIGN §2.3-2.4 |
| H5 | **last-resort invariant**: if nothing is eligible, the least-pressured Claude bucket's `sonnet` cell (a `protected: true` cell) is selected with `reason=last_resort_over_ceiling`, journaled at WARN, founder-notified. `all_arms_capped` ceases to exist as a reason; a quota number can never produce `exit 4` | SELECTOR-DESIGN §2.3, adopted verbatim |
| H6 | UNKNOWN is eligible (never OVER, never 0 %) | D1 |

### 2.2 Continuous part — one additive number per (cell, bucket)

```
ecost(c,b) = c.cost                                   # 0.33 .. 9, static, config
           + cap_penalty(c,E)                         # 100 per matched cost_penalties row (config, tags-based)
           + freepool_floor(c)                        # +100, existing FP-08, unchanged
           + pressure_penalty(b)                      # P_max · pressure(b)^k,  P_max=10, k=2 (config)
           + unknown_penalty(b)                       # +2 if state(b)=UNKNOWN (config; see why not 20 below)
           + peak_penalty(c,now)                      # config time_windows: mode=ban → ineligible; mode=multiplier → c.cost·(m−1)
           + retry_penalty(c)                         # +1000 if c.arm ∈ failed_arms[task]
sort key  = (ecost, pressure(b), −throughput_score(c), c.arm, c.tier)   then anti-sticky rotation among equal ecost
```

**Why these magnitudes (bands that cannot cross):** economics live in 0..~19 (cost ≤ 9 + pressure ≤ 10);
capability/safety penalties are 100 so no amount of quota comfort buys a cheap cell a task it is
config-marked unfit for; retry is 1000 so round N never re-picks a failed arm. Within the economic band
pressure *can* invert cost — that is the founder's requirement ("distribute by remainder is the only
way not to hit the wall") — but convexity (k=2) keeps cheap arms preferred until real danger:
pressure 0.5 → +2.5 (glm 3.5 still beats sonnet 5); pressure 0.8 → +6.4 (glm 7.4 loses).

**Why `unknown_penalty=2`, not SELECTOR-DESIGN's 20:** with +20 an unknown codex (3+20) loses to sonnet
(5) forever; measured while its probe read 401: codex `terminal=win` 95, `fail` 0. The evidence says
unknown ≠ bad. +2 puts codex-volume (5) in a tie with sonnet (5) and lets pressure decide; the loud
`degraded=quota_codex` token (§2.4) makes the guess visible instead of hiding it inside a big number.

**pressure(b)** — the piece that makes the two windows and the two accounts real:

```
for each window w of bucket b:
  remaining_w   = ceiling(b,role,w) − pct_w                         # points left before this role's ceiling
  ttr_w         = reset_epoch_w − now                               # seconds to reset
  if rate_w known (≥2 samples inside the current window, rate_limit_history):
      exhaust_w = remaining_w / max(rate_w, ε)                      # hours until we hit the ceiling at current burn
      pressure_w = clamp(1 − exhaust_w / ttr_w, 0, 1); pressure_source=rate
  else:
      pressure_w = clamp((pct_w − soft_w) / (ceiling_w − soft_w), 0, 1), soft_w = ceiling_w − 30; pressure_source=static
pressure(b) = clamp(max(severity_w · pressure_w), 0, 1)             # severity: five_hour 1.0, seven_day 1.5 (config)
state UNKNOWN ⇒ pressure(b) = 0.5 (config unknown_policy.pressure)   # neither hogs nor starves
```

The weekly severity 1.5 encodes the asymmetry the founder named: a 5h wall costs ≤ 5 hours, a weekly
wall costs days. After 09-15 the personal bucket's 5h ceiling is quartered; nothing in this formula
mentions the tier — `rate_w` rises 4× on that bucket and its pressure rises with it. Buckets are keyed
by `account_key` (stable identity, `rate_limit_history.account_key`), **never by the tier label**.

### 2.3 Effort and tier — part of the same pick (founder addendum 2026-09-02)

The cell already *is* a (model, tier) pair (`codex` ×3 tiers in the matrix). Today the tier is chosen by
a human `--tier` and effort by cell tags alone. Design: `cost_penalties` rows keyed on `complexities`,
`duration_classes`, `subsystems_min`, `risk_classes` steer the pair; `effort_rules` map the winning
cell + `E` to `low|medium|high`:

| condition (config row) | penalised tags | effect |
|---|---|---|
| `complexities:[complex]` | `[cheap, mechanical]` | flash/freepool out; **glm-5.3 stays in** (today's row also lists `bulk, background`, which throws every `complex` task off the GLM family — that contradicts GLM-FIRST-01's exception list, which has no "complex" exception) |
| `subsystems_min: 4` | `[bulk, background, cheap, mechanical]` | the GLM-FIRST-01 *integration-critical* exception, now data-driven from the judge's `subsystems_touched` |
| `risk_classes:[safety_publish_payments]` (from **path/flag** source only) | `[volume, cheap, mechanical, bulk, background]` | codex-standard/sonnet, never codex-volume, for protected code |
| `complexities:[trivial,simple]` + `duration_classes:[short]` | `[exhaustive, architecture]` | no-op on cost today (those cells lose on price anyway); exists so the row is explicit |
| effort: `complex` or `adversarial|safety` tag or `plan` kind or protected ⇒ high; `trivial|simple` + `mechanical|cheap` ⇒ low; else medium | | `--tier`/`--effort` remain as overrides with a mandatory `--reason`, journaled `tier_source=override` |

### 2.4 Emit — the interface contract (single line, additive tokens; existing parsers use named tokens via `sed`, so additions are safe)

```
arm=<a> model=<m> tier=<t> bucket=<account_key|glm|codex|freepool> effort=<e> reason=<cheapest_capable|last_resort_over_ceiling|…>
chain=<a1,a2,…> ecost=<a1:3.0,a2:5.2,a3:7.4>
q_glm=5h:1/90,7d:13/80,p:0.00,src:rate  q_codex=unknown,p:0.50  q_claude:<key1>=5h:52/90,7d:49/95,p:0.31,src:static  q_claude:<key2>=…
inputs=class:fallback,complexity:fallback,safety:none,kind:cli,throughput:absent
degraded=quota_codex,complexity_fallback   route_quality=<ok|guess>
```

`route_quality=guess` when ≥ 2 inputs are degraded; the dispatcher journals it and the status pulse
shows it. **Degradation is loud by construction**: an absent input appears as a named token with value
`unknown|absent|fallback`, never as a number.

Descriptor additions (JSON, additive): `flag_source`, `estimate_source`, `subsystems_touched`,
`risk_class`, `failed_arms[]`, `round_n`, `buckets[]` (from quota-live, all accounts, keyed by
`account_key`). Dispatcher consumes `bucket=` and hands the matching `config_dir` from the profile
registry to `claude-subsession.sh` (seam: `:440-496`), so the arbiter's bucket choice **is** the
account choice — one decision.

Config additions (`router_v2`, all with defaults reproducing today's behaviour): `quota_ceilings.<p>.{five_hour_work_pct, five_hour_review_pct}`
(default = today's weekly value), `pressure: {p_max: 10, exponent: 2, severity: {five_hour: 1.0, seven_day: 1.5}, soft_margin: 30}`,
`unknown_policy: {penalty: 2, pressure: 0.5}`, `time_windows: [{provider: glm, utc: "06:00-10:00", mode: ban|multiplier, factor: 3}]`,
`last_resort: {arm: sonnet}`, `cost_penalties` (superset of `complexity_penalty`; the old key keeps working).

### 2.5 rate_limit_history — the read contract this design needs from QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01

Present in that brief's schema and sufficient for Anthropic: `captured_epoch, account_key, is_active,
state, five_hour_pct, five_hour_reset_epoch, seven_day_pct, seven_day_reset_epoch, binding_window,
source`, index `(account_key, captured_epoch DESC)`. **Requested extension**: rows for `glm` and
`codex` too (either `account_key='glm'|'codex'` with a `provider` column, or a sibling table with the
same shape) — without them `rate_w` exists only for Claude and glm/codex pressure falls to the static
formula (journaled `src:static`, acceptable, but the founder should know the weekly GLM rate is then a
guess). Reader is read-only (`sqlite3 -readonly`), single `SELECT … LIMIT 3`; writer is the probe's one
INSERT per run — no lock contention beyond SQLite's own.

---

## §3. Each of the seven inputs — source, effect, and what happens when it is missing or lying

| input | source (file:line) | effect in §2 | missing / unreliable → behaviour (always journaled) |
|---|---|---|---|
| **weekly window** | glm `weekly.pct` (`quota-live.sh:58-60`), codex `windows[kind=…].used_percent` (`arbiter:106-107`; **UNVERIFIED** which `kind` strings Codex exposes — the probe is 401 today), anthropic `seven_day_pct` per account (`ratelimit-probe.sh:94`) + history rate | H3 OVER at `work_pct|review_pct`; pressure_7d with severity 1.5 | `status≠ok` or sample older than 2×TTL → UNKNOWN: eligible, +2, pressure 0.5, `degraded=quota_<b>_7d` |
| **5-hour window** | `five_hour.pct` / `five_hour_pct` / codex 5h window; `reset_iso` → `ttr` | H3 OVER at new `five_hour_*_pct`; pressure_5h with severity 1.0; `ttr` makes "resets in 20 min" cheap | same as above; if reset_epoch missing, `ttr` = window length (5h/7d) and `src:static` |
| **model capability** | `capability_matrix` cells (`routing.yaml:59-84`): kinds/sizes/protected/tags/cost | H1 filter; base cost; tags drive penalties/effort | a cell is *asserted*; `capability_source=asserted` on every line until ARM-CAPABILITY-FROM-OUTCOMES-01 lands; an out-of-vocabulary kind still folds to `code` and is journaled `kind_unmapped=` (today `size_unmapped` exists, kind does not) |
| **task complexity** | `leadv2-task-judge.sh` → `complexity, duration_class, subsystems_touched, risk_class, estimate_source` | `cost_penalties`, effort, tier | `estimate_source=fallback` (90 % today) → still used, but `inputs=complexity:fallback` and the class-hint→complex shortcut (`task-judge.sh:96-100`) no longer triggers the `complex` penalty row on its own (a fallback `complex` needs `lines>300` **and** class Heavy; see D0.2 — the haiku judge is bypassed on the live path, hypothesis at §9) |
| **throughput** | **absent** — see §4 | `−throughput_score` as the 3rd sort key, weight 0 until `n ≥ 10` per (arm,class) | `inputs=throughput:absent`; never a number |
| **effort** | `effort_rules` (successor of `effort_matrix`) + E | effort on the winning cell; codex tier via penalty rows | complexity unknown → `medium`, `effort_source=default`; `--effort` override journaled |
| **task type** | `--kind` (CLI), judge `work_kind`, flags `--protected/--safety/--ui-judgment` (source `cli`), lane write set / `Writes:` matched against `protected_path_patterns` (source `path`), prose regex (`dispatch-code:7577`) and fallback substrings (`task-judge.sh:109-112`) (source `prose`) | H1 kind; H2 trusted from `cli|path` only; prose/judge_risk → effort high + protected reviewer required at review | no path set and no flag (the previous architect measured 0 of 324 missions carry `Reads:/Writes:`) → `safety:none`; arms are **not** stripped; the review gate matches the *diff paths* against the globs — evidence that exists at review time, unlike prose at dispatch time. Note: `agent/safety/pre-execute.sh` matches none of today's globs (`*safety*gate*` needs "gate"); the tenant list must gain `*/safety/*` |

---

## §4. Throughput — what exists, what does not, and how to measure it without lying

- **No per-arm tokens/min metric exists.** The only timing field in the real journals is
  `model_select_telemetry … spawn_to_terminal_s` — medians sonnet 33 s, codex 30 s, glm-flash 26 s,
  freepool 28 s, glm 24 s, with `terminal=win` at ~30 s. That is **launcher latency**, not work; it
  must not be read as throughput.
- **What can measure it:** phase records already carry `started_at`/`ended_at` per phase
  (`leadv2-phase-record.sh` header schema). `build.yaml` exists in 102+43+24+17+16 leadv2 handoff dirs.
  Whether `ended_at` is populated is **unmeasured** (D0.5). If it is, `median_build_min(arm, class)` is
  derivable today with no new writer. Concurrency is derivable from the dispatch ledger rows
  (`state`, `arm`, `created_epoch` — `_dispatch_row_fields`, `dispatch-code:2939`).
- **Definition proposed:** `throughput_score(c) = completions_per_hour(arm,class) over trailing 14 d`
  with `n`, plus `inflight(provider)`; enters the sort as the *third* key only, and only when
  `n ≥ 10`. Until the reader `leadv2-throughput.sh` (to-create) prints a non-absent row for a cell, the
  arbiter emits `throughput:absent` and the key is 0 for every cell. No steering wheel that turns
  nothing: the input is either measured or visibly absent.

---

## §5. Who wins under which conditions — measured today vs. designed

Live state used for "today": glm 5h 1 % / weekly 13 %; codex probe **unknown (http 401)**; Claude
active max_20x 5h 52 / 7d 49, second account max_5x 5h 54 / 7d 26 (`leadv2-quota-live.sh json`,
2026-09-03 18:1x UTC). "Today" includes the post-pick gates because they, not the sort, decide the
final arm.

| # | condition | today (measured mechanism) | after this design |
|---|---|---|---|
| 1 | glm free + claude loaded, `code/standard`, clean prose, off-peak | arbiter: glm-flash (0.33) wins; gate passes → **glm-flash** | **glm-flash** (cost 0.33, pressure 0) — same, but the line now shows both windows per bucket |
| 2 | same, **peak hours 06–10 UTC** | arbiter picks glm-flash → `glm-quota-gate` refuses `peak_hours` → re-arbiter over remaining → codex-volume if probe ok, else **sonnet** (43 measured after `glm_quota_gate`) | peak is inside the arbiter (`time_windows`): `mode=ban` (today's policy, default) → glm family ineligible, one pick: codex-volume (3+2 unknown) ties sonnet (5) → pressure decides; `mode=multiplier` (founder knob) → flash 0.33·3≈1 still beats codex 3 → **glm-flash** |
| 3 | both free, `code/standard`, off-peak | **glm-flash** | **glm-flash**; `heavy` non-complex → **glm** (flash not sized for heavy) |
| 4 | claude free + **glm at weekly ceiling** (≥ 80) | glm/glm-flash capped (one provider) → freepool floored (+100) → codex-volume (3) or **sonnet** when codex unknown | OVER on glm weekly → ineligible; **codex** (3+2=5) vs sonnet (5) tie → pressure: claude static p≈0.05 vs codex 0.5 → **sonnet**; with rate data on codex → codex. Pressure begins shifting load from glm at ~50–65 % weekly *only if* the rate says the ceiling arrives before reset |
| 5 | **real safety task** (mission on `agent/safety/pre-execute.sh`, prose without "safety gate/publish/payment") | regex misses → not protected → **glm-flash** writes safety code (founder's measured false negative) | `Writes:`/lane write set matches `*/safety/*` (tenant glob to add) → `flag_source=path` → trusted only + `risk` row penalises `volume` → **codex-standard** (4), effort high, protected reviewer at review |
| 6 | prose mentions "publishes" / "payment flow" but touches nothing protected (18 of 19 measured false positives) | `require_trusted` → glm family + freepool stripped (`arm_excluded protected_path` 183/196) → codex-volume or **sonnet** (codex unknown) — this is how Light tasks reached sonnet 49× | prose is advisory: arms kept → **glm-flash**; reviewer rank raised; diff-path check at review is the enforcement |
| 7 | **codex utilisation unknown** (401, live today), protected task, standard | codex `unknown_capped` → excluded → **sonnet** always | codex eligible at 3+2=5, tie with sonnet 5 → pressure; `degraded=quota_codex route_quality=…` on every such line until D0.6 fixes the refresh; after 09-15 the pressured Claude bucket loses the tie → **codex** |
| 8 | **Light** class, clean, off-peak | SIZE_MAP light→standard → glm-flash… but measured Light final arms: sonnet 49, glm-flash 22, freepool 18, codex 9, refuse 8 (rows 6+7 chain) | **glm-flash**, effort low; freepool competes only when its gate is up (unchanged FP-08) |
| 9 | Heavy + `complex` (judge or fallback) | `complex` → +100 on `bulk/background` → glm out → **codex-standard** (4) / sonnet (5); measured heavy: codex 72, sonnet 50, glm 3 | narrowed row → **glm** (1) unless `subsystems_touched ≥ 4` (integration exception → codex-standard/sonnet) or path-protected; effort high; codex reviewer. *Founder decision required*: this reverses today's de-facto "Heavy ≠ GLM" (§2.3, row 1) |
| 10 | **5h window burning, weekly free** (claude 5h 91, 7d 30), review job, codex unknown | util = max = 91 < 95 review ceiling → **sonnet** runs until the 5h wall → lockout → benched for the rest of the window | `five_hour_review_pct=95` → still eligible, but pressure_5h (rate) ≈ high → the **other Claude bucket** (max_5x 5h 54) wins the tie by pressure; codex at +2 also ahead of a bucket at pressure > 0.55 |
| 11 | **weekly burning, 5h free** (claude 7d 96, 5h 10), any Claude-needing job, codex unknown | util = 96 ≥ 95 → capped → with codex unknown → **`all_arms_capped`, exit 4** | OVER on weekly → ineligible for work; review at 95 → OVER too → **last resort** = least-pressured Claude bucket (max_5x 7d 26) with `reason=last_resort_over_ceiling` + founder notification — never `exit 4`; second bucket used by design, not by accident |
| 12 | **all probes dead** (headless session without secrets; 18 real cases) | **refuse, exit 4** | all UNKNOWN → eligible; cheapest capable wins (glm-flash) with `route_quality=guess degraded=quota_glm,quota_codex,quota_claude`; if the lane is protected → sonnet on the pinned bucket, loud |
| 13 | **two Claude buckets after 2026-09-15**: personal (Max 5x) 5h 70 % rising 30 pts/h, work (Max 20x) 5h 40 % rising 5 pts/h, protected task, codex ok at 60 % | arbiter scores the *pinned/active* account only; `profile-select` may still pick the other at spawn — two decisions | cells expand per bucket: sonnet@personal p≈0.9 → 5+8.1; sonnet@work p≈0.1 → 5.1; codex-std 4+0.2 → **codex-standard** (4.2), then sonnet@work; personal bucket last. `bucket=` is handed to the launcher — one decision |
| 14 | `no_capable_cell` (config vocabulary gap, 16 sandbox lines) | `exit 68` → ladder fall-open (correct) | unchanged; `kind_unmapped=` token added so the yaml gap is named |

---

## §6. Work order D0..D7 — each with acceptance and a named negative-control mutation

**D0 — Measure (no code, commands recorded in the deliverable, each re-runnable).**
- D0.1 Refusal census in real journals (done: 20/450; commands in §0.1). Reproduce one all-unknown line by running `leadv2-quota-live.sh json` under `env -i HOME=$HOME PATH=$PATH bash …` and record which secret each provider lacks.
- D0.2 Estimate provenance: why 416/463 estimates are `fallback`. Hypothesis to test: `_dispatch_complexity_estimate` (`dispatch-code:2886-2897`) calls the judge **without** `LEADV2_ROUTER_V2=1`, while the shadow path passes it (`:2855`), and the judge's haiku call is gated on it. Acceptance: the cause named with the judge's line number and one live run yielding `estimate_source=judge`.
- D0.3 Safety classifier census on the real journals: per dispatch, `arm_excluded reason=protected_path` vs. whether the lane's diff (`LANE_START_SHA..HEAD`) touched a `protected_path_patterns` glob. Acceptance: false-positive and false-negative rates with the query.
- D0.4 Peak-hour share of `route_headroom_chosen after=glm_quota_gate` (54) by hour-of-day of the journal line. Acceptance: N peak vs N quota.
- D0.5 `build.yaml` with non-empty `ended_at` across `docs/handoff/dispatch-*/phases.d/`; if ≥ 30, per-arm median build minutes. Decides whether D6 can be seeded from existing data.
- D0.6 Codex probe 401 (`leadv2-quota-read.py` refresh): fix or name the cause. Acceptance: `leadv2-quota-live.sh json` → `codex.status=ok`. Prerequisite for row 7; separate lane.
- D0.7 Profile selector: is it opted in on this machine (`LEADV2_CLAUDE_PROFILE_PROBE` semantics, registry has 2 entries)? Acceptance: recent `claude-profile.log` lines exist or do not, with the reason token.
- D0.8 Phase writers: why 0 `close.yaml` on disk although `phase8-close.sh:285-286` records `close` (§8).
Negative control for D0: each number must reproduce on a second run of its own command; a census whose command is not in the deliverable is not a measurement.

**D1 — Truthful inputs.** Delete `return (100.0, True)` (`arbiter:102`) → `(None, UNKNOWN)`; three states; `unknown_penalty`; last-resort; `inputs=`, `degraded=`, `route_quality=` tokens; dispatcher `elif` at `:7671` retargeted (`all_arms_capped` retired; only `all_arms_operator_excluded` exits 4). Acceptance (`tests/test-route-arbiter.sh` cases): all-unknown → `last_resort`/cheapest, never `refuse`; codex unknown + glm ok → glm-flash with `degraded=quota_codex`. **Mutation:** restore `(100.0, True)` → the all-unknown case emits `arm=refuse` → suite red.

**D2 — Window model.** Per-window ceilings; per-bucket expansion of Claude cells from `quota-live` accounts keyed by `account_key`; pressure with rate from `rate_limit_history` (contract §2.5) and static fallback; `q_*` tokens. Acceptance: fixture claude 5h 92 / 7d 30 → OVER for work, eligible for review; fixture two buckets (5h 80 rising 20/h, 1 h to reset vs 5h 40 flat) → the flat bucket wins the tie. **Mutation:** replace `max(severity·pressure_w)` with `min` → both fixtures red.

**D3 — Decision function + single pick.** `ecost` as §2.2; `time_windows` (peak) inside the arbiter; `bucket=` consumed by the dispatcher and handed to `claude-subsession.sh` via the profile registry (`:440-496`); the post-pick `glm-quota-gate` reroute becomes a *verification* (it must agree; disagreement is journaled `gate_arbiter_disagree` and counted). Acceptance: the §5 table encoded as golden fixtures, one assertion per row (14 rows). **Mutation:** set `p_max=0` → rows 10, 13 red; remove `time_windows` handling → row 2 red.

**D4 — Task-type truth.** `flag_source`; prose regex and fallback substrings demoted to advisory; path match from `LANE_WRITES`/`Writes:`; review gate matches diff paths against the globs and requires a protected reviewer on a hit; plugin default glob list gains `*/safety/*`. Acceptance: the founder's 19 flagged missions re-classified → ≤ 1 protected by prose-only; the real safety mission → protected by path. **Mutation:** delete the diff-path check in the review gate → the "untrusted arm touched `*/safety/*`" fixture passes review → suite red.

**D5 — Effort/tier pair.** `cost_penalties` rows of §2.3; `effort_rules`; `--tier/--effort` become overrides with `--reason`, journaled. Acceptance: complex+heavy+subsystems 5 → codex-standard/top, effort high; trivial/short → glm-flash, effort low. **Mutation:** drop the `complexities` match in `effort_rules` → the trivial fixture resolves `medium` → red.

**D6 — Throughput ledger.** Reader `leadv2-throughput.sh` (to-create) over `phases.d/build.yaml` durations + dispatch-ledger inflight; arbiter reads it, `n ≥ 10` gate, third sort key. Acceptance: reader prints `arm class n median_min`; arbiter emits `throughput:absent` when `n < 10` and the pick is byte-identical to D5. **Mutation:** make the reader return `n=999, median=0` for freepool → a cost-tie fixture (two Claude buckets at equal pressure) must flip order → if it does not, the key is dead → red.

**D7 — Shadow → enforce.** New arbiter runs beside the old for ≥ 50 real dispatches, both lines journaled (`route_shadow=`); a disagreement table is written to this handoff dir; enforce after the founder reads it. Acceptance: ≥ 50 shadow pairs, disagreement report with the per-row reason token. **Mutation:** none — shadow is a measurement; the negative control is that the shadow line count equals the dispatch count (a shadow that runs on 30 of 50 dispatches is not a shadow).

---

## §7. Layers, data flow, migration, risks

**Layers affected:** `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` (decision), `leadv2-dispatch-code.sh`
(descriptor at `:7570-7611`, consumers at `:7612-7680`, `:7737-7751`, `:8050-8059`, `:8367`; bucket →
launcher), `claude-subsession.sh:440-496` (bucket → `CLAUDE_CONFIG_DIR`), `config/leadv2-routing.yaml`
(additive keys), `leadv2-quota-live.sh`/`leadv2-quota-read.py` (all accounts already returned; add
`account_key`), `rate_limit_history` (read-only consumer), review gate (D4), phase-record (D6 reader).

**Data flow (one dispatch):** 1 mission → admission class + judge estimate (source recorded) → 2 lane
flags + path match → 3 `quota-live json` (all buckets) + `rate_limit_history` rates → 4 arbiter: H1..H6
→ ecost → sort → rotation → effort/tier → single line → 5 dispatcher adopts chain, sets bucket/tier/
effort, spawns → 6 gates verify (never re-pick unless the arm dies) → 7 telemetry records final arm +
`route_quality` → 8 review gate checks diff paths (D4) → 9 phase `build.ended_at` feeds D6.

**Migration:** all config keys additive with today's defaults; output tokens appended; descriptor keys
additive; `all_arms_capped` retired only together with the dispatcher `elif` (same commit); shadow before
enforce; tenant yaml (`persona-engine/.claude/ref/leadv2-routing.yaml`) untouched except the recommended
`*/safety/*` glob.

**Risks and mitigations:**

| risk | mitigation |
|---|---|
| **Two sources for the same ceilings** — arbiter reads `router_v2.quota_ceilings` (yaml), gates read `config/leadv2-quota-ceilings.sh` (`glm-quota-gate:38`, `provider-quota-gate:8`). Today both say 80/90/90/95/95/95, tomorrow they drift. *CRITICAL config contradiction (checklist item 5).* | one source: the `.sh` reads the yaml (or is generated from it) in D2; a test asserts equality |
| e2e-gate sandbox: with H5 the nested dispatch no longer refuses — it could spawn a real `sonnet` | the sandbox already uses fake arm names (`trusted-arm/free-arm/cheap-arm` chains in the picks census); D1 adds `LEADV2_ROUTE_ARBITER_LAST_RESORT=off` for the harness and a test that the harness never reaches a real launcher |
| pinned `active_account: max_20x` (`routing.yaml:10`) is a tier label; after 09-15 the personal account is Max 5x | buckets keyed by `account_key`; the label is display-only |
| anti-sticky state file (`/tmp/leadv2-route-arbiter-last-arm`) is machine-global; bucket expansion changes what "same arm" means | key rotation on `arm+bucket`; the file already writes atomically (`:254-266`) |
| `rate_limit_history` reader vs. probe writer | reader `-readonly`, single indexed SELECT; SQLite WAL; no arbiter write path |
| the peak rule moves from a gate into the arbiter — if both run, they may disagree | D3 makes the gate a verifier with a counted disagreement token; the gate's cooldown record stays as the safety net |
| review-time enforcement of "protected code by trusted arm" (D4) is a **policy change** | needs founder approval; fallback keeps prose stripping but only for `safety[_-]?gate|publish` as *word* tokens on `Writes:` lines, not free prose |

**Constraint checklist:** env vars introduced are `LEADV2_ROUTE_ARBITER_LAST_RESORT`, `LEADV2_THROUGHPUT_BIN`
(both `LEADV2_*`, none in `.claude/settings.json` today — nothing to contradict); no `claude -p`
invocations introduced; concurrent files: `rate_limit_history` (probe writes / arbiter reads, above),
arbiter state file (already atomic), `phases.d/build.yaml` (phase-record is the sole writer, D6 reader
only); paths: every path cited above exists on disk except `leadv2-throughput.sh` (to-create) and the
config keys (to-create in the yaml).

**Out of scope for the implementing agent:** the bandit and `route-outcomes.jsonl` (SELECTOR-DESIGN §3
says kill it — not this lane), ARM-CAPABILITY-FROM-OUTCOMES-01, the ladder's order and the freepool
floor semantics, the review-pool resolver (`leadv2-glm-policy-resolve.py`), the Codex 401 root cause
(D0.6 is a prerequisite lane), the phase-pipeline gaps of §8 (measurement only here), tenant yaml edits
beyond the one glob.

---

## §8. "Do tasks go through phases?" — measured answer

Declared phases (`leadv2-phase-record.sh` header): `plan, gate1, build, review, deploy, close, test,
live_verify`; also observed on disk: `classify, diverge, e2e`. Writers found: `leadv2-dispatch-code.sh`
records `build` (3 sites), `classify` (1), `plan` (1); `leadv2-gate1-prompt.sh:166` → `gate1`;
`leadv2-dispatch-product-close.sh:2733/2887/2963/3482` → `e2e`, `review`; `leadv2-phase8-close.sh:285-286`
→ `close`; `diverge` writer not located within budget (it is on disk, so one exists).

On disk, leadv2 (`docs/handoff/dispatch-*/phases.d`, 814 dirs):

| phase set | dirs |
|---|---|
| *(no phases.d at all)* | 508 (includes `-review` sub-dispatch dirs, e2e fixtures, task-id-named dirs — lane vs non-lane split not measured) |
| build+classify | 102 |
| build+classify+e2e | 43 |
| e2e+review | 39 (the `dispatch-<X>-review` dirs: a lane's review is recorded in a *separate* dir, never in its own) |
| build+classify+diverge+e2e+gate1+plan | 24 |
| classify only | 20 |
| build+classify+e2e+gate1+plan | 17 |
| build+classify+diverge+gate1+plan | 16 |

persona-engine (23 dirs): build+classify 11; plan+gate1 4; diverge+gate1+plan 3; full with review 1; empty 3;
`dispatch-dispatch-7a8f236f` gate1 only (a doubled prefix — a naming bug, unmeasured further).

**Never observed in any of the 837 dirs: `deploy`, `close`, `test`, `live_verify` — 0 records each,
although `close` has a live writer in `phase8-close.sh` (D0.8).** `review` appears in 1/23 lane dirs in
persona-engine and only in sibling `-review` dirs in leadv2.

So: lines go through phases **partially and by class**. Light admission → `route: dispatch` → only
`classify → build (→ e2e)` (e.g. `dispatch-395cf9b2`: Light, `source: fallback`, phases build+classify+e2e);
Standard+ → `plan → gate1 (→ diverge) → build`. Review is recorded elsewhere; deploy/close/test/
live_verify are declared and silently never recorded. That last gap is the "lying-green" shape: a phase
that is asserted (`--status done` calls exist in code) but has never left a record on disk.

---

## §9. What I do not know (named, not estimated)

1. Which `kind` strings the Codex probe exposes for its windows (`five_hour`/`weekly`?) — the probe is
   401 today; the arbiter code selects `kind == binding_window` (`:106`). Row 7 assumes both windows exist.
2. Whether the haiku judge is gated off on the live path (D0.2 hypothesis: `LEADV2_ROUTER_V2` not passed at
   `dispatch-code:2897`). 416/463 fallback is measured; the cause is not.
3. Whether `build.yaml.ended_at` is populated (D0.5). If not, D6 needs a writer and starts from zero.
4. Whether the founder accepts moving "protected code only by a trusted arm" from dispatch-time prose to
   review-time diff paths (D4). Without that approval, rows 6 and 8 keep sending Light tasks to sonnet.
5. Whether `leadv2-claude-profile-select.sh` is opted in on this machine (registry has 2 entries; the
   opt-in env semantics are unverified — D0.7). Row 13 "today" may therefore be one decision or two.
6. The ladder's own spawn distribution: the coordinator's `worker_spawned` counts (codex 142, glm 85,
   sonnet 45, kimi 6…) come from `docs/handoff` and include sandbox lines (kimi was retired 2026-08-05,
   so `kimi 6` cannot be recent real work); my real-journal grep found no `worker_spawned` token at all.
   The closest real proxy is `model_select_telemetry terminal=win` (§0.3), which records the *final* arm.
7. The two real refusals with numeric glm/codex and unknown claude — which task class and flags they
   carried (not decoded).
8. Which window the codex quota gate reads (`lib/leadv2-codex-quota-gate.sh` not read).
9. `router_v2` shadow scorer (`leadv2-router-v2.py`, `headroom_weights`, `usable_now`) — off on the live
   path (`LEADV2_ROUTER_V2` unset); not read; may contain reusable window math.
10. How many of the 508 phase-less handoff dirs are lanes that ran a build and recorded nothing.

DELIVERABLE_COMPLETE

---

## §10. Founder decisions — answered 2026-09-03, binding

The three rows §5.2, §5.9 and D4 were escalated with variants. The founder's answers:

| # | question | decision | consequence for the design |
|---|---|---|---|
| §5.2 | GLM during peak hours 06–10 UTC: ban (today) or multiplier | **keep the ban** | `time_windows` implements `mode=ban` only; the multiplier branch is NOT built. GLM family stays ineligible in peak and that load stays on Claude/Codex by choice, not by accident. Do not reopen this as an optimisation. |
| §5.9 | Heavy + complex: reverse the de-facto "Heavy ≠ GLM" | **allow, with exceptions** | Heavy routes to `glm` (cost 1) unless `subsystems_touched >= 4` (integration exception → codex-standard/sonnet) or the lane's write set matches a protected path. Effort high, codex reviewer. This is the single biggest volume shift off Claude. |
| D4 | what makes a task "protected": prose regex or write paths | **write paths** | `flag_source=path` from `LANE_WRITES`/`Writes:`; prose demoted to advisory; plugin default globs gain `*/safety/*`; the review gate matches diff paths and requires a protected reviewer on a hit. The 18-of-19 false positives stop reaching sonnet; the real `agent/safety/pre-execute.sh` mission becomes protected. |

Acceptance for §5.9 is not "glm appears in a decision line" — it is the pair: a Heavy
non-integration mission resolves to `glm`, and a Heavy mission touching four subsystems or a
protected path does NOT. Both fixtures, or the row is not closed.
