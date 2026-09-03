# QUOTA-GATE-PARITY-01 — architect prepass (mechanism-closed design)

Repo: `~/Projects/leadv2` @ base 2eaea77. Role: architect prepass. No code written.

---

## §0. Where the mission's framing is wrong (design against the code, not the brief)

The mission says: *"declared quota_ceilings … are enforced ONLY for GLM (`leadv2-glm-quota-gate.sh`)"* and
*"a dead Codex silently yields status=unreviewed (all_arms_unavailable)"*. Both are false as written. The tree
says something narrower and more actionable:

| Surface | Claimed | Actual (verified in tree) |
|---|---|---|
| GLM **build** | gated | gated — `leadv2-glm-quota-gate.sh:39` `THRESHOLD="${GLM_QUOTA_THRESHOLD:-80}"`, trips on EITHER window |
| GLM **review** | ungated | **gated at 90** — `lib/leadv2-glm-policy-resolve.py:75` `DEFAULT_GLM_REVIEW_THRESHOLD_PCT = 90.0`, applied in `resolve_review_pool` (`:537`, `:589`) |
| Codex **review** | ungated | **gated at 95** — same resolver, `:54` `DEFAULT_REVIEW_THRESHOLD_PCT = 95.0`; live read via `live_codex_weekly_pct` (`:314`); `--quota-live` defaults to the real `leadv2-quota-live.sh` (`:1041-1043`), so this runs in prod |
| Claude **review** | ungated | **gated at 95** — `:76` `DEFAULT_ANTHROPIC_REVIEW_THRESHOLD_PCT = 95.0` |
| Codex **build** | ungated | **gate exists but is a no-op in this repo, and is bypassed entirely on one of the two spawn paths** — see below |
| Claude **build** | ungated | **genuinely ungated. No reader, no caller.** |

### The two real holes (this is what let Codex reach 100%)

**Hole 1 — the codex build threshold is config-conditional, and this repo has no config.**
`codex-task.sh:325 _codex_quota_gate` reads its threshold from `_codex_quota_thresholds` (`:154`), which reads
`codex_quota_gate.build_threshold_pct` out of the routing yaml resolved by `_codex_quota_routing_yaml` (`:134`)
= `<repo_root>/.claude/ref/leadv2-routing.yaml`. In `~/Projects/leadv2` that file exists (2687 bytes,
hand-written 2026-08-15) and contains **no `codex_quota_gate:` block and no `glm_policy:` block** — verified:
`grep -n codex_quota_gate .claude/ref/leadv2-routing.yaml` → no match. `_codex_quota_thresholds` returns empty,
and `_codex_quota_gate:346` does `[[ -z "$_threshold" ]] && return 0`. **The codex build threshold check is
silently skipped in the leadv2 repo.** The `codex_quota_gate:`/`glm_policy:` blocks live only in
`plugins/leadv2/config/leadv2-routing.yaml:181`, which is the *canonical registry*, not the path this resolver
reads.

**Hole 2 — the second codex spawn path never had a threshold check at all.**
`leadv2-codex-session-runner.sh:502` calls `codex_spawn_gate exec`. `lib/leadv2-codex-quota-gate.sh:29`
implements exactly two checks — arm-cooldown memory and the circuit breaker — and its own header says so:
*"The threshold check (routing-yaml + live quota reader) is NOT in this lib; it lives in codex-task.sh's
`_codex_quota_gate`."* The session runner bypasses `codex-task.sh` entirely. **Every `codex exec` through the
session runner is unthresholded regardless of config.**

Net: the correct statement of gap #3 is not "write a codex gate" — it is "make the codex gate unconditional and
put it on **both** spawn paths", plus "give claude a build-side reader at all". That is a smaller, sharper diff
than the mission implies, and it is the diff that actually explains the 100%/0-remaining observation.

### Where the numbers live today (three sources, currently in agreement except one)

| Ceiling | `router_v2.quota_ceilings` (declared) | Enforcing code | Agree? |
|---|---|---|---|
| glm work | 80 | `leadv2-glm-quota-gate.sh:39` default 80 | yes |
| glm review | 90 | resolver `:75` 90.0 | yes |
| codex work | 90 | resolver `:53` `DEFAULT_BUILD_THRESHOLD_PCT = 80.0` | **NO — 80 vs 90** |
| codex review | 95 | resolver `:54` 95.0 | yes |
| claude work | 95 | *(none)* | n/a |
| claude review | 95 | resolver `:76` 95.0 | yes |

