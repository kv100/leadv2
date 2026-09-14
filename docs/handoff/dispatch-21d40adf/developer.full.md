# ANTHROPIC-PRICE-OR-A-REASON-WE-CANNOT-HAVE-ONE-01 — Anthropic half

Owner: this lane (1b53c47b6a08). Does not touch codex, `router_v2.cost`, `reset_urgency`, the
decision-record schema, the launcher-refusal event, the judge parser, or `~/.claude/burn/
history.db`'s writer. No price was written anywhere.

## Item 1 — published per-model weight search

**Finding: no authoritative per-model weight exists for the Claude subscription's pooled
5h/7d quota. This is a reported negative result, not a stopped search.** Four surfaces examined:

1. **This CLI's own accounting** (`leadv2-quota-read.py`, the tool this repo already trusts for
   quota reads). Its Anthropic path calls `https://api.anthropic.com/api/oauth/usage` and parses
   exactly two fields: `u["five_hour"]["utilization"]` and `u["seven_day"]["utilization"]`
   (`leadv2-quota-read.py:994-1008`, `leadv2-quota-read.py:22-29` docstring). Both are pooled
   percentages across the whole account — no per-model key anywhere in the parsed shape.

2. **Live probe of that exact code path, this session** (no secrets printed, per the evidence
   contract):
   ```
   $ python3 plugins/leadv2/scripts/leadv2-quota-read.py anthropic --no-cache
   {
     "provider": "anthropic", "status": "unknown",
     "error": "no fresh in-process access token ...",
     "rate_limit_info_captured": {
       "account_label": "max_20x",
       "five_hour_pct": 9.0, "seven_day_pct": 16.0,
       "binding_window": "seven_day", "source": "ratelimit-probe"
     }
   }
   ```
   The direct API call itself came back `unknown` (no fresh in-process OAuth token available to
   this subprocess — expected, this is a worker, not an interactive session), but the tool's own
   fallback signal — the last captured `rate_limit_info` snapshot, sourced from a live
   ratelimit-probe — is real, current data from this account, and confirms the same schema:
   pooled `five_hour_pct` / `seven_day_pct` only, no per-model field, no credit/weight unit.

3. **Published API docs**, `https://platform.claude.com/docs/en/api/rate-limits` (fetched live).
   This page documents a *different* mechanism — the developer Messages-API tier system
   (RPM/ITPM/OTPM per model, e.g. Opus 5: 2,000,000 ITPM / 400,000 OTPM at Start tier) — in raw
   token units, not weighted credits, and it governs API-key traffic, not the Claude
   Max/subscription 5h/7d pooled quota this repo actually meters. Response headers documented
   there (`anthropic-ratelimit-tokens-remaining`, `anthropic-ratelimit-input-tokens-remaining`,
   etc.) are also raw-token, per-model-class, not a normalized weight.

4. **The `anthropic-ratelimit-unified-*` header family** (Claude Max unified limits — searched via
   public GitHub issues `anthropics/claude-code#55333`, `#56047`, `#12829`, since these headers are
   not on the public rate-limits doc page): `anthropic-ratelimit-unified-5h-utilization`,
   `-7d-utilization`, `-status`, `-reset`, `-representative-claim`, `-fallback-percentage`. Every
   one of these is a pooled, account-level figure ("unified" is the operative word) — the search
   surfaced no per-model breakdown field in this header family either.

5. **Third-party estimation** (explicitly non-authoritative, cited for completeness): informal
   reports put one Opus conversation at roughly 10+ Sonnet conversations' worth of quota, but the
   source itself states "Anthropic does not advertise these figures" — this is exactly the
   "believed but never fitted" category the mission opened by warning against, so it is reported
   here as a data point about market folklore, not as evidence.

