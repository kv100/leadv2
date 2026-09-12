# Per-account quota by default; the breaker decides on the account (3e55153ca645)

Commit: `fe41fcf4` on `main` (pathspec-limited; the parallel lane's staged
beat-chain deletions were left staged, untouched). Contract clause:
PER-ACCOUNT-BY-DEFAULT (`docs/handoff/DECISION-LAYER-CONTRACT/decision.md`).

## What was reproduced (pre-change)

**Defect 1 — default is the blend.** With the opt-in truly unset
(`env -u LEADV2_CLAUDE_MULTIPROFILE`), `--report` line 1 was the blended
aggregate wearing a safety word:

```
Quota: 5h 100% (3854 / 8000000 in, claude% only, cap est.) | weekly(claude,
total-token, calibrated 2026-08-17) 30% (window=rolling_7d) | cache-hit 1.00 | exhausted
```

while the per-account probe (same minute, opt-in set) said work=81% warn /
personal=4% safe — two accounts, one word, neither account's. Note on the
brief's "byte-identical with and without the opt-in": that reproduces only in
a shell where the var is EXPORTED — the dispatch environment of a lane exports
`LEADV2_CLAUDE_MULTIPROFILE=1`, so `--report` and
`LEADV2_CLAUDE_MULTIPROFILE=1 --report` were byte-identical there
(`cmp -s` → BYTE-IDENTICAL, captured /tmp/3e55_rep_{default,optin}.txt). The
code default, proven by `env -u`, is the blend. Nothing persistent anywhere
sets the var — the flattery was environmental.

**Defect 2 — `--check` blends.** On the pre-change code (`git show HEAD:`),
fixture DB aggregate healthy (5h 0%, weekly 0%, no RL kv) + identity
work=90% exhausted:

```
--- pre-fix:  --check → rc=0   ← BLENDED BREAKER LETS AN EXHAUSTED ACCOUNT PASS
--- post-fix: --check → rc=1
QUOTA-EXHAUSTED: identity=work seven_day=90% usable_now=0.1 (worst account wins;
blended aggregate 5h 0%/wk 0% is NOT the safety signal; basis=profile-select windows)
```

## What changed

`plugins/leadv2/scripts/leadv2-quota-status.sh`:
- Gate flipped opt-in → **opt-out** (`LEADV2_QUOTA_STATUS_PER_ACCOUNT=0`),
  with the why in-source. The selector's own gate
  (`profile-select.sh:221`) is forced open on the one MEASUREMENT invocation
  only (`profile-status.sh:59` precedent) — switching stays opt-in, per the
  contract's exact split. Single-account machines stay byte-identical: no
  registry → selector prints `profile=- reason=single_profile` (no `windows=`)
  → unavailable → legacy line, zero network.
- `--check` gains the same worst-account arm `--report`/`--json` already use
  (REPORT_STATUS): worst measurable identity exhausted → exit 1 naming the
  identity; warn → stderr QUOTA-WARN, exit 0. **Unmeasurable** (windows pct
  `-` → status `unknown`) is never selected as worst and never refuses
  (bd7f811eb05c doctrine). The aggregate arm (RL kv + claude% cap) is
  untouched.

