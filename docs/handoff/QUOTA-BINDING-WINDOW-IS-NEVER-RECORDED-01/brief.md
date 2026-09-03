# QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01 — implementation brief (WRITE side)

**Purpose (re-aimed 2026-09-03):** the consumer is the **arbiter**, not an analyst — it must read, **per account**, which window is currently binding and when it resets, so it can spread work across two non-pooling buckets. The subscription decision is already made (Max 20x cancelled, personal account → Max 5x effective **2026-09-15**), so that 5-hour ceiling drops 4× in twelve days. History stays valuable — it is the only way to see whether the downgrade actually moved the binding window — but it is now the *secondary* consumer. Sibling lane **CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01** owns the READ side (§6 is our contract); it does not touch these files, this lane does not touch its files.

## 1. Verified facts (on disk, 2026-09-03)

| Fact | Evidence |
|---|---|
| Writer overwrites one row, **active account only** | `leadv2-ratelimit-probe.sh:118` `INSERT OR REPLACE INTO kv …`; adapter picks `next((a for a in accounts if a.get("active")), …)` at `:79` |
| Writer already has `BEGIN IMMEDIATE`, `PRAGMA busy_timeout=3000`, `connect(timeout=5)`, block ends `\|\| true` | probe `:110-124` |
| Writer owns its own DDL; history.db's real schema owner (`turn_events`,`hourly`,`cold_returns`,`schema_version`) is **not in this repo** (`grep "CREATE TABLE IF NOT EXISTS turn_events"` = 0 hits) | probe `:114` |
| Probe fully test-injectable | `LEADV2_QUOTA_LIVE_SH`, `LEADV2_BURN_DB`, `LEADV2_RATELIMIT_PROBE_NOW` (probe `:26-37`) |
| **4 kv readers, only 3 order** | `leadv2-quota-read.py:355`, `leadv2-status-surface.sh:2312`, `leadv2-limits-refresh.sh:142` use `ORDER BY rowid DESC LIMIT 1`; **`leadv2-quota-status.sh:141` = `SELECT value FROM kv WHERE key='rate_limit_anthropic';` — no ORDER BY, no LIMIT** |
| **`account_label` is TIER-derived, not identity-derived** — returns `max_20x`/`max_5x` from `subscription_type`/`tier` | `leadv2-quota-read.py:389-401` |
| Stable per-account discriminator exists upstream | `leadv2-quota-read.py:475-487`: `entry_suffix` (`default`\|`file`\|keychain-service suffix) + `service`, alongside `account_label` |
| Probe-rate ceiling | `leadv2-limits-refresh.sh:57` `LEADV2_LIMITS_TTL_CLAUDE:-90` → ≤960 probes/day |
| Existing kv test uses a from-scratch fixture DB (only `turn_events`+`kv`), plain `INSERT INTO kv` | `tests/test-quota-weekly-total.sh:42-49,137` |
| sqlite window functions OK | local 3.51; need ≥3.25; bookworm 3.40 → container-safe. `docs/handoff/*/brief*.md` is git-tracked (`.gitignore:49-51`) |

Coordinator correction absorbed: `~/.claude/config/leadv2-quota-ceilings.sh` was missing until 20:04 today (now symlinked to `plugins/leadv2/config/leadv2-quota-ceilings.sh`; claude 95/95, glm 80/90, codex 90/95) and three gates failed open silently. **Nothing here was measured from gate behaviour** — every measurement above is of the probe, the four kv readers, and the test fixtures, so none is invalidated. Ceilings bind the arbiter's threshold, which is the sibling lane's side.

## 2. D1 — Storage: NEW TABLE `rate_limit_history`. Do **not** make `kv` append-only.

1. **`leadv2-quota-status.sh:141` would silently read the OLDEST capture.** With no `ORDER BY`/`LIMIT` sqlite3 returns every matching row on its own line; `RL_RAW` goes multi-line and the `sed … | head -1` parses at `:145-149` bind to the **first** line → `captured_epoch` permanently stale → `RL_FRESH=0` → `RL_CAP_BASIS` falls back to `heuristic_estimate` and the `provider_reset` weekly basis dies. A silent regression of the exact gauge this task exists to fix.
2. `kv.key` is `TEXT PRIMARY KEY`; append-only means dropping the PK = full rebuild of a DB whose schema owner is outside this repo, on the founder's laptop, with a concurrent aggregator writing.
3. Per-account rows make it worse: one kv key cannot carry two accounts without inventing a key convention all four readers would have to learn.

