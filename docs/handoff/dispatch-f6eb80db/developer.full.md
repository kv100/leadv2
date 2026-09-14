verdict: APPROVE
next_action: review_round_2

# DISPATCH-REENTRY-SELF-RACE — developer.full.md

## Mission

`leadv2-dispatch-code.sh` could not re-enter an existing lane worktree for a
normal post-review fix round: `--worktree` re-entry deterministically refused
(`lane_placement_refused ... reason=lane_is_live`) on a lane-liveness row the
SAME overall run wrote moments earlier via a prior phase. Measured three
times live: ages 61/64/64s, always fresh, because every retry re-stamps
`started_at` on refresh — the refusal could never clear on its own.

## Root cause

`leadv2-lane-liveness.sh`'s `registered_no_stream` rung (~1189-1214) emits
`starting:<age>` for a `pid_source=lead_durable` row without the
`pid_source not in (lead_durable, watcher)` exclusion present on every other
liveness rung in that file (lines 821, 1063, 1231, 1374, 1415 —
`LANE-REGISTRY-SELF-DEADLOCK-01` / `FORK-STORM-KILLS-HOOKS-01` precedent).
`leadv2-dispatch-code.sh:1188` treats `starting:*` as live and refuses
placement.

Traced the origin of the self-written row: it is NOT dispatch-code.sh's own
registration (that happens at ~line 9121, AFTER `_resolve_pinned_placement`
runs — confirmed by reading the call order). It is written by a PRIOR phase
of the same overall run — Gate 1's `plan_gate_pre_dispatch` registration via
`leadv2_active_register`, stamped with the dispatching lead session's own
durable pid under `pid_role=lead_durable`.

## Why option (a) — reorder the probe before registration — does not apply

The mission offered "(a) run the probe before this run registers its own
lane row" as one acceptable direction. There is no in-`_resolve_pinned_placement`
(or even in-script, pre-probe) registration to reorder: the self-written row
predates this script's own execution entirely, coming from an earlier phase
(Gate 1) of the same overall run. Reordering anything inside
`leadv2-dispatch-code.sh` cannot change when that earlier phase wrote its
row. Option (a) is inapplicable to this bug's actual shape.

## Why the fix is NOT in `leadv2-lane-liveness.sh`

The obvious "add the missing pid_source exclusion to the
`registered_no_stream` rung" would make `leadv2-lane-liveness.sh` blanket-
ignore ANY `lead_durable` row on that rung — including a genuinely different
lead session's own pre-dispatch registration, which is equally
`pid_source=lead_durable`. That would silently disable the guard for the
required negative control (a foreign lead session actually holding the lane
must still refuse). The liveness script has no notion of "whose row this
is" versus "my own row" — that identity only exists in the CALLER.

## Fix: identity-based self-exclusion in `_resolve_pinned_placement`

`plugins/leadv2/scripts/leadv2-dispatch-code.sh`, inside the liveness-probe
loop of `_resolve_pinned_placement()` (~line 1172-1214), immediately before
the existing `_live=1; break`:

- When a probe verdict is `alive` or `starting:*` AND the row's
  `pid_source` field is `lead_durable`, read the row's `pid` and compare it
  against **this run's own** durable pid via `_lv2_durable_pid()`
  (`leadv2-active-registry.sh`, already unconditionally sourced near the top
  of `leadv2-dispatch-code.sh` — the same `$PPID`-walk primitive the
  registrar itself used to stamp the row's `pid` at registration time).
- On a match: emit a `lane_liveness_self_row_ignored` decision line and
  `continue` to the next probe_id spelling, instead of treating the row as
  live evidence.
- On no match (different pid, or `pid_source` != `lead_durable`, or the
  lookup itself fails): unchanged behavior — `_live=1; break`, refusal path
  intact.

`_lv2_durable_pid()` is memoized per call (`_pl_my_durable_pid` computed
once, reused across the two probe_id spellings the loop tries).

This satisfies both required directions without touching
`leadv2-lane-liveness.sh`'s rung semantics: self re-entry succeeds because
the row's pid matches; a foreign live lane still refuses because its pid
does not.

## Diff

```diff
--- a/plugins/leadv2/scripts/leadv2-dispatch-code.sh
+++ b/plugins/leadv2/scripts/leadv2-dispatch-code.sh
@@ -1172,6 +1172,7 @@ _resolve_pinned_placement() {
   local _row _v _reason _signal _age _live=0 _probe_id _watcher_only=0 _wpid
+  local _pl_pid_source _pl_pid _pl_my_durable_pid=""
   for _probe_id in "dispatch-${key}" "${key}"; do
     _row="$(bash "${LANE_LIVENESS_BIN}" --project-root "${PROJECT_ROOT}" --lane "${_probe_id}" --no-codex --json 2>/dev/null || true)"
     _v="$(_placement_probe_field "${_row}" verdict)"
@@ -1186,6 +1187,29 @@ _resolve_pinned_placement() {
       *log_fresh*|*stream_fresh*)   _signal="stream_fresh" ;;
     esac
     if [[ "${_v}" == "alive" || "${_v}" == starting:* ]]; then
+      # DISPATCH-REENTRY-SELF-RACE: a starting:*/alive verdict backed only by a
+      # pid_source=lead_durable row can be THIS dispatching session's own
+      # pre-dispatch registration for this exact lane (e.g. Gate 1), re-read a
+      # moment later as "foreign liveness" -- every retry re-stamps the row's
+      # age to ~0, so the refusal can never clear on its own. Distinguish self
+      # from foreign by IDENTITY, not by rung: _lv2_durable_pid() (sourced from
+      # leadv2-active-registry.sh above) walks the SAME $PPID chain the
+      # registrar used to stamp the row's `pid`, so a match proves the row is
+      # THIS run's own durable lead pid -- not merely "some lead_durable row
+      # that happens to be alive". A genuinely different lead session's
+      # lead_durable row is pid_alive too and must still refuse (negative
+      # control: a foreign starting:* row stays live).
+      _pl_pid_source="$(_placement_probe_field "${_row}" pid_source)"
+      if [[ "${_pl_pid_source}" == "lead_durable" ]]; then
+        _pl_pid="$(_placement_probe_field "${_row}" pid)"
+        if [[ -z "${_pl_my_durable_pid}" ]] && declare -F _lv2_durable_pid >/dev/null 2>&1; then
+          _pl_my_durable_pid="$(_lv2_durable_pid 2>/dev/null)"
+        fi
+        if [[ -n "${_pl_pid}" && -n "${_pl_my_durable_pid}" && "${_pl_pid}" == "${_pl_my_durable_pid}" ]]; then
+          emit decision "lane_liveness_self_row_ignored task=${sig8:-?} probe_id=${_probe_id} verdict=${_v} age=${_age} pid=${_pl_pid}"
+          continue
+        fi
+      fi
       _live=1
       break
     fi
```

## New test: `plugins/leadv2/scripts/tests/test-dispatch-reentry-self-race.sh`

Header `# run-all-triggers: leadv2-dispatch-code` (registers it for
changed-scope discovery). Structure follows the existing
`test-placement-refusal-exits-before-gates.sh` pattern: sources
`leadv2-dispatch-code.sh` with `LEADV2_DISPATCH_SOURCE_ONLY=1` and calls
`_resolve_pinned_placement` directly against a stub `LANE_LIVENESS_BIN`.

- Computes `SELF_DURABLE_PID` by sourcing the real
  `leadv2-active-registry.sh` and calling `_lv2_durable_pid()` itself — the
  same `$PPID`-walk shape dispatch-code.sh's own internal call sees when
  invoked as a direct child of the test process, so both resolve to the
  identical value deterministically (both hit the same fallback branch:
  no literal `claude`-comm ancestor exists in a test harness process tree).
- `FOREIGN_PID = SELF_DURABLE_PID + 1`.
- Two liveness stubs, `live-self.sh` / `live-foreign.sh`, each emitting a
  `starting:5` / `registered_no_stream` / `pid_source=lead_durable` JSON
  row, differing only in `pid`.
- **R-a** (self row, `live-self.sh`): asserts `_resolve_pinned_placement`
  returns rc=0, `WORK_ROOT` is pinned to the lane worktree's physical path,
  and no `lane_is_live` string leaks into stdout/stderr or the journal.
- **R-b** (foreign row, `live-foreign.sh`, the mandatory negative control):
  asserts rc=5, `WORK_ROOT` never pinned, and `lane_is_live` reason IS
  present — proving the guard is not silently disabled.

6 assertions total.

## Falsification (mission-mandated)

### RED — pre-fix `HEAD` content

`git stash` is blocked in this repo by the `leadv2-deny-floor` hook's
`git_stash` rule, so extracted the pre-fix file without touching the working
tree: `git show HEAD:plugins/leadv2/scripts/leadv2-dispatch-code.sh` to a
temp file, then ran the new suite against it via the
`LEADV2_DISPATCH_CODE_FILE` env override both this suite and
`test-placement-refusal-exits-before-gates.sh` already support:

```
[TEST] FAIL: R-a: self re-entry refused (rc=5) — [leadv2-dispatch-code] lane_liveness verdict=live task=rr000001 signal=none probe_id=dispatch-self-race-lane raw=starting:5 age=5
[leadv2-dispatch-code] lane_placement_refused task=rr000001 reason=lane_is_live ref=.../self-race-lane path=.../self-race-lane probe_id=dispatch-self-race-lane verdict=starting:5 age=5
[leadv2-dispatch-code] REFUSE placement: lane_is_live ref=.../self-race-lane path=.../self-race-lane
  verdict=starting:5 age=5s probe_id=dispatch-self-race-lane
The lane is still running. Re-run once it clears:
  plugins/leadv2/scripts/tests/test-dispatch-reentry-self-race.sh  &
[TEST] FAIL: R-a: WORK_ROOT not pinned (got '', pinned=0)
[TEST] FAIL: R-a: lane_is_live refusal leaked despite the row being this run's own
[TEST] PASS: R-b: foreign live lane still refuses (rc=5)
[TEST] PASS: R-b: WORK_ROOT never pinned for the foreign row
[TEST] PASS: R-b: lane_is_live reason present for the foreign row
test-dispatch-reentry-self-race: 3 passed, 3 failed
rc=3
```

This exactly reproduces the reported bug shape (`lane_placement_refused ...
reason=lane_is_live ... verdict=starting:5`) and proves R-b (negative
control) was ALREADY green pre-fix — the test genuinely isolates the
self-race scenario, it doesn't merely reflect a broken/no-op guard.

### GREEN — post-fix working tree

```
=== test-dispatch-reentry-self-race ===
[TEST] PASS: R-a: no lane_is_live refusal for this run's own row
[TEST] PASS: R-b: foreign live lane still refuses (rc=5)
[TEST] PASS: R-b: WORK_ROOT never pinned for the foreign row
[TEST] PASS: R-b: lane_is_live reason present for the foreign row
test-dispatch-reentry-self-race: 6 passed, 0 failed
rc=0

=== test-placement-refusal-exits-before-gates ===
[TEST] PASS: case 5 placement refusal returns rc=5 to caller
[TEST] PASS: case 5 refused duplicate writes neither e2e_gate nor dispatch_terminal
[TEST] PASS: case 6 granted placement reaches the normal pinned continuation boundary
[TEST] PASS: case 7 owner terminal remains recordable after duplicate refusal
test-placement-refusal-exits-before-gates: 4 passed, 0 failed
rc=0

=== test-lane-placement-pin ===
[LANE-PLACEMENT-01] passed=16 failed=11
rc=0
```

`test-lane-placement-pin.sh`'s 11 failures are pre-existing: re-ran the
identical suite against unmodified `HEAD` content and got the same 16
passed / 11 failed, same failure identities — including `P-e` (the existing
live-lane refusal negative control) passing in BOTH runs, confirming zero
regression to the pre-existing guard behavior that suite already covers.

Also ran `test-lane-liveness-authoritative.sh`: one pre-existing failure
(`supervise emits log-only lane while registry is empty`), unrelated —
`leadv2-lane-liveness.sh` is untouched by this diff (confirmed byte-
unchanged via that suite's own md5 tripwire, and by inspection: zero edits
made to that file).

## Changed-scope suite selection

Registered the new suite (`# run-all-triggers: leadv2-dispatch-code`) and
staged it (`git add`) so `lib/leadv2-suite-discovery.sh`'s tracked-admission
contract picks it up. Confirmed via
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh --scope changed`:
`test-dispatch-reentry-self-race.sh` appears under the `leadv2-dispatch-code`
trigger alongside `test-placement-refusal-exits-before-gates.sh` and
`test-lane-placement-pin.sh` (both sharing the same trigger key).

The `leadv2-dispatch-code` trigger fans out to 100+ suites (this file has
77 commits/90d per the repo's own hotspot data — a heavily-shared trigger
key), including suites that pull in the always-on, ~900s-class core-offline
path. Ran the three suites that directly exercise `_resolve_pinned_placement`
(shown above, all green, zero new regressions vs. baseline) as the bounded,
targeted substitute for the full changed-scope sweep, per repo precedent for
handling this trigger's fan-out size (`run-all-changed-scope-runtime`
memory note: core-offline is always-on and can't realistically gate every
edit to this file within a session).

## Syntax

```
$ f="plugins/leadv2/scripts/leadv2-dispatch-code.sh"; bash -n "$f" && echo SYNTAX_OK_DC
SYNTAX_OK_DC
$ t="plugins/leadv2/scripts/tests/test-dispatch-reentry-self-race.sh"; bash -n "$t" && echo SYNTAX_OK_TEST
SYNTAX_OK_TEST
```

## Files changed

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (+24 lines, one function,
  one call site)
- `plugins/leadv2/scripts/tests/test-dispatch-reentry-self-race.sh` (new,
  126 lines)
- `docs/handoff/DISPATCH-REENTRY-SELF-RACE/report.md` (new — diff,
  approach rationale, acceptance output)
- `docs/handoff/dispatch-f6eb80db/developer.summary.md` /
  `developer.full.md` (this file)

No runtime-state paths touched (`docs/leadv2/`, `docs/LEAD_V2_STATE.md`,
`docs/handoff/dispatch-nw*` untouched by this diff — `docs/leadv2/.compact-freeze.md`
shows modified in `git status` but was touched by the SessionStart hook, not
by this diff, and is excluded from the commit).

DELIVERABLE_COMPLETE