Test suites: new `test-check-decides-per-account.sh` (11/0); opt-out export
added to glm-filter/weekly-total/weekly-live (they pin other axes; keeps them
hermetic under the default-on probe); identity-report cases 6/7 comments and
case 7 moved to the opt-out var — same assertion intent ("callers that opt
out see no change"), same count.

## git diff --stat (commit fe41fcf4)

```
 plugins/leadv2/scripts/leadv2-quota-status.sh      | 65 ++++--
 plugins/leadv2/scripts/tests/test-check-decides-per-account.sh | 223 +++++++++++++
 plugins/leadv2/scripts/tests/test-quota-glm-filter.sh          |   4 +-
 plugins/leadv2/scripts/tests/test-quota-identity-report.sh     |  28 +--
 plugins/leadv2/scripts/tests/test-quota-weekly-live.sh         |   4 +-
 plugins/leadv2/scripts/tests/test-quota-weekly-total.sh        |   4 +-
 6 files changed, 297 insertions(+), 31 deletions(-)
```

## Acceptance suite — green

```
bash ~/Projects/leadv2/plugins/leadv2/scripts/tests/test-check-decides-per-account.sh
PASS=11 FAIL=0
```

Pins: (1) default, every per-account env var explicitly unset, selector stub
that refuses to emit windows unless the measurement gate was forced → line 1
per-account, both accounts listed, json status_source=identity:work;
opt-out → legacy line. (2) `--check` rc=1 with ONE exhausted account, blend
0%/0% healthy, refusal names identity=work; json top status=exhausted while
aggregate.status=safe. (3) one unreadable meter → rc=0 and the account
represented pct=null status=unknown; ALL meters unreadable → rc=0,
worst=null, status_source=aggregate. Plus warn-parity (rc=0) and the
aggregate arm intact (fresh unhealthy RL kv → rc=1).

## Guarding suites (no regressions)

| suite | result |
|---|---|
| test-quota-identity-report.sh | 9/0 (baseline 9/0) |
| test-quota-glm-filter.sh | 8/0 (baseline 8/0) |
| test-quota-weekly-total.sh | 13/0 (baseline 13/0) |
| test-quota-weekly-live.sh | 8/0 (baseline 8/0) |
| test-claude-profile-select.sh | **152/0** (baseline 152/0, post-b7469eff) |

Rest of the `quota|profile|balancer` set: balancer-ranks-by-usable-now 18/0,
quota-daemon 11/0, claude-profile-requested / codex-quota-gate /
quota-model-tier-granularity / quota-read-anthropic-liveness /
quota-standdown-duration rc=0. Pre-existing REDS, proven NOT mine:
balancer-every-arm 17/5 and quota-lockout-postspawn rc=1 re-run byte-identical
against HEAD `leadv2-quota-status.sh` (file swapped out and restored, shasum
verified) — same failures on the unmodified code; codex-quota-guardrails,
provider-quota-gate (28 passed / 2 failed: routing-yaml drift) and
quota-reset-arbiter reference neither quota-status nor any caller of it
(grep-proven), so my diff cannot reach them.

## Negative controls — all three RED (artifacts: docs/handoff/3e55153ca645/mutation-control/)

| # | mutation (exact source string, count==1 enforced by tool) | red_line |
|---|---|---|
| NC1 | gate reverted to opt-in: `"${LEADV2_QUOTA_STATUS_PER_ACCOUNT:-1}" != "0"` → `"${LEADV2_CLAUDE_MULTIPROFILE:-}" == "1"` | `FAIL: 2a default line1 not per-account: Quota: 5h 0% … safe` |
| NC2 | refusal arm neutered: `"$WORST_STATUS" == "exhausted"` → `"mutant_never"` | `FAIL: 5 --check rc=0 (want 1)` |
| NC3 | unreadable folded to a number: `pct = None` (except path) → `pct = 100` | `FAIL: 6 --check rc=1 … QUOTA-EXHAUSTED: identity=personal seven_day=100%` |

Run via `leadv2-mutation-control.sh` (worker mode, scratch copy),
`LEADV2_LANE_START_SHA=3d5e9d84`; artifacts
`20260912T213835Z-97598.txt`, `20260912T213909Z-10495.txt`,
`20260912T213931Z-18204.txt`.

## CI selection

Suite declares `# run-all-triggers: leadv2-quota-status` (line 32); admitted
by `lib/leadv2-suite-discovery.sh` (listed, tracked) and selected under
`--scope changed` twice over: the changed production file's stem
(`leadv2-quota-status`) maps to it via the discovered trigger row, and a
changed suite file selects itself (`run-all.sh` case rule).

## Self-check

`bash -n` on all 6 changed shell files: OK. Python files changed: 0
(py_compile vacuous). No files under docs/leadv2/ runtime-state paths touched
in either repo.
