# QUOTA-GATE-PARITY-01 — fix round 2 — architect prepass (mechanism-closed)

Lane: `.claude/worktrees/b413968c`, branch `worktree-b413968c`, HEAD `bef2b86`. All line
numbers below are read from that worktree, not from the mission text.

## 0. Where the mission's framing and the code disagree

Two of the seven findings are stated in a way the tree contradicts. Designing against the
code, not the finding text:

- **F5–F7 ("limit_reached means 100% has no probe artifact").** Two of the three named sites
  already OR the top-level flag correctly — `leadv2-provider-quota-gate.sh:61-62` and
  `leadv2-burn-governor.sh:213`. The defect at those two sites is *only* the missing evidence
  artifact, not the logic. Only the third site (`lib/leadv2-glm-policy-resolve.py:314`) has a
  logic hole, and that hole is F1. So F1 and F5–F7 collapse into one code change plus two
  comment changes.
- **F2 ("the unconditional live gate makes tests depend on host quota").**
  `codex_spawn_gate` check 3 (`lib/leadv2-codex-quota-gate.sh:68`) already honours three test
  overrides, because it execs `leadv2-provider-quota-gate.sh` as a child process and that
  script reads `LEADV2_PROVIDER_QUOTA_GATE`, `LEADV2_QUOTA_LIVE`, `LEADV2_QUOTA_CEILINGS` and
  `LEADV2_QUOTA_CACHE_DIR` from the inherited environment (`:8`, `:9`, `:16`, `:38`). The
  gate needs no new env var. The defect is that `tests/test-codex-quota-guardrails.sh` sets
  none of them at rows a4 / c3 / c4 / e1, so those rows fall through to the host's real
  `~/.claude/state/leadv2/quota-cache/codex.json`. **The fix is test-side isolation, and one
  documentation comment in the lib naming the contract so the next author does not re-break
  it.** Inventing a fourth `LEADV2_CODEX_GATE_SKIP_LIVE`-style flag would add a production
  bypass to fix a test bug; rejected.

## 1. CALLERS / CALLEES

### 1a. `codex_spawn_gate` — `plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh:27`

Callers (two independent production paths — they are *not* a wrapper and its wrappee):

| Caller | file:line | What it does with a nonzero rc |
|---|---|---|
| codex session runner | `leadv2-codex-session-runner.sh:502` | `log_error … exit 2` — the whole runner process dies before `codex exec` |
| codex-task dispatcher | `codex-task.sh:334` | `codex_spawn_gate "$SUB" \|\| exit "$?"` — propagates rc 2 verbatim to the router |
| (fail-closed sibling) | `leadv2-codex-session-runner.sh:498` | if the function is undefined and `CODEX_SKIP_QUOTA_GATE!=1`, `exit 2` without calling |

Test callers: `tests/test-codex-quota-guardrails.sh:108,229,244,344`,
`tests/test-codex-quota-gate.sh`, `tests/test-provider-quota-gate.sh:65` (syntax only).

Callees, in order:

1. `arm_cooldown_state codex` — `lib/leadv2-arm-cooldown.sh`, sourced at `:20`.
2. `codex_circuit_state` — `lib/leadv2-codex-circuit.sh`, sourced at `:22`.
3. `../leadv2-provider-quota-gate.sh codex <build|review>` — `:68`, a **child process**, not
   a sourced function. This is the live-quota leg and the one F2 is about.

### 1b. `leadv2-provider-quota-gate.sh`

Only one in-tree production caller: `lib/leadv2-codex-quota-gate.sh:68`. `glm` and `claude`
are documented (`docs/routing-enforcement.md:108,133`) but have **no** production caller —
`claude build` is explicitly ungated. Test caller: `tests/test-provider-quota-gate.sh:59`.
Callee: `leadv2-quota-live.sh <glm|codex|anthropic>` at `:29`, backgrounded with a hand-rolled
poll loop at `:31`.

### 1c. `LEADV2_QUOTA_READ_TIMEOUT` — two independent implementations

This is the "independent copy nobody named". The var is consumed at **two** sites that each
roll their own bounded-subprocess loop, with different tick granularity:

| Site | Code | Ticks |
|---|---|---|
| `leadv2-provider-quota-gate.sh:28,31` | `timeout_s="${LEADV2_QUOTA_READ_TIMEOUT:-8}"` → `(( elapsed < timeout_s * 10 ))` | 0.1 s |
| `codex-task.sh:223-224` | `_deadline_s="${LEADV2_QUOTA_READ_TIMEOUT:-8}"` → `_ticks=$(( _deadline_s * 2 ))` | 0.5 s |

Fixing only `:28` leaves `codex-task.sh:223` unbounded on exactly the same input, on the
dispatcher path that runs far more often. Both are in scope.

### 1d. `live_codex_weekly_pct` — `lib/leadv2-glm-policy-resolve.py:314`

Callers: `:447` (via `_live_pct_memo`, itself called from `_live_pct_for_arm`) and `:530`
(`_pct_for` inside `resolve_review_pool`). Return value is a float percentage compared against
`codex_threshold` (`:537`). Callee: `subprocess.run(["bash", quota_live_bin, "codex"], timeout=10)`.

### 1e. `THRESHOLD` — `leadv2-glm-quota-gate.sh:44`

Producer chain: `config/leadv2-quota-ceilings.sh:23` (`LEADV2_CEIL_GLM_WORK="${…:-80}"`) →
`leadv2_quota_ceiling glm build` (`:33`) → `_glm_default_threshold` (`:41`) → `THRESHOLD`
(`:44`, `GLM_QUOTA_THRESHOLD` wins if set). Consumer: the arithmetic at `:122`
`(( five_pct >= THRESHOLD || wk_pct >= THRESHOLD ))`. Callers of the script itself are lane
launchers keyed on rc 0/1/2 per the header contract at `:21`.

## 2. STATES AND RETURN CODES

### 2a. `leadv2-provider-quota-gate.sh`

| State | rc | `codex_spawn_gate` maps to | User-visible consequence |
|---|---|---|---|
| bad provider / bad purpose / ceiling lookup fails (`:14,15,21`) | 3 | 3 ≠ 1 → gate returns 0 | spawn proceeds ungated; usage error on stderr |
| `LEADV2_PROVIDER_QUOTA_GATE=0` (`:16`) | 0 | pass | spawn proceeds, `WARN: gate disabled` logged |
| ceilings file missing / malformed / lookup fn absent (`:17,19,20`) | 0 | pass | fail-open, spawn proceeds |
| ceiling non-numeric (`:22`) | 0 | pass | fail-open |
| ceiling > 100 (`:23`) | 0 unless pct ≥ ceil | pass | gate inert — **see §4 counterexample** |
| quota-live helper missing (`:24`) | 0 | pass | fail-open |
| `mktemp` fails (`:27`) | 0 | pass | fail-open |
| quota-live nonzero / empty / killed at timeout (`:32,34`) | 0 | pass | fail-open, `quota-live exited 124` |
| cache older than 2×TTL (`:45`) | 0 | pass | fail-open, staleness logged |
| JSON malformed / status≠ok / no numeric window (`:71`) | 0 | pass | fail-open |
| codex `limit_reached` true, top-level or binding window (`:61,62`) | 1 | **2** | Codex spawn refused. Runner `exit 2`; codex-task propagates 2 → router picks the next candidate arm, so the work runs on GLM or Anthropic instead of stalling |
| pct ≥ ceiling (`:73`) | 1 | **2** | same as above |
| pct < ceiling (`:78`) | 0 | pass | spawn proceeds |

Terminal trace for rc 2: no retry loop exists on either caller. `codex-task.sh:334` exits;
the router treats `LEADV2_DISPATCH_REFUSED: quota_gate` on stderr as "try the next arm". If
*every* arm refuses, the dispatch produces no worker and the lane reports a refusal — in plain
words, **the task is not started on Codex and is either re-routed to another provider or, if
all are blocked, is not started at all this cycle**.

### 2b. `codex_spawn_gate`

| State | rc | Consequence |
|---|---|---|
| `CODEX_SKIP_QUOTA_GATE=1` (`:31`) | 0 | all three checks skipped |
| cooldown `cooling <until>` (`:38`) | 2 | refuse; `reason=cooldown` |
| circuit `open <until>` (`:54`) | 2 | refuse; `reason=circuit` |
| circuit `unknown` (`:60`) | 2 | refuse fail-closed; `reason=circuit-unknown` |
| child gate rc 1 (`:70`) | 2 | refuse; `reason=threshold` |
| child gate rc 3 / 127 / 0 | 0 | **pass** — anything that is not exactly 1 is treated as "allow". A missing child script (127) fails open by construction. |