The codex-work divergence is *stricter* than declared, so it is not a safety hole. Per the mission's "do NOT
change the values", this lane **does not touch 80.0 → 90.0**. It records the divergence in the new config file
and adds a drift test (§2, T7) so the next person sees it rather than rediscovering it.

---

## §1. CALLERS / CALLEES

### 1.1 `leadv2-glm-quota-gate.sh`
- **Callees:** `lib/leadv2-arm-cooldown.sh` (`arm_cooldown_record`, `arm_cooldown_ladder_note`,
  `_arm_cooldown_epoch_iso`); `leadv2-quota-live.sh glm` (`:38` `LIVE=`).
- **Callers:** invoked as a standalone binary by the dispatcher/launcher via the
  `LEADV2_DISPATCH_REFUSED: quota_gate` + rc contract (rc 0 allow / 1 quota reroute / 2 peak refusal).
- **Change here:** one line — `THRESHOLD` default is sourced from the new ceilings file instead of the literal
  `80`. Value unchanged. rc contract untouched (peak-hours rc 2 stays GLM-only and stays in this file).

### 1.2 `lib/leadv2-codex-quota-gate.sh :: codex_spawn_gate`
- **Callers — two, on different paths, and this is the miss the mission did not name:**
  1. `plugins/leadv2/scripts/codex-task.sh:334` — inside `_codex_quota_gate`, `codex_spawn_gate "$SUB" || exit "$?"`.
     Followed by the yaml-threshold check at `:337-352` (no-op in this repo, Hole 1).
  2. `plugins/leadv2/scripts/leadv2-codex-session-runner.sh:502` — `codex_spawn_gate exec`, and **nothing else**.
     No yaml read, no live-quota read (Hole 2).
- **Callees:** `arm_cooldown_state` (lib/leadv2-arm-cooldown.sh), `codex_circuit_state`
  (lib/leadv2-codex-circuit.sh). Both sourced idempotently at `:20-24`.
- **Change here:** add check 3 — call the new generic gate for provider `codex`, purpose derived from `$1`
  (`review|adversarial-review|review-bg` → `review`, everything else incl. `exec` → `build`). `codex_spawn_gate`
  currently does `shift || true` and discards `$1`; it must capture it first. Returning **2** (not 1) preserves
  both callers' contract (`codex-task.sh` does `|| exit "$?"` and the router maps 2 → next candidate;
  `leadv2-codex-session-runner.sh:503-505` treats any non-zero as refuse-and-exit-2).

### 1.3 `leadv2-burn-governor.sh`
- **Callers — exactly one:** `leadv2-dispatch-code.sh:4782 _burn_gate` → `:1425`
  `bash "${BURN_GOVERNOR_BIN}" verdict`, where `BURN_GOVERNOR_BIN` is set at `:3354`. It parses with five
  `sed -n 's/.*<key>=\(...\).*/\1/p` expressions requiring `verdict=[a-z]*`, `burn24h=[0-9]*`, `soft=[0-9]*`,
  `hard=[0-9]*`, `reason=[^ ]*`. **No caller passes `--provider`.** Also referenced (docs only) at
  `plugins/leadv2/docs/routing-enforcement.md:52`.
- **Callees:** `python3` (threshold resolve + classify), `sqlite3` via `_lbg_bounded_sqlite` against
  `${LEADV2_CLAUDE_BURN_DIR:-$HOME/.claude/burn}/history.db`.
- **Change here:** additive `--provider` arg. Default path (no flag) must remain **byte-identical** — including
  the exact key order of the output line — because `_burn_gate`'s regexes and `tests/test-burn-governor.sh`
  both key on it.

### 1.4 `lib/leadv2-glm-policy-resolve.py :: resolve_review_pool` (`:476`) and `live_codex_weekly_pct` (`:314`)
- **Callers of `resolve_review_pool` (CLI `--review-pool`) — two independent copies of the same call site:**
  1. `leadv2-review-run.sh:110 resolve_review_pool_call` → parsed at `:1101-1104`.
  2. `leadv2-dispatch-product-close.sh:~300-393 resolve_review_pool_call` → parsed at `:2468-2473`.
  The review-run copy's own header (`:18`) says it is *"lifted verbatim"* from product-close. **Any journal line
  added to only one of these two is invisible on the other path** — this is exactly the "independent copy nobody
  named" case, and it is why §3 puts the emit in a shared lib rather than inline.
  3. `leadv2-plan-run.sh:182` uses the same resolver with `--plan-pool` (out of scope: plan pool, not review).
- **Callee of `live_codex_weekly_pct`:** `leadv2-quota-live.sh codex` → `leadv2-quota-read.py codex` → cache
  `~/.claude/state/leadv2/quota-cache/codex.json`.