A new table changes **zero bytes** of the four reader queries. That is the design's whole point.

## 3. D2 — Account identity: key on `account_key`; `account_label` is an observed attribute

`account_label` is computed from `subscription_type`/`tier` (`leadv2-quota-read.py:389-401`), so on **2026-09-15 the same credential's label flips `max_20x` → `max_5x`.** Keying history on the label would make the downgrade read as "one account vanished, another appeared", break every join across the boundary, and **collide** two distinct accounts that share a tier — exactly the two-buckets case the arbiter must keep apart.

- **`account_key` = `entry_suffix` (fall back to `service` when the suffix is empty).** Stable across a tier change, non-secret (a keychain *entry* discriminator, never a credential value).
- **`account_label`** stays a recorded column: the tier *at capture time* — precisely the signal that shows the 09-15 downgrade in history.
- Never fabricate: no `entry_suffix`/`service` → `account_key='unknown'`, asserted by the suite. Do not synthesise a key from the label.
- **One row per account per probe**, from the full `accounts[]` array — not only the `active` one. Active is a boolean column, never a filter.

## 4. D3 — Schema, indexes, retention

```sql
CREATE TABLE IF NOT EXISTS rate_limit_history (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  captured_epoch        INTEGER NOT NULL,  -- probe's own NOW_EPOCH
  account_key           TEXT NOT NULL,     -- STABLE identity (entry_suffix); 'unknown' if absent
  account_label         TEXT,              -- tier AT CAPTURE TIME (max_20x|max_5x|…) — a label, never an id
  is_active             INTEGER NOT NULL DEFAULT 0,
  state                 TEXT,              -- ok | unauthenticated | unreachable
  status                TEXT,
  overage_status        TEXT,
  five_hour_pct         REAL,
  five_hour_reset_iso   TEXT,
  five_hour_reset_epoch INTEGER,           -- PRECOMPUTED at write time
  seven_day_pct         REAL,
  seven_day_reset_iso   TEXT,
  seven_day_reset_epoch INTEGER,           -- PRECOMPUTED at write time
  binding_window        TEXT,              -- five_hour | seven_day | NULL
  source                TEXT               -- 'ratelimit-probe' | 'seed:kv'
);
CREATE INDEX IF NOT EXISTS rate_limit_history_acct  ON rate_limit_history(account_key, captured_epoch DESC);
CREATE INDEX IF NOT EXISTS rate_limit_history_epoch ON rate_limit_history(captured_epoch);
```

- `*_reset_epoch` is precomputed **because the hot path is bash on macOS**: `date -d` is GNU-only and parsing ISO-8601 in bash 3.2 is exactly the trap this repo has hit before. The arbiter must get `reset_in_s` from one integer subtraction.
- `rate_limit_history_acct` is the **hot-path index**: `WHERE account_key=? ORDER BY captured_epoch DESC LIMIT 1` becomes an index seek (O(log n), sub-ms at 90k rows). `rate_limit_history_epoch` serves the retention prune and the historical scan.
- **No second "current" table.** The composite index makes the point lookup fast enough; a second table doubles the write path and adds a divergence surface for no measured gain.
- No `UNIQUE`: tests pin `LEADV2_RATELIMIT_PROBE_NOW`, and a constraint violation inside `BEGIN IMMEDIATE` would abort the kv upsert too. Dedupe is policy (§5), not a constraint.
- pct columns nullable: `unauthenticated`/`unreachable` captures are real signal (probe `:50-55`,`:103`).

**Volume:** ceiling 960 probes/day × 2 accounts = 1920 rows/day worst case; with §5 dedupe ≈ **250–500 rows/day** (~160 B/row ≈ 60 KB/day). **Retention 180 days** (`LEADV2_RATELIMIT_HISTORY_RETAIN_DAYS`, default 180) → ≤90k rows / ≤15 MB against a 12.6 MB DB today. Prune = an indexed range `DELETE` in the same transaction, normally matching 0 rows. No cron, no timer.

## 5. D4 — Write path (inside the probe's existing python block, function-shaped)

One `BEGIN IMMEDIATE`, the **existing** connection, in this order:

1. `CREATE TABLE IF NOT EXISTS rate_limit_history …` + both indexes (writer owns its DDL — §1).
2. Seed (§8) — **before** the kv upsert.
3. `INSERT OR REPLACE INTO kv …` — byte-identical to today (kv keeps carrying the ACTIVE account only).
4. `_append_history(conn, rows)` — a **module-level python function**, not inline script code. Hard requirement: the negative control (§10) must be insertable *inside a function body*. Body = per account row: read that account's previous row → compute `should` → insert → prune.
5. `conn.commit()`.

