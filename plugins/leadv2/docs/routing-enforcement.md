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