- **Change here:** `live_codex_weekly_pct` treats `limit_reached: true` (top level or on the binding window) as
  a hard 100.0 even when `used_percent` is missing/None. Today a `limit_reached` payload with no numeric
  `used_percent` returns `None` → the arm is scored `codex:unknown:` (`:583-587`), and if codex were ever the
  terminal arm in `review_arm_order` it would be **admitted** by the "terminal arm is never blocked by an
  unknown read" rule. With `DEFAULT_REVIEW_ARM_ORDER = ["codex","glm","kimi","opus","sonnet"]` (`:74`) codex is
  first, so this is latent today — but a repo that sets `review_arm_order: [opus, codex]` gets a dead reviewer.

### 1.5 New: `leadv2-provider-quota-gate.sh` (to-create)
- **Callees:** `plugins/leadv2/config/leadv2-quota-ceilings.sh` (to-create, sourced);
  `leadv2-quota-live.sh <glm|codex|anthropic>`; `python3` for JSON parse; `stat` for cache mtime.
- **Callers (after this lane):** `lib/leadv2-codex-quota-gate.sh:codex_spawn_gate` (both codex spawn paths);
  `tests/test-provider-quota-gate.sh`. **Not** wired to any anthropic refusal path — see §4.

---

## §2. STATES AND RETURN CODES

### 2.1 `leadv2-provider-quota-gate.sh <glm|codex|claude> <build|review>`

| # | State | rc | stderr/stdout marker | What the caller does | User-visible consequence |
|---|---|---|---|---|---|
| S1 | usage error (bad/missing provider or purpose) | 3 | `[provider-quota-gate] usage:` | `codex_spawn_gate` treats rc 3 as **fail-open** (returns 0) — a gate that can brick dispatch on its own arg bug is worse than no gate | nothing changes; a WARN appears in the lane log |
| S2 | `LEADV2_PROVIDER_QUOTA_GATE=0` (kill switch) | 0 | `WARN: gate disabled` | proceed | lane runs as it does today |
| S3 | quota-live helper missing / not executable | 0 | `FAIL-OPEN: quota-live helper missing` | proceed | lane runs; WARN in log |
| S4 | quota-live exits non-zero, or emits nothing | 0 | `FAIL-OPEN: quota-live exited N` | proceed | lane runs; WARN in log |
| S5 | JSON unparseable | 0 | `FAIL-OPEN: malformed <p> JSON` | proceed | lane runs; WARN in log |
| S6 | `status != "ok"` (network/auth/endpoint down) | 0 | `FAIL-OPEN: <p> quota read is unknown` | proceed | lane runs; WARN in log |
| S7 | cache file mtime older than 2× that bucket's TTL | 0 | `FAIL-OPEN: <p> quota-cache stale (age=Ns ttl=Ns)` | proceed | lane runs; WARN in log |
| S8 | pct read OK, `pct < ceiling(provider,purpose)` | 0 | `OK — <p> <pct>% < <ceil>%` on **stdout** | proceed | lane runs normally |
| S9 | pct read OK, `pct >= ceiling` | 1 | `LEADV2_DISPATCH_REFUSED: quota_gate` + `REROUTE — <p> <pct>% >= <ceil>% (<purpose>)` | see 2.2 | see 2.2 |
| S10 | `limit_reached: true` (codex) with no numeric pct | 1 | same as S9 with `pct=100 source=limit_reached` | see 2.2 | see 2.2 |

Fail-open is the default for **every** telemetry-side failure. The only rc-1 paths are S9/S10, i.e. a *known*
number at or over a *known* ceiling. This mirrors `leadv2-glm-quota-gate.sh` §3 verbatim.

### 2.2 Terminal trace of rc 1 out of the gate

