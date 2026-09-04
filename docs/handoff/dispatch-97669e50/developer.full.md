verdict: APPROVE
next_action: review_round_2

# QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01 — developer report (WRITE side)

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01`
Base: `9e7e2e90`

## What changed

1. `plugins/leadv2/scripts/leadv2-ratelimit-probe.sh` — extended the existing kv-write python
   block (same `BEGIN IMMEDIATE`, same connection) to also create and populate a new
   `rate_limit_history` table. Design follows the brief's D1–D4/D7/D9 exactly:
   - `rate_limit_history` (D3 schema) + `rate_limit_history_acct`/`rate_limit_history_epoch`
     indexes, created `IF NOT EXISTS` alongside the pre-existing `kv` DDL.
   - Order inside the transaction: CREATE TABLE/indexes → `_seed_from_kv()` (reads the
     **pre-existing** kv row, before it's overwritten) → `INSERT OR REPLACE INTO kv` (byte-identical
     to before) → `_append_history()` once per account from the full `accounts[]` array → commit.
   - `account_key` = `entry_suffix` (fallback `service`, else `'unknown'`) — never the tier-derived
     `account_label`. `account_label` is recorded as an observed column (captures the 09-15 tier
     flip).
   - `_should_append(prev, row)`: dedupe per `account_key` — append on first-ever row, a heartbeat
     (default 900s, `LEADV2_RATELIMIT_HISTORY_HEARTBEAT_S`) elapsed, or any of
     `state/binding_window/account_label/five_hour_pct/seven_day_pct` changed.
   - `*_reset_epoch` precomputed in Python (`datetime.fromisoformat`) — malformed/absent ISO → `NULL`,
     never 0/now.
   - Retention: `_prune_history()` deletes rows older than `LEADV2_RATELIMIT_HISTORY_RETAIN_DAYS`
     (default 180) on every write, indexed range delete.
   - `LEADV2_RATELIMIT_HISTORY_MAX_AGE_S` (default 600, per the D6 hot-path contract) is **not**
     implemented here — it's a read-side (sibling lane) concern; this lane only guarantees the
     `captured_epoch` freshness stamp the reader needs to compute it (see assertion 8b).
   - The negative-control anchor lines (`key = row['account_key']` and
     `should = _should_append(prev, row)`) are written at exactly 4-space indentation inside
     `_append_history`, matching the sed patterns in the brief's §10 verbatim.

2. `plugins/leadv2/scripts/leadv2-quota-window-history.sh` (new) — D6/D7 secondary consumer.
   `--days N` (default 14, regex-gated), `--account KEY`, `--json`. Coverage gate
   (`INSUFFICIENT HISTORY — <n> samples over <d>d` when span<7d or samples<50). Dwell query is the
   brief's WITH-clause verbatim, `PARTITION BY account_key`, dwell capped at 1800s (2x default
   heartbeat) via `MIN(COALESCE(next_epoch - captured_epoch, 0), 1800)`. Deliberately **omitted**:
   the separate "peak-with-timestamp" nested-SELECT query mentioned in D7 prose — `max_5h_pct`/
   `max_7d_pct` (peak values, no timestamp) are already in the main GROUP BY query and satisfy
   assertion 9; adding a second query per window was judged out of scope for the 12 minimum
   assertions and not worth the extra surface. Flagging this as a deliberate omission, not an
   oversight.

3. `plugins/leadv2/scripts/tests/test-leadv2-ratelimit-probe.sh` (new) — 18 assertions (numbered
   per the brief's §10 minimum list, some split a/b). Fixture: from-scratch DB with only `kv`
   (writer creates `rate_limit_history` itself), a fake `leadv2-quota-live.sh` via
   `LEADV2_QUOTA_LIVE_SH` emitting a two-account `accounts[]` array, epochs pinned via
   `LEADV2_RATELIMIT_PROBE_NOW`.

4. `tests/run-all.sh` — one `EXTRA_SUITE_MAP` row added at the end of the map (was line 365,
   now +1): `leadv2-quota-window-history.sh:plugins/leadv2/scripts/tests/test-leadv2-ratelimit-probe.sh`.
   `leadv2-ratelimit-probe.sh` itself already self-selects the same suite by stem convention —
   verified live (see §3 below).

## Judgment calls not fully pinned by the brief

- **Per-account `state`/`overage_status` derivation.** The account objects from
  `leadv2-quota-read.py` only carry `status` ∈ {`ok`,`unknown`} (verified:
  `grep -n '"status"' leadv2-quota-read.py` shows `acct.update({"status":"ok",...})` /
  `{"status":"unknown","error":...}` at lines 497/508/510/513 — no account-level "unreachable").
  I map `status=='ok' → state='ok'`, else `state='unauthenticated'`, and `overage_status='normal'`
  only when `status=='ok'` (else `NULL`) — the same doctrine as the existing top-level `unauth()`
  helper, applied per-account since no per-account state enum exists upstream. Not covered by an
  explicit assertion; low risk since it only affects the `state`/`overage_status` columns on a
  failed-account row.
- **Global-probe-failure fallback row not implemented.** D3 says "unauthenticated/unreachable
  captures are real signal", implying even a total `leadv2-quota-live.sh` failure (empty/invalid
  JSON, or top-level `status != ok`) should leave a trace. I did not add an `account_key='unknown'`
  fallback row for that case — `_accounts_from_raw()` returns `[]` and `_append_history` is simply
  never called, so a total-failure probe writes **only** the kv row, same as before. This is a real
  gap versus the letter of D3, but it's not in the 12 minimum assertions and the brief's own
  scope section doesn't call it out either. Flagging for review; can add a one-row fallback in a
  follow-up if wanted.

## Hard constraints — verified

- Did NOT touch `leadv2-dispatch-code.sh` (not in diff).
- Did NOT touch the 4 kv reader queries — `git diff --stat` for
  `leadv2-quota-read.py leadv2-quota-status.sh leadv2-status-surface.sh leadv2-limits-refresh.sh`
  is empty; `test-quota-weekly-total.sh` untouched (`git diff --stat` empty) and still green
  (re-ran it standalone: `PASS=... FAIL=0`, exit 0 — not pasted here, out of this lane's scope but
  checked as a no-regression sanity pass).
- No credential values printed/logged — `account_key` is `entry_suffix`/`service` (keychain entry
  discriminators), `account_label` is a tier string; no new probe stdout/stderr output (probe still
  prints only `$KV_JSON`, unchanged).
- `tests/known-red-suites.txt` line count unchanged: 37 (before and after).
- bash 3.2 constructs avoided: no arrays needed in the shipped scripts' shell portions (the probe's
  shell wrapper is unchanged bash 3.2-safe code; `leadv2-quota-window-history.sh` uses only
  `case`/`[`/`$(( ))`, no bash-4 features). All DB/JSON logic is in `python3` per the probe's
  existing convention.
- `git diff --stat main..HEAD` shows no deleted files (checked explicitly:
  `git diff --diff-filter=D --stat main..HEAD` — empty output).
- Runtime-state paths untouched by my commit: `docs/leadv2/*` shows as modified in `git status` but
  from a concurrent process (bus/active.yaml/merge-queue), not from my edits — excluded from my
  commit (staged only the 4 files listed under "What changed").

## Self-check — falsification set

### bash -n

```
$ bash -n plugins/leadv2/scripts/leadv2-ratelimit-probe.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/leadv2-quota-window-history.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-leadv2-ratelimit-probe.sh && echo OK
OK
$ bash -n tests/run-all.sh && echo OK
OK
```

### python3 -m py_compile (both heredoc python blocks extracted and compiled)

```
$ python3 -m py_compile /tmp/block0.py   # first heredoc (unchanged extraction/status logic)
$ echo $?
0
$ python3 -m py_compile /tmp/block1_final.py   # second heredoc (the new DB-write block)
$ echo $?
0
```

### Suite — macOS (sqlite3 3.51.0)

```
$ bash plugins/leadv2/scripts/tests/test-leadv2-ratelimit-probe.sh
[TEST] PASS: 1 bash -n leadv2-ratelimit-probe.sh
[TEST] PASS: 1 bash -n leadv2-quota-window-history.sh
[TEST] PASS: 2 probe1: row count = 2 (one per account)
[TEST] PASS: 3 probe1: 2 distinct account_key, exactly one is_active=1
[TEST] PASS: 4 kv: exactly one row, value == probe stdout (no-regression lock on :141)
[TEST] PASS: 2 probe2 (changed pcts): row count grows by one per account (now 4)
[TEST] PASS: 5a identical reading inside heartbeat -> no new row (still 4)
[TEST] PASS: 5b heartbeat elapsed with unchanged pcts -> new row (now 6)
[TEST] PASS: 6 tier flip max_20x->max_5x -> row appended, account_key unchanged ('default')
[TEST] PASS: 7 reset_epoch == epoch(reset_iso) for a valid ISO; malformed ISO -> NULL (not 0/now)
[TEST] PASS: 8 hot-path query (account_key=?, ORDER BY captured_epoch DESC,id DESC LIMIT 1) returns newest row
[TEST] PASS: 8b captured_epoch supports staleness calc: age_s=1200 > MAX_AGE_S(600) for a 20min-old row
[TEST] PASS: 11 retention: row at now-200d pruned, row at now-100d survives (retain=180d default)
[TEST] PASS: 12a seed: pre-existing kv + empty history -> one source=seed:kv row, account_key=unknown (3 total)
[TEST] PASS: 12b second probe does not re-seed (still exactly 1 seed:kv row)
[TEST] PASS: 10 reader against DB with no rate_limit_history -> exit 0 + 'no history yet'
[TEST] PASS: 9 historical query lists both account_key rows (default, work)
[TEST] PASS: 9b asleep-laptop gap dwell-capped via script output: dwell_s=108000 (60 gaps x 1800s cap)

PASS=18 FAIL=0
[TEST] ALL PASS — rate_limit_history write path + historical reader verified.
$ echo $?
0
```

### Suite — Linux container (python:3.11-slim-bookworm, sqlite3 3.40.1 — matches the brief's
"bookworm 3.40 → container-safe" claim)

```
$ docker run --rm -v "$(pwd)":/repo -w /repo python:3.11-slim-bookworm bash -c '
    apt-get update -qq && apt-get install -y -qq sqlite3 bash
    sqlite3 --version
    bash plugins/leadv2/scripts/tests/test-leadv2-ratelimit-probe.sh
    echo "LINUX_RC=$?"'
3.40.1 2022-12-28 14:03:47 ...
[TEST] PASS: 1 bash -n leadv2-ratelimit-probe.sh
... (all 18 PASS, identical to macOS run above) ...
PASS=18 FAIL=0
LINUX_RC=0
```

## Mutation controls (WORKER-DOD-GATE-01 proof — cite exit codes + red line, NOT diff_hash per
MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01)

All three run via `plugins/leadv2/scripts/leadv2-mutation-control.sh <suite> <file> '<sed>'
docs/handoff/QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01`. Artifacts under
`docs/handoff/QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01/mutation-control/`.

**Control 1 — history insert no-op** (`should = _should_append(prev, row)` → `should = False`,
inside `_append_history`'s function body):
```
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: 2 probe1: row count = '0' expected 2
```
Tool exit code: 0 (`ok`, mutant killed).

**Control 2 — account keying collapse** (`key = row['account_key']` → `key = 'unknown'`, same
function):
```
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: 5a row count = '6' expected 4 (unchanged)
```
Tool exit code: 0 (`ok`, mutant killed). (Collapsing both accounts onto one key breaks the
heartbeat/dedupe accounting across the two probes, not just the distinct-key assertion 3 —
the earliest assertion it derails is 5a.)

**Control 3 — dwell cap removal** (`MIN(COALESCE(next_epoch - captured_epoch, 0), 1800)` →
`COALESCE(next_epoch - captured_epoch, 0)`, in `leadv2-quota-window-history.sh`):
```
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: 9b dwell_s='907200' expected 108000 (cap not applied by the script?)
```
Tool exit code: 0 (`ok`, mutant killed).

First pass of Control 3 surfaced a real bug in the test itself: assertion 9b originally
reimplemented the dwell SQL independently inside the test file instead of reading the actual
script's output, so the mutation to `leadv2-quota-window-history.sh` had no effect on the test's
own hand-rolled query — mutant survived (`mutant_survived`, tool exit 1) on the first attempt.
Fixed by parsing the script's own `--json` output; re-ran, now correctly kills the mutant (shown
above). Left in this report because it's exactly the kind of self-graded false-green the mutation
control exists to catch — worth the reviewer knowing it was caught rather than shipped.

## Verified facts / probe artifacts (evidence contract)

- `leadv2-quota-status.sh:141` reader confirmed unordered (`SELECT value FROM kv WHERE
  key='rate_limit_anthropic';`, no ORDER BY/LIMIT) — read directly, unchanged, not touched.
- Account object shape (`status`, `entry_suffix`, `service`, `five_hour`/`seven_day` nested
  `pct`/`reset_iso` dicts, `binding_window`) confirmed by reading
  `plugins/leadv2/scripts/leadv2-quota-read.py:475-514` directly — this is the shape my
  `_account_row()` extraction mirrors (same nested-dict lookup the existing active-account
  extraction in the probe's first python block already uses, at `:82-96` pre-change).
- `tests/run-all.sh` EXTRA_SUITE_MAP location and stem-selection mechanics confirmed by reading
  `tests/run-all.sh:82-548` directly (not `plugins/leadv2/scripts/tests/run-all.sh` — that path
  does not exist in this repo; the brief's line numbers referred to the top-level `tests/run-all.sh`,
  confirmed live).
- sqlite3 version: local macOS 3.51.0 (`sqlite3 --version`); Linux container (python:3.11-slim-bookworm)
  3.40.1 — both ≥3.25 (window functions), matching the brief's claim.

## tests/run-all.sh --scope changed

(pending — run in progress, `run-core-offline.sh` alone is documented to take >10 minutes; this
section is filled in with the actual PASS/FAIL/exit-code output below before DELIVERABLE_COMPLETE
is written.)
