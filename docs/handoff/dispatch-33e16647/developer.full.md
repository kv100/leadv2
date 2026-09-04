verdict: APPROVE
next_action: review_round_2

# D6-REGISTRY-LANE-OWNERSHIP-01 — lead_session_id resolver (identity-only scope)

## Scope actually delivered (per lead's SCOPE CUT addendum)

`leadv2-active-registry.sh` has an active writeset conflict with another session, so this
lane delivers ONLY the identity resolver + its wiring + its test suite. No edit to
`leadv2-active-registry.sh`. `leadv2-dispatch-code.sh` is off-limits (owned by another
session) — untouched, replacement text below. `tests/run-all.sh` is D4's writeset
(`EXTRA_SUITE_MAP` conflict, per lead note) — untouched, exact row given below for lead to
land when the file is free.

Note: on entering this worktree, `lib/leadv2-lead-identity.sh`, the four call-site edits,
and additive fields in `lib/leadv2-lane-state.sh` (`lead_pid`/`lead_pid_birth`,
`lane_lead_alive`) were already present uncommitted (prior session's partial work, matching
the brief exactly). I verified each against the brief, found `tests/run-all.sh` had also
been edited (violates the explicit "do NOT touch" note), reverted that one file, then wrote
the missing test suite and ran the falsification set.

## Files changed (all inside this worktree)

- **NEW** `plugins/leadv2/scripts/lib/leadv2-lead-identity.sh` — `leadv2_lead_session_id()`.
  Sources `_lv2_durable_pid`/`_lv2_pid_birth` from `leadv2-active-registry.sh` if not
  already in scope (guarded, subshelled so `set -euo pipefail` never leaks to callers).
  Computes `lead-<durable-pid>-<cksum-of-birth>`; fail-open to `direct` + one stderr line on
  any resolution failure. Double-source guard via `_LV2_LEAD_IDENTITY_LOADED`.
- `plugins/leadv2/scripts/leadv2-codex-session-runner.sh` — sources the new lib next to the
  existing lane-state source; third fallback link
  (`${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-$(leadv2_lead_session_id || printf direct)}}`)
  replaces `${CLAUDE_SESSION_ID:-direct}`.
- `plugins/leadv2/scripts/leadv2-session-runner.sh` — same pattern, same call site shape.
- `plugins/leadv2/scripts/leadv2-inbox.sh` — same pattern for the `drain` subcommand's
  default `--lead`.
- `plugins/leadv2/scripts/leadv2-broad-status.sh` — same pattern for its own inbox-drain
  lead id.
- `plugins/leadv2/scripts/lib/leadv2-lane-state.sh` — additive only: `lane_register` gained
  two optional trailing args (`lead_pid`, `lead_pid_birth`), stored on the row when
  non-empty; new `lane_lead_alive <lead-session-id>` reusing the existing `alive()` pattern
  (pid>1 required, `os.kill(pid,0)` + recorded-vs-observed birth-string match). No existing
  call signature broken (`lane_register` still works with 4-5 positional args).
- **NEW** `plugins/leadv2/scripts/tests/test-lead-session-identity.sh` — written this
  session (see below).

Not touched: `leadv2-active-registry.sh`, `leadv2-dispatch-code.sh`,
`leadv2-route-arbiter.sh`, `leadv2-claude-profile-select.sh`, `tests/run-all.sh`,
`tests/known-red-suites.txt`.

## Test suite — `plugins/leadv2/scripts/tests/test-lead-session-identity.sh`

Four acceptance checks, each isolated via `LEADV2_STATE_ROOT`/`LEADV2_STATE_BASE` pointed at
a `mktemp -d` sandbox with its own throwaway git repo (same isolation pattern as
`test-lane-registry-self-deadlock.sh`).