Dedupe is **per `account_key`**:

```
should = _should_append(prev, row)
# True when prev is None, OR any of (state, binding_window, account_label,
# five_hour_pct, seven_day_pct) differs, OR row.captured_epoch - prev.captured_epoch >= HEARTBEAT_S
```

`HEARTBEAT_S` = `LEADV2_RATELIMIT_HISTORY_HEARTBEAT_S`, default **900** — heartbeats keep §7's time-weighting honest and keep the hot-path row fresh when nothing moves. `account_label` is in the change set on purpose: the 09-15 tier flip must produce a row.

Failure posture unchanged: keep the `|| true`; the probe still prints `$KV_JSON`. A history write must never be able to fail a probe.

## 6. D5 — Hot-path contract with CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01

That lane's "source of truth for remaining budget and reset time" for the `claude` arm is **`~/.claude/burn/history.db` → `rate_limit_history`** (`LEADV2_BURN_DB` honoured). Read-only, one statement per decision:

```sql
SELECT account_key, account_label, is_active, state, binding_window,
       five_hour_pct, five_hour_reset_epoch, seven_day_pct, seven_day_reset_epoch, captured_epoch
  FROM rate_limit_history
 WHERE account_key = ?            -- one bucket; repeat per key for the full picture
 ORDER BY captured_epoch DESC, id DESC LIMIT 1;
```

Semantics both lanes agree on — neither re-invents a shape:

| Field | Meaning for the arbiter |
|---|---|
| `account_key` | stable bucket identity; **two rows with different keys = two non-pooling budgets** |
| `account_label` | tier at capture (`max_20x`/`max_5x`) — display + tuning only, **never a join key** |
| `binding_window` | which window is closest to its ceiling now: `five_hour` \| `seven_day` \| NULL |
| `five_hour_pct` / `seven_day_pct` | 0–100 utilisation; `NULL` = unmeasured, **never treat as 0** |
| `*_reset_epoch` | absolute unix seconds; `reset_in_s = reset_epoch - now` |
| `captured_epoch` | freshness basis; `age_s = now - captured_epoch` |
| `state` | only `ok` carries usable pcts; anything else = unmeasured |

**Staleness rule (mandatory on the read side):** if `state <> 'ok'` OR `age_s > LEADV2_RATELIMIT_HISTORY_MAX_AGE_S` (default **600**), treat the account as **UNMEASURED** and fall back to existing behaviour — never as "0% used". Same doctrine as `RL_FRESH` (`leadv2-quota-status.sh:150-157`). Missing table / zero rows → UNMEASURED, exit 0, never an error. This lane guarantees the write shape and the freshness stamp; it does **not** decide the wait-vs-switch rule.

## 7. D6 — Historical query (secondary consumer, kept)

New script **`plugins/leadv2/scripts/leadv2-quota-window-history.sh` (to-create)**: `--days N` (regex-gated `^[0-9]+$`, default 14), `--account <key>`, `--json`. bash 3.2 safe — no arrays, no `${x^^}`, no `date -d`; all work in `sqlite3`.

```sql
WITH s AS (
  SELECT captured_epoch, state, account_key, binding_window, five_hour_pct, seven_day_pct,
         LEAD(captured_epoch) OVER (PARTITION BY account_key ORDER BY captured_epoch) AS next_epoch
    FROM rate_limit_history
   WHERE captured_epoch >= strftime('%s','now') - (30 * 86400)
), w AS (
  SELECT *, MIN(COALESCE(next_epoch - captured_epoch, 0), 1800) AS dwell
    FROM s WHERE state = 'ok'
)
SELECT account_key,
       COALESCE(binding_window,'(none)')                             AS window,
       COUNT(*)                                                      AS samples,
       SUM(dwell)                                                    AS dwell_s,
       ROUND(100.0*SUM(dwell)/NULLIF(SUM(SUM(dwell)) OVER (PARTITION BY account_key),0),1) AS dwell_pct,
       ROUND(MAX(five_hour_pct),1)                                   AS max_5h_pct,
       ROUND(MAX(seven_day_pct),1)                                   AS max_7d_pct
  FROM w GROUP BY account_key, 2 ORDER BY account_key, dwell_s DESC;
```

