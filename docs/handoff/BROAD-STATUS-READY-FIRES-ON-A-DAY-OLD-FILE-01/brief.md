# Mission: BROAD_STATUS_READY fires on a day-old founder-status.md

Constraints: `docs/handoff/WAVE4/shared-constraints.md` (binding — in-body negative control, green
macOS+linux, real prod fn faked one level lower, CI must SELECT your suite, off-limits below).

## Goal
`at=` in the `BROAD_STATUS_READY` line must be the FILE's own confirmed-write stamp, never the
beat's wall clock. A stale file must never be relayed to the founder as current.

## Root cause (file:line, mechanism proven)
**Emitter+writer** (same file): `plugins/leadv2/scripts/leadv2-broad-status.sh`.
- `_emit_ready_line()` (def L136, printf L144-146) stamps `at=%s` with `$BEAT_AT` (L110:
  `BEAT_AT="${LEADV2_BROAD_STATUS_BEAT_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"`, defaults to "now").
- **Proximate bug, L1423-1426**: the real write is unguarded — `printf ...>"$FOUNDER_STATUS_PATH.tmp"
  && mv "$FOUNDER_STATUS_PATH.tmp" "$FOUNDER_STATUS_PATH" && _stamp_epoch` (L1423), then L1426
  unconditionally calls `_emit_ready_line "$ROWS_N"` (fresh `$BEAT_AT`) with **no check of
  L1423's exit status**. Contrast: collector-failure (L245-248) and render-failure (L1349-1352)
  both `if`-guard the write and route to `_emit_fail_line`/degraded — L1423 is the one write site
  with no guard. If `mv` fails (perm/race/ENOSPC) the plain READY still fires fresh over an
  untouched file.
- **Structural gap (defense-in-depth)**: the right primitive already exists —
  `FOUNDER_STATUS_EPOCH_PATH` (L99, `.founder-status-epoch`), stamped by `_stamp_epoch()`
  (L100-105), plus a documented rule (L89-96): `now_epoch - epoch_in_file < BEAT_S`
  (`LEADV2_SINGLE_LEAD_BEAT_S`, default 1800) = FRESH — advisory prose only; `_emit_ready_line`
  never reads it before stamping `at=`.
- **Consumer/relay**: `leadv2-single-lead-beat.sh` DELIVER L161-196. L166 extracts `AT` from the
  log's last line; gates are L169 "session saw this AT before" and L177 "body hash changed since
  this session last saw it" — per-session deltas, not absolute-age checks, so a brand-new
  session's first fire always relays the log tail as-is. Owner-role CTX (L183-185): "paste
  founder-status.md verbatim; compare its line-1 stamp with the beat above" — **prose to the
  LLM**, not a bash gate.
- **Precedent**: `test-beat-stamp-agreement.sh` names the same defect class
  (ANTI-SILENCE-ONE-MECHANISM-01) — a prior `at=`/line-1-stamp mismatch "fixed" by telling the
  LLM to compare-then-speak. That suite locks WITHIN-RUN agreement only, never ACROSS-TIME staleness.
