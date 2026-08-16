# Architect prepass — PULSE-IS-A-PLUGIN-DUTY-01, fix round 1

Worktree: `.claude/worktrees/2b6c3f01`. Review: `docs/handoff/dispatch-2b6c3f01/review-gate.md` (fail, 0 critical, 1 verified high).

## 1. The defect, precisely

`plugins/leadv2/scripts/leadv2-broad-status.sh` has **two** early-exit failure paths, not one:

| line | trigger | today |
|---|---|---|
| 79–85 | collector exits non-zero | logs `collection failure`, `_emit_ready_line "-" degraded`, `exit 0` |
| 292–296 | python render fails / no render.json | logs `render failure`, `_emit_ready_line "-" degraded`, `exit 0` |

`founder-status.md` is written **only** on the happy path (line 333). So on either failure the ready-line
fires — `[SUPERVISE-URGENT] BROAD_STATUS_READY … path=docs/leadv2/founder-status.md degraded=1` — and the
mandated verbatim relay opens a file whose content is the **previous, healthy** beat. The `degraded=1` flag
lives in the log line, which the relay is not obliged to reproduce; the artifact the founder reads carries
no failure signal at all. Worst shape for a status duty: not silent, but confidently stale.

The review found line 83. Line 294 is the identical bug and must be fixed in the same round.

## 2. Design

Two properties, one mechanism each.

### P1 — a failed beat is visibly failed (in the artifact, not only in the log)

Add one helper next to `_emit_ready_line`, and route both failure paths through it:

```
_write_degraded_status() {   # <reason> -> rc 0 if the artifact was replaced
  local reason="$1" block
  block="$(
    printf '%s [BROAD_STATUS] dispatched=%s degraded=1\n' "$BEAT_AT" "$DISPATCHED"
    printf '| Линия | Что делает | Кто делает | Состояние | Уже на диске |\n'
    printf '|---|---|---|---|---|\n'
    printf '| (статус не собран) | — | — | %s | — |\n\n' "$reason"
    printf 'СТАТУС НЕ СОБРАН на beat %s: %s.\n' "$BEAT_AT" "$reason"
    printf 'Таблица линий за этот beat недоступна — это НЕ значит, что линий нет.\n'
    printf '[BROAD_STATUS_END]\n'
  )"
  printf '%s\n' "$block" >>"$LOG_FILE"
  printf '%s\n' "$block" >"$FOUNDER_STATUS_PATH.tmp" 2>/dev/null \
    && mv "$FOUNDER_STATUS_PATH.tmp" "$FOUNDER_STATUS_PATH" 2>/dev/null
}
```

Both failure sites become:

```
if _write_degraded_status "<reason>"; then
  _emit_ready_line "-" degraded
else
  _emit_fail_line "<reason> + founder-status.md not writable"
fi
exit 0
```

Content contract is unchanged and honoured: one lane table (one row) + 2 prose lines (cap is 3), same
`[BROAD_STATUS] … / [BROAD_STATUS_END]` envelope, same atomic tmp+mv write as the happy path.

`_emit_fail_line` is the "refuse to signal READY" branch — the artifact could not be replaced, so nothing may
point at it:

```
_emit_fail_line() {  # <reason>
  … same leadv2_alarm_transition dedupe, key broad_status_ready, value "$BEAT_AT failed" …
  printf '%s [SUPERVISE-URGENT] BROAD_STATUS_FAILED at=%s reason=%s stale_file_kept=1\n' …
}
```

No `path=` token → the relay contract (relay *the file* on `BROAD_STATUS_READY`) cannot fire on it, while the
`SUPERVISE-URGENT` substring still passes the founder's real `grep URGENT` filter. C1 (a failed beat still
wakes) survives; the stale file is never advertised as fresh.

### P2 — staleness detectable without trusting the writer

The two artifacts already carry the same beat identity from independent print sites: the ready-line's `at=$BEAT_AT`
(line 74) and `founder-status.md`'s first line `$BEAT_AT [BROAD_STATUS] …` (line 327). Make that a stated
**reader-side** obligation rather than an accident:

> Before relaying, compare the `at=` in the `BROAD_STATUS_READY` line with the leading timestamp on line 1 of
> `founder-status.md`. If they differ, the file is from an earlier beat — publish that fact, not the file.

This is the property the mission asks for: it holds even if a *future* failure path forgets to write, because
the check runs in the reader. Documented in the two surfaces the supervisor actually reads at relay time —
`plugins/leadv2/docs/supervisor-role.md` and `plugins/leadv2/hooks/leadv2-task-anchor.sh` — appended to the
existing relay sentence, so the T8 wording-drift assertions (`'verbatim relay of a'`, `BROAD_STATUS_READY` ×2)
keep passing.

## 3. Test — `plugins/leadv2/scripts/tests/test-broad-status-duty.sh`

