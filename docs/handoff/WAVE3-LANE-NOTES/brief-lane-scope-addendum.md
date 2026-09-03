
---

## Lane scope addendum (lead, 2026-09-03) — read before you touch anything

**Files owned by OTHER live lanes. Do not edit them. If your fix needs one, stop and report it
instead of editing:**

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — owned by the Wave-2 lane.
- `plugins/leadv2/scripts/leadv2-ratelimit-probe.sh` and the `rate_limit_anthropic` **write** path
  into `~/.claude/burn/history.db` — owned by lane `QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01`,
  which is adding per-probe history. You may **READ** quota state (via
  `plugins/leadv2/scripts/leadv2-quota-read.py` / `leadv2-quota-status.sh` /
  `leadv2-quota-live.sh`); you may not change how it is written or stored.

**Useful facts already measured — do not re-derive, but verify anything you build on:**

- The live `rate_limit_anthropic` kv row carries exactly these fields, and they are the raw
  material for "remaining" and "reset": `five_hour_pct`, `five_hour_reset_iso`, `seven_day_pct`,
  `seven_day_reset_iso`, `binding_window`, `captured_epoch`, `account_label`, `overageStatus`.
  Live values at dispatch time: `five_hour_pct=10.0`, `seven_day_pct=43.0`,
  `binding_window="seven_day"`.
- So for the Claude arm the reset time you need is already on disk. Check whether the same is true
  for glm / codex / kimi **before** designing a fetcher — a provider that already exposes a reset
  needs a reader, not a new probe.
- `captured_epoch` is a staleness signal. A reading older than the window it describes must degrade
  to a named default, never to a silent zero (see brief item 1).

**Non-negotiables:**

- Negative control goes INSIDE a function body, never at file top level — a top-level insert makes
  every suite red for the wrong reason and reads as a pass. Show red, revert, show green, and paste
  both exit codes.
- Green on macOS AND in a linux container; paste both exit codes.
- Never print or log a credential value. The account registry holds labels only — keep it that way.
- Do not weaken assertions; do not add anything to `tests/known-red-suites.txt`; never commit to
  `main`.
- Before you finish: `git diff --stat main..HEAD`. If the lane shows files being DELETED because it
  branched early, restore them from `main`. This trap hit 5 lanes today.
