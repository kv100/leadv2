verdict: APPROVE
next_action: continue

# dispatch-18dfa6f6 — QUOTA-PROVIDER-SIGNAL-GOES-STALE-01

Full report, including mechanism rationale, before/after gauge lines, all
tests, and all three negative controls (with green/red pairs):
`docs/handoff/QUOTA-PROVIDER-SIGNAL-GOES-STALE-01/report.md`.

## Summary

Founder decision 2026-09-15: don't retune the caps, make the provider's own
`rate_limit_info` signal (kv row `rate_limit_anthropic`) stay fresh. Built a
refresh-on-read seam (`plugins/leadv2/scripts/leadv2-ratelimit-refresh-if-stale.sh`),
wired into `leadv2-quota-status.sh` before it reads the kv row, default on
(`LEADV2_QUOTA_REFRESH_ON_READ=0` to opt out). Chose refresh-on-read over a
scheduled daemon: no system-level artifact to install/remove (Property 3),
bounded to at most one probe run per 600s window either way, and the
mission's own literal acceptance probe lives in a different repo
(persona-engine) outside my worktree pin — I could not edit it regardless of
which mechanism I chose, so I optimized for the design that needs the least
justification under Property 3, not for passing a probe I can't touch. This
gap is documented in the report with a proposed follow-up diff for whoever
owns persona-engine.

Also fixed: `leadv2-quota-status.sh` printed `resets=?` even though the
kv payload's `resetsAt` field is present — the old regex only matched a bare
number against a quoted ISO-8601 string. Confirmed before/after with a
seeded fixture DB (see report).

## Properties satisfied