### 2c. `leadv2-glm-quota-gate.sh`

| State | rc | Consequence |
|---|---|---|
| `GLM_SKIP_QUOTA_GATE=1` (`:52`) | 0 | bypass, logged |
| quota-live missing (`:57`) | 0 | fail-open |
| quota-live rc≠0 (`:78`) | 0 | fail-open |
| unparseable / `_parse_error` / `_unknown` (`:99,102,106`) | 0 | fail-open |
| either window ≥ THRESHOLD (`:122`) | 1 | reroute; cooldown recorded; lane runs elsewhere |
| peak hours without `GLM_ALLOW_PEAK` (`:141`) | 2 | lane refused until 10:00 UTC |
| otherwise | 0 | lane starts |
| **THRESHOLD non-numeric (today)** | **2 (bash fatal)** | `(( … >= abc ))` under `set -u` aborts the script. rc 2 is the *peak-hours refusal* code, so the launcher reads a config typo as "wait until 10:00 UTC". In plain words: **every GLM lane silently stops starting, and the operator is told it is peak hours.** This is the F3 defect and it is worse than the finding states — it is not just an abort, it is an abort that impersonates a documented refusal. |
| **`five_pct`/`wk_pct` = `None` (today)** | **2 (bash fatal)** | identical failure. Python prints the literal `None` when `five_hour.pct` is absent from an otherwise `status:ok` payload; `:117` `${five_pct:-0}` only defends against *empty*, not against `None`. Same impersonation of rc 2. Adjacent to F3, same line, must be fixed with it. |

## 3. CONFIGURATION BOUNDARIES

`LEADV2_QUOTA_READ_TIMEOUT` (`provider-quota-gate.sh:28`, `codex-task.sh:223`)

| Input | Today | Designed |
|---|---|---|
| absent | 8 s | 8 s |
| empty string | `(( elapsed < * 10 ))` → `*` is a syntax error → loop body never runs → child killed at once, rc 124 → fail-open | 8 s |
| `0` | loop never runs; child killed immediately; fail-open on every call — the gate is silently off | clamped to 1 |
| `1` | 1 s | 1 s |
| `86400` | **the gate polls for 24 h and every spawn behind it blocks** | clamped to 60, warn |
| `abc` | `(( elapsed < abc * 10 ))` → unbound variable under `set -u` → gate aborts | 8 s, warn |
| `-5` | negative → loop never runs → gate effectively off | clamped to 1, warn |
| `8.5` | bash arithmetic syntax error | 8 s, warn (integers only) |

`LEADV2_CEIL_GLM_WORK` / `GLM_QUOTA_THRESHOLD` (`glm-quota-gate.sh:41,44`)

| Input | Today | Designed |
|---|---|---|
| absent | 80 (from `ceilings.sh:23`) | 80 |
| empty | `THRESHOLD=""` → `(( … >= ))` syntax error, rc 1 → **false reroute**: every GLM lane is told it is over quota | 80, warn |
| `0` | every read trips → all GLM lanes reroute | honoured (0 is a legitimate "drain GLM" setting) |
| `100` | only a 100 % read trips | honoured |
| `150` | never trips, gate inert | honoured, warn inert (parity with `provider-quota-gate.sh:23`) |
| `abc` | fatal abort disguised as rc 2 (§2c) | 80, warn |
| `80; id` | arithmetic-context command substitution — `(( … >= 80; id ))` evaluates the injected expression | rejected by the `^[0-9]+$` guard, falls back to 80 |

`five_hour.pct` / `weekly.pct` in the GLM payload

absent → `None` → fatal (§2c) · `null` → `None` → fatal · non-integer `12.5` → arithmetic
syntax error, rc 1, **false reroute** · negative → never trips · `>100` → trips.
Designed: any value not matching `^[0-9]+$` is treated as unknown → fail-open with a named warn.

`limit_reached` in the codex payload — see §4 for the over-cap interaction.
absent → falsy, fall through to `used_percent` · `false` → fall through · `true` → block ·
`null` → falsy (`is True` comparison, correct) · string `"true"` → **falsy**, does not block;
acceptable because the producer (`leadv2-quota-read.py:291,300`) copies a JSON boolean verbatim.

