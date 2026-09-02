# CI minutes & timeouts — test-suites.yml (CI-RUNS-THE-SUITES-01 round 2)

Measured on the lane Mac (2026-09-02). GitHub's billing multipliers are taken
from GitHub's published docs (Actions minute multipliers: macOS = 10x, Ubuntu
= 1x; public repos free) — UNVERIFIED against a bill, they are the standard
published figures.

## What runs where, and why

| Job | Runner | Runs | Why this runner |
|---|---|---|---|
| `changed-scope` | ubuntu-latest | PRs + pushes to main | Nothing in the tree needs Darwin; the suite code is bash-3.2-safe (runs on 3.2..5.x) |
| `bash32-darwin` | macos-latest | PRs + pushes to main | `tests/test-status-surface-bash32.sh` hardcodes Apple `/bin/bash` 3.x (SWIFTBAR-BASH32-01) |
| `full-scope-nightly` | ubuntu-latest | nightly cron + manual | Full sweep; bash32 coverage lives in `bash32-darwin`, which also runs nightly |

This is the round-2 "macOS confined to what genuinely needs Apple's
/bin/bash 3.2" split: before it, every PR burned macOS minutes for the whole
run just so one suite could see a 3.2 parser.

## Per-run minutes (measured)

- `test-status-surface-bash32.sh` standalone: **2m10s** on the lane Mac
  (`time bash tests/test-status-surface-bash32.sh` → 2:09.56 total). This is
  the entire macOS cost per PR run.
- `test-status-surface-fast-names.sh`: 6s. The other always-on status suites
  are seconds-scale.
- The heavy part is `run-core-offline.sh`: 83 nested suites. A --scope
  changed run with only one injected suite plus the three always-on status
  suites took **~11 min wall clock** on the lane Mac (21:59–22:10 local,
  this round's case-A proof); the full 83-suite set is budgeted at 30+ min —
  the final measured number for the full changed run is recorded in the lane
  round report (docs/handoff/dispatch-02f41cdd round note).
- `timeout-minutes: 45` on `changed-scope` = measured ~11–30 min + headroom;
  `15` on `bash32-darwin` = measured 2m10s + 7x headroom; `120` on the
  nightly is a round-1 estimate (a full --scope all local run was never
  attempted — it is nightly for exactly that reason).

## Per-month minutes

Assumptions: a busy solo repo — 10 PRs/day, 3 pushes per PR (= 30 changed
runs + 30 darwin runs per day, but concurrency `cancel-in-progress` kills
superseded runs, so count ~1.5 effective runs per PR, ~45/month-equivalent
below uses 15 effective changed runs + 15 darwin runs per day), plus 30
nightly runs/month.

### Public repo (this one today)

Everything is free — Actions minutes are unmetered for public repos, on any
runner. The split still matters for queue contention, not cost.

### Private repo (the template-adopter case; macOS bills at 10x)

| Scenario | changed-scope (ubuntu, 1x) | bash32-darwin (macOS, 10x) | nightly (ubuntu, 1x) | Billed macOS min/month |
|---|---|---|---|---|
| Busy (15 eff. changed runs/day) | 15 × ~30 min = 450 min/day | 15 × 2.2 min = 33 min/day × 10 = 330 billed | 30 × ~90 min = 2700 min/month | **9,900 min/month (~16.5 h)** |
| Light (3 eff. changed runs/day) | 3 × 30 = 90 min/day | 3 × 2.2 × 10 = 66 billed/day | 2,700/month | **~2,000 min/month (~33 h)** |

The pre-split shape (whole run on macOS) would bill the SAME busy schedule at
15 × 30 × 10 = **4,500 min/day (~2,250/month, ~37 h)** — the split is a ~4x
reduction of billed macOS minutes. If an adopter wants zero macOS spend, the
bash32-darwin job is the only thing to delete, at the cost of losing
SwiftBar-bash-3.2 coverage (documented, not silent: deleting the job removes
a named check from branch protection).

## What a timeout bump must never be

`timeout-minutes` is a hang-catcher, not a budget knob. If a run starts
approaching the cap, measure which suite grew (`bash <suite>` standalone,
`time` it) before raising the number.