**Conclusion for item 1:** unlike glm-flash's 0.33 (a real published number, `leadv2-routing.yaml:
178`), there is no analogous authoritative anchor for Anthropic. The scale-times-known-weights fit
the mission describes as the reward for finding one cannot be run — there is no `known_relative_
weight` vector to multiply by. This is the actual, checked answer, not an unstopped search.

## Item 2 — nested windows, tested with numbers

Both `five_hour_pct` and `seven_day_pct` are recorded on every `rate_limit_history` row (confirmed
via `.schema rate_limit_history`: `five_hour_pct`, `five_hour_reset_epoch`, `seven_day_pct`,
`seven_day_reset_epoch`, `binding_window` all live on the same row) — so a **paired** per-interval
comparison is possible without re-sampling. Built as a standalone, reusable tool: `plugins/leadv2/
scripts/leadv2-anthropic-window-compare.py` (see "What shipped" below). Run against this session's
live account (`account_key=eb6c5b97`, `~/.claude/burn/history.db`, 200 `state='ok'` snapshots,
`min/max captured_epoch` = 1788468279 / 1789346025):

```
account=eb6c5b97 intervals_total=199 tokened_intervals=42 clean_intervals=31 zero_token_nonzero_delta=123
window=5h clean=31 mean_pct_per_token=5.272868987e-05 stdev=0.0001197416715
window=7d clean=31 mean_pct_per_token=6.699053537e-06 stdev=2.468905801e-05
ratio_5h_over_7d n=9 mean=3.83333 stdev=2.38048 min=0 max=9
ttr_bucket=near_reset      n=10 tokens=784858   d5pct_per_token=1.783762158e-05 d7pct_per_token=2.548231655e-06
ttr_bucket=mid             n=10 tokens=3111338  d5pct_per_token=8.356533427e-06 d7pct_per_token=1.607025659e-06
ttr_bucket=far_from_reset  n=11 tokens=5105841  d5pct_per_token=5.092207141e-06 d7pct_per_token=5.875623624e-07
unattributed_drain zero_token_intervals=123 explained_by_other_account=0 unexplained=123
```

**Yes, it varies, by a lot, on every axis asked about:**

- **By window:** 5h moves ~7.9x faster per token than 7d on average (5.27e-5 vs 6.70e-6) — expected
  in isolation (different quota sizes), but the *ratio itself* is unstable: on the 9 intervals where
  both deltas were nonzero, the pairwise ratio ranges from 0 to 9 with stdev 2.38 on a mean of 3.83
  — not a fixed conversion factor, which it would need to be for one window's fit to stand in for
  the other.
- **By time-to-reset:** intervals near a 5h reset show a rate ~3.5x higher than intervals far from
  reset (1.78e-5 vs 5.09e-6 pct/token), monotonic across all three tertiles. n=10-11 per bucket is
  small and not volume-normalized, so treat the *direction and rough size* as real, not the exact
  multiple.
- **By which meter is binding:** the account this lane runs under stayed pinned to `binding_window=
  seven_day` for all 200 snapshots (verified: `SELECT binding_window,count(*) ... WHERE account_key
  ='eb6c5b97'` → `seven_day|200`), so the "does the reading source change" question can't be
  answered from THIS account's history alone. It is real elsewhere in the same database, though:
  account `5a3c2328` (200+ snapshots, not this lane's account, so not joinable to its own token
  counts with the same confidence) shows `binding_window` split `five_hour|33` / `seven_day|169` —
  live proof the binding meter does move over an account's lifetime, corroborating that a fitter
  which reads one fixed column regardless of which meter is actually constraining is reading the
  wrong thing some of the time.

- **The dominant effect, not previously named:** of 199 intervals, only 42 (21%) have ANY tokens
  attributed to this account_key; 157 have zero. Of those 157 zero-attribution intervals, **123
  (78% of them, 62% of ALL intervals) still show a nonzero percentage delta on at least one window.**
  Cross-checked against every OTHER account_key's `turn_events` rows in the same wall-clock span
  (not just this account's) — **0 of the 123 are explained by any known account's recorded usage.**
  The quota is moving with no attributed cause anywhere in this database, for the majority of
  observed intervals. This is very likely the actual reason `leadv2-drain-weights.py` gets a
  negative R² regardless of grouping: the independent variable (attributed tokens) is missing most
  of the real drain, so no weight vector can explain the dependent variable's movement — a
  measurement-completeness problem, not a model-specification or collinearity problem. (Percentage
  resolution is confirmed integer-only — 0 of 200 `five_hour_pct` values are non-integer — so this
  isn't sub-percent rounding noise; it's real, whole-point movement with no counterpart in
  `turn_events`.)

## Item 3 — a designed calibration path, costed honestly

The account is provably NOT isolable to "this lane's" usage using account_key alone (item 2's
123/157 result) — `account_key` is derived from `realpath(CLAUDE_CONFIG_DIR)`
(`leadv2-quota-read.py`/`leadv2-drain-weights.py` both import `account_key_for_config_dir`), which
groups every session sharing that config dir (founder's interactive session, the lead session,
other lanes) under one key. So "read quota, issue N known tokens, read quota again" cannot assume
isolation; it has to be designed around the confound, and costed with it included:

1. **Verify a probe window, don't assume it.** Immediately before a probe run, pull the last ~10
   minutes of `rate_limit_history` for the live account and require `zero_token_nonzero_delta`-style
   quiet (no delta movement with no attributed cause) for at least one full inter-snapshot gap.
   Given the 123/157 result above, this condition will often NOT hold — that's itself the finding,
   not a bug in the check.
2. **Use the API's own token accounting, not an estimate.** Read `usage.input_tokens` /
   `usage.output_tokens` off the actual response, never `max_tokens` or a guessed count, so "known
   size" is exact.
3. **Probe with `--no-cache` before and after each request**, one model at a time, and log the
   wall-clock, the exact token count, and both percentages.
4. **Repeat enough times per model to average out the concurrent-session confound** rather than
   trust a single before/after pair.

**Cost, from the numbers already measured (item 2), stated as an upper bound since those rates are
contaminated by the 62%-unattributed drain and so are likely UNDER the true single-model rate,
meaning MORE tokens than this per tick in reality:**

- Resolution is 1 percentage point (confirmed integer-only). At the observed (contaminated) 7-day
  rate of 6.7e-6 pct/token, moving the 7d counter by its own resolution floor takes on the order of
  **~150,000 tokens** — most single Claude Code turns are far smaller than that, so **a single
  request will typically not move the 7-day counter at all**; only an accumulated batch will,
  meaning the measurement unit is "tokens until the counter ticks," not "tokens per request."
- At the (also contaminated) 5-hour rate of 5.27e-5 pct/token, one tick costs roughly **~19,000
  tokens** — cheaper to observe, but the 5h window resets every ~5 hours, so a multi-model
  calibration run risks spanning a reset mid-experiment (exactly the `dropped_reset` case
  `leadv2-drain-weights.py` already guards against) and must budget for discarding those intervals.
- For 4 models (haiku/sonnet/opus/fable) with even 3 clean before/after pairs each, at ~19-150K
  tokens per usable pair, total spend lands in the **low hundreds of thousands to low millions of
  tokens**, and collecting enough *verified-quiet* 7-day-window intervals (the more trustworthy
  window, since it resets far less often) could take **multiple days**, for the same structural
  reason `leadv2-drain-weights.py` already documents for its own 7d fit (48h `turn_events`
  retention plus needing ~7 days of clean history).
- **Error bar:** because most individual requests are below the resolution floor, a probe's
  measured rate is really `(tokens in one accumulated batch) / (1 percentage point)`, so the
  precision is bounded by how large a batch you're willing to run per tick — a smaller batch gives
  a tighter nominal rate but a proportionally larger relative uncertainty in exactly when the tick
  landed (an off-by-one-request timing question against a background of possible concurrent-session
  ticks). Expect double-digit-percent relative error per model without a very large batch (many
  hundreds of thousands of tokens) per observation.

**Conclusion for item 3:** a designed path exists and is describable, but it is not cheap or fast —
it is a multi-hundred-thousand-to-million-token, multi-day undertaking to get an error bar tight
enough to trust, and it depends on a "verified idle" condition that item 2's own data shows often
does not hold on this account. That cost-and-uncertainty profile is itself the deliverable the
mission asked for in the "or an evidenced statement that no such path exists" branch's spirit: the
path exists, but publishing a number from a shortcut version of it (a handful of probes) would
repeat exactly the six-invented-numbers mistake this whole thread exists to stop.

**Known landmine restated for whoever eventually writes a number:** `PRICE-KEY-ANTHROPIC-VS-CLAUDE-
MISMATCH-01` — `router_v2.cost` keys Anthropic as `anthropic:` while `capability_matrix` rows carry
`provider: claude`, so a real number written under `anthropic:` would silently fall through to the
cost median exactly like `null` does today. Not touched here (off-limits), but any future write
must fix the key mismatch in the same change or the number will be inert.

## What shipped

- `plugins/leadv2/scripts/leadv2-anthropic-window-compare.py` — new, reusable comparison tool (not
  a fitter, never prints a price). Computes the paired 5h-vs-7d per-token rate, the ratio between
  them, time-to-reset tertile buckets, and the zero-attributed-token/nonzero-delta unattributed-
  drain count with a cross-account explain check. This is the tool that produced every number in
  item 2 above; rerunning it against `~/.claude/burn/history.db` reproduces them.
- `plugins/leadv2/scripts/tests/test-anthropic-window-compare.sh` — hermetic suite against a
  synthetic fixture db (6 snapshots / 5 intervals covering: a clean interval, a 5h-reset-dropped
  interval, a true-idle interval, and both branches of the unattributed-drain check). Self-registers
  via `# run-all-triggers:` (same convention as `test-codex-drain-fit.sh`) — no `run-all.sh` edit
  needed. 11/11 assertions pass.
