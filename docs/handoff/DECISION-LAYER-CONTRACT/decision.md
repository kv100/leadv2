# Decision-layer contract — one system, one picture

Row `3e1e978c7189` · decision task · 2026-09-12 · author: lane worker (glm-5.3) · status: proposed (review round = read #2, §5)

Founder order, 2026-09-12: make the arbiter, balancer, estimator and dispatcher one
system, as smart as possible. An LLM call to decide and a slower decision are both
explicitly authorised. What stays forbidden is a decision made on a number nobody
measured. This document is the contract those four layers implement against; it
changes no behaviour by itself.

## 0. The four layers and their stores, as they are today

| layer | embodiment | decision it owns |
|---|---|---|
| Arbiter | `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` (2045 ln) | which ARM runs the work (typed stage list, :1087) |
| Balancer | `plugins/leadv2/scripts/leadv2-claude-profile-select.sh` (810 ln) + account ranking | which ACCOUNT (keychain slot) serves a claude arm |
| Estimator | `leadv2-cost-estimate.sh` (USD cap, NOT a routing input, dispatch-code.sh:3480-3483) + the arbiter's own spend forecast (:735-849) | "does the next task fit what is left" |
| Dispatcher | `leadv2-dispatch-code.sh` (10849 ln) | admission: phase guard, lane cap, descriptor build, cost-estimate write, terminal recording |

Stores underneath: quota cache `~/.claude/state/leadv2/quota-cache/*.json`
(writer `leadv2-quota-read.py`, served by `leadv2-quota-live.sh` / daemon snapshot);
phase state `docs/handoff/dispatch-<sig>/phases.d/*.yaml` (writer
`leadv2-phase-record.sh`); events journal `~/.claude/cache/leadv2-events/<repo>.jsonl`
(writer `leadv2-event.sh`, readers: failure memory, spend forecast, cost actuals —
"one journal, one rule", arbiter :788-826 and lib/leadv2-cost-actuals.sh:28-31);
lane liveness `docs/leadv2/active.yaml` (writer active-registry/dispatcher).

Landed-state correction to the brief: row `4c06462a1a71` (cost actual) is ALREADY
MERGED at `8e4152ae` ("feat(arbiter): learn what work costs") — write half
`lib/leadv2-cost-actuals.sh`, read half arbiter :1629-1690. The census below
describes the tree AFTER that merge. Proof: `git -C ~/Projects/leadv2 log --oneline
-1 -- plugins/leadv2/scripts/lib/leadv2-cost-actuals.sh` → `8e4152ae`.

Method: direct code reads at the cited lines plus live probes; read #2 is this
lane's review round (discipline rule: no self-spawned write-role second opinion).
Every load-bearing "written but unread" claim was re-derived by falsification
greps (§1 footnotes).

## 1. Part 1 — Census: every fact the decision layer consumes

Format: fact · written by · read by · who needs it but cannot see it (consequence).

| # | fact | written by | read by | needs it, cannot see it |
|---|---|---|---|---|
| 1 | glm `five_hour`/`weekly` pct; codex `windows[]` (primary/secondary `used_percent` + `limit_reached`); anthropic per-account `five_hour`/`seven_day` pct | `leadv2-quota-read.py` :337-413 (glm), :487-556 (codex), :809-927 (anthropic), cached :115 | arbiter `util()` :624-727 (binding = worst readable window, :697-700); profile-select probe_outcome :640-668; glm-policy-resolve | — (this one is healthy) |
| 2 | **model-scoped windows**: anthropic `limits[]` rows incl. `kind=weekly_scoped scope.model.display_name=Fable percent=1 resets_at=…` — value, reset AND scope all present | `leadv2-quota-read.py:889` — RAW passthrough `"limits": u.get("limits")`, no parsing | **nobody**. Falsified twice: `grep -rn weekly_scoped plugins/leadv2 --include=*.sh --include=*.py` → only a comment (glm-policy-resolve.py:103, which itself calls bucket identity UNVERIFIED) and a test; `grep -n "limits\|scoped" lib/leadv2-route-arbiter.sh` → zero data-plane hits | arbiter `util()` :682-684 prices claude from `five_hour`/`seven_day` ONLY — fable's own weekly window is invisible in both the pct (:682) and the forecast `_allwin` (:714-720). Same gap for glm per-model `models{}` (written :399, read by the glm policy resolver only, never by the arbiter). Consequence (row 0485): the number the arbiter prices from is not the binding constraint; whichever direction the scoped window leans on a given day, the decision is made on a different meter than the provider enforces |
| 3 | account identity: which keychain slot is `active`, per-account `status`/`account_state` | `resolve_active_account` quota-read.py:776; `classify_account_state` :660-692 (401+team/max→`unmetered`, 401+pro→`unknown`, 200→`ok`); normalize_payload re-pins :989-997 | arbiter :666-681 (active-but-not-ok falls back to any ok account, same label first; all-unmetered → pct=100 `priced_from=configured_allowance_conservative` :677-680) | — |
| 4 | **failure semantics for one probe failure**: quota side caches `status!=ok` for `FAIL_TTL=20s` (quota-read.py:78, applied :105-107 — "retry soon"); profile side writes `probe-cooldown-until` for `COOLDOWN_S=900` (profile-select.sh:138, write :673-687 on `verdict` = 401/403/expired/revoked/malformed/invalid/unauthorized/forbidden :662-666) | quota-read.py cache; profile-select.sh :673 (also account-switch.sh:333) | quota cache TTL: quota-read itself. Cooldown: **only profile-select :548-574** (falsified: `grep -rn probe-cooldown-until scripts/ hooks/` → no other consumer) | the arbiter and dispatcher never see the 900s cooldown: for the SAME 401, the quota layer concludes "unmetered — price conservatively, keep the account a candidate" (:677-680) while the balancer concludes "credential dead — do not touch this account for 15 minutes" (:674). One event, two verdicts, two TTLs, zero cross-reads (row bd7f). Precise divergence from the brief recorded in §5 |
| 5 | **spend forecast basis**: p75 (`FORECAST_QUANTILE=0.75`, :779) of `worker_spawned`→`worker_terminal` WALL CLOCK per provider | derived in-arbiter from the events journal, :788-849 | the fit check `_forecast_check` :853-884 (forecast vs every readable window's remainder) | the estimator's own comment admits the proxy (:750-754): wall clock includes idle and abandoned lanes; token telemetry (cost-flush) exists but is claude-stream-only, "not comparable provider-quota actuals for GLM and Codex". Consequence: the number named "expected spend" measures lane-open time, and a provider whose lanes are abandoned-long looks expensive; one whose lanes close fast looks cheap regardless of tokens burned |
| 6 | cost ESTIMATE (USD cap) | dispatch `_dispatch_record_cost_estimate` :3484-3499, `phase=pre_arm_selection`, `--main-model sonnet` HARDCODED :3491; computed by `leadv2-cost-estimate.sh` from LEAD_V2_STATE.md class + prior-art.yaml + phase-token table | `phase-advance.sh:36-76` (class_cap_usd gate), backlog-pump :711-714 (admission class), dispatch re-entry :5030-5035. Explicitly NOT a routing input (:3480-3483) | — |
| 7 | cost ACTUAL (rounds, wall_s, arm, tokens) | **landed 2026-09-12**: `leadv2_cost_actual_record` lib/leadv2-cost-actuals.sh, hooked at dispatch terminal :2323-2325; one `kind=cost_actual` row in the SAME events journal | arbiter `read_cost_actuals` :1655-1690, gate `LEADV2_ARBITER_OBSERVED_COST` :1654, `no_history` named loudly when empty | tokens are `-` for glm/codex (cost-actuals.sh:36-38: no per-task token telemetry today) — the actual is rounds+wall, an approximation of spend, and the forecast (:5) has NOT been switched onto it |
| 8 | complexity / duration_class / class | `leadv2-task-judge.sh` (LLM judge) called on every dispatch :3411-3478; degrade `arbiter_uses_size_only` :3457; `complexity_source` provenance key rides out :3465-3472 | descriptor keys consumed at arbiter :990-995 (absent → `unknown`, conf 0.0), size/task_class :507, protected/safety :517-518 | — |
| 9 | **phase state**: `phases.d/<phase>.yaml` | `leadv2-phase-record.sh`; dispatch stamps `classify` UNCONDITIONALLY immediately before the guard (:5287-5291) | the phase guard at DISPATCH time only, scope=pre-build :5312-5331: bootstrap admit when phases.d holds nothing but `classify` (:5306-5329, one-shot by definition but time-unbounded) | nothing AFTER dispatch re-checks the prefix: a lane admitted in bootstrap can record `build` with `plan`/`gate1` never written (row f37f — two lanes measured). Consumers of "build happened" (review, close) trust the phase name without the prefix |
| 10 | **lane liveness**: live lanes, per-lead-session count, per-arm in-flight | active-registry library + dispatcher writes `docs/leadv2/active.yaml`; cap enforced `lead_session_lane_cap` (2) :9163-9169; cap sources: override file > active.yaml meta > `LEADV2_LANE_CAP` (memory, three-source rule) | dispatcher admission; lead status surfaces | **the arbiter has zero lane awareness** — falsified: `grep -c "active.yaml\|in_flight\|lane_load" lib/leadv2-route-arbiter.sh` → `0`. Consequence: arm selection cannot see that glm already holds 4 live lanes and opus holds 0; load balancing across arms is a side effect of price, not a fact |
| 11 | arm failure memory | events journal `worker_spawned`/`arm_refused` rows + failure ledger terminal rows | `read_failure_memory` :1193-1266: allow-list `arm_failure_causes` from routing.yaml :1182-1190; unmapped deaths NAMED not silently zero (:1231-1247); open-spawn reported as open, never as death (:1252-1264); unreadable journal = `unavailable`, never zero (:1196) | — (healthy; the vocabulary drift is named in-code) |
| 12 | quota cache freshness | `fetched_at` stamped by the reader; TTL judged on payload age, not mtime (:84-109) | cache_get | — |
| 13 | **what silence means** (the unmeasurable, today) | three independent decodings coexist: (a) unreadable window → skipped, `unknown` + pct=100 + penalty (:643, :713); (b) unmetered account → pct=100 `priced_from=configured_allowance_conservative` (:677-680); (c) cooldown-file present → skip probing entirely (:552-574); plus journal-unreadable → `unavailable` (:1196) | each consumer picks its own decoding | the same absent number means "throttled meter", "dead credential" or "never measured" depending on which layer you ask — and on 2026-09-12 those three produced opposite behaviours on the same day (rows bd7f + 3e55) |

Live evidence (probe run 2026-09-12, cache `fetched_at=2026-09-12T12:50:36Z`):

```
$ python3 - <<'EOF'   # anthropic.json accounts summary
- label=max_20x active=True  status=unknown state=unknown fh=None sd=None limits_kinds=[]
- label=max_5x  active=False status=unknown state=unknown fh=None sd=None limits_kinds=[]
- label=max_20x active=False status=ok     state=ok     fh=7.0 sd=3.0 limits_kinds=['session','weekly_all','weekly_scoped(Fable)']
EOF
```

The active-flagged entry is the broken one (the :651-665 fallback case, live); the
ok entry carries the scoped window the arbiter never parses. Full scoped row:

```
{"kind":"weekly_scoped","group":"weekly","percent":1,"severity":"normal",
 "resets_at":"2026-09-18T22:00:00Z","scope":{"model":{"display_name":"Fable"}}}
```

Value, reset and scope are ALL present in the cache today. The missing piece is a
reader, not a producer — the implementing row is a parser + a kind→window-name
mapping decision, not new instrumentation.

## 2. Part 2 — The contract

Each clause: layer · fact · failure mode it closes. `CONTRACT:` lines are the
checkable surface for the four implementing rows.

CONTRACT: QUOTA-WINDOWS — the quota layer (leadv2-quota-read.py) MUST publish
  EVERY window the provider meters, including model-scoped ones, as
  `{kind, scope, pct, resets_at, measured_at}`; the arbiter MUST price an arm by
  the worst of ALL windows applicable to the arm's model(s) — an arm mapped to a
  scoped window (fable→weekly_scoped) is priced by max(aggregate, scoped), never
  by the aggregate alone. Closes: a decision made on a meter the provider does
  not enforce (row 0485). The kind→window-name mapping (session↔five_hour,
  weekly_all↔seven_day, weekly_scoped↔own) MUST be declared in one place, not
  inferred per reader.
CONTRACT: FACT-SHAPE — every published fact carries
  `{value?, status, measured_at, writer}` with
  `status ∈ {live, stale(age>TTL), failed(reason), never_measured}` and
  `reason ∈ {throttle, auth, network, parse}`. A missing value is a STATUS,
  never a number. Closes: silence decoding as zero (census #13).
CONTRACT: SILENCE-DECODING — consumers MUST decode by status and reason:
  `failed(throttle)` = meter says throttled → consume headroom pessimistically,
  keep candidate; `failed(auth)` = credential-level verdict → quarantine via the
  single failure store, do NOT price; `never_measured` = price at the declared
  conservative default AND emit a probe request; `stale` = usable for ranking,
  not for fit. No layer may invent its own decoding for the same status.
  Closes: one event → two opposite verdicts (row bd7f).
CONTRACT: SINGLE-FAILURE-STORE — failure memory (cooldowns, quarantines,
  bans) has exactly ONE writer per failure class and one TTL per class, chosen
  by class semantics (auth-failure TTL ≠ throttle TTL), and every consumer
  (arbiter, balancer, dispatcher) reads THAT store. A layer writing a private
  cooldown variant is a defect even if its local logic is correct. Closes:
  FAIL_TTL=20 vs COOLDOWN_S=900 on one 401 (row bd7f); the cooldown-invalidation
  sidecar discipline (profile-select :553-574) moves with it.
CONTRACT: PER-ACCOUNT-BY-DEFAULT — account-level quota facts are recorded for
  EVERY configured account on every probe, regardless of
  `LEADV2_CLAUDE_MULTIPROFILE`; the opt-out flag may gate account SWITCHING,
  never account MEASUREMENT. Blending accounts into one reading is a derivation
  the arbiter may request, not a storage decision. Closes: breaker blending
  accounts by default (row 3e55).
CONTRACT: ESTIMATE-LIFECYCLE — a cost estimate is provisional and MUST be
  paired with an actual at terminal state in the same journal (shape landed in
  8e4152ae); the estimator MUST expose estimate-vs-actual calibration, and any
  forecast used for the fit decision MUST carry a `basis` that names what it
  measured. A forecast derived from lane wall-clock MUST carry
  `basis=proxy:wall_clock` and MUST be replaced by metered spend per provider as
  soon as such a meter exists; a proxy wearing a measurement's name is a defect
  (census #5). Closes: matrix price as the entire answer forever (row 4c06,
  write half landed).
CONTRACT: PHASE-PREFIX — phase state is a monotone prefix; EVERY consumer of a
  phase ≥ build (dispatch, review admission, close) MUST verify the full
  mandatory prefix for the class, not just presence of the latest phase. The
  bootstrap grace is one-shot AND time-bounded (a lane in bootstrap past N
  minutes is a named anomaly, not a standing bypass). Closes: build recorded
  with neither plan nor gate1 (row f37f).
CONTRACT: LANE-LOAD-VISIBILITY — the dispatcher/active-registry MUST publish
  per-arm in-flight lane counts where the arbiter reads quota, and the arbiter
  MUST treat an arm at in-flight saturation as a named stage (`lane_load`),
  ranked but not necessarily excluded. Closes: load balancing as an unmeasured
  side effect of price (census #10).
CONTRACT: DESCRIPTOR-PROVENANCE — every descriptor key the arbiter consumes
  (complexity, complexity_source, duration_class, expected_hours, protected)
  names its producer; a degraded estimate MUST arrive as `source=degraded`, and
  the arbiter MUST print which inputs were degraded on the decision line.
  Closes: `arbiter_uses_size_only` being invisible downstream (dispatch :3457).
CONTRACT: ESTIMATE-INPUT-TRUTH — the pre-arm USD estimate MUST be recorded
  with the model actually resolved by the arbiter (or the resolution marked
  `pre_selection`), never a hardcoded `--main-model sonnet` (dispatch :3491).
  Closes: estimate/actual pairs that compare different models' prices.
CONTRACT: DECISION-QUALITY-FLOOR — cheapness of the decision is not a
  constraint (founder, 2026-09-12): the arbiter MAY spend an LLM call and MAY
  decide slower. What it may NOT do is decide on an unmeasured number: every
  ranking input is either a published fact (per FACT-SHAPE) or a named
  conservative default. A cheaper decision built on a fabricated or absent
  number violates this contract even when it picks the "right" arm.
CONTRACT: ONE-JOURNAL — cross-layer facts live in the events journal under one
  attribution rule (last spawn wins, arbiter :788-826, cost-actuals.sh:28-31).
  No layer adds a second store for a fact the journal already carries; two
  writers for one number drift (cost-actuals.sh header, paid for already).

## 3. Part 3 — Sequencing of the five rows

Write sets derived from the code regions each row must touch (not from titles):

| row | files · regions (verified line spans) | landed state |
|---|---|---|
| bd7f (failure semantics) | quota-read.py :78, :105-107 (FAIL_TTL) + :660-692 (classify_account_state); profile-select.sh :138, :548-574, :640-687 (cooldown read/write); arbiter :624-681 IF the cooldown becomes an arbiter input | open |
| 4c06 (cost actual) | lib/leadv2-cost-actuals.sh + dispatch :2323-2325 + arbiter :1629-1690 | **merged 8e4152ae** |
| f37f (phase guard) | dispatch-code.sh :5286-5375 (guard + bootstrap admit) + phase-record.sh (_verify_artifact); possibly review/close admission points | open |
| 0485 (scoped windows) | quota-read.py :889 region (parse limits[] → account windows) + arbiter :645-684 (windows dict, both pct and _allwin) | open |
| 3e55 (per-account default) | profile-select.sh :221 (opt-in gate) + claude-subsession.sh :504 + quota-read.py account enumeration :809-927 | open |

Verdict:

- **f37f runs parallel with everything.** Its write set (dispatch guard region
  :5286-5375, phase-record) is disjoint from every other row's regions; the only
  shared file is dispatch-code.sh, where the other rows touch :2323/:3484-3499 —
  >1000 lines away, no logical coupling.
- **{bd7f, 0485, 3e55} serialise among themselves, in that order.** All three
  edit the same seam — "what one anthropic account reading IS": bd7f defines the
  failure/status vocabulary of an account probe (the FACT-SHAPE statuses the
  other two consume); 0485 extends the account reading with scoped windows
  (same `windows` construction at arbiter :645-684 the bd7f fallback branch
  :666-681 also edits, and the same quota-read anthropic block); 3e55 changes
  which accounts get probed at all (profile-select :221 + quota-read :809-927 —
  the same enumeration 0485's parser iterates). Running any two concurrently
  produces merge conflicts with semantic content, not just textual.
- **4c06 is done** — its remaining obligation under this contract is
  ESTIMATE-LIFECYCLE's calibration half (estimate-vs-actual exposure), a small
  follow-up on already-landed code, parallel-safe.
- Recommended order: this contract lands first (it is the shared vocabulary);
  then bd7f (statuses), then 0485 (windows), then 3e55 (default); f37f and the
  4c06 follow-up any time. Estimated serialization cost: one lane at a time
  through the account seam, ~3 lanes total.

## 4. Not measured / what would have to exist first

- Per-provider metered spend for glm/codex (tokens per task) does not exist
  (cost-actuals.sh:36-38). Until it does, the fit forecast must keep its
  `basis=proxy:wall_clock` label — that is a named limit, not a defect to hide.
- `limits[].is_active` semantics (session=true, weekly=false observed) is
  UNVERIFIED: no doc, no consumer. The 0485 parser must either determine its
  meaning from provider behaviour or ignore it explicitly in the mapping table.
- Whether a bare 429 ever reaches profile-select's verdict list (see §5) — not
  measured; the probe that would answer it is a live 429 against the usage
  endpoint, which we deliberately do not synthesize (live-write discipline).

## 5. Disagreements (recorded, not averaged)

1. **Brief vs code — "the same 429".** The brief says profile-select "~:590
   reads the same 429 as confirmed_live_failure". Current code
   (profile-select.sh:640-668, mtime 2026-09-12 15:33) classifies `verdict`
   (→900s cooldown) ONLY on 401/403/expired/revoked/malformed/invalid/
   unauthorized/forbidden; a bare 429 prints `-` (unmeasurable) and does NOT
   cool down. The split-brain is real for 401/403-class failures; for 429
   specifically the balancer today concludes nothing. Implementing bd7f against
   the brief's wording without re-checking this list would build the wrong
   unification.
2. **Brief vs tree — 4c06 already merged** (8e4152ae). The brief's "no actual is
   ever recorded" was true at row-filing time; the census must start from the
   merged state or the sequencing answer is wrong (it changes one row from
   "implement" to "verify + follow-up").
3. **p90 vs p75.** The brief names p90 of spawn→terminal; the code says
   `FORECAST_QUANTILE=0.75` (arbiter :779). Same proxy, different number — the
   contract clause (ESTIMATE-LIFECYCLE) is unaffected, the citation matters.

## 6. Self-check

- Acceptance: `[ -f ~/Projects/leadv2/docs/handoff/DECISION-LAYER-CONTRACT/decision.md ]`
  and `grep -qE "^CONTRACT:" <file>` — run post-commit, output below.
- No shell/python file was changed by this lane → `bash -n` / `py_compile`
  vacuously green; no test suite applies (read-only task, no core-flow touch →
  no mutation-suite obligation). Changed-scope runner selects nothing for a
  docs-only commit in leadv2.
