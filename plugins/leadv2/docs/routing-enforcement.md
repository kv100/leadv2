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

## Provider quota ceilings (QUOTA-GATE-PARITY-01)

Before this lane, the declared per-provider/per-purpose quota ceilings
(`router_v2.quota_ceilings` in `config/leadv2-routing.yaml`: glm 80/90, codex 90/95, claude
95/95 — work/review) were enforced end-to-end only for GLM. Codex ran to 100% weekly with days
left in its window and nothing rerouted its mandatory review duty. Two gaps let that happen,
both in the codex **build** path specifically (codex review, glm review/build, and claude
review were already enforced by `leadv2-glm-quota-gate.sh` and
`lib/leadv2-glm-policy-resolve.py`'s resolver thresholds):

1. `codex-task.sh`'s legacy yaml-threshold check reads `codex_quota_gate.build_threshold_pct`
   from `.claude/ref/leadv2-routing.yaml`. A repo with no `codex_quota_gate:` block there (this
   one, until now) makes that check a silent no-op.
2. `leadv2-codex-session-runner.sh`'s `codex exec` spawn path calls `codex_spawn_gate` directly
   and never went through `codex-task.sh` at all — no threshold check on that path, ever,
   regardless of config.

**Fix:** a threshold check now lives in `lib/leadv2-codex-quota-gate.sh::codex_spawn_gate` (the
function BOTH spawn paths call), so it can no longer be config-conditional or path-dependent.

- `plugins/leadv2/config/leadv2-quota-ceilings.sh` — the one editable place for the six
  declared ceilings, sourced (not executed) by the two bash gates below. `leadv2_quota_ceiling
  <glm|codex|claude> <build|review>` echoes the integer ceiling, rc 1 on unknown input.
  **Known divergence, deliberately not fixed here:** `lib/leadv2-glm-policy-resolve.py`'s
  `DEFAULT_BUILD_THRESHOLD_PCT` enforces codex **build** at 80.0, not the 90 declared in the
  routing yaml and mirrored here — stricter than declared, so not a safety hole.
  `tests/test-provider-quota-gate.sh` asserts this exact exception by name so it cannot
  silently widen.
- `leadv2-provider-quota-gate.sh <glm|codex|claude> <build|review>` — the generic gate. Reads
  the live per-provider quota-cache (`leadv2-quota-live.sh`), fails OPEN on every telemetry or
  configuration fault (missing/malformed JSON, non-ok status, stale cache — older than 2× the
  provider's TTL, non-numeric or missing ceiling): only a *known* percentage at or above a
  *known* ceiling refuses (rc 1, `LEADV2_DISPATCH_REFUSED: quota_gate`). A `limit_reached: true`
  codex reading with no numeric `used_percent` is treated as a hard 100%, never as "unknown".
  Kill switch: `LEADV2_PROVIDER_QUOTA_GATE=0`.
- `lib/leadv2-codex-quota-gate.sh::codex_spawn_gate` now calls the generic gate as a third check
  (after cooldown memory and the circuit breaker), purpose derived from the sub-command
  (`review|adversarial-review|review-bg` → review, else build). This single function is shared
  by both `codex-task.sh` and `leadv2-codex-session-runner.sh`, closing both gaps above at once.
- `leadv2-glm-quota-gate.sh`'s build threshold now sources its default from the ceilings file
  instead of a bare literal `80` — no behaviour change, one fewer place the number could drift.
- `lib/leadv2-glm-policy-resolve.py::live_codex_weekly_pct` now treats `limit_reached: true`
  (top-level or on the binding window) as a hard 100.0 even when `used_percent` is missing —
  previously that combination read as `unknown`, which is only ever *admitted* for the pool's
  terminal arm (harmless with the default review-arm order, live for any repo that reorders it).
- `lib/leadv2-review-reroute-note.sh::leadv2_review_reroute_note` — when the review pool
  resolver reroutes away from a `blocked`/`unknown` codex, this emits one
  `codex_dead_reroute task=<id> from=codex to=<reviewer> codex=<disposition> pool=<pool>`
  journal line. Silent when codex is healthy or is the reviewer. Called identically from BOTH
  independent copies of the pool-resolve call site (`leadv2-review-run.sh` and
  `leadv2-dispatch-product-close.sh`) so the observability fix can't land on only one of them.

**Explicitly out of scope / non-goals** (see the architect prepass for the full reasoning):
Claude **build** remains ungated — nothing calls `leadv2-provider-quota-gate.sh claude build`
today. Wiring a refusal into `claude-subsession.sh` would also refuse the lead's own
architect/critic subagent spawns, converting a soft cost problem into `status: unreviewed`; that
is a founder decision, not one this lane makes. Every gate here is a pre-launch check on a
cached number — a single long lane can still cross its ceiling mid-flight; that needs pacing,
which is blocked on the Pro-5x tier decision. `CODEX_SKIP_QUOTA_GATE=1` /
`GLM_SKIP_QUOTA_GATE=1` remain unconditional, logged bypasses — not removed here.

Env knobs:
- `LEADV2_PROVIDER_QUOTA_GATE` (default 1) — `0` disables the generic gate.
- `LEADV2_CEIL_GLM_WORK` / `_GLM_REVIEW` / `_CODEX_WORK` / `_CODEX_REVIEW` / `_CLAUDE_WORK` /
  `_CLAUDE_REVIEW` — override an individual ceiling (tests; production reads the file defaults).
- `LEADV2_QUOTA_CEILINGS` / `LEADV2_QUOTA_LIVE` / `LEADV2_QUOTA_CACHE_DIR` — override the
  ceilings file / quota-live binary / cache directory (tests).
- `LEADV2_QUOTA_READ_TIMEOUT` (default 8s) — bounds the gate's own quota-live subprocess so a
  hung provider endpoint fails open instead of stalling every codex spawn.
- `leadv2-burn-governor.sh --provider <glm|codex|claude>` — an additive mode: verdict from
  quota-cache percentage vs. the declared work ceiling (`soft = ceiling-10`, `hard = ceiling`)
  instead of the 24h token-burn DB. Ignores `LEADV2_BURN_SOFT_24H`/`LEADV2_BURN_HARD_24H`. The
  default (no-flag) invocation is byte-identical to pre-existing behaviour.

Tests: `tests/test-provider-quota-gate.sh` (gate states S1–S10, boundary ceilings, the
yaml/py/ceilings-file drift assertion), `tests/test-codex-dead-reroute.sh` (resolver + reroute
note + both call sites), `tests/test-burn-governor.sh` (`--provider` cases appended, default
path untouched).
