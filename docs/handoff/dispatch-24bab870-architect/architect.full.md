# ARCHITECT PREPASS — GLM-FIRST-RECOVERY-01

Repo: `~/Projects/leadv2` (plugin canonical). Job: design only, no implementation.

---

## 1. Diagnosis — measured, not assumed

### 1.1 The evidence

`arm_resolved` lines across the consuming repo's task journals (`~/Projects/persona-engine/docs/leadv2/tasks/*/journal.md`):

| count | line |
|---|---|
| 358 | `arm_resolved job=build arm=glm reason=none` |
| **90** | **`arm_resolved job=build arm=sonnet reason=codex_quota_gate_80pct`** |
| 64 | `arm_resolved job=build arm=sonnet reason=safety_gate_publish_payments` |
| 39 | `arm_resolved job=build arm=sonnet reason=integration_critical_4subsystems` |
| 33 | `arm_resolved job=build arm=codex reason=codex_fitting_kind` |
| 12 | `arm_resolved job=build arm=kimi reason=ui_design_judgment` |

Note the emitter (`leadv2-dispatch-code.sh:3292`) prints `reason=${rule}` — the journal's `reason=`
field carries the resolver's **rule**, not its `reason`. So the founder-observed rows are
`rule=codex_quota_gate_80pct`, produced at `leadv2-glm-policy-resolve.py:702`.

Live readings taken 2026-08-15T20:25Z from the repo root:

```
$ bash plugins/leadv2/scripts/leadv2-quota-live.sh glm
{"provider":"glm","status":"ok","five_hour":{"pct":2,...},"weekly":{"pct":40,...},"binding_window":"weekly"}

$ bash plugins/leadv2/scripts/leadv2-quota-live.sh codex
{"provider":"codex","status":"unknown","error":"refresh http 401","needs_login":true,...}
```

GLM is at 2% / 40% — wide open. Codex's probe is **stuck unknown** (expired login, HTTP 401),
and has been for the whole window in question. The mission's "all three readings return None"
observation is partly an artifact of how the probe was invoked; GLM reads fine from the repo root.
Codex genuinely does not.

On-disk lockout store (`~/.claude/cache/dispatch-ledger/quota-lockout-*.json`): codex locked until
`2026-08-08T16:00:00Z`, glm until `2026-08-14T02:57:53Z` — **both expired**, and `_lockout_blocked`
(`resolve:228`) compares against `now`, so neither is blocking anything today.

### 1.2 What is actually happening

Mission question 1 — *why is the fallback chosen at all?* Two mechanisms compose:

**Cause A — an unreadable Codex probe permanently marks Codex blocked.**
`resolve:670-676`:

```python
if quota_codex_pct is None and quota_live_bin:
    quota_codex_pct = live_codex_weekly_pct(quota_live_bin)
quota_known  = quota_codex_pct is not None
codex_blocked = (not quota_known) or _num_ge(quota_codex_pct, threshold)
```