`LEADV2_QUOTA_CEILINGS`, `LEADV2_QUOTA_LIVE`, `LEADV2_QUOTA_CACHE_DIR`
absent → default under `SCRIPT_DIR` / `$HOME` · empty → treated as missing → fail-open ·
non-existent path → fail-open (`:17`, `:24`) · directory instead of file → `source` fails →
fail-open. No change needed; these are the three levers the F2 test fix uses.

## 4. COUNTEREXAMPLE — what still violates the invariant after all seven are fixed

The invariant: *no Codex spawn is admitted while the account is hard-limited.* After all seven
fixes, three ways to violate it remain.

**(a) The inert-ceiling escape, and it is reachable.** `provider-quota-gate.sh:23` warns when
`ceil > 100` but keeps going, and the refusal at `:73` is `pct >= ceil`. With
`LEADV2_CEIL_CODEX_WORK=150`, the synthesized `pct=100` from `limit_reached` is *less than*
the ceiling, so a hard-limited account is admitted while the log says `gate is inert`. The
whole point of F5–F7 — that `limit_reached` is a standalone block signal, not a percentage —
is exactly what makes this a bug: a standalone signal must not be routed through a numeric
comparison it can lose. **The design therefore short-circuits `limit_reached` to rc 1 before
the ceiling comparison**, not merely relabels the constant. This is in scope; it is the only
change that makes F5–F7's stated intent true rather than decorative.

**(b) Everything above the gate is fail-open by design, and there are eleven such paths**
(§2a). A killed `quota-live`, a stale cache, a `status:unknown` payload, a missing ceilings
file — each admits the spawn on an account that may be at 100 %. That is the deliberate
contract (`leadv2-glm-quota-gate.sh:17` §3) and this task must not change it, but it means the
gate is a headroom-protector, not a hard limit. The circuit breaker
(`lib/leadv2-codex-circuit.sh`, check 2) is the actual backstop after a refusal has been
observed once.

**(c) `codex_spawn_gate` only treats rc==1 as refusal** (`:70`). If
`leadv2-provider-quota-gate.sh` ever grows a new refusal rc, or is deleted (rc 127), the spawn
is admitted. Not fixed here — widening it would change the fail-open contract — but noted so
the next author does not assume rc-completeness.

What I checked to reach this: every consumer of `LEADV2_QUOTA_READ_TIMEOUT`,
`LEADV2_CEIL_GLM_WORK` and `limit_reached` in the worktree (§1c, §1e, and the three sites in
F5–F7), the full rc table of both gates, and both `codex_spawn_gate` production callers.

## 5. EVIDENCE — the `limit_reached` mapping (closes F5–F7)

Producer: `plugins/leadv2/scripts/leadv2-quota-read.py:273` fetches
`https://chatgpt.com/backend-api/wham/usage`; `:281-291` reads `rate_limit.limit_reached` and
`rate_limit.primary_window.used_percent` as **two independent fields** and copies
`rl["limit_reached"]` onto both the primary window (`:291`) and the top level (`:300`).

Live probe, captured 2026-08-24T13:54Z from `~/.claude/state/leadv2/quota-cache/codex.json`
(written by the fetcher above):

```
$ python3 -c 'import json;d=json.load(open("codex.json"));print({k:d.get(k) for k in ("status","limit_reached","binding_window")});print(d["windows"])'
{'status': 'ok', 'limit_reached': False, 'binding_window': 'primary'}
[{'kind': 'primary', 'used_percent': 4, 'limit_window_seconds': 604800,
  'reset_epoch': 1788133618, 'reset_iso': '2026-08-30T23:46:58Z',
  'limit_reached': False, 'remaining_pct': 96.0, 'hours_to_reset': 156.877,
  'usable_now': 0.6119429398703174}]
```

What this establishes: `limit_reached` is carried verbatim from the provider and is *not*
derived from `used_percent` (here `used_percent=4` with `limit_reached=false`). What it does
**not** establish: that `limit_reached=true` co-occurs with `used_percent=100` — no
limit-reached sample is on disk, and the OpenAI endpoint is undocumented publicly.

Therefore the design records the honest form in all three sites:

> `UNVERIFIED:` a true `limit_reached` has never been observed alongside its `used_percent`,
> so `100` is a **saturating block sentinel, not a measured percentage**. The mapping is safe
> in the refusal direction only, which is why `limit_reached` must also short-circuit the
> ceiling comparison (§4a).