- **Ruled OUT**: "writer only reachable from a retired path" (PULSE-IN-SINGLE-LEAD-01 sibling) —
  `find ~/Projects/leadv2 -iname leadv2-supervise-loop.sh` returns nothing (deleted,
  SUPERVISOR-DELETE-01 2026-08-17, hook L4-10). Writer is live: hook L213-217 →
  `pulse-beat.sh --check` (bg) → `_run_beat()` L368 → `bash "$BROAD_STATUS_SH"` — already-fixed
  defect, does not recur here. (Concurrency: `_stamp_epoch` PID-suffixes its tmp, L102; L1423/L226
  don't — real but secondary race, see Out of scope.)

## Files allowlist
- `plugins/leadv2/scripts/leadv2-broad-status.sh` — guard L1423-1426; `_emit_ready_line` sources
  `at=` from `FOUNDER_STATUS_EPOCH_PATH` (fallback: stat) not `$BEAT_AT`; add `_file_age_s()`.
- `plugins/leadv2/hooks/leadv2-single-lead-beat.sh` — DELIVER L161-196: staleness in bash from
  the same epoch file; branch CTX deterministically.
- `plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh` (extend) OR new
  `.../tests/test-broad-status-stale-file.sh` (to-create) — pick one.
- `tests/run-all.sh` — only if stem-match misses; append one `EXTRA_SUITE_MAP` row (L134+), never reorder.
- Off-limits: `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`,
  `tests/known-red-suites.txt`, `leadv2-alarm-dedupe.sh` (keep `dedupe_value` on `$BEAT_AT`),
  `~/MythicalGames`, `m3` settings.json, `main` branch.

## Steps
1. `_file_age_s()` in `leadv2-broad-status.sh`: reads `FOUNDER_STATUS_EPOCH_PATH`, returns
   `now - file_epoch` (missing/non-numeric epoch → 0, fails safe as maximally stale).
2. Guard L1423: `if printf ... && mv ... && _stamp_epoch; then _emit_ready_line "$ROWS_N"; else
   _emit_fail_line "founder-status.md write failed"; fi` — mirrors L245/L1349.
3. `_emit_ready_line`: `age=$(_file_age_s)`; `at=` from the epoch value (ISO8601), not
   `$BEAT_AT`; append `stale=1` when `age >= ${LEADV2_SINGLE_LEAD_BEAT_S:-1800}`. `dedupe_value`
   stays on `$BEAT_AT` (beat identity, not display truth).
4. Hook DELIVER: same epoch/age calc; when stale, swap owner-role "paste verbatim" for a stale notice forbidding relay-as-current (guest-role CTX is already safe — leave it).
5. Extend/create the suite hermetically (stub collector/claude, throwaway `LEADV2_PROJECT_ROOT`).
6. `tests/run-all.sh --scope changed` — confirm your suite is selected.

## Acceptance commands (re-runnable)
```bash
cd ~/Projects/leadv2
F=/tmp/broad-status-accept/docs/leadv2; mkdir -p "$F"
EPOCH_25H=$(( $(date +%s) - 25*3600 ))
printf '%s\n\nold\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$F/founder-status.md"
printf '%s' "$EPOCH_25H" > "$F/.founder-status-epoch"
# (a) fake the file 25h old, assert NO plain (non-stale) READY:
touch -t "$(date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || date -d '25 hours ago' +%Y%m%d%H%M.%S)" "$F/founder-status.md"
LEADV2_PROJECT_ROOT=/tmp/broad-status-accept LEADV2_FOUNDER_STATUS_PATH="$F/founder-status.md" \
  LEADV2_FOUNDER_STATUS_EPOCH_PATH="$F/.founder-status-epoch" \
  bash plugins/leadv2/scripts/leadv2-broad-status.sh
grep 'BROAD_STATUS_READY' "$F/supervise-loop.log" | tail -1 | grep -qv 'stale=1' && echo FAIL || echo PASS
# (b) fresh file (real run, real write) -> plain READY must appear:
bash plugins/leadv2/scripts/leadv2-broad-status.sh
tail -1 "$F/supervise-loop.log" | grep -q 'BROAD_STATUS_READY' && tail -1 "$F/supervise-loop.log" | grep -qv 'stale=1' && echo PASS || echo FAIL
# (c) at= equals the file's own mtime, not now:
LINE_AT=$(tail -1 "$F/supervise-loop.log" | sed -n 's/.* at=\([^ ]*\).*/\1/p')
LINE_EPOCH=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$LINE_AT" +%s 2>/dev/null || date -u -d "$LINE_AT" +%s)
FILE_EPOCH=$(stat -f %m "$F/founder-status.md" 2>/dev/null || stat -c %Y "$F/founder-status.md")
[ "$LINE_EPOCH" = "$FILE_EPOCH" ] && echo PASS || echo "FAIL: $LINE_EPOCH != $FILE_EPOCH"
```
Report all three exit states verbatim, macOS AND linux container, per shared-constraints.md.

## Negative control
Mutate INSIDE `_file_age_s()`'s body (never top-level): force `now - file_epoch` to
unconditionally `printf '%s' 0` — every call reports "age 0 = fresh." Run your suite (or
`tests/run-all.sh --scope changed`) — must go RED (25h-stale fixture loses its `stale=1`).
Revert, show GREEN. Record both exit codes verbatim.

## Decision: (a) suppress / (b) label-stale / (c) regenerate-first
**Primary: (b).** `leadv2-broad-status.sh` already carries a standing "[Critical] a degraded beat
must still SPEAK" invariant (ANTI-SILENCE-ONE-MECHANISM-01, L199-207) — suppression (a) would
violate a decision already encoded in this file. **Fallback: (c)-flavored** — DELIVER runs before
an unconditional TRIGGER (`pulse-beat.sh --check`, hook L213-217) every fire, so async self-heal
already retries each beat; no new trigger needed. (a) is never the sole behavior.

## Out of scope
- Diagnosing WHY the L1423 write can fail in prod (perms/race/disk) — runtime forensics, not
  this lane; the guard + epoch-sourced `at=` makes the failure visible regardless of cause.
- `leadv2-alarm-dedupe.sh`, dispatch scripts, or hook *registration* (wiring is correct — only
  DELIVER logic inside the already-registered hook changes).
- Resurrecting `leadv2-supervise-loop.sh` — confirmed deleted, do not recreate.
- PID-suffixing L1423/L226's tmp files (`_stamp_epoch` already PID-suffixes its own, L102) —
  optional hardening for a secondary race, not required for acceptance.

---

## LEAD ADDENDUM — the stamp-agreement check passes on stale data. Observed 2026-09-03.

The relay protocol says: compare the ready-line's `at=` with the timestamp on line 1 of
`founder-status.md`; if they differ, the file is from an earlier beat. Measured this beat:

```
beat fired at : 2026-09-03T19:03:23Z
ready-line at=: 2026-09-03T18:52:11Z
file line 1   : 2026-09-03T18:52:11Z   <- agrees, so the check PASSES
file mtime    : 2026-09-03T19:03:20Z   <- written seconds ago
file line 2   : "19:03 · посты 0/6 …"  <- and line 2 disagrees with line 1
```

So the file was regenerated NOW and stamped with an 11-minute-old time, and the two numbers the
protocol compares agree because they come from the SAME stale source. The check cannot detect
this: it compares a value against a copy of itself.

Two things follow for this row:

1. The fix is not only "carry the file's mtime instead of the beat's". The stamp must be the time
   the CONTENT was gathered, and the file must not contain two different times for one snapshot —
   line 1 saying 18:52 while line 2 says 19:03 is the defect visible inside a single file.
2. Add to acceptance: regenerate the file and assert every timestamp it carries refers to the same
   gathering, and that a consumer comparing them cannot get a false PASS from two copies of one
   stale value.