`PARTITION BY account_key` everywhere — dwell must never be computed across two accounts' samples. The 1800s cap (2× heartbeat) is the anti-lying clause: a laptop asleep 12 h must not score as 12 h of "seven_day binding". Peak-with-timestamp is one query per window, each wrapped as `SELECT * FROM (SELECT … ORDER BY <pct> DESC, captured_epoch DESC LIMIT 1)` — in a compound SELECT an un-nested `ORDER BY`/`LIMIT` binds to the whole compound. Always print a coverage line (`COUNT(*)`, `MIN`/`MAX(captured_epoch)`); if span < 7 days or samples < 50, print `INSUFFICIENT HISTORY — <n> samples over <d>d` **before** the tables and exit 0. **Post-2026-09-15 use:** compare `dwell_pct` for the same `account_key` before and after its label flips to `max_5x` — that is the measurement of whether the downgrade moved the binding window.

## 8. D7 — Backfill: seed the one historical row

Same transaction, **before** step 3, only when `SELECT 1 FROM rate_limit_history LIMIT 1` is empty: parse the *pre-existing* kv value and insert it with its own `captured_epoch`, `source='seed:kv'`, `is_active=1`. It carries no `entry_suffix`, so `account_key='unknown'` and `account_label` from the blob (`max_20x` today) — do **not** guess a key. Idempotent by construction. Ordering matters: seeding after the upsert would copy the row we just wrote. kv absent/unparseable → skip silently. Nothing else is backfilled; inventing history is the lying-green disease.

## 9. D8 — Concurrency

- **Reuse the existing connection and `BEGIN IMMEDIATE`.** A second connection from the same process would block on the write lock this process holds → `database is locked` after the timeout.
- Keep `connect(timeout=5)` + `PRAGMA busy_timeout=3000`. Two INSERTs + one indexed DELETE add microseconds to a lock the out-of-repo aggregator already tolerates.
- **Do NOT set `journal_mode=WAL`** or any persistent PRAGMA — journal mode is database-global and shared with that aggregator. Cross-process hazard, out of scope.
- Both readers open **read-only** (`file:…?mode=ro`) and never take a write lock.

## 10. MANDATORY negative control

- **Suite (to-create):** `plugins/leadv2/scripts/tests/test-leadv2-ratelimit-probe.sh` — this exact name self-selects under `tests/run-all.sh --scope changed`: the stem loop (`tests/run-all.sh:519-539`) derives `stem="leadv2-ratelimit-probe"` from a `plugins/leadv2/scripts/*.sh` change and probes `plugins/leadv2/scripts/tests/test-${stem}.sh`. **Add one `EXTRA_SUITE_MAP` row** (`tests/run-all.sh:134`) so a reader-only change also selects it: `leadv2-quota-window-history.sh:plugins/leadv2/scripts/tests/test-leadv2-ratelimit-probe.sh`. Prove both by pasting `tests/run-all.sh --scope changed` output.
- **Control 1 — the history insert (inside a function body; one line, no newline in the replacement, so BSD+GNU sed safe):** `sed -i 's/^    should = _should_append(prev, row)$/    should = False/'` on `plugins/leadv2/scripts/leadv2-ratelimit-probe.sh`. Reverts the history insert to a no-op *inside* `_append_history` while the kv upsert and stdout JSON stay intact — i.e. exactly today's behaviour. **The suite must go red.** Still green ⇒ the suite asserts on the kv row or on string presence, not on recorded history.
- **Control 2 — account keying (the new load-bearing decision):** `sed -i "s/^    key = row\[.account_key.\]$/    key = 'unknown'/"` collapses both accounts onto one key; the two-account fixture must go red.
- **Control 3 — read path:** mutate `MIN(COALESCE(next_epoch - captured_epoch,0),1800)` → `COALESCE(next_epoch - captured_epoch,0)`; the asleep-laptop fixture must go red.
- **Proof format — do NOT cite `diff_hash`.** Known open defect **MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01**: `diff_hash` records the SHA-256 of the empty string. Until its blast radius is counted, the accepted proof is the **pair of exit codes (baseline_rc=0 / mutated_rc≠0) plus the literal red suite line**, copied verbatim into the report. Run each control through `plugins/leadv2/scripts/leadv2-mutation-control.sh <suite> <file> '<sed>' docs/handoff/QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01` and attach the artifact — but cite the exit codes and the FAIL line, never the hash. Tool exit 1 (`mutant_survived`) or 2 (`control_not_applied`) = not done.

