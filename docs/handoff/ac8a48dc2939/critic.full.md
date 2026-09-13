# Critic review — leadv2 commit 776d5329 (ac8a48dc2939 + ca28025443a6)

verdict: REVISE
next_action: review_round_2

Reviewed in the live worktree at
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ac8a48dc2939`
(branch `worktree-ac8a48dc2939`, HEAD `776d5329`). All commands run there or against
the live `~/.claude` keychain/DB (read-only where noted). `main` in the primary
checkout does not have this commit — do not review it there.

## Findings

| severity | file:line | finding | evidence |
|---|---|---|---|
| BLOCKING | `plugins/leadv2/scripts/leadv2-quota-read.py:1123-1131` (`normalize_payload`) and `:1140-1158` (`_daemon_snapshot_get`) | The config-dir-derived active-account fix (`resolve_active_account`) is only invoked on a cache miss / daemon miss. Guard `if len([a for a in accounts if a.get("active")]) != 1:` skips re-derivation whenever the cached/daemon blob already carries exactly one `active=True` (which every healthy blob does, by the "mark exactly one" invariant the same commit adds). Reproduced live: seeded a cache blob with `active=True` on `5a3c2328` (as if written under `~/.claude-work`), then called `normalize_payload()` under `CLAUDE_CONFIG_DIR=~/.claude` — result served `work_acct`, not the `~/.claude`-derived `eb6c5b97`. The cache dir (`~/.claude/state/leadv2/quota-cache`) and the quota daemon's snapshot are both **shared, not keyed by `CLAUDE_CONFIG_DIR`**, and the statusline's real call chain (`quota-fragment.sh → quota-refresh.sh → quota-live.sh`, confirmed via `grep` — `probe()` calls `bash "$LIVE" "$1"` with no `--no-cache`) goes through exactly this path with a 300s TTL. Only `leadv2-ratelimit-probe.sh` forces `--no-cache` (confirmed: header comment "always forces --no-cache", `RAW_JSON=$(bash "$QUOTA_LIVE" --no-cache anthropic ...)`), so the `rate_limit_history`/drain-weights write path IS fixed, but the mission's explicit human-facing requirement ("The statusline shows the account the session is actually running under") is not. No test in either suite exercises `normalize_payload`, `cache_get`, or `_daemon_snapshot_get` — zero coverage of the exact code path that defeats the fix. |
| HIGH | `docs/handoff/dispatch-1786402f/review-gate.md` (worktree) | Acceptance requires a report with a `drain-weights.py`/table-of-numbers and a "second-model review verdict" row. Neither exists: `docs/handoff/dispatch-1786402f/` contains no report file at all, and `review-gate.md` reads `status: blocked reason: gate_engine_aborted rc: 143` — the second-model review was killed (SIGTERM) and never produced a verdict. |
| MEDIUM | `plugins/leadv2/scripts/leadv2-quota-read.py:857-905` (commit message claim) | Commit message names exactly two live anchors (`eb6c5b97`, `5a3c2328`). Live keychain (`security dump-keychain`, read-only) also carries a third suffixed entry `Claude Code-credentials-496ffed8` that maps to no directory on this machine (`~/.claude-profiles`→`cb563ee9`, `~/.claude-mem`→`4477c89e`, checked). Not a code bug — the ladder correctly falls through unmatched keys — but it's an unaccounted-for account the fix's own commit message implies is fully mapped; worth a line in the report, not a silent gap. |
| MEDIUM | `plugins/leadv2/scripts/tests/test-account-truth-active-is-metered.sh`, `test-quota-telemetry-can-price-an-arm.sh` | `run-all.sh --scope changed` selection could not be independently confirmed within review budget — two concurrent invocations of the full `run-all.sh` (one from another session, one from mine) were both still running after 2+ minutes on this large repo. Selection is asserted only by the self-registered `# run-all-triggers: ...` header comment in each suite file (present, correctly lists the changed filenames) — not proven end-to-end by an actual `--scope changed` run completing and reporting these two suites selected. |
| LOW | `plugins/leadv2/scripts/lib/leadv2-cost-actuals.sh:~70` (`leadv2_lane_token_total`, part (b)) | Opens the burn DB with `sqlite3.connect(db, timeout=2)` (read-write mode) for a read-only `SELECT SUM(...)`, instead of `file:...?mode=ro`, unlike `leadv2-quota-read.py`'s equivalent read (`con = sqlite3.connect("file:%s?mode=ro" ...)`). Inconsistent with the rest of the diff's own read-only discipline; low risk since it never writes, but a lock contention on a hot DB from a supposedly read-only helper is avoidable. |
| LOW | mypy --strict output (see below) | 160 errors, all `no-untyped-def`/`no-untyped-call` — the entire file has never had type annotations; this diff neither introduces nor worsens the count in kind (every new function added — `account_key_for_config_dir`, the ladder's new branch — is exactly as unannotated as its neighbors). Advisory only; not this diff's debt to fix alone. |

## Lens-by-lens detail

### Lens 1 — did it close the three holes?
- **Hole 1 (rate_limit_history NULL pct for active account):** Root cause was `resolve_active_account` picking the bare `default` service. Fix logic verified correct via test suite (assertions 3/4) AND live: `python3 leadv2-quota-read.py anthropic --no-cache` under `CLAUDE_CONFIG_DIR=~/.claude` now returns `"account_resolution": "config_dir"`, `"active_account": "max_20x"` with `entry_suffix=eb6c5b97` marked `active:true` (previously `default` would have been active). But this only reaches production data via `leadv2-ratelimit-probe.sh`, which forces `--no-cache` — the **statusline's own read path does not** (BLOCKING finding above). So: closed for the telemetry write path, not closed for the display requirement the row explicitly named.
- **Hole 2 (turn_events no account key):** `leadv2-turn-account-attribute.py` genuinely runs on the live path (wired into `leadv2-ratelimit-probe.sh` behind `|| true`) and has already executed against the live production DB: `SELECT COUNT(*), COUNT(account_key) FROM turn_events` → `9224` total, `8881` non-null (measured directly, read-only query). Real, not just plumbed-and-unreachable.
- **Hole 3 (cost_actual_recorded empty tokens):** `leadv2_lane_token_total` is wired into both dispatch close paths (`leadv2-dispatch-code.sh:2335`, `leadv2-dispatch-product-close.sh:377`) and passes a real 8th positional token count instead of the previous omission. Suite assertions 7a-8 exercise this against real fixtures (costs.yaml, turn_events, unknown-lane fallback) and the NC-M2 mutation (constant `-` output) correctly turns the suite red. Reaches the live path.

### Lens 2 — sha256_8(realpath(CLAUDE_CONFIG_DIR)) rung
Computed independently, not taken on faith:
```
python3 -c "import hashlib,os; p=os.path.realpath(os.path.expanduser('~/.claude')).rstrip('/'); print(p, hashlib.sha256(p.encode()).hexdigest()[:8])"
→ /Users/kostiantyn.vlasenko/.claude eb6c5b97
python3 -c "... ~/.claude-work ..." → 5a3c2328
```
Cross-checked against the real keychain (read-only enumeration, no secrets read):
```
security dump-keychain 2>/dev/null | grep '"svce"<blob>="Claude Code'
→ ...-eb6c5b97, ...-5a3c2328, ...-496ffed8 (unaccounted, see MEDIUM finding)
```
The derivation is genuinely computable and matches. Not a BLOCKING issue.

### Lens 3 — prohibitions
`git show 776d5329 | grep -niE "ccswitch --switch|routing.yaml|capability_matrix|add-generic-password|security add|login"` → only comment/doc lines ("no ccswitch", assertion-8 test name). No hits on `leadv2-routing.yaml` in the diff stat. No credential writes, no login, no `ccswitch --switch` anywhere in the 11 changed files. Clean.

### Lens 4 — remaining_pct semantics
Suite assertion "PASS: 6 polarity: consumed 91.0/42.0 stored verbatim (not 9.0/58.0)" directly guards this; nothing in the diff touches `quota-fragment.sh` or flips a `pct`/`remaining_pct` meaning anywhere. Clean.

### Lens 5 — negative controls (run, not read)
Both run against **the real production function bodies** via `sed`-produced scratch copies wired through the suite's own env-injection points (`LEADV2_QUOTA_READ_PY`, `LEADV2_TURN_ACCOUNT_ATTRIBUTE_PY`, `LEADV2_COST_ACTUALS_SH`) — confirmed these env vars are read by the suites themselves before running the mutation, not by a hardcoded path. Not a "mutate a copy the suite never sees" control.

```
$ bash nc-account-truth-active-is-metered.sh
...FAIL: 4 ladder: resolution ladder regression (AssertionError: session_credential)
pass=13 fail=1
--- NC: suite exit=1 ---
NC-PASS: suite went red with the config-dir rung disabled — the ladder assertions bite
RC=0

$ bash nc-quota-telemetry-can-price-an-arm.sh
--- NC M1 ---  pass=14 fail=3 (attributor, idempotent, NNLS-after all failed as expected) → suite exit=1
--- NC M2 ---  pass=15 fail=2 (7a/7b token totals failed as expected) → suite exit=1
NC-PASS: every mutation turned the suite red — attribution and token-total assertions bite
RC=0
```
Both negative controls PASS (i.e., correctly demonstrate the suites go red under mutation).

### Lens 6 — the two suites (run, not read)
```
$ bash test-account-truth-active-is-metered.sh   → pass=14 fail=0, RC=0
$ bash test-quota-telemetry-can-price-an-arm.sh  → pass=17 fail=0, RC=0
```
Spot-checked assertion 4 (ladder) source: constructs a realistic fixture (bare service pre-flagged `active=True` from a stale resolution, two suffixed accounts) and asserts the config-dir rung wins, the "mark exactly one" invariant holds, and the explicit-operator-env rung still outranks the derivation. Not tautological — assertions fail concretely if the ladder order changes (confirmed by NC1 above). No coverage gap found in these two suites themselves; the coverage gap is at the cache/daemon layer neither suite touches (BLOCKING finding).

### Lens 7 — leadv2-drain-weights.py (run against live DB, read-only)
```
$ python3 leadv2-drain-weights.py --window 5h
window=5h account=eb6c5b97 kept=99 threshold=12 dropped_reset=28 dropped_idle=40
fable_intervals_excluded=7 r2=-0.3152 max_abs_corr=1.000 degenerate_pairs=7
weights: claude-sonnet-5=0.00016274 (dominant), others ~0

$ python3 leadv2-drain-weights.py --window 7d
window=7d account=eb6c5b97 kept=61 threshold=12 dropped_reset=2 dropped_idle=101
fable_intervals_excluded=10 r2=-0.7937 max_abs_corr=1.000 degenerate_pairs=7
```
Before (mission baseline, 2026-09-13 scratch): 5h kept=18 R²=-0.743; 7d kept=10 NOT-ENOUGH-DATA.
After: 5h kept=99 R²=-0.3152; 7d kept=61 (now above `MIN_INTERVALS=12`, so no longer NOT-ENOUGH-DATA) R²=-0.7937.

Both R² remain **negative** — worse than the mean, i.e. still noise, not a priced arm. `max_abs_corr=1.000` with `degenerate_pairs=7` confirms the mission's own warning: per-provider (not per-model) metering makes the model-token columns collinear, so no amount of clean data separates them with this design. **This is a legitimate second honest negative** per the mission's own acceptance language ("a second honest negative is a real finding and is worth more than a fitted number nobody can defend") — but the lane did not write this down anywhere (see HIGH finding: no report file exists).

## Measured numbers (mission's required table)

| item | value |
|---|---|
| `drain-weights.py` 5h: kept, R², before → after | kept 18→99, R² -0.743→-0.3152 |
| `drain-weights.py` 7d: kept, R², before → after | kept 10 (NOT-ENOUGH-DATA)→61, R² n/a→-0.7937 |
| rows in `rate_limit_history` with non-null pct for the live account, before → after | live account `eb6c5b97`'s own rows have always had non-null pct (401/200 split, table); what changed is `is_active` correctly flagging `eb6c5b97` instead of `default` — verified live via direct `--no-cache` call (`account_resolution: config_dir`). No new `rate_limit_history` rows were captured since the commit landed at review time (max `captured_epoch` in the live DB predates the commit by ~19 min; probe had not cycled again) |
| `turn_events` rows carrying an account key | 8881 / 9224 (measured live, read-only) |
| `cost_actual_recorded` rows with non-empty tokens | not independently re-measured against a live journal (out of review budget); logic verified via suite assertions 7a-8 and NC-M2, which is behavioral proof of correctness on fixtures, not a live-journal count |
| both suites rc | `test-account-truth-active-is-metered.sh` rc=0 (14/14); `test-quota-telemetry-can-price-an-arm.sh` rc=0 (17/17) |
| `run-all.sh --scope changed` selection proof | NOT independently confirmed — command did not complete within review budget (two concurrent full runs observed, neither finished in 2+ min); selection mechanism (self-registered `run-all-triggers:` header) is present and correctly named, but end-to-end proof is missing (MEDIUM finding) |
| second-model review verdict | none — `review-gate.md` shows `status: blocked reason: gate_engine_aborted rc: 143` (HIGH finding) |
| commit sha in `~/Projects/leadv2` | `776d53290ba982eef482c3eb67a95418e50240ce`, present on branch `worktree-ac8a48dc2939` in worktree `.claude/worktrees/ac8a48dc2939`. **Not present on `main`** in the primary `~/Projects/leadv2` checkout — per shared-tree doctrine, this is live in the worktree but not yet durable until merged/committed to main. |

## mypy --strict raw output (changed .py files)

```
$ python3 -m mypy --strict plugins/leadv2/scripts/leadv2-quota-read.py plugins/leadv2/scripts/leadv2-turn-account-attribute.py plugins/leadv2/scripts/leadv2-drain-weights.py
plugins/leadv2/scripts/leadv2-quota-read.py:613: error: Function is missing a type annotation  [no-untyped-def]
plugins/leadv2/scripts/leadv2-quota-read.py:656: error: Function is missing a type annotation  [no-untyped-def]
plugins/leadv2/scripts/leadv2-quota-read.py:670: error: Call to untyped function "_registry_keychain_services" in typed context  [no-untyped-call]
... (160 errors total, all no-untyped-def / no-untyped-call — the file has never carried annotations; new functions in this diff match the surrounding style exactly)
Found 160 errors in 3 files (checked 3 source files)
```
Advisory (LOW) — pre-existing condition of every function in this file family, not a regression introduced by this diff.

## Contradiction scan (pre-finalize)

- `remaining_pct` semantics: unchanged, guarded by suite assertion 6. No contradiction.
- Env var names: `LEADV2_QUOTA_READ_PY`, `LEADV2_TURN_ACCOUNT_ATTRIBUTE_PY`, `LEADV2_COST_ACTUALS_SH`, `LEADV2_RATELIMIT_PROBE_SH` — all consistently named and consistently read by both the suites and the negative controls that target them; no drift found.
- `SCHEMA_VERSION` claim ("unchanged, 1"): confirmed by suite assertion 5 ("lib.py SCHEMA_VERSION still 1"); the additive `ALTER TABLE turn_events ADD COLUMN account_key` never touches `SCHEMA_VERSION`. No contradiction.
- Path existence: `~/.claude/burn/lib.py:8 TURN_EVENTS_RETENTION_HOURS` cited by `drain-weights.py`'s 48h retention comment — this is a real file outside the leadv2 repo (the personal statusline addon), not verified byte-for-byte against line 8 in this review (out of scope: not part of the diff), flagged only if it were false — no contradiction found in what WAS checked.
- No flag semantics were flipped between this diff and any other usage found (`account_state="unmetered"` is consistently a "no number, don't guess" sentinel everywhere it appears, both in `leadv2-quota-read.py`'s pre-existing classifier and the newly-added persistence in `leadv2-ratelimit-probe.sh`).

None of these produced a new finding beyond what's already tabled above.

## Verdict

**LAND WITH FIXES** is the substantive verdict on the code — the primitives (`account_key_for_config_dir`, the resolution ladder, the attribution join, the token-total helper) are correct, tested, and reach the live path for the telemetry/pricing half of the mission (which is the one gated as "foundation" for the arbiter work). But the BLOCKING cache/daemon gap means the row's own stated requirement — "the statusline shows the account the session is actually running under" — is not met for the dominant real-world call path, and the acceptance report + second-model review are both missing/aborted. Per the "Critical/High must block" rule, this must not land as-is:

**DO NOT LAND** until:
1. The cache (`cache_get`/`normalize_payload`) and daemon-snapshot paths either key their storage by the derived `CLAUDE_CONFIG_DIR` account key, or re-run `resolve_active_account` unconditionally on every read (not gated on "already has exactly one active flag") — with a test that plants a foreign-context cache/daemon blob and asserts the CURRENT session's derivation wins.
2. A report file lands in `docs/handoff/dispatch-1786402f/` (or wherever the lane's report belongs) carrying the required before/after table — the numbers exist (this review measured them), they just were never written down.
3. The second-model review is re-run to completion (current one aborted rc=143) or its absence is explicitly waived by the founder/lead.

DELIVERABLE_COMPLETE