This is the mission's second option — tag the mapping `UNVERIFIED:` *and* make the code treat
`limit_reached` as a standalone block signal — chosen because option one (add a probe
artifact) is not achievable without a hard-limited account to sample.

## 6. CHANGES — exact files, stated as intent

### C1 — `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` (F1, F5–F7)
Add a module constant `CODEX_LIMIT_REACHED_PCT = 100.0` carrying the §5 note verbatim.
In `live_codex_weekly_pct` (`:314`), evaluate the top-level `d.get("limit_reached") is True`
**before** the `for w in windows` loop, so the binding-window branch can no longer return
early past it; keep the per-window check inside the loop. Net effect: the two flags are a
true OR. Behaviour on every other input is unchanged.
Non-goal: changing the function's return type or plumbing a new `codex_block_cause` value —
that ripples into `_live_pct_memo`, `_pct_for` and `resolve_review_pool` and is not needed.

### C2 — `plugins/leadv2/scripts/leadv2-provider-quota-gate.sh` (F4, F5–F7, §4a)
1. Clamp the timeout: accept `^[0-9]+$` only, else default 8 with a named warn; clamp `<1`→1
   and `>60`→60 with a named warn. Applied before the poll loop at `:31`.
2. Refuse on `limit_reached` **before** the `pct >= ceil` comparison at `:73`, so an inert
   (`>100`) ceiling cannot swallow it. The existing `parsed` protocol already carries the
   discriminator as `source=limit_reached` (`:61,62,72`); branch on it.
3. Add the §5 evidence note at `:61`.
Non-goal: changing any fail-open path, or gating `claude build`.

### C3 — `plugins/leadv2/scripts/leadv2-glm-quota-gate.sh` (F3 + the `None` twin)
Validate `THRESHOLD` after `:44` against `^[0-9]+$`; on failure warn with the offending value
and fall back to `80`. Warn (do not fail) when `>100`, matching `provider-quota-gate.sh:23`.
Validate `five_pct` and `wk_pct` against `^[0-9]+$` at `:117`, replacing the
`${five_pct:-0}` idiom that does not catch the literal `None`; a non-numeric reading is
*unknown*, so fail open per §3 of the file's own header rather than defaulting to 0 silently —
emit `FAIL-OPEN: GLM quota read is non-numeric (…)` and exit 0.
Non-goal: touching the peak-hours logic or the cooldown recording.

### C4 — `plugins/leadv2/scripts/codex-task.sh:223` (F4, second copy)
Same timeout clamp as C2.1, applied to `_deadline_s` before `_ticks=$(( _deadline_s * 2 ))`.
Three lines; no other change to this file.

### C5 — `plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh` (F2, documentation half)
Extend the comment above `:68` to name the three env vars that make check 3 hermetic
(`LEADV2_QUOTA_LIVE`, `LEADV2_QUOTA_CEILINGS`, `LEADV2_QUOTA_CACHE_DIR`) and to state that
check 3 is a child process which inherits them. No code change; no new bypass flag.

### C6 — `plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh` (F2, the actual fix)
Add a shared fixture quota-live emitter and scratch cache dir next to the existing `STUBBIN`
block (`:28`), and export `LEADV2_QUOTA_LIVE`, `LEADV2_QUOTA_CACHE_DIR` and
`LEADV2_QUOTA_CEILINGS` on rows a4 (`:107`), c3 (`:229`), c4 (`:244`) and e1 (`:344`) so no
row can read `~/.claude/state/leadv2/quota-cache/`. Add one row asserting the isolation
itself: with `HOME` pointed at an empty scratch dir and the fixture emitter supplying a
0 % codex reading, `codex_spawn_gate exec` returns 0 regardless of host state.

### C7 — `plugins/leadv2/scripts/tests/test-provider-quota-gate.sh` (F1, F3, F4, §4a)
New rows, using the existing `FAKE_LIVE` / `run_gate` harness:
- timeout `abc` → rc 0, warn names the fallback; timeout `99999` → warn names the clamp and
  the gate still completes promptly; timeout `0` → clamped to 1, gate still evaluates.
- codex `limit_reached:true` with `LEADV2_CEIL_CODEX_WORK=150` → rc 1 (the §4a regression).
- `GLM_QUOTA_THRESHOLD=abc` and `LEADV2_CEIL_GLM_WORK=abc` against `GLM_GATE_BIN` → rc 0 or 1
  by threshold 80, never rc 2, and stderr names the fallback.