`live_codex_weekly_pct` returns `None` for `status != "ok"` (`resolve:301`). Codex's 401 therefore
resolves as `codex_blocked=True` on **every** dispatch — not during peak, not for a window, but
until somebody re-authenticates the Codex CLI. This is a deliberate prior fix ("quota unknown !=
known-0%") and on its own it is defensible: don't send work to an arm whose admission you cannot
read. It is not, by itself, the GLM-FIRST inversion.

**Cause B — the spill walk explicitly deletes GLM from the candidate chain.** `resolve:694-704`:

```python
blocked = {"codex"} if codex_blocked else set()
if arm in blocked:
    skip = {arm, base_arm} | blocked          # base_arm == "glm" on every build dispatch
    nxt  = [a for a in spill if a not in skip and a in _dispatchable and ...]
    arm  = nxt[0] if nxt else "sonnet"
    rule = "codex_quota_gate_%dpct" % int(threshold)
```

With `spill == ["glm","codex","sonnet"]` and `skip == {"codex","glm"}`, `nxt == ["sonnet"]`.
**Sonnet is not the next-best arm here; it is the only arm left after the primary was deliberately
removed.** GLM's own quota is never read on the build path at all — the build gate reads exactly one
bucket, Codex's.

The two compose into the 90 rows: mission kind matched `codex_fitting_mission_kinds` → arm=codex →
Codex probe unknown → codex blocked → spill skips glm → **sonnet**, forever.

### 1.3 Why the `base_arm` skip is wrong here, specifically

The skip's comment argues that `base_arm` "was already overridden by the precedence rules above —
resurrecting it here would undo that decision." That reasoning is correct for six of the seven
precedence rules and wrong for the seventh:

| precedence rule | what it means about GLM | glm resurrectable? |
|---|---|---|
| `opus_mission_kind` | GLM disqualified by kind | no |
| `safety_gate_publish_payments` | GLM disqualified by safety surface | no |
| `integration_critical_4subsystems` | GLM disqualified by complexity | no |
| `ui_design_judgment` | GLM disqualified by judgment need | no |
| `glm_failed_twice` | GLM disqualified — it already failed | no |
| `glm_lock_busy_no_second_channel` | GLM unavailable | no |
| **`codex_fitting_mission_kind`** | **GLM is fine; Codex merely fits better** | **yes** |

Only the last row is a *preference*, not an *exclusion* — and it is the only row that can reach the
spill walk at all (the other six all resolve to `opus`/`sonnet`/`kimi`, never `codex`, so
`arm in blocked` is false and the walk never runs). The skip set is therefore wrong in **100% of the
cases where it fires**.

### 1.4 Mission question 2 — is there a stale cached verdict?

**No.** `resolve_arm()` is called fresh per dispatch (`leadv2-dispatch-code.sh:3276`), the resolver
holds no state, and the one persistent store (`quota-lockout-*.json`) is TTL-checked against `now`
and currently expired for both providers. There is nothing to invalidate. The "never comes back"
is not staleness — it is a **structural** exclusion (Cause B) plus a **permanently** unknown reading
(Cause A). Fix those two and recovery is automatic and needs no new machinery: the next lane
re-resolves from live conditions, because it already does.

This matters for scope: **do not build a re-evaluation timer, a decision cache, or a recovery
daemon.** They would be solving a problem that does not exist.

### 1.5 Mission question 3 — legibility

`rule=codex_quota_gate_80pct` names a rule that fired. It does not say Codex read `unknown` rather
than `91%`, and it does not say GLM was at 2%/40% and was skipped anyway. A lead reading the journal
cannot tell a correct peak-hour fallback from a stuck-401 inversion — which is exactly why 90 rows
accumulated unremarked.

---

## 2. Design

Four changes, all inside the one resolver plus one journal line. No new files on the runtime path,
no new state, no timers.

### C1 — classify the precedence override as exclusion vs preference

In `resolve_glm_policy`, extend the `rules` table with a `glm_excluded` boolean per row (True for
the six exclusion rows, **False** for `codex_fitting_mission_kind`), and carry the fired row's value
in a local `glm_excluded` (default `False` when no rule fired). Derive it from the rules table, not
from a rule-name string comparison — no hand-kept arm or rule list outside the table that already
governs precedence.

In the spill walk:

```python
skip = {arm} | blocked
if glm_excluded:
    skip.add(base_arm)
```

Effect: `codex_fitting` + codex blocked → spill yields `glm`. Every other path is byte-identical.

### C2 — a known-hot GLM still steps aside (symmetry, no hardcoded list)

C1 alone would route to GLM even if GLM were at 99%. Since the gate path is already paying for
readings (C3), filter the spill chain by each candidate's *known* reading:

- candidate's live pct is **known and ≥ the build threshold** → skip it;
- candidate's live pct is **unknown** → keep it eligible (the resolver's stated posture: an
  unmeasured bucket beats an outage) — **except** `codex`, whose unknown-blocks semantics
  (`resolve:672-676`, a prior deliberate BLOCKING fix) is preserved unchanged;
- `sonnet` remains the terminal arm and is never filtered out — the chain must never empty.

Reuse the existing `live_glm_pct` / `live_anthropic_pct` / `live_codex_weekly_pct` readers and the
existing `_lockout_blocked` store. Threshold comes from `gate["build_threshold_pct"]`; no new
constants, no arm names introduced anywhere but the spill order that is already in YAML.

### C3 — say what the world looked like

Add an **additive** resolver output line, emitted only when the gate block evaluated and
`codex_blocked` is true (so the cost lands only on the already-degraded path):

```
readings=glm=2% codex=unknown anthropic=44%
```

Each reading taken once per process and memoised. `arm=`, `rule=`, `reason=`, `tier=`,
`codex_quota_blocked=` stay **byte-identical** — router.sh passes `reason` through verbatim
(`router.sh:595-609`) and the bandit special-cases `glm_default`, so changing those strings has
blast radius; adding a line does not. Callers that don't parse `readings=` are unaffected.

`leadv2-dispatch-code.sh` parses the new line the same way it parses the others (`sed -n
's/^readings=//p'`) and appends it to the journal emit at `:3292`:

```
arm_resolved job=build arm=glm reason=codex_quota_gate_80pct readings=glm=2% codex=unknown anthropic=44%
```

Absent line → the emit is byte-identical to today.

### C4 — router.sh import-mode parity

`leadv2-router.sh:248` calls `resolve_glm_policy` in-process. It inherits C1/C2 for free. Confirm it
either surfaces or ignores `readings` without breaking; if the function returns a new dict key, a
caller that only reads known keys is unaffected. Expected: **no edit needed** — verify, don't
change speculatively.

