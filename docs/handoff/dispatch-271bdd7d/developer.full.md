verdict: APPROVE
next_action: review_round_2

# LIVENESS-HAS-NO-SUITE-01 — developer full deliverable

Full census + design rationale is in `docs/handoff/LIVENESS-HAS-NO-SUITE-01/report.md`
(that is this lane's own evidence artifact, per lane-mission.md's boundary that notes live
there). This file carries the acceptance evidence the DoD gate checks for: full negative-
control run output, EXTRA_SUITE_MAP diff proof, and the `--scope changed` selection proof.

## Files changed

- `plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh` (new, 9 checks)
- `tests/run-all.sh` (append-only: 3 new EXTRA_SUITE_MAP rows, via temp-file + mv, no existing
  line reformatted or moved)
- `docs/handoff/LIVENESS-HAS-NO-SUITE-01/report.md` (census + evidence)

## Census (short form — full table in report.md)

6 authoritative liveness-answering locations found and characterized:
1. `lib/leadv2-lane-state.sh` — `alive()`/`lane_alive`: (pid, start-time) pair, the mission's
   reference rule. Finding F1: `lane_alive` collapses "no record" and "dead" into the same
   rc=1 — it does NOT satisfy the tri-state-in-return-value requirement by itself.
2. `leadv2-lane-heartbeat.sh` — `resolve_verdict()` + the `status` command's not-found branch:
   genuinely tri-state at the rc level (verdict rows rc=0, no-record rc=4). Finding F2:
   `pid_confirmed_dead()` is bare `kill(pid,0)`, no start-time corroboration — vulnerable to
   case 5 unlike #1.
3. `leadv2-lane-liveness.sh` — a third, independent (pid, lstart) corroboration implementation,
   1065-line python-in-heredoc. Documented, not exercised by a mutation control (no safe
   function-level seam found within this lane's time budget).
4. `lib/leadv2-watch-lifecycle.sh` — `kill -0` + per-pid cmdline-substring check against a
   caller-supplied needle (never a whole-process-table scan). Verified clean by T3/T4.
5. `leadv2-status-surface.sh` — `_pid_alive()` (R4): EPERM-as-alive (case 6) + rc captured
   directly from command substitution (case 7/8 avoided). Good reference, out of scan scope
   (3353-line file).
6. `leadv2-dispatch-product-close.sh` — explicit "NEVER uses pgrep -f" comment, already
   documents/avoids case 1/3.

Real violators found OUTSIDE this suite's scan scope, reported not fixed (off-limits:
`plugins/leadv2/scripts/*.sh` may not be edited in this lane):
- `leadv2-fanout.sh:1244` — `pgrep -f "/leadv2 ${tid}"` (case 1/3).
- `leadv2-spawn-rate.sh:119` — `ps -Ao comm=,etimes= | grep -E 'leadv2-(...)'` (case 11).

## Suite design

`plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh`, 9 checks: T0 (bash -n) + T1..T4,
each with its own mutation-tested negative control (T1NC/T2NC/T3NC/T4NC). Every mutation is
inserted INSIDE a real function body (`_lv2_lane_state_mutate()` in lib/leadv2-lane-state.sh,
or the `not_found` branch of leadv2-lane-heartbeat.sh's `status` command) on a SCRATCH copy
(`.nc-*` files under an EXIT trap, never committed, never the tracked file) — never a
top-level/whole-file change.

- T1: `lane_alive()` on a pid whose OBSERVED start time mismatches the RECORDED one (case 5,
  pid reuse) answers dead, while naive `kill -0` on the same still-genuinely-alive pid answers
  alive.
- T2: `leadv2-lane-heartbeat.sh status` on an unregistered task_id returns rc 4, distinct from
  BOTH a live answer (rc 0, running) and dead answer (rc 0, dead) — cases 4, 12.
- T3: static scan — neither `lib/leadv2-lane-state.sh` nor `lib/leadv2-watch-lifecycle.sh`
  contains a `pgrep -f` or `ps ... | grep` liveness check — cases 1, 2, 3, 11.
- T4: static scan — neither file reads `$?` after a value-losing pipe stage (head/tail/wc/
  sort/uniq/column) instead of from the command itself — cases 7, 8.

## Falsification set — raw output

### bash -n

```
$ bash -n plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh && echo SYNTAX_OK
SYNTAX_OK
$ bash -n tests/run-all.sh && echo SYNTAX_OK
SYNTAX_OK
```

### Full suite run — negative controls red-then-green (baseline_rc/mutated_rc pairs)

```
[TEST] T0: bash -n on the two canonical liveness libs + heartbeat reader
[TEST] PASS: T0: bash -n OK
[TEST] T1: lane_alive() with a mismatched start time -> dead, not alive
[TEST] PASS: T1: pid genuinely alive (naive kill-0 rc=0) but lane_alive correctly says dead (rc=1) on start-time mismatch
[TEST] T1-NC: mutating alive()'s pair comparison must flip T1's verdict
[TEST] T1-NC: baseline_rc=1 (from T1, unmutated) mutated_rc=0
[TEST] PASS: T1-NC: mutated alive() now (wrongly) reports the reused pid as alive (rc=0) -- the negative control is red as required, proving T1 is falsifiable
[TEST] T2: no record at all -> return code distinct from BOTH alive and dead
[TEST] T2: rc_alive=0 ({
  "task_id": "ALIVE",
  "status": "running",
  "reason": "heartbeat age 0.0m <= 25m threshold",
  "backend": "terminal",
  "pid": 96623
}) rc_dead=0 ({
  "task_id": "DEAD",
  "status": "dead",
  "reason": "heartbeat age 60.0m > 25m AND pid=999999 confirmed gone (kill -0 failed)",
  "backend": "terminal",
  "pid": 999999
}) rc_unknown=4 ({"error": "not_found", "message": "task_id NEVER-REGISTERED not in active.yaml"})
[TEST] PASS: T2: absent-record rc=4 differs from both alive(rc=0) and dead(rc=0) in the RETURN VALUE, not only in text
[TEST] T2-NC: mutating the not_found exit code must collapse it onto rc=0
[TEST] T2-NC: baseline_rc=4 (from T2, unmutated) mutated_rc=0
[TEST] PASS: T2-NC: mutated not_found path now (wrongly) returns rc=0, indistinguishable from a real verdict -- the negative control is red as required
[TEST] T3: static scan -- no pgrep -f / ps|grep in the two canonical liveness libs
[TEST] PASS: T3: no process-name-pattern liveness check found in scan scope
[TEST] T3-NC: inserting a pgrep -f line inside a real function body must be caught
[TEST] T3-NC: baseline_rc=0 (from T3, unmutated) mutated_rc=1
[TEST] PASS: T3-NC: scanner caught the injected pgrep -f and named file:line -- .../plugins/leadv2/scripts/lib/.nc-pattern-leadv2-lane-state.sh:36: process-name-pattern liveness check: pgrep -f "$1" >/dev/null 2>&1 && return 0  # NC-MUTATION
[TEST] T4: static scan -- no $? captured after head/tail/wc/sort/uniq in the two canonical liveness libs
[TEST] PASS: T4: no post-filter-pipe $? capture found in scan scope
[TEST] T4-NC: inserting a piped-through-head command + trailing $? read must be caught
[TEST] T4-NC: baseline_rc=0 (from T4, unmutated) mutated_rc=1
[TEST] PASS: T4-NC: scanner caught the post-filter-pipe $? read and named file:line -- .../plugins/leadv2/scripts/lib/.nc-pipe-leadv2-lane-state.sh:36: $? read after a value-losing pipe stage instead of from the command itself: ps -eo pid,comm | head -3  # NC-MUTATION

=== test-liveness-tristate-01.sh: 9 passed, 0 failed ===
```

### EXTRA_SUITE_MAP registration (append-only, temp-file + mv — verified no reformatting)

Appended 3 lines directly before the closing `"` of the existing `EXTRA_SUITE_MAP` string in
`tests/run-all.sh`, written via a Python script that produced `tests/run-all.sh.tmp` then
`mv`d over the original (no in-place edit):

```
leadv2-lane-state.sh:plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh
leadv2-lane-heartbeat.sh:plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh
leadv2-watch-lifecycle.sh:plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh
```
`bash -n tests/run-all.sh` → `SYNTAX_OK` (above). Diff below (last lines of the file only,
context = the pre-existing anchor line + the 3 new rows):
```
$ git diff tests/run-all.sh | tail -8
+leadv2-lane-state.sh:plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh
+leadv2-lane-heartbeat.sh:plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh
+leadv2-watch-lifecycle.sh:plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh"
-leadv2-repo-install.sh:plugins/leadv2/scripts/tests/test-repo-install-tracked-settings.sh"
+leadv2-repo-install.sh:plugins/leadv2/scripts/tests/test-repo-install-tracked-settings.sh
```
(the only "change" to the anchor line is its trailing `"` moving to the new last row, since
bash string literals need exactly one closing quote — every other existing line is untouched.)

### `--scope changed` selection proof

`tests/run-all.sh`'s self-select rule (its own comment: *"A changed test suite must select
itself even when its matching production file did not change in this run"*) matches:
```bash
case "${cf}" in
  plugins/leadv2/scripts/tests/test-*.sh|.claude/scripts/tests/test-*.sh|plugins/leadv2/tests/test-*.sh|tests/test-*.sh)
    add_suite "${ROOT}/${cf}"
    ;;
esac
```
against `git -C "${ROOT}" diff --name-only HEAD`. After staging:
```
$ git add plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh tests/run-all.sh
$ git diff --name-only HEAD | grep -v ^docs/leadv2
docs/LEAD_V2_STATE.md
plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh
tests/run-all.sh
```
`plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh` is in that list and matches the
case pattern verbatim, so `add_suite` fires under `--scope changed`.

**Honesty note — what I did NOT do:** I did not paste a full `run-all.sh --scope changed`
execution transcript reaching our suite. `run-all.sh` unconditionally runs
`plugins/leadv2/scripts/tests/run-core-offline.sh` FIRST (line 111-112, gated only on the file
existing, not on scope), and that nested wrapper is independently documented (session memory
`run-all-changed-scope-runtime`) as taking >10 minutes alone. A background run under a 90s
window only reached `[RUN] .../run-core-offline.sh` (its first line) and a second attempt under
a 15s `bash -x` trace captured only 9 of the selection-phase `add_suite` calls before I had to
kill it (per the coordinator's instruction not to loop further verification). I verified
selection via the exact case-pattern match instead of waiting out the nested-run transcript.
This is the one acceptance item I could not fully execute end-to-end within budget — the
static-match proof above is real but is not the same as a green `[PASS]` line for our suite
printed by a completed `--scope changed` run.

### macOS vs Linux

Ran entirely on macOS (Darwin 25.5.0, this worktree's host). This suite does not call the
route arbiter (`leadv2-route-arbiter`) at all — it only sources `lib/leadv2-lane-state.sh`,
`lib/leadv2-watch-lifecycle.sh` (never invoked, only static-scanned), `leadv2-lane-heartbeat.sh`,
and `leadv2-active-registry.sh` — so ROUTE-ARBITER-DIES-SILENTLY-ON-LINUX-01 does not apply to
it. Did not additionally run it in a Linux container; stating this plainly rather than
presenting the macOS run as covering both.

## What I deliberately left alone

- `leadv2-lane-liveness.sh` (biggest decider, 1065 lines, no safe function-level mutation seam
  found within this lane's time budget) — documented in the census, not exercised by a
  mutation-tested check in this suite. Natural follow-up lane.
- The two real process-name-pattern violators (`leadv2-fanout.sh:1244`,
  `leadv2-spawn-rate.sh:119`) — reported, not fixed. `plugins/leadv2/scripts/*.sh` edits are
  off-limits for this lane per `lane-mission.md` ("если перепись нашла нарушителя, это находка
  в отчёт, а не правка в этой линии").
- Finding F1 (`lane_alive()` collapses "no record" into the same rc as "dead") — reported, not
  fixed, same off-limits boundary. This is exactly why T2 targets `leadv2-lane-heartbeat.sh`
  (which does not have this gap) rather than `lib/leadv2-lane-state.sh` (which does) for the
  tri-state-in-return-value requirement.
- `docs/leadv2/*` runtime-state files dirty in this worktree from unrelated concurrent lane
  merges (bus.jsonl, active.yaml, merge-queue.jsonl, etc.) — untouched, not staged, not
  committed by this lane (off_limits per the DoD gate's item (d)).
- `docs/LEAD_V2_STATE.md` shows as modified in `git diff --name-only HEAD` — this is lead-owned
  state; I did not intentionally edit it and did not stage or commit it.

DELIVERABLE_COMPLETE