**Minimum assertions** (fixture DB built like `test-quota-weekly-total.sh:42-49` — only `kv`, no `rate_limit_history`, so the writer must create it; fake `leadv2-quota-live.sh` via `LEADV2_QUOTA_LIVE_SH` emitting a **two-account** `accounts[]`; epochs pinned via `LEADV2_RATELIMIT_PROBE_NOW`):

1. `bash -n` on both scripts.
2. Two probes with different pcts → row count grows by one **per account** per probe. **← control 1 kills this.**
3. Two accounts in one probe → two rows, distinct `account_key`, exactly one `is_active=1`. **← control 2 kills this.**
4. kv still has exactly ONE row for the key, value == newest ACTIVE-account probe JSON (no-regression lock on `:141`).
5. Identical readings inside the heartbeat → no new row; epoch advanced past `HEARTBEAT_S` → new row.
6. Tier flip (`max_20x`→`max_5x`) at the same key, same pcts → a row IS appended and `account_key` is unchanged.
7. `*_reset_epoch` equals the epoch of `*_reset_iso`; a malformed ISO → `NULL`, not 0, not `now`.
8. Hot-path query returns the newest row per `account_key`; a fixture whose newest row is 20 min old reports UNMEASURED (`MAX_AGE_S=600`), not 0%.
9. Historical query: known 5h/7d mix → expected per-account `dwell_pct` split and peaks; asleep-laptop fixture is dwell-capped. **← control 3 kills this.**
10. Reader against a DB with no `rate_limit_history` → exit 0 + "no history yet".
11. Retention: row at `now-200d` pruned after one probe; row at `now-100d` survives.
12. Seed: pre-existing kv + empty history → one `source='seed:kv'` row with `account_key='unknown'`; a second probe does not re-seed.

## 11. Hard constraints (restate in the lane mission)

- **Do NOT touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh`** — owned by another lane.
- **Do NOT touch the CLASSIFIER lane's files.** This lane owns the WRITE side and §6's shape; that lane owns the READ side and the wait-vs-switch rule.
- **Do NOT modify the four kv reader queries** (`leadv2-quota-read.py:355`, `leadv2-quota-status.sh:141`, `leadv2-status-surface.sh:2312`, `leadv2-limits-refresh.sh:142`) — byte-identical; `test-quota-weekly-total.sh` untouched and green.
- **No credential values.** `account_key` is a keychain *entry* discriminator and `account_label` is a tier label — never an email, token, or keychain blob. No new probe stdout/stderr output.
- **No weakening**, nothing added to `tests/known-red-suites.txt` (`tests/known-red-guard.sh` fails if the count grows).
- **macOS bash 3.2 + linux container:** no `mapfile`/`readarray`, no assoc arrays, no `${x^^}`, no GNU `date -d` (why `*_reset_epoch` is precomputed), no `sed -i ''`/`sed -i` divergence in shipped code. Keep the probe's `command -v sqlite3` guard semantics; all JSON/DB work stays in `python3`.
- **Env naming:** new vars `LEADV2_RATELIMIT_HISTORY_RETAIN_DAYS`, `LEADV2_RATELIMIT_HISTORY_HEARTBEAT_S`, `LEADV2_RATELIMIT_HISTORY_MAX_AGE_S` — `LEADV2_*` prefix, matching `LEADV2_BURN_DB` / `LEADV2_LIMITS_TTL_CLAUDE`; greped, none exists today, so no semantic contradiction. No `claude -p` invocation is introduced, so the `--max-turns` / `--permission-mode bypassPermissions` / `--output-format json` check is N/A.
- **Concurrent access:** `~/.claude/burn/history.db` is written by this probe *and* by the out-of-repo aggregator, and now read on a hot path by the arbiter. Mitigation is §9 (one transaction, existing busy_timeout, no journal-mode change, read-only readers). No new lock file needed or wanted.

## 12. Out of scope (implementer: ignore)

The arbiter's routing decision, the wait-vs-switch rule, any `route_resolved` log line (sibling lane). Fixing `leadv2-quota-status.sh:141` to order its read (separate task — this design makes it unnecessary). Changing `account_label()` in `leadv2-quota-read.py`. Touching the three quota gates or the ceilings file. A SwiftBar/status-surface row. Charting. GLM/Codex/Kimi history (Anthropic only). Moving the DB schema owner into this repo. WAL. Any new timer/cron. Changing probe cadence or `LEADV2_LIMITS_TTL_CLAUDE`. Backfilling beyond the one existing kv row.

DELIVERABLE_COMPLETE
