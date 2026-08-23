# Routing Enforcement Policy

## Rule: architect/critic/security-auditor → Codex-first or Opus

For Phase 2 (Plan) and Phase 5 (Review), these agents carry the highest reasoning
cost and correctness requirement. The correct routing priority is:

1. **Codex (gpt-5.5, zero Claude quota)** — `~/.claude/scripts/codex-task.sh`
2. **Opus** — `Agent(subagent_type=<role>, model=opus)`
3. **Sonnet** — only valid for review R2/R3 rounds (per `feedback_review_routing`)

## codex_enabled flag

Read from `<repo>/.claude/leadv2-overrides/codex-policy.yaml`:

```yaml
codex_enabled: true   # persona-engine: Codex allowed
codex_enabled: false  # m3-market: absolute ban — Opus only, never Codex
```

When `codex_enabled: false`, the routing guard recommends Opus only and MUST NOT
mention Codex (m3-market corp ban).

## Hook behavior

`leadv2-routing-guard.sh` (PreToolUse:Agent):
- Fires on `subagent_type ∈ {architect, critic, security-auditor}` AND `model == sonnet`
- Emits advisory to stderr — NEVER blocks (always exits 0)
- Reads `codex-policy.yaml` from repo root to tailor the message
- Safe for all repos; no-op when model is opus or role is developer/devops/etc.

## Legitimate sonnet uses for these roles

- Critic R2/R3 review rounds (lead has already done R1 with Opus/Codex)
- security-auditor on Trivial/Light tasks where Opus is overkill
- Any spawn where the router explicitly returned sonnet

The hook warns; the lead decides. It is never a hard block.

## Forks always cost Opus (WHEN-TO-FORK-01)

`Agent(subagent_type=fork)` inherits the caller's model — for the lead that is **Opus** —
and **silently ignores any `model=` override**. No guard can see this (the spawn input may
say `model: sonnet` while the fork actually runs on Opus), so it is a routing rule, not a
hook: never fork to save cost, never fork to bypass the Opus quota, and never pass `model=`
on a fork spawn (it is a no-op that only misleads the audit trail). Fork only per the
criteria in `docs/work-placement.md` — session-context-dependent, no reviewed diff, no
isolation need.

## Burn governor (BURN-GOVERNOR-01)

`leadv2-dispatch-code.sh` consults `leadv2-burn-governor.sh verdict` FIRST in `cmd_resolve`
— before placement, worktree creation, ledger reservation, or the architect prepass. It
reads the local 24h token-burn total from `${LEADV2_CLAUDE_BURN_DIR:-$HOME/.claude/burn}/history.db`
(table `hourly`) and returns `ok`, `soft`, or `hard`. `hard` refuses the dispatch with exit
code 6 — no worker, no worktree, no ledger row — and parks the mission to
`docs/leadv2/burn-deferred.jsonl` (list/retry via `leadv2-dispatch-code.sh burn-deferred
[--list|--retry-all|--json]`, mirroring the existing `glm-deferred` subcommand). `soft`
prints an advisory and proceeds. The governor is fail-open: missing sqlite3, missing db,
missing table, or a locked db all collapse to `verdict=ok reason=no_telemetry` — a fresh
machine or a moved burn dir never blocks dispatch.

Env knobs:
- `LEADV2_BURN_GOVERNOR` (default 1) — `0` disables the gate entirely.
- `LEADV2_BURN_SOFT_24H` / `LEADV2_BURN_HARD_24H` (default 800000000 / 1300000000) — 24h
  token-sum thresholds. A misconfigured pair (`hard <= soft`, or either non-numeric)
  silently falls back to the defaults and the verdict's `reason` gains a `+bad_config`
  suffix — always reported, never suppressed.
- `LEADV2_BURN_OVERRIDE=1` — bypasses a `hard` refusal (journaled `overridden=1`).
  **`--force` never bypasses it** — burn follows the same rule dedup already does.
- `LEADV2_BURN_GOVERNOR_BIN` / `LEADV2_CLAUDE_BURN_DIR` — override the governor script /
  its telemetry directory (tests).

Every caller of `leadv2-dispatch-code.sh` has its own rc-6 arm: `leadv2-fanout-lane-launcher.sh`
and `leadv2-backlog-pump.sh` record the lane as `parked`/deferred (never `dead`/`spawn_failed`
— a burn refusal is a deliberate park, not a failure); `leadv2-fanout.sh` records `parked` and
deliberately does **not** fall back to `_fanout_launch_full_cycle` — a burn refusal exists to
save tokens, and the full-cycle fallback is the single most expensive path in the system.