Existing T5 asserts only that `degraded=1` appears. That is exactly the test that passed while the bug was
live; it stays, and four cases are added that assert on **what the relay would publish**:

- **T9a — collector failure replaces the artifact.** Seed `founder-status.md` with a sentinel healthy block
  (`HEALTHY-SENTINEL-DO-NOT-KEEP` + an old beat stamp). Run with `LEADV2_STATUS_COLLECTOR_BIN=/bin/false` and
  pinned `LEADV2_BROAD_STATUS_BEAT_AT`. Assert: sentinel **absent**, `СТАТУС НЕ СОБРАН` present, pinned
  `BEAT_AT` present, `degraded=1` on line 1.
- **T9b — render failure replaces the artifact.** Collector stub writes a snapshot that is not valid JSON;
  same three assertions, reason mentions render. (Covers line 294, which the review did not name.)
- **T9c — stamp coherence.** On a healthy beat *and* on a degraded beat, the `at=` value parsed out of the
  ready-line equals the leading timestamp of `founder-status.md` line 1. This is P2 as an executable invariant.
- **T9d — unwritable artifact refuses READY.** Point `LEADV2_FOUNDER_STATUS_PATH` into a `chmod 500` dir
  holding a pre-existing stale file. Assert: zero `BROAD_STATUS_READY` lines, exactly one
  `BROAD_STATUS_FAILED … stale_file_kept=1`, stale file byte-identical. Skip with a logged SKIP when `EUID=0`.

Hermetic per suite convention: throwaway `LEADV2_PROJECT_ROOT`/`LEADV2_STATE_ROOT`, stubbed claude, no crontab,
no loop needed — T9a–T9d invoke `leadv2-broad-status.sh` directly, so they cost seconds, not the ~60s cycle.

## 4. Files

| file | change |
|---|---|
| `plugins/leadv2/scripts/leadv2-broad-status.sh` | `_write_degraded_status`, `_emit_fail_line`; both failure paths routed through them |
| `plugins/leadv2/scripts/tests/test-broad-status-duty.sh` | T9a–T9d |
| `plugins/leadv2/docs/supervisor-role.md` | one sentence: stamp-compare before relay |
| `plugins/leadv2/hooks/leadv2-task-anchor.sh` | same sentence in the relay DIRECTIVE |
| `docs/handoff/PULSE-IS-A-PLUGIN-DUTY-01/report.md` | one line: what the relay publishes on a failed beat (deliverable, excluded from LANE_WRITES per protocol) |

## 5. Risks

| risk | mitigation |
|---|---|
| Degraded write itself fails → silent regression to today's bug | that is exactly the `_emit_fail_line` branch; T9d proves it |
| `_emit_fail_line` shares the dedupe key with READY → a beat that degrades then recovers is suppressed | dedupe **value** differs (`$BEAT_AT failed` vs `$BEAT_AT degraded`), and the value is compared, not just the key |
| Content-contract drift (settled: 1 table + ≤3 lines) | degraded block is 1 table + 2 lines; asserted implicitly by T9a's exact-string checks |
| T8 wording-drift assertions break on the appended sentence | append only; `grep -q 'verbatim relay of a'` and the `BROAD_STATUS_READY` count of 2 in the anchor are untouched — verify by running T8 |
| `chmod 500` fixture leaks a non-removable dir | restore mode in the case's own cleanup before suite teardown |
| Three live repos share the tree | no `reset --hard` / `clean` / `stash`; edits confined to the files above |

## 6. Non-goals

- The pulse content contract (one lane table + ≤3 lines) — settled, unchanged.
- `docs/leadv2/open-threads.md` — untouched.
- `plugins/leadv2/commands/leadv2.md` and `hooks/leadv2-supervisor-mode-reinject.sh`: the stamp-compare sentence
  is **not** added there this round to keep the fix diff bounded; note it as a follow-up thread.
- The Haiku tail, the collector, the renderer, the dedupe library, the loop, the watchdog.
- No change to the happy path's output bytes.

acceptance:
  surface: file_artifact
  observable: |
    A beat whose collector (or renderer) fails leaves docs/leadv2/founder-status.md opened by the founder
    reading, on line 1, the current beat's timestamp followed by "degraded=1", a single-row lane table whose
    Состояние cell names the failure, and the sentence "СТАТУС НЕ СОБРАН на beat <this beat's timestamp>: <reason>."
    The previous beat's healthy table is gone from the file. If that file could not be rewritten, the founder
    instead sees an URGENT line reading BROAD_STATUS_FAILED … stale_file_kept=1 and no BROAD_STATUS_READY line
    anywhere in the beat, so nothing points them at the stale file.
  authored_at: 2026-08-17T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh, plugins/leadv2/scripts/tests/test-broad-status-duty.sh, plugins/leadv2/docs/supervisor-role.md, plugins/leadv2/hooks/leadv2-task-anchor.sh

DELIVERABLE_COMPLETE
