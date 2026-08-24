# Single-lead pulse beat — PULSE-IN-SINGLE-LEAD-01

## What this is

The founder's 30-minute status (`[BROAD_STATUS]`) used to be emitted only from
the supervisor loop's beat branch (retired 2026-08-17, SUPERVISOR-DELETE-01). Single-lead mode never ran that loop, so the composer
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
- `scripts/leadv2-pulse-watch.sh` — the bounded watcher run inside a persistent lead-session
  `Monitor`. It observes the rendered file's mtime and emits only its first line on a rewrite.
- `hooks/leadv2-pulse-watch-arm.sh` — the SessionStart directive that arms that Monitor for the
  main-checkout lead only; workers and subagents never create duplicate watchers.

## Why an in-session Monitor, not a daemon or `CronCreate`

The former hook-clock-only position is superseded by founder order 2026-08-24. A composed status
must wake an otherwise idle lead session so the existing delivery hook can relay it. The watcher
is not a daemon and `CronCreate` remains explicitly out: it is one `persistent=true` Monitor in
one main-checkout lead session, with one mtime filter and at most one capped line per rewrite.
Workers and subagents are gated out, so it does not multiply per lane. This answers the
token-discipline concern without accepting silent delivery rot.

**Consequence:** delivery is no longer deferred until the founder types: a composed beat wakes the
lead and then follows the existing RELAY=full/none rules. Composition still remains hook-driven;
an idle session alone does not compose a new beat.

## The armed-watcher contract

At SessionStart, the main lead receives `PULSE-WAKE` and arms the named watcher immediately with
`persistent=true`. A lead session without that watcher armed is in violation. On an mtime event,
the watcher creates a turn; `leadv2-single-lead-beat.sh` performs the actual relay under the
existing owner/guest `RELAY=full/none` rules. The watcher never composes a status and never emits
a synthetic `BROAD_STATUS_READY` line.

## Known limits

The Monitor is scoped to the session lifetime. If the session is killed, compacted into a new
process, or cleared, its watcher ends; the next SessionStart re-arms it. The residual gap is from
session death until the founder next starts a session.

The watcher is downstream of the composer. An idle session fires no prompt/tool hook, so no
composer run may rewrite `founder-status.md`; no mtime change means no wake. This mechanism fixes
"a composed beat rots undelivered," not "no beat is composed while idle." A composer-triggering
watcher is a separate scope decision.

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
| `LEADV2_PULSE_WATCH` | `1` | Set to `0` to suppress both SessionStart arming and an already-running watcher. |
| `LEADV2_PULSE_WATCH_INTERVAL_S` | `60` | Watch poll seconds; malformed values use 60 and values clamp to 5–3600. |

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

`bash scripts/tests/test-pulse-watch.sh` covers watcher suppression, rewrite and creation wakes,
empty-header fallback, switches, SessionStart gates, malformed intervals, and shell syntax.

## Release note

Directory-source plugin caches do not necessarily refresh when content changes without a version
change. Copy/update the plugin cache and restart the session before relying on the new SessionStart
hook; otherwise the hook does not run at all.