`leadv2-provider-quota-gate.sh` rc 1
→ `codex_spawn_gate` maps to **return 2** + prints `CODEX_REFUSED_QUOTA reason=threshold used=<pct> threshold=<ceil>` and `LEADV2_DISPATCH_REFUSED: quota_gate`
→ **path A** `codex-task.sh:334` `|| exit "$?"` ⇒ codex-task exits 2 ⇒ the dispatcher's arm ladder maps rc 2 to "try the next candidate arm" ⇒ **the build runs on GLM or a Claude arm instead; the founder sees the lane complete, authored by a different arm, with one `CODEX_REFUSED_QUOTA reason=threshold` line in the lane log.**
→ **path B** `leadv2-codex-session-runner.sh:503` ⇒ `log_error "codex spawn refused by quota gate"` + `exit 2` ⇒ the runner does **not** retry (the refusal is outside the `attempt/MAX_ATTEMPTS` retry body's error handling — it exits before the spawn). **User-visible: that codex session produces no output, and the caller that launched it sees a rc-2 dead arm rather than a hang.** This is the intended outcome (a refusal that reports itself beats a 100%-quota provider burning the retry budget on guaranteed failures), but it must be stated: **path B does not reroute — it dies. Rerouting on path B is the caller's job and is unchanged by this lane.**

### 2.3 `leadv2-burn-governor.sh`

| Invocation | Output line | Consumer behaviour |
|---|---|---|
| `verdict` / no args / unknown arg (today) | `verdict=<ok\|soft\|hard> burn24h=<int> soft=<int> hard=<int> reason=<token>` | `_burn_gate`: ok→proceed silently; soft→journal `burn_gate … verdict=soft` + a ⚠ stderr line, **dispatch still allowed**; hard→journal + park + `exit 6` unless `LEADV2_BURN_OVERRIDE=1` |
| `--provider glm\|codex\|claude` (new) | `verdict=<ok\|soft\|hard> burn24h=0 soft=<softpct> hard=<ceilpct> reason=<token> provider=<p> used_pct=<n> unit=pct` | **no production consumer today.** The `soft=`/`hard=` fields carry percentages, not tokens, hence the explicit `unit=pct`. Key names and order for the first five fields are preserved so a future caller can reuse `_burn_gate`'s existing sed set |
| `--provider <p>` with unknown/stale/malformed cache | `verdict=ok burn24h=0 soft=<softpct> hard=<ceilpct> reason=no_telemetry provider=<p> unit=pct` | fail-open |
| `--provider <p>` with a bad provider name | `verdict=ok … reason=bad_provider` | fail-open |

The script **always exits 0**, in every mode. That invariant is load-bearing (`_burn_gate` has no rc handling)
and this lane must not break it.

Mapping: `soft = ceiling - 10`, `hard = ceiling`, ceiling = the **work** ceiling for the provider (the governor
has no purpose argument and its one prospective consumer, `_burn_gate`, gates *dispatch*, i.e. build).
`used_pct >= hard` → `hard`/`over_hard`; `>= soft` → `soft`/`over_soft`; else `ok`/`under_soft`.

### 2.4 `leadv2-review-run.sh` review-gate exits (existing — for the reroute trace)

| rc | `review-gate.md` `status:` | Reached when | User-visible |
|---|---|---|---|
| 0 | `pass` / `ran` | a reviewer ran and the union verdict passed | lane merges |
| 6 | `blocked` `reason: review_body_lost` | arm rc 0 but body under `LEADV2_REVIEW_BODY_MIN_BYTES` (300) | lane blocked, founder sees a named arm |
| 7 | `fail` `reason: selfcheck_red_round0` | round-0 selfcheck red | lane blocked |
| 8 | roundcap escalation (`REVIEW-ROUNDCAP-01`, commit ed37b05) | max rounds hit | lane escalated |
| 9 | `unreviewed` `reason: all_arms_unavailable` | `:1112` (no reviewer from the resolver) **or** `:1246` (every fanned-out arm failed) | **merge blocked; nobody reviewed the diff; the founder must review by hand.** `leadv2-dispatch-product-close.sh:2447` maps rc 9 → `_dl_note dead all_arms_unavailable` + `_stamp_review_terminal unreviewed` |

**The codex-dead case does *not* reach rc 9 today.** With codex at 100% and `review_threshold_pct` 95, the pool
is `codex:blocked:100,glm:blocked:92,kimi:…,opus:ok:65,sonnet:author` and `reviewer=opus`. The reroute already
happens. What does not happen is that anyone can *see* it happened for quota reasons: the pool string is emitted
only inside `review_pool_resolve … pool_n=<count>` (product-close `:392`, count only, not the string) and
rendered into `review-gate.md` on the failure paths. **The deliverable-3 defect is observability, not routing** —
so the fix is a journal line, not a new pool mechanism, which is also what the mission asked for.

---

## §3. CONFIGURATION BOUNDARIES

### 3.1 `plugins/leadv2/config/leadv2-quota-ceilings.sh` (to-create; sourced shell, not yaml)

Shape — deliberately a sourced `.sh` with a lookup function, because both consumers are bash and the repo has no
guaranteed PyYAML (`lib/leadv2-glm-policy-resolve.py:106` already regex-parses yaml for this reason):

```
LEADV2_CEIL_GLM_WORK=80    LEADV2_CEIL_GLM_REVIEW=90
LEADV2_CEIL_CODEX_WORK=90  LEADV2_CEIL_CODEX_REVIEW=95
LEADV2_CEIL_CLAUDE_WORK=95 LEADV2_CEIL_CLAUDE_REVIEW=95
leadv2_quota_ceiling <provider> <build|review>   # echoes int, rc 1 on unknown
```

Values copied verbatim from `plugins/leadv2/config/leadv2-routing.yaml:38-41`. Env vars use the `LEADV2_` prefix
(constraint-checklist item 1 — `LEADV2_`, never `LEAD_V2_`).

| Input | Absent | Empty | Minimum | Maximum / over-cap | Malformed |
|---|---|---|---|---|---|
| ceilings file itself | gate cannot source it → **fail-open, rc 0, WARN `FAIL-OPEN: ceilings file missing`**. Never fall back to a hardcoded literal — a silent literal is how the two-source drift started | n/a | n/a | n/a | `source` of a syntactically broken file aborts under `set -e`; the gate runs `set -uo pipefail` **without `-e`** and guards with `leadv2_quota_ceiling` existence check ⇒ fail-open |
| `leadv2_quota_ceiling <p> <purpose>` | unknown provider → rc 1, gate → S1 (rc 3, fail-open) | empty purpose → S1 | 0 → every read trips ⇒ the provider is fully withdrawn. Loud and intended (this is the "test the gate" knob) | >100 → gate never trips; equivalent to disabled. Must **not** clamp silently — emit `WARN: ceiling <n> > 100, gate is inert` so a typo is visible | non-numeric → the `(( ))` comparison in bash 3.2 would evaluate a bare word as 0 and refuse **everything**. Guard with `[[ "$ceil" =~ ^[0-9]+$ ]]` before comparing; non-numeric ⇒ fail-open + WARN |

### 3.2 `LEADV2_PROVIDER_QUOTA_GATE` (new env, kill switch)
absent → `1` (enabled). `0` → S2 bypass with a WARN. Any other value → treated as enabled (fail-safe direction).
Never silent — mirrors `GLM_SKIP_QUOTA_GATE`'s "logged, never silent" rule.

### 3.3 quota-cache JSON (`~/.claude/state/leadv2/quota-cache/<p>.json`)
Dir overridable via `LEADV2_QUOTA_CACHE_DIR` (`leadv2-quota-read.py:60`). TTLs: `LEADV2_QUOTA_TTL_GLM` 60 /
`LEADV2_QUOTA_TTL_CODEX` 120 / `LEADV2_QUOTA_TTL_ANTHROPIC` 300 (`:62-64`).

| Input | Absent | Empty | Min | Max / over-cap | Malformed |
|---|---|---|---|---|---|
| cache file | quota-live refetches; if the fetch fails, `status != ok` ⇒ S6 fail-open | 0-byte ⇒ JSON parse error ⇒ S5 fail-open | `pct: 0` ⇒ S8 allow | `pct: 100` ⇒ S9 refuse; `pct: 150` (provider bug) ⇒ S9 refuse — correct direction, no clamp needed | non-dict / missing `status` ⇒ S5/S6 |
| `pct` field | glm: `five_hour.pct` + `weekly.pct`, **either** over ⇒ trip (matches `leadv2-glm-quota-gate.sh:112`). codex: window matching `binding_window`, else `max(used_percent)` (matches `codex-task.sh:_codex_quota_read`). anthropic: active account's `seven_day_pct`, else `five_hour_pct` (matches `live_anthropic_pct:363`) | null ⇒ unknown ⇒ S6 | — | — | float/string ⇒ round via python to int before the bash compare |
| `limit_reached` (codex only) | absent ⇒ ignore | — | `false` ⇒ ignore | `true` ⇒ **force pct 100** (S10), even if `used_percent` is null | non-bool ⇒ ignore, fall through to `used_percent` |
| staleness | mtime unavailable (`stat` differs macOS/Linux) ⇒ **skip the staleness check entirely, do not fail** | — | age 0 ⇒ fresh | age > `2 × TTL` ⇒ S7 fail-open + WARN. A stale cache must **never** refuse | — |

`stat` portability: `stat -f %m` (BSD/macOS) vs `stat -c %Y` (GNU). Use `python3 -c 'import os,sys;print(int(os.path.getmtime(sys.argv[1])))'` — python3 is already a hard dependency of every script on this path.

### 3.4 `LEADV2_BURN_SOFT_24H` / `LEADV2_BURN_HARD_24H` (existing, unchanged)
Already boundary-hardened at `leadv2-burn-governor.sh:33-51` (`_lbg_resolve_thresholds`: non-digit or
`hard <= soft` ⇒ defaults + `reason=…+bad_config`; arbitrary-precision python, never bash `(( ))`, so a 21-digit
env cannot wrap negative). **`--provider` mode must not read these at all** — it derives soft/hard from the
ceilings file. If a caller sets both `--provider` and the env vars, the env vars are ignored; state that in the
`--help` text so it is not discovered as a bug.

### 3.5 `review_arm_order` / thresholds in `codex_quota_gate:` (existing, unchanged by this lane)
Absent block ⇒ resolver `DEFAULT_*` constants (`:41-76`) — that is the live behaviour in this repo. Present but
empty ⇒ `order = []` ⇒ empty pool ⇒ rank-table floor (`_review_floor:278`) ⇒ pool never empty. Over-cap (a
threshold > 100) ⇒ that arm is never blocked. Malformed (non-numeric) ⇒ the `float()` in `:121` raises inside a
`try` and the key falls back to the default. All already handled; no change needed, listed for completeness.

---

## §4. COUNTEREXAMPLE — what still violates the invariant after every finding here is fixed

The invariant: *no provider is dispatched work once its declared weekly ceiling for that purpose is reached.*

Three things still violate it after this lane, and I checked each rather than assuming:

1. **Claude *build* remains ungated by design.** After this lane, `leadv2-provider-quota-gate.sh claude build`
   exists and returns a correct verdict, but **nothing calls it.** The anthropic spawn channel is
   `plugins/leadv2/scripts/claude-subsession.sh` (66,889 bytes, high churn), and wiring a refusal there would
   also refuse the lead's own subagents — including the architect/critic spawns the review engine depends on
   (`leadv2-review-run.sh:1001`, `:1018` both spawn through it). A gate that stops the reviewer at 95% Anthropic
   converts a soft cost problem into `status: unreviewed` (rc 9, merge blocked). **That is a founder decision,
   not an architect one**, so this lane ships the reader and leaves the wiring out. Claude *review* is already
   gated at 95 by the resolver, so the exposed surface is exactly "build work dispatched to a Claude arm above
   95% weekly". One-line recipe when the founder says go: in `claude-subsession.sh`, immediately after arg parse,
   `bash "$SCRIPT_DIR/leadv2-provider-quota-gate.sh" claude build || exit 2`, behind
   `LEADV2_CLAUDE_QUOTA_GATE=1` defaulting to 0.
2. **Every gate is a *pre-launch* check on a *cached* number, so a single long lane can cross the ceiling
   mid-flight and nothing stops it.** GLM went 80→92 on the weekly window with the 5h window reading 1% — burst
   consumption inside one admission. The cache TTL (60/120/300 s) bounds how stale the number is at admission,
   not how much a running lane burns after admission. Closing this needs pacing (research gaps #1/#2), which the
   mission puts explicitly out of scope pending the Pro-5x decision. **This lane cannot and does not fix it.**
3. **`CODEX_SKIP_QUOTA_GATE=1` and `GLM_SKIP_QUOTA_GATE=1` remain unconditional bypasses**, checked before every
   other check (`lib/leadv2-codex-quota-gate.sh:33`, `codex-task.sh:326`, `leadv2-glm-quota-gate.sh:44`). They
   are logged, which is the existing design (an emergency hatch that announces itself). Not changed — removing an
   emergency hatch is a separate decision with its own blast radius.

What I checked and found *not* to be a hole: the review pool's unknown-read rule (`resolve_review_pool:583-587`)
looked like it could admit a dead codex, but codex is index 0 in `DEFAULT_REVIEW_ARM_ORDER` and the exception
only applies to the terminal arm — and §1.4's `limit_reached` change closes it for reordered repos anyway. The
`_review_floor` emergency floor (`:278`) *does* bypass quota gating outright, by design and with a `:floor:`
marker in the pool string, and `_engine_arm_from_floor` (`leadv2-review-run.sh:942`) already surfaces it — so a
floor-sourced reviewer cannot silently read as quota-cleared. I consider that pre-existing and correct.

---

## §5. Change list (exact files, exact edits)

| # | File | Edit | Size |
|---|---|---|---|
| C1 | `plugins/leadv2/config/leadv2-quota-ceilings.sh` **(to-create)** | 6 ceiling vars + `leadv2_quota_ceiling()`; header records the codex-work 80-vs-90 divergence and that it is deliberately not changed here | ~40 lines |
| C2 | `plugins/leadv2/scripts/leadv2-provider-quota-gate.sh` **(to-create)** | the generic gate, states S1–S10 of §2.1. Structure lifted from `leadv2-glm-quota-gate.sh` (same fail-open ladder, same `LEADV2_DISPATCH_REFUSED` marker) minus the GLM peak block | ~150 lines |
| C3 | `plugins/leadv2/scripts/leadv2-glm-quota-gate.sh` | `:39` `THRESHOLD` default now `$(leadv2_quota_ceiling glm build)` with the literal `80` retained as the source-failure fallback; source C1 near `:36`. **No behaviour change** | ~6 lines |
| C4 | `plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh` | capture `$1` before `shift`; add check 3 calling C2 with provider `codex` + derived purpose; return 2 on rc 1, return 0 on any other rc (fail-open). Closes Hole 1 **and** Hole 2 in one place, because both spawn paths route through this function | ~25 lines |
| C5 | `plugins/leadv2/scripts/leadv2-burn-governor.sh` | `--provider` arg + `cmd_verdict_provider`; default path untouched | ~60 lines |
| C6 | `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` | `live_codex_weekly_pct` (`:314`): `limit_reached: true` ⇒ return 100.0 | ~8 lines |
| C7 | `plugins/leadv2/scripts/lib/leadv2-review-reroute-note.sh` **(to-create)** | `leadv2_review_reroute_note <task> <pool> <reviewer>` — if the pool holds `codex:blocked:` or `codex:unknown:` and `reviewer` is non-empty and != codex, print one `codex_dead_reroute task=… from=codex to=<reviewer> codex=<disposition> pool=<pool>` line. Silent otherwise. Never returns non-zero | ~30 lines |
| C8 | `plugins/leadv2/scripts/leadv2-review-run.sh` | source C7; call it right after the pool parse at `:1104`, `emit decision "$(leadv2_review_reroute_note …)"` guarded on non-empty | ~6 lines |
| C9 | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | the identical 6 lines after `:2473` — **the independent second copy of the resolve point** | ~6 lines |
| C10 | `plugins/leadv2/scripts/tests/test-provider-quota-gate.sh` **(to-create)** | §2.1 S1–S10 per provider from fixture cache JSONs + fixture ceilings file; the boundary rows of §3.1/§3.3 (ceiling 0, ceiling >100, non-numeric ceiling, stale mtime, `limit_reached` with null pct); `bash -n` on C2/C3/C4 | ~250 lines |
| C11 | `plugins/leadv2/scripts/tests/test-burn-governor.sh` | **append** `--provider` cases; the existing default-mode cases are the backward-compat assertion and must not be edited | ~80 lines added |
| C12 | `plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh` **(to-create)** | fixture codex.json with `limit_reached: true` + null `used_percent` ⇒ resolver returns `codex:blocked:100`, reviewer is the next `:ok:` arm, and `codex_dead_reroute` appears on **both** the review-run and product-close paths | ~180 lines |
| C13 | `plugins/leadv2/scripts/tests/run-core-offline.sh` | three registry rows in `SUITE_DEFS`, format `"<name>|||bash $TEST_DIR/<file>"` (see `:329`) | 3 lines |
| C14 | `plugins/leadv2/docs/routing-enforcement.md` | one new `## Provider quota ceilings (QUOTA-GATE-PARITY-01)` section after `## Burn governor` (`:50`): the ladder, the two holes it closed, the claude-build non-goal | ~40 lines |

**Concurrency (constraint-checklist item 4):** C2 is read-only against the quota cache; the only writer is
`leadv2-quota-read.py`, which already writes atomically via `mkstemp` + `os.replace` (`:81-84`). No lock needed
and none should be added — a gate that can block on a lock reintroduces the hang that `_LBG_SQL_TIMEOUT_S`
exists to prevent. C4 adds a subprocess to a hot spawn path; C2 must therefore bound its own quota-live call the
way `codex-task.sh:_codex_quota_read` does (`LEADV2_QUOTA_READ_TIMEOUT:-8`, background + poll + kill, no
GNU `timeout`).

**No `claude -p` invocation is introduced by this lane** (constraint-checklist item 3 — n/a).

---

## §6. Out of scope (implementing agent: ignore)

- Research gaps #1, #2, #4, #5, #7 — pacing, per-day budgets, reserve wiring, unified dashboard, time-of-week
  shifting. Blocked on the Pro-5x tier decision.
- Changing any ceiling **value**, including the codex-work 80→90 divergence in §0.
- Wiring a claude-build refusal into `claude-subsession.sh` (§4 item 1 — founder decision).
- Removing or narrowing `CODEX_SKIP_QUOTA_GATE` / `GLM_SKIP_QUOTA_GATE`.
- Any new review-pool mechanism, any change to `resolve_review_pool`'s selection logic, `_review_floor`, or the
  `review_arm_order` contract. C6 is a single-value normalisation inside one live-read helper, nothing more.
- `leadv2-plan-run.sh` / the `--plan-pool` path.
- Touching anything outside `~/Projects/leadv2`.

---

## §7. Risks

| Risk | Mitigation |
|---|---|
| C4 puts a network-backed read on the hot codex spawn path; a hung z.ai/OpenAI endpoint stalls every spawn | C2 bounds its quota-live call at `LEADV2_QUOTA_READ_TIMEOUT:-8` s using the portable background+poll+kill pattern already proven at `codex-task.sh:207-240`; timeout ⇒ S4 fail-open. The 120 s codex cache TTL means the endpoint is hit at most once per 2 min |
| C4 refuses on both spawn paths at once — if the ceiling or cache is wrong, codex is fully withdrawn | Every telemetry failure mode is fail-open (§2.1 S1–S7); only a *known* pct ≥ a *known* numeric ceiling refuses. Plus `LEADV2_PROVIDER_QUOTA_GATE=0` and the pre-existing `CODEX_SKIP_QUOTA_GATE=1` |
| C5 breaks `_burn_gate`'s five sed regexes | Default path is byte-identical; C11 keeps the existing default-mode assertions untouched as the compat oracle |
| C1 becomes a *fourth* source of truth rather than replacing the others (the resolver keeps its python constants) | C10 includes a drift assertion: parse `router_v2.quota_ceilings` from `plugins/leadv2/config/leadv2-routing.yaml`, the `DEFAULT_*` constants from `lib/leadv2-glm-policy-resolve.py`, and C1's vars, and fail if any disagree — **except** the one documented codex-work 80/90 divergence, which is asserted as an expected exception so it cannot silently widen |
| C8/C9 drift apart (the two independent copies of the resolve point) | The logic lives in C7 only; C8 and C9 are call sites, not copies. C12 asserts the line on both paths |
| `leadv2-glm-policy-resolve.py` is the repo's worst-health file (1.0/10) | C6 is confined to one function's return value with a `try`-guarded read; C10/C12 cover it from fixtures, no live network |

---

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >-
      With the codex quota-cache showing the weekly window used up, a lane that would
      have run its build on Codex instead runs on another arm, and the lane log carries
      one line naming Codex, the percentage it was at, and the ceiling it crossed —
      instead of the lane silently handing work to a provider with nothing left.
    authored_at: 2026-08-24T00:00:00Z
  - surface: log_line
    observable: >-
      When Codex is out of quota and the review is handed to another reviewer, the task
      journal shows a line that names Codex as dead and names which reviewer took over.
      Before this change the handover left no trace and the founder could not tell a
      quota reroute from a normal reviewer choice.
    authored_at: 2026-08-24T00:00:00Z
  - surface: log_line
    observable: >-
      With the quota cache deleted, or holding unreadable text, or older than twice its
      refresh interval, every lane still starts and the log says the gate allowed it
      because the number was unavailable. No lane is ever blocked by missing telemetry.
    authored_at: 2026-08-24T00:00:00Z
  - surface: file_artifact
    observable: >-
      The six declared ceilings appear in exactly one editable place, and a suite run
      fails loudly if that place ever disagrees with the numbers the routing config and
      the review-pool resolver use — with the single known codex-work difference spelled
      out by name rather than passing unnoticed.
    authored_at: 2026-08-24T00:00:00Z
  - surface: log_line
    observable: >-
      The existing burn-gate behaviour is unchanged: with no provider named, the governor
      still reports the same 24-hour Claude token burn verdict it reports today, and a
      dispatch that is allowed today is still allowed.
    authored_at: 2026-08-24T00:00:00Z
```

LANE_WRITES: plugins/leadv2/config/leadv2-quota-ceilings.sh, plugins/leadv2/scripts/leadv2-provider-quota-gate.sh, plugins/leadv2/scripts/leadv2-glm-quota-gate.sh, plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh, plugins/leadv2/scripts/leadv2-burn-governor.sh, plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py, plugins/leadv2/scripts/lib/leadv2-review-reroute-note.sh, plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-provider-quota-gate.sh, plugins/leadv2/scripts/tests/test-burn-governor.sh, plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/docs/routing-enforcement.md

DELIVERABLE_COMPLETE