- No other files touched. `router_v2.cost`, `leadv2-codex-drain-fit.py`, `reset_urgency`, the
  decision-record schema, the launcher-refusal event, the judge parser, and `history.db`'s writer
  are all untouched, per off-limits.

## Acceptance item 4 — regression suites

Ran every suite the mission named:

```
test-arbiter-prices-by-provider.sh   NOT FOUND — verified absent (git grep across full history,
                                      `git log --all -- '*arbiter-prices-by-provider*'` finds no
                                      such file ever committed; only referenced in the two MISSION.md
                                      docs, never as an actual test). Reporting as a finding per the
                                      unrecognized-entity rule, not fabricating a result for it.
test-codex-drain-fit.sh              SUMMARY pass=13 fail=0
test-codex-lane-token-total.sh       SUMMARY pass=9 fail=0
test-reset-urgency.sh                SUMMARY: pass=10 fail=0
test-arbiter-decision-record-inputs.sh  pass=6 fail=0
test-launcher-refusal-event.sh       launcher-refusal-event: PASS=4 FAIL=0
test-leadv2-task-judge.sh            === Results: 36 passed, 0 failed ===
```

Full changed-scope run (`tests/run-all.sh --scope changed`, after staging the two new files):
`run-all: 5 passed, 0 failed, scope=changed` — selected `run-core-offline.sh` (always-on),
`test-status-surface-bash32.sh` / `-single-lead.sh` / `-fast-names.sh` (pre-existing changed-scope
selection, unrelated to this diff), and `test-anthropic-window-compare.sh` (self-selected via its
new trigger comment, confirming registration works). All green.

## Self-check (falsification set)

```
$ bash -n plugins/leadv2/scripts/tests/test-anthropic-window-compare.sh && echo OK
OK
$ python3 -m py_compile plugins/leadv2/scripts/leadv2-anthropic-window-compare.py && echo OK
OK
$ bash plugins/leadv2/scripts/tests/test-anthropic-window-compare.sh
... (11 PASS lines) ...
SUMMARY pass=11 fail=0
```

No red output at any point — this suite was built and passed on the first fixture design that
matched the tool's actual bisect semantics (events at exactly the left edge of an interval belong
to the PRECEDING interval, same convention `leadv2-drain-weights.py` already uses); the one bug
caught before commit was a stale rate-only gate (`clean_intervals<2`) that blocked a legitimate
single-interval ratio print — fixed to `<1` and reverified against both the fixture and the live
account.

DELIVERABLE_COMPLETE