### Data flow (numbered)

1. `leadv2-dispatch-code.sh:resolve_arm()` builds `signals_json` from `DC_*` env, calls
   `leadv2-glm-policy-resolve.py --job build --base-arm glm`.
2. Resolver loads `glm_policy` from the routing YAML (tenant → plugin-local → canonical self-heal).
3. Precedence table runs → `(arm, rule, reason, glm_excluded)`.
4. Gate block (only if `codex_quota_gate:` present in YAML): read Codex live pct → `codex_blocked`.
5. If `arm in blocked`: walk `build_spill_order`, skipping the blocked arm, the current arm,
   `base_arm` **only when `glm_excluded`**, non-dispatchable arms, review exclusions when
   `job=="review"`, and any candidate with a *known* over-threshold reading.
6. Emit `arm=/rule=/reason=/tier=/codex_quota_blocked=` unchanged, plus `readings=` when the gate
   fired.
7. `dispatch-code.sh` journals `arm_resolved … readings=…`.

### Interface contract

| surface | before | after |
|---|---|---|
| resolver stdout `arm=` | `sonnet` on codex_fitting+blocked | `glm` (when GLM readable/under threshold) |
| resolver stdout `rule=` | `codex_quota_gate_80pct` | unchanged |
| resolver stdout `reason=` | `codex_quota_gate` | unchanged |
| resolver stdout `readings=` | absent | `glm=<pct|unknown> codex=… anthropic=…`, gate-path only |
| `resolve_glm_policy()` return | `{arm,rule,reason,tier,codex_quota_blocked,job}` | + `readings` (additive key) |
| journal `arm_resolved` | `… reason=<rule>` | `… reason=<rule> [readings=…]` |

No DB, no schema, no migration — this repo is bash + Python + markdown.

---

## 3. Risks and mitigations

| # | risk | mitigation |
|---|---|---|
| R1 | `test-kimi-spill-resolve.py` asserts the kimi-before-codex spill outcome; with GLM re-admitted, `[glm,kimi,codex,sonnet]` + codex blocked now yields **glm**, not kimi. | This is the intended GLM-FIRST semantic, not a regression. Update that test's expectation **and** state the change in the report — do not silently rewrite it. |
| R2 | Re-admitting GLM sends work to an arm that is itself exhausted → stall instead of downgrade. | C2: a known ≥threshold GLM reading skips it; unknown keeps it eligible (primary arm, outage-beats-unmeasured). |
| R3 | Two extra 10s-timeout subprocesses per build dispatch. | Readings computed only when the gate evaluated **and** `codex_blocked`; memoised per process. Happy path (`arm=glm reason=none`, 358 of 536 rows) pays nothing. |
| R4 | Changing `reason=`/`rule=` would break router.sh pass-through and the bandit's `glm_default` special-case. | Explicitly out of scope — `readings=` is additive only. |
| R5 | Fix lands only in canonical; a consuming repo keeps a stale copy. | Plugin-owned files are per-file symlinks to `~/Projects/leadv2`. Verify with `ls -l` on persona-engine's copy; never create a real copy. Hook cache is not involved (no hook changes). |
| R6 | The underlying Codex 401 is unfixed, so `codex=unknown` persists. | Out of scope for this lane (it is a re-login, not code) — but after this fix an unknown Codex reading costs nothing: lanes go to GLM, which is the founder's primary. The `readings=` line makes the 401 visible for the first time. |
| R7 | Resolver is large (913 lines) and edited under `LEADV2_LEAD_GUARD` restrictions. | Implementer edits canonical directly; if the Edit tool is guarded, fix-forward via a `/tmp` patcher + Bash (see memory `lead-edit-guard-canonical-edit`). |
| R8 | Review path regression (`job=="review"`, base_arm codex, glm in `review_arm_exclusions`). | The `job=="review" and a in exclusions` filter in the walk is untouched; C1's `skip.add(base_arm)` only relaxes for build's `codex_fitting` row. Add a regression test asserting review never resolves glm. |

---

## 4. Non-goals (explicit — implementer must ignore)

- **No** decision cache, re-evaluation timer, cron, or recovery daemon. §1.4 proves nothing is
  cached; per-dispatch re-resolution already exists.
- **No** change to `arm=`/`rule=`/`reason=`/`tier=`/`codex_quota_blocked=` string values.
- **No** hardcoded arm exclusion or hand-kept arm list. Spill order stays YAML-driven.
- **No** change to `_lockout_blocked`, the lockout store schema, or its TTL semantics — verified
  correct and currently expired.
- **No** change to `resolve_review_pool`, the review threshold, `review_arm_exclusions`, or the
  kimi probe gate.
