# Single-lead pulse beat — PULSE-IN-SINGLE-LEAD-01

## What this is

The founder's 30-minute status (`[BROAD_STATUS]`) used to be emitted only from
the supervisor loop's beat branch (retired 2026-08-19, SUPERVISOR-DELETE-01). Single-lead mode never ran that loop, so the composer
(`scripts/leadv2-broad-status.sh`) was regenerating `docs/leadv2/founder-status.md` correctly but
nobody ever composed a beat in the first place, and nobody woke the founder to relay it. This is
the single-lead driver + delivery mechanism. It never touches `leadv2-broad-status.sh` — that
renderer's content quality is owned by a separate lane (`fded7b89`).

## Files

- `scripts/leadv2-pulse-beat.sh` — the driver. `--check` (background-safe, throttled, no-ops if a
  real supervise loop is live), `--now` (synchronous, throttle bypassed), `--due` (predicate only).
  Runs the backlog pump before the composer, same order as the loop
  (the now-retired supervisor loop, formerly lines 842-852), then execs the unmodified
  `scripts/leadv2-broad-status.sh`. Never renders anything itself.
- `hooks/leadv2-single-lead-beat.sh` — wired to `UserPromptSubmit` and `PostToolUse` (matcher
  `.*`). Two steps, always in this order: **deliver** (relay the last beat's ready-line into the
  session as `additionalContext`, once, if the artifact actually changed) then **trigger** (kick
  off `leadv2-pulse-beat.sh --check` in the background if due).

## Why hook-clock, not a daemon or `CronCreate`

A beat only needs to fire while the lead is actually working. A detached 30-minute daemon armed
via a lead-side `Monitor` would bill the founder for a wake on every remaining turn of an idle
session, per `~/.claude/CLAUDE.md` §Token discipline rule 5, and `CronCreate` is explicitly out —
the beat must stay plugin-owned, not lead-owned. Hook-clock means: no background process, no
orphan to sweep, and the cost during an idle session is exactly zero.

**Consequence:** cadence is "≥30 min, delivered on the lead's next turn after that" — not a
wall-clock alarm. An idle session produces no beat, and that's correct: nothing is happening.

## The idempotency contract

Every hook fire compares the log's last `BROAD_STATUS_READY`/`BROAD_STATUS_FAILED` line's `at=`
stamp against `<state>/.pulse-delivered`. A new `at=` is not enough on its own to wake the founder
— the hook also hashes `founder-status.md` with its first line stripped and compares it against
`<state>/.pulse-body-hash`. Only a `at=` change **and** a body change produces an
`additionalContext` emission; either way, the new `at=` is recorded as delivered so an unchanged
body is never re-hashed on every remaining turn.

## State files

| File | Meaning |
|---|---|
| `.pulse-beat-last` | mtime/content = last beat *triggered* (throttle clock, written before dispatch so a hung composer can't cause a beat storm) |
| `.pulse-delivered` | last `at=` stamp injected into a session |
| `.pulse-body-hash` | sha256 of the last delivered artifact body (first line excluded) |
| `.pulse-beat.lock` | non-blocking `flock` target |

All under the control-plane root resolved by `leadv2-state-path.sh` — never a session-scoped path.
Two lead sessions in the same repo share the same beat clock; single-lead mode means one lead, so
this is accepted rather than built out as session-scoped state.

## Env

| Var | Default | Meaning |
|---|---|---|
| `LEADV2_SINGLE_LEAD_BEAT` | `1` | **The one-step rollback.** `0` disables both the driver and the hook completely — no pump call, no composer call, no state touched. |
| `LEADV2_SINGLE_LEAD_BEAT_S` | `1800` | Cadence floor, seconds. |

## On demand

`bash scripts/leadv2-pulse-beat.sh --now` forces a beat synchronously, ignoring the throttle. It
still goes through the same delivery de-dup on the next hook fire — asking twice in a row with
nothing changed produces no second wake.

## What this deliberately does not fix

Grep for `.supervise-active` / `.supervise-loop.json` across `hooks/*.sh` and `scripts/*.sh` for
the full list of other paths that are gated on the supervise loop and therefore inert in
single-lead mode (loop-detection, post-compact pulse-mode reinject, the supervisor prose/bash
guards, the fallback backlog-pump caller, several status-surface sections). Two of these — loop
detection and the post-compact reinject — are real behaviour losses, not cosmetics, and are
tracked as open threads rather than fixed here.

## Test

`bash scripts/tests/test-single-lead-beat.sh` — hermetic, stubs the composer's `claude` call and
the backlog pump exactly as `test-broad-status-duty.sh` does. Covers: a real beat composed and
delivered with matching `at=`/file stamps, a second unchanged fire staying silent, loop-liveness
making `--due` report `loop-owns` and leaving the throttle stamp untouched, and the kill-switch
making both the driver and the hook full no-ops.
