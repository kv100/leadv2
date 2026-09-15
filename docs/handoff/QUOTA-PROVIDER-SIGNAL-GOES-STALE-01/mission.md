# QUOTA-PROVIDER-SIGNAL-GOES-STALE-01

Founder decision 2026-09-15, verbatim in intent: **do not touch the cap numbers — make the
provider's own rate_limit readable instead.** All writes in **`~/Projects/leadv2`**.

## The measurement
The gauge already prefers Anthropic's own `rate_limit_info` over its heuristic caps. From
`leadv2-quota-status.sh` itself: when the kv key is *"present and fresh it is preferred over the
heuristic cap and can trip `--check` directly (no further gauge change needed)"*.

It is not fresh. Measured today:

```
kv rate_limit_anthropic captured_epoch=1789470036, age 61 minutes (window: 600s)
gauge line: "rate_limit:  not captured (heuristic cap in use) — kv hook: key=rate_limit_anthropic"
```

One manual run of `plugins/leadv2/scripts/leadv2-ratelimit-probe.sh` changed the gauge to:

```
rate_limit:  rate_limit_info (status=ok overage=normal resets=?) — provider signal, preferred over cap est.
```

Zero code changed. The payload already carries everything needed: `seven_day_pct`,
`five_hour_pct`, `account_label`, `five_hour_reset_iso`, `seven_day_reset_iso`, `resetsAt`,
`overageStatus`, `status`, `state`, `captured_epoch`.

So the defect is **cadence**, not capability: nothing refreshes the key, so in normal operation the
gauge silently falls back to a heuristic.

## Why it matters right now
Both accounts read `tier=default_claude_max_5x` (verified via
`leadv2-claude-account-check.sh`: `slot=personal … tier=default_claude_max_5x`,
`slot=work … tier=default_claude_max_5x`). The weekly heuristic cap is a **single-point
calibration recorded in `leadv2-quota-status.sh`, taken 2026-08-17 on a `max_20x` account**
(`cap = 1,422,463,108 / 0.34 = 4,183,721,494`). On a 5x account that fallback is roughly 4× too
generous, so the 24h burn gate and the weekly gauge both read freer than they are — while the work
account is at `seven_day=96% status=exhausted`.

**Do not re-derive, re-calibrate, or scale any of those constants.** Not `MAX_WK_TOTAL`, not
`MAX_5H_IN=8000000`, not `_LBG_DEFAULT_SOFT=800000000` / hard `1300000000`. They stay exactly as
they are; making the provider signal reliable is what demotes them to what they already claim to
be — a fallback.

## The change
Keep the signal fresh in normal operation, without anyone running the probe by hand.

Pick the mechanism and **state why** — both are acceptable, neither is assumed:
- **refresh-on-read**: when a reader finds the key older than the freshness window, refresh it
  before answering; or
- **a scheduled refresher** at a cadence under the window.

Whichever you pick, three properties are required:
1. **No stampede.** Up to 8 lanes read this concurrently. One refresh, not eight — take a lock, or
   rate-limit by the key's own `captured_epoch`. Hammering the provider for a quota reading is an
   absurd way to run out of quota.
2. **A failed refresh must not look like a fresh reading.** If the probe fails, the key keeps its
   old `captured_epoch` and the gauge keeps saying `not captured`. Never write a row with a new
   timestamp and stale contents — that converts "I could not read it" into "there was nothing to
   read", which is the exact failure family this repo keeps paying for.
3. **No system-level daemon without saying so.** If you choose a launchd agent or a cron entry,
   name the file it installs and make removal a single documented step. Prefer the in-repo seam.

Secondary, cheap, in scope: the gauge prints `resets=?` although `resetsAt` **is** present in the
payload. Fix the read.

## Acceptance
Registered probe, red today, must go rc=0:
`bash ~/Projects/persona-engine/scripts/probe-ratelimit-kv-stays-fresh.sh`

It currently answers `RED: no scheduled refresher for leadv2-ratelimit-probe.sh (checked launchd,
crontab, ~/.claude/hooks, LaunchAgents)`. Note it deliberately tests for the **refresher**, not for
momentary freshness — a hand-run probe makes the key fresh for ten minutes and would turn a
momentary check green while the defect is untouched.

If you choose refresh-on-read, that probe cannot see your fix. Then **change the probe** so it
detects the seam you built, keep its two-part shape (mechanism exists AND the signal is fresh), and
justify the change in the report. A probe that cannot see the fix is a bad probe; a probe widened
until anything passes is worse.

Also required beyond the probe:
- A test that a **failed** refresh leaves `captured_epoch` unchanged and the gauge still saying
  `not captured`.
- A test that concurrent readers cause one refresh, not N.
- `leadv2-quota-status.sh` prints a real `resets=` value.

## Negative controls — one per independent check, ALL RUN
1. Disable the refresher → the freshness assertion goes RED.
2. Make the refresh path swallow its failure and write a new timestamp anyway → the
   failed-refresh test goes RED.
3. Remove the lock / rate limit → the concurrency test goes RED.

Paste all three red/green pairs. An unmatched mutation anchor is a test failure, never a silent
skip.

## Off limits
- Every absolute cap constant named above. This row makes them unnecessary; it does not retune them.
- The 80/90/95 thresholds and the no-bypass rule — those are percentages of the real window and are
  already correct under 5x.
- Arm selection, the route arbiter, the review gate.
- Never print or log a credential, token, account id or org id. The existing scripts already redact
  to `account=..6ab506` style suffixes — keep that.
- Do not `git stash`, `git reset --hard` or `git clean`: this checkout is shared with live sessions
  in three other repos.

## Report
`docs/handoff/QUOTA-PROVIDER-SIGNAL-GOES-STALE-01/report.md`: the mechanism you chose and why, the
before/after gauge line, the three tests, all three controls, and — if you changed the probe — what
you changed and why it still tests the same property. End with `DELIVERABLE_COMPLETE`.