- **No** reversal of the "unknown Codex quota blocks Codex" fix (`resolve:672-676`).
- **No** re-authentication of the Codex CLI, no credential work, no deploy, no merge, no touching
  `docs/leadv2/open-threads.md`.
- **No** router-v2 (`LEADV2_ROUTER_V2`) path changes — it overwrites `rule=router_v2` and did not
  produce the observed rows.

---

## 5. Tests (implementer writes these)

New `plugins/leadv2/scripts/tests/test-glm-first-recovery.sh` (bash, stub `--quota-live` script for
deterministic readings, same harness shape as `test-codex-quota-gate.sh`):

1. `codex_fitting` kind + codex reading **unknown** + glm `ok/2%` → `arm=glm`, `rule=codex_quota_gate_80pct`, `readings=` contains `codex=unknown` and `glm=2%`.
2. `codex_fitting` + codex **91%** + glm ok → `arm=glm` (the recovery case at peak).
3. `codex_fitting` + codex unknown + **glm 95%** → `arm=sonnet` (R2 guard holds).
4. `codex_fitting` + codex **44%** → `arm=codex` (gate does not fire; unchanged).
5. `safety_gate_publish_payments` + codex unknown → `arm=sonnet` (exclusion row still excludes GLM).
6. `job=review`, base_arm codex, codex blocked → `arm=sonnet`, never `glm` (R8).
7. No `codex_quota_gate:` in YAML → output byte-identical to pre-change (v1 equivalence).
8. Happy path (`no rule fired`) → `arm=glm rule=none`, **no** `readings=` line, no quota subprocess.
9. `dispatch-code.sh` emit: with `readings=` present the journal line carries it; absent → byte-identical.

Plus: update `test-kimi-spill-resolve.py` per R1, and re-run `test-dispatch-arm-vocabulary.sh`,
`test-plan-arms-role-scoped.sh`, `test-review-arm-pool.sh`, `test-codex-quota-gate.sh` green.

---

## 6. Mandatory constraint checklist

1. **Env vars** — no new env vars introduced. Existing reads (`LEADV2_QUOTA_LOCKOUT_DIR`,
   `LEADV2_DISPATCH_KIMI_BIN`, `LEADV2_QUOTA_NOW_EPOCH`, `LEADV2_DISPATCH_CACHE_DIR`) all carry the
   `LEADV2_` prefix; no `LEAD_V2_` drift. **PASS.**
2. **File paths** — every path in §7 verified on disk except the new test file, marked `(to-create)`.
   **PASS.**
3. **`claude -p` commands** — none introduced by this design. **N/A.**
4. **Concurrent access** — the resolver is read-only against the routing YAML and the lockout store;
   the lockout writer uses `tmp + mv -f` (atomic rename, `dispatch-code.sh:1023-1031`). No new write
   surface, no lock needed. **PASS.**
5. **Config contradiction** — `build_threshold_pct` (default 80.0) is reused for the C2 candidate
   filter, the same threshold the Codex gate uses. Same units (percent, 0-100) across
   `live_glm_pct` / `live_codex_weekly_pct` / `live_anthropic_pct`. No contradiction. **PASS.**

---

## 7. Files

| path | exists | change |
|---|---|---|
| `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` | yes | C1, C2, C3 |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | yes | C3 — parse + journal `readings=` |
| `plugins/leadv2/scripts/leadv2-router.sh` | yes | C4 — verify parity; edit only if the import-mode caller breaks |
| `plugins/leadv2/scripts/tests/test-glm-first-recovery.sh` | **(to-create)** | new suite, §5 cases 1-9 |
| `plugins/leadv2/scripts/tests/test-kimi-spill-resolve.py` | yes | update expectation per R1 |

---

acceptance:
  - surface: log_line
    observable: >
      A build lane dispatched while the Codex quota probe is unreadable writes, in its task
      journal, an `arm_resolved job=build arm=glm` line whose trailing `readings=` field shows
      `codex=unknown` alongside GLM's live percentage — the founder reads the journal and sees
      the lane went to GLM, and sees the three readings that decided it.
    authored_at: 2026-08-15T20:40:00Z
  - surface: file_artifact
    observable: >
      `docs/handoff/GLM-FIRST-RECOVERY-01/report.md` shows, side by side, the resolver output for
      the same mission before and after the change: `arm=sonnet` before, `arm=glm` after, with the
      Codex reading unknown in both — and a second pair showing the lane still choosing Sonnet when
      GLM's own reading is over threshold.
    authored_at: 2026-08-15T20:40:00Z

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-router.sh, plugins/leadv2/scripts/tests/test-glm-first-recovery.sh, plugins/leadv2/scripts/tests/test-kimi-spill-resolve.py

DELIVERABLE_COMPLETE