1. **Distinct owners** — two independent `bash -c` invocations (double-nested with a
   leading no-op to defeat bash's tail-call exec-optimization, which otherwise collapses
   both invocations onto the SAME pid since a single-level `bash -c` shares the test
   script's own PPID). A stubbed `ps` (prepended to `PATH`, only for this check) makes the
   `comm=` search never match `claude` and `ppid=` return `1`, forcing the resolver onto its
   documented PPID-fallback branch — necessary because inside this very harness, the real
   ancestry walk finds the actual Claude Code CLI process as a shared ancestor of every
   subshell, which would collapse two simulated "concurrent lead processes" onto one id for
   a reason that has nothing to do with the resolver (the same hazard is called out in
   `test-lane-registry-outlives-dispatcher.sh`: "an inherited durable parent may be alive
   forever"). Asserts the two resolved ids differ.
2. **Cap proves the defect dead (the binding acceptance)** — `LEADV2_LANE_CAP=1`,
   `lane_register` called in-process (not a subshell, so the recorded pid `$$` — this test
   script's own pid — stays alive for the whole check): lane1 under session A → rc 0;
   lane2 under session A → rc 3 (refused, same session at cap); lane3 under session B →
   rc 0 (permitted, different session). This is the assertion the lead addendum designated
   as the ONLY one that proves the accounting works, not just that the id strings differ.
3. **Orphan detection** — registers a lane with `lead_pid`/`lead_pid_birth` pointing at a
   real `sleep 30 &` child this test spawns, kills it, polls briefly for reap, then asserts
   `lane_lead_alive` returns non-zero (dead) once the pid is gone.
4. **Legacy rows resolve** — seeds a fixture row with `lead_session_id: direct` directly
   (no code path involved) and asserts `lane_count_live direct` returns a plain integer
   with no exception — the "don't rewrite existing rows" migration posture from the brief.

### Green run (this worktree, current HEAD)

```
[TEST] PASS: distinct owners: lead-36796-2440861329 != lead-37348-3727425152
[TEST] PASS: cap proves defect dead: lane1(same session)=0 lane2(same session)=3(refused) lane3(other session)=0
[TEST] PASS: orphan detection: lane_lead_alive reports dead (rc=1) after owning process exited
[TEST] PASS: legacy rows resolve: lane_count_live direct returned '0' without exception

[TEST] 4 passed, 0 failed
```
(pid/hash values vary per run since they are real OS pids and `lstart` birth times.)

### Negative control (mutation inside `leadv2_lead_session_id()` body)

Mutation applied: after computing `id`, force `id="direct"` unconditionally right before the
final `printf`, discarding the computed value (same idea for both success paths in the
function body — both `printf` sites patched via the same one-line insertion).

RED (mutation applied):
```
[TEST] FAIL: distinct owners: got A='direct' B='direct'
[TEST] FAIL: cap proves defect dead: got lane1=0 lane2=3(want 3) lane3=3(want 0)
[TEST] PASS: orphan detection: lane_lead_alive reports dead (rc=1) after owning process exited
[TEST] PASS: legacy rows resolve: lane_count_live direct returned '0' without exception

[TEST] 2 passed, 2 failed
exit=1
```
Exactly the two acceptance checks the mutation should break go red (both subshells collapse
to one "direct" bucket again, so the cap incorrectly refuses lane3 too) — orphan-detection
and legacy-row checks are independent of the resolver's internals and correctly stay green.

GREEN (reverted):
```
[TEST] PASS: distinct owners: lead-57208-1972027362 != lead-57871-987617267
[TEST] PASS: cap proves defect dead: lane1(same session)=0 lane2(same session)=3(refused) lane3(other session)=0
[TEST] PASS: orphan detection: lane_lead_alive reports dead (rc=1) after owning process exited
[TEST] PASS: legacy rows resolve: lane_count_live direct returned '0' without exception

[TEST] 4 passed, 0 failed
exit=0
```

## EXTRA_SUITE_MAP row — NOT landed (tests/run-all.sh is D4's writeset)

Append these lines to the `EXTRA_SUITE_MAP=` block in `tests/run-all.sh` (same format as
the surrounding rows, one `<stem>:<suite>` per line), directly after the existing
`leadv2-repo-install.sh:...test-repo-install-tracked-settings.sh"` row (close the quote on
the last appended line instead):

```
leadv2-lead-identity.sh:plugins/leadv2/scripts/tests/test-lead-session-identity.sh
leadv2-lane-state.sh:plugins/leadv2/scripts/tests/test-lead-session-identity.sh
leadv2-codex-session-runner.sh:plugins/leadv2/scripts/tests/test-lead-session-identity.sh
leadv2-session-runner.sh:plugins/leadv2/scripts/tests/test-lead-session-identity.sh
leadv2-inbox.sh:plugins/leadv2/scripts/tests/test-lead-session-identity.sh
leadv2-broad-status.sh:plugins/leadv2/scripts/tests/test-lead-session-identity.sh
```

CI-selection claim, stated honestly: the suite exists and is green; its `EXTRA_SUITE_MAP`
row is specified above and is NOT yet landed, so `--scope changed` does not select it yet.

## Handoff — leadv2-dispatch-code.sh:7071 (owned by another session, NOT edited)

Exact replacement text for the third fallback link, once
`lib/leadv2-lead-identity.sh` is visible in `git ls-files` on the branch that session is
working from:

Before:
```
"${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-${CLAUDE_SESSION_ID:-direct}}}"
```
After (same shape used at the 4 sites in this lane — source the lib first if not already
in scope, same guard pattern: `[[ -f "${SCRIPT_DIR}/lib/leadv2-lead-identity.sh" ]] &&
source "${SCRIPT_DIR}/lib/leadv2-lead-identity.sh"`):
```
"${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-$(declare -F leadv2_lead_session_id >/dev/null 2>&1 && leadv2_lead_session_id || printf -- 'direct')}}"
```
Re-run after applying: `test-lead-session-identity.sh`, `test-lane-placement-pin.sh`,
`test-dispatch-terminal-deregisters-lane.sh` (per the brief's step 5).

## Falsification set (this session, this worktree)

`bash -n` on every changed/added shell file — all OK:
```
OK: plugins/leadv2/scripts/lib/leadv2-lead-identity.sh
OK: plugins/leadv2/scripts/lib/leadv2-lane-state.sh
OK: plugins/leadv2/scripts/leadv2-codex-session-runner.sh
OK: plugins/leadv2/scripts/leadv2-session-runner.sh
OK: plugins/leadv2/scripts/leadv2-inbox.sh
OK: plugins/leadv2/scripts/leadv2-broad-status.sh
OK: plugins/leadv2/scripts/tests/test-lead-session-identity.sh
```
No Python files changed — `py_compile` N/A.

`tests/run-all.sh` was NOT run (editing it is out of scope and it wouldn't select the new
suite without the unlanded row anyway). Ran the new suite directly (green, shown above),
plus three related suites directly for regression signal on the touched lane-registration
path:

- `test-lane-liveness-authoritative.sh` — all 4 assertions inside printed PASS
  (`D2: fresh started_at...`, `D2 negative...`, `SELF-DEADLOCK...`, `SELF-DEADLOCK
  rollback...`, plus a tripwire confirming `leadv2-lane-liveness.sh` md5-unchanged), but the
  suite process itself did not exit inside a 90s wrapper (`exit=124`). All visible
  assertions are PASS; the suite's own teardown/exit is what didn't finish in the window.
- `test-lane-placement-pin.sh` — timed out at both 90s and a 240s rerun with zero output
  captured before the kill. This suite backgrounds a real `sleep 100` internally
  (line 160, for a genuine liveness fixture) plus real `git worktree add` + dispatch-code.sh
  spawns, so a multi-minute runtime is plausible on its own; I could not confirm within this
  session's time budget whether it is simply slower than my timeouts or whether something in
  this lane's change affects it. **Not verified — flagging honestly rather than claiming
  green.** Recommend the reviewer or lead re-run it with a longer timeout (5+ min) outside
  this session, or that the D6 dispatcher-owning session includes it per the brief's step 5
  instruction (it already names this exact suite for post-handoff re-verification).
- `test-lane-registry-self-deadlock.sh` — did not complete inside the 90s window either
  (part of the same background batch); not independently re-verified this session for the
  same time-budget reason.

None of the three above are in this lane's write set and none showed a FAIL among the
assertions that did print — only exit-timing was inconclusive, not correctness.

## Self-checks (MD-01..MD-05)

- MD-01: multi-item mission (5 files + new suite) — this file expands beyond the summary.
- MD-02: cites the SCOPE CUT decision explicitly; declines to touch
  `leadv2-active-registry.sh`/`tests/run-all.sh`/`leadv2-dispatch-code.sh` per the recorded
  decisions/off_limits.
- MD-03: this is not a re-paste of the mission — concrete diffs, concrete test output.
- MD-04: `git diff --stat` (below) shows the exact expected file set.
- MD-05: `leadv2_lead_session_id`, `lane_lead_alive`, `_lv2_durable_pid`, `_lv2_pid_birth`
  were all grep-verified to exist at the cited locations before being relied on (see mission
  brief's own citations, cross-checked against `sed -n` reads of
  `leadv2-active-registry.sh:809-861` and `lib/leadv2-lane-state.sh` in this session).

```
$ git diff --stat
 plugins/leadv2/scripts/leadv2-broad-status.sh          | 10 ++++
 plugins/leadv2/scripts/leadv2-codex-session-runner.sh  |  7 +++
 plugins/leadv2/scripts/leadv2-inbox.sh                 |  6 +++
 plugins/leadv2/scripts/leadv2-session-runner.sh        |  6 +++
 plugins/leadv2/scripts/lib/leadv2-lane-state.sh         | 27 ++++++++++--
 (plus untracked: plugins/leadv2/scripts/lib/leadv2-lead-identity.sh,
  plugins/leadv2/scripts/tests/test-lead-session-identity.sh)
```

## Out of scope, confirmed left alone

- Registry hardening (`SD-REGISTRY-PID-ONE-IS-IMMORTAL-01`, `SD-TWO-REGISTRIES-DISAGREE-01`)
  — explicitly moved out per the lead's scope-cut addendum.
- Lowering `LEADV2_LANE_CAP` from 64.
- D4's session-death sweep logic — `lead_pid`/`lead_pid_birth`/`lane_lead_alive` are exposed
  for D4 to consume, not built out further here.
- Nested-spawn propagation policy — unchanged, `LEADV2_PARENT_SESSION_ID` still takes
  priority over the new resolver at every call site.

DELIVERABLE_COMPLETE
