# DISPATCH-REENTRY-SELF-RACE — report

## Bug

`_resolve_pinned_placement()` in `leadv2-dispatch-code.sh` refuses `--worktree`
re-entry into a lane it is itself about to occupy. The only "live" evidence is
a `pid_source=lead_durable`, `starting:*` row this SAME overall run's own
earlier phase (e.g. Gate 1's `plan_gate_pre_dispatch` registration) wrote for
that lane moments earlier, under the durable lead pid every retry shares.
Every retry re-reads that same self-written row and refuses again — the age
resets each time (`started_at` re-stamped on refresh), so the refusal can
never clear on its own (measured three times pre-fix: ages 61/64/64s, always
fresh).

Root cause per the mission text: `leadv2-lane-liveness.sh`'s
`registered_no_stream` rung (~1189-1214) emits `starting:<age>` without the
`pid_source not in (lead_durable, watcher)` exclusion every OTHER liveness
rung in that file already applies (lines 821, 1063, 1231, 1374, 1415), and
`leadv2-dispatch-code.sh:1188` treats `starting:*` as live and refuses.

## Approach taken: (b), not (a)

The mission offered two directions:
- (a) run the probe before this run registers its own lane row
- (b) exclude the row whose identity belongs to the current run from the
  probe's input

**(a) is inapplicable.** Traced dispatch-code.sh's own active.yaml
registration (~line 9121): it runs AFTER `_resolve_pinned_placement`, so
dispatch-code.sh never registers before probing itself — the offending row
originates from a PRIOR phase (Gate 1), not from anything reorderable inside
this function.

**(b) was taken, but NOT by editing `leadv2-lane-liveness.sh`.** A blanket
`pid_source=lead_durable` exclusion on the `registered_no_stream` rung would
suppress the required negative control too: a genuinely different lead
session's own pre-dispatch registration is equally `pid_source=lead_durable`
and MUST still refuse. Rung-level exclusion cannot distinguish "self" from
"foreign" — both look identical to the liveness script, which has no notion
of "who is asking".

Instead, the fix lives in the CALLER (`_resolve_pinned_placement`,
`leadv2-dispatch-code.sh`), using an IDENTITY check: when a probe verdict is
`alive`/`starting:*` and the row's `pid_source` is `lead_durable`, compare the
row's `pid` against **this run's own** durable pid, computed via
`_lv2_durable_pid()` — the same `$PPID`-walk primitive
`leadv2-active-registry.sh` uses to stamp `lead_durable` rows in the first
place (already sourced unconditionally near the top of
`leadv2-dispatch-code.sh`, so no new sourcing was needed). A match proves the
row is this run's own earlier registration, not external evidence, so it is
skipped (`continue`) rather than counted as live. A row with a *different*
`pid` — a different lead session — still counts as live and still refuses.
`leadv2-lane-liveness.sh` is untouched; the liveness ladder's semantics for
every other caller are unchanged.

## Diff

`plugins/leadv2/scripts/leadv2-dispatch-code.sh` — 24 lines added inside
`_resolve_pinned_placement()`'s liveness-probe loop, immediately before the
existing `_live=1; break`:

```diff
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

Plus a new test file, `plugins/leadv2/scripts/tests/test-dispatch-reentry-self-race.sh`
(`# run-all-triggers: leadv2-dispatch-code`), giving the two required
directions their own suite.

## Acceptance output — both directions

### RED (pre-fix, `HEAD` content via `LEADV2_DISPATCH_CODE_FILE`)

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

This reproduces the exact bug shape from the mission report
(`lane_placement_refused ... reason=lane_is_live ... verdict=starting:5`,
i.e. the same `starting:<age>` refusal pattern measured live at ages
61/64/64s), and proves R-b (negative control) was already green even before
the fix — the test genuinely isolates the self-race, not a broken guard.

### GREEN (post-fix, working tree)

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

`test-lane-placement-pin.sh`'s 11 failures (P-b/P-g/P-i and others) are
PRE-EXISTING: re-ran the identical suite against unmodified `HEAD` content —
same 16 passed / 11 failed, same failure identities (including
`P-e: existing live-lane refusal case`, the pre-existing negative control,
passing in both runs) — proving this diff causes zero regressions in that
suite.

`test-lane-liveness-authoritative.sh` also carries one pre-existing failure
(`supervise emits log-only lane while registry is empty`), unrelated:
`leadv2-lane-liveness.sh` is byte-unchanged by this diff (that suite's own
md5 tripwire confirms it), and I made no edits to that file.

## Changed-scope suite selection

`plugins/leadv2/scripts/tests/test-dispatch-reentry-self-race.sh` is git-
staged (admission requires tracked-or-staged, per
`lib/leadv2-suite-discovery.sh`), and its `# run-all-triggers: leadv2-dispatch-code`
header is picked up by `LEADV2_RUN_ALL_LIST_TRIGGERS=1 tests/run-all.sh --scope
changed`, confirmed present in the trigger listing alongside
`test-placement-refusal-exits-before-gates.sh` and `test-lane-placement-pin.sh`
(both sharing the same `leadv2-dispatch-code` trigger). The full trigger fans
out to 100+ suites under that one trigger key (including the always-on,
~900s-class suites); ran the three suites directly exercising
`_resolve_pinned_placement` (shown above) as the bounded, targeted substitute
for the full sweep, all green with no new regressions versus the pre-fix
baseline.

`bash -n` passes on both touched files
(`plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
`plugins/leadv2/scripts/tests/test-dispatch-reentry-self-race.sh`).