- glm payload with `five_hour:{}` (absent `pct`) → rc 0 with the non-numeric fail-open warn,
  never a bash abort.
- `live_codex_weekly_pct` invoked via `python3 -c` against a fixture emitter returning
  `{"status":"ok","limit_reached":true,"binding_window":"primary","windows":[{"kind":"primary","used_percent":4}]}`
  → `100.0` (the F1 regression: today it returns 4).

### C8 — `plugins/leadv2/docs/routing-enforcement.md`
Update `:147` to state the clamp range and both consumer sites; add the §5 evidence note and
the `limit_reached`-short-circuits-the-ceiling rule to the gate description at `:108`.

## 7. NON-GOALS

- No changes to any review script or to the reviewer's verify infrastructure (the empty
  verify files are explicitly out of scope per the mission).
- No new production bypass env var for the codex gate.
- No change to the fail-open contract at any of the eleven fail-open paths in §2a.
- No widening of `codex_spawn_gate`'s `rc==1`-only refusal test (§4c) — recorded, not fixed.
- No gating of `claude build`; no change to `config/leadv2-quota-ceilings.sh` values (the
  drift assertion at `test-provider-quota-gate.sh:170` pins them).
- No change to `leadv2-quota-read.py` or `leadv2-quota-live.sh`.
- No change to `leadv2-burn-governor.sh` logic — its OR at `:213` is already correct; it
  receives only the §5 evidence comment.

## 8. RISKS

| Risk | Mitigation |
|---|---|
| C2.2 changes a refusal path — a fixture with `limit_reached` and a normal ceiling must keep returning rc 1, not a new code | C7 keeps the existing S10 row unchanged and adds the `ceil=150` row beside it |
| C3's non-numeric-reading change converts a silent `0` into a fail-open exit; a lane launcher parsing stdout could see new text | rc is unchanged (0) and the new line uses the file's existing `FAIL-OPEN:` prefix, which the header at `:21` already tells launchers not to parse |
| C6 alters four existing test rows; a row could pass for the wrong reason | the added isolation row asserts host-independence directly, with `HOME` redirected |
| Two sessions editing the same worktree | single lane, single branch `worktree-b413968c`; commit on that branch only, do not recreate it |
| `codex-task.sh` is a high-churn file (77 commits/90d on its sibling dispatcher) | C4 is confined to three lines in one function and adds no new control flow |

## 9. ACCEPTANCE

```yaml
acceptance:
  authored_at: 2026-08-24T14:05:00Z
  - surface: log_line
    observable: >
      When the codex quota cache reports that the account has hit its limit, the
      dispatcher's log shows the codex spawn being refused for quota and the work moving to
      another provider — and it shows this even when the codex ceiling has been set above
      100, where today the log instead says the gate is inert and the spawn goes ahead.
  - surface: log_line
    observable: >
      With a nonsense value configured for the GLM ceiling, a GLM lane still starts (or
      reroutes on a genuinely high reading) and the log names the bad value and the 80%
      fallback. Today the lane instead stops with the peak-hours message, at any hour.
  - surface: log_line
    observable: >
      With the quota read timeout configured to a day, a spawn is admitted or refused within
      about a minute rather than hanging, and the log states that the configured value was
      clamped.
  - surface: file_artifact
    observable: >
      The core offline suite's summary file shows the codex quota-guardrail rows passing on a
      machine whose real codex quota cache says the account is hard-limited — the same rows
      that pass today only because the developer's own account happens to have headroom.
  - surface: file_artifact
    observable: >
      Every place in the tree that turns "the account is limited" into the number 100 carries,
      next to it, the captured codex.json sample and a plain statement that no
      limit-reached sample has ever been observed, so the number is a block sentinel and not a
      measurement.
```

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py, plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh, plugins/leadv2/scripts/leadv2-provider-quota-gate.sh, plugins/leadv2/scripts/leadv2-glm-quota-gate.sh, plugins/leadv2/scripts/leadv2-burn-governor.sh, plugins/leadv2/scripts/codex-task.sh, plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh, plugins/leadv2/scripts/tests/test-provider-quota-gate.sh, plugins/leadv2/docs/routing-enforcement.md

DELIVERABLE_COMPLETE