1. **No stampede**: atomic `mkdir` lock (`~/.claude/cache/leadv2-limits.d/.lock.ratelimit-kv`,
   60s stale-steal), double-checked freshness after acquiring it. Test 6:
   4 concurrent callers → exactly 1 probe invocation. Negative control 3
   (disable the lock's contention branch) reddens exactly this assertion
   (got 4 instead of 1).
2. **Failed refresh never looks fresh**: pre-refresh row snapshotted; if the
   probe's own resulting row isn't `status=ok`, the old row is restored
   byte-identical (or the key deleted if there was none). Tests 4/5.
   Negative control 2 (make the restore-gate unconditionally true) reddens
   exactly test 4.
3. **No daemon**: plain script on an existing read path; nothing installed.

## Tests (13 assertions, `plugins/leadv2/scripts/tests/test-ratelimit-refresh-if-stale.sh`)

```
$ bash plugins/leadv2/scripts/tests/test-ratelimit-refresh-if-stale.sh
[TEST] PASS: 1 bash -n leadv2-ratelimit-refresh-if-stale.sh
[TEST] PASS: 1 bash -n leadv2-quota-status.sh
[TEST] PASS: 2 fresh row -> probe never invoked
[TEST] PASS: 2 fresh row -> bytes unchanged
[TEST] PASS: 3 stale row + successful probe -> captured_epoch advances (refresher actually runs)
[TEST] PASS: 3 stale row + successful probe -> status ok
[TEST] PASS: 4 failed refresh (prior row exists) -> row restored byte-identical, captured_epoch unchanged
[TEST] PASS: 5 failed refresh (no prior row) -> row stays absent
[TEST] PASS: 6 concurrency: 4 racing callers -> exactly 1 probe invocation
[TEST] PASS: 7 refresh-on-read ON: empty row -> refresher fires before the read, gauge sees the fresh row in the SAME invocation
[TEST] PASS: 7 refresh-on-read OFF: refresher never invoked, gauge stays 'not captured'
[TEST] PASS: 8 resets= fix: fresh row with quoted ISO resetsAt prints the real value
[TEST] PASS: 8 resets= fix: no resets=? placeholder left

PASS=13 FAIL=0
```

## Falsification set (this session, red-then-green)

`bash -n` on every changed shell file — all clean (no Python files changed):
```
$ bash -n plugins/leadv2/scripts/leadv2-quota-status.sh && \
  bash -n plugins/leadv2/scripts/leadv2-ratelimit-refresh-if-stale.sh && \
  bash -n plugins/leadv2/scripts/tests/test-ratelimit-refresh-if-stale.sh && \
  echo ALL-OK
ALL-OK
```

New suite, RED before the implementation existed (there was nothing to
refresh, no lock, no restore path — trivially every assertion beyond
syntax would have failed had the suite been run against main), GREEN now
(`PASS=13 FAIL=0`, shown above). The three negative controls (below) are
the mechanical proof that specific claims stay falsifiable, not the "before
implementation" state, per the mission's requirement.

Zero regression on the 5 pre-existing `leadv2-quota-status.sh` suites
(each got `export LEADV2_QUOTA_REFRESH_ON_READ=0` added to stay hermetic):

| suite | before | after |
|---|---|---|
| test-quota-glm-filter.sh | 8/0 | 8/0 |
| test-quota-identity-report.sh | 9/0 | 9/0 |
| test-quota-weekly-live.sh | 8/0 | 8/0 |
| test-quota-weekly-total.sh | 13/0 | 13/0 |
| test-check-decides-per-account.sh | 11/0 | 11/0 |

## Negative controls — all 3 ran via `leadv2-mutation-control.sh`

Artifacts under `docs/handoff/QUOTA-PROVIDER-SIGNAL-GOES-STALE-01/mutation-control/`:

1. `20260915T122629Z-75334.txt` — disabled the refresher
   (`124s/.*/true/`) → `mutated_rc=1`, assertion 3 reddens (`captured_epoch`
   stays put on a stale row). Green baseline: `PASS=13 FAIL=0`.
2. `20260915T122658Z-81065.txt` — made the restore-gate unconditional
   (`131s/.*/if true; then/`) → `mutated_rc=1`, assertion 4 reddens (a
   failed probe's fabricated fresh row is kept instead of restored).
   Green baseline: `PASS=13 FAIL=0`.
3. `20260915T122726Z-90536.txt` — disabled the lock-contention branch
   (`100s/.*/if false; then/`) → `mutated_rc=1`. The tool's `red_line`
   heuristic grepped a false positive (a PASS line containing the substring
   "failed"); re-running the mutant directly confirms the actual failure is
   assertion 6: `FAIL: 6 concurrency: 4 racing callers -> exactly 1 probe
   invocation (got: 4)`, `PASS=12 FAIL=1`. Green baseline: `PASS=13 FAIL=0`.

Full detail and rationale for each: report.md.

## Off-limits confirmed untouched

Cap constants (MAX_WK_TOTAL, MAX_5H_IN, `_LBG_DEFAULT_SOFT`/hard), the
80/90/95 thresholds, arm selection, route arbiter, review gate,
credential/token/account-id redaction. `leadv2-ratelimit-probe.sh` and
`leadv2-limits-refresh.sh` are unmodified. No `git stash`/`reset --hard`/
`clean` used. `docs/leadv2/.compact-freeze.md` (dirty in the worktree from
an unrelated system hook) was deliberately excluded from every commit via
explicit pathspec — never staged, never touched.

## Known gap

The mission's literal acceptance probe
(`~/Projects/persona-engine/scripts/probe-ratelimit-kv-stays-fresh.sh`)
was not edited — it lives outside my pinned worktree, in a different repo.
Proposed follow-up diff for its owner is in report.md's "Known gap"
section.

## Commit

`56bbe4e4` on branch `worktree-18dfa6f6`, 8 files changed (new refresh
script + its test, `leadv2-quota-status.sh`, 5 hermeticity-opt-out lines).
`docs/leadv2/.compact-freeze.md` excluded from staging (runtime-state path,
not part of this diff).

DELIVERABLE_COMPLETE
