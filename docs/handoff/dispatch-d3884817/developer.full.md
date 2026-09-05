# WRITESET-REFUSAL-NEVER-NAMES-THE-BLOCKER-01 — developer full report

## What I found

A prior attempt (killed by a false liveness reading) had already landed 82
insertions / 11 deletions, uncommitted, in this worktree:
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` carried a working
`_emit_writeset_refusal()` helper and both call sites already rewired to
capture the registry's stderr instead of discarding it. I reviewed it,
finished the missing pieces, and did not rewrite it.

## What was already correct (verified, not rebuilt)

- `_emit_writeset_refusal()` (new function, ~L3699-3762) parses the real
  registry stderr line `[registry] writeset conflict: other=<id>
  reason=pending_resolution` or `... other=<id> paths=<a>,<b>` via `sed -nE`,
  and emits:
  - `dispatch_refused reason=writeset_pending task=<sig> blocked_by=<id>
    age_s=<n|unknown> window_s=<n> writes=<...>` for the pending case (plus a
    best-effort `age_s` computed by re-reading the incumbent's `started_at`
    from active.yaml via a python3 snippet that degrades to `unknown` on any
    failure — never blocks the refusal).
  - `dispatch_refused reason=writeset_overlap task=<sig> blocked_by=<id>
    paths=<a,b,...> writes=<...>` for the real path-collision case.
  - Falls back to the legacy bare `dispatch_refused reason=writeset_conflict
    task=<sig> writes=<...>` when the stderr parses to neither shape (regressed
    registry message format) — worst case is today's behaviour, never wrong.
- Call site 1 (`cmd_resolve`, first `leadv2_active_register` call): stderr now
  captured to a mktemp file (`_register_errf`), read into `_register_err`,
  and the `5)` branch calls `_emit_writeset_refusal` with it. Falls back to
  `2>/dev/null` semantics only if `mktemp` itself fails.
- Call site 2 (second `leadv2_active_register` call, ~L7300s): swapped
  `>/dev/null 2>&1` for `2>&1 >/dev/null` captured into `_ws_err`, so stdout
  (unused chatter) drops and stderr (the conflict line) is kept; `5)` branch
  wired to `_emit_writeset_refusal`.

## What I added

1. **`plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh`**
   (new, registered via the `# run-all-triggers: leadv2-dispatch-code.sh`
   self-select convention used by sibling suites, e.g.
   `test-glm-flash-handle.sh`, `test-mission-writeset.sh`,
   `test-broad-status-lanes-blind.sh`). It:
   - Truncates the real `leadv2-dispatch-code.sh` just before its trailing
     dispatch-case block (same technique as
     `test-dispatch-checkpoint-commit-cutoff.sh`) to source the real function
     bodies without dispatching anything.
   - Drives the REAL `leadv2-active-registry.sh` against a fresh scratch git
     repo + `LEADV2_STATE_ROOT` per case (case isolation — a shared registry
     across cases caused case 2's incumbent register to itself fail exit 5
     against case 1's still-pending row, killing the subshell before it could
     print anything).
   - Case 1 (pending): registers a real incumbent with NO write set, then a
     real candidate register captured the fixed way, then calls
     `_emit_writeset_refusal` on the captured stderr. Asserts `reg_rc=5`,
     `reason=writeset_pending blocked_by=<incumbent>`, `age_s=.../window_s=`
     present, NO `paths=`, and the `LEADV2_DISPATCH_REFUSED: writeset_pending`
     token.
   - Case 2 (overlap): registers a real incumbent with a declared write that
     intersects the candidate's. Asserts `reason=writeset_overlap
     blocked_by=<incumbent> paths=contested/b.txt`.
   - Case 3: asserts the two refusal lines differ and carry mutually
     exclusive discriminators (`window_s=` vs `paths=`) — distinguishable
     from the refusal text alone, no registry read needed.
   - Case 4 (mandatory negative control): re-runs the pending shape but
     captures the candidate register the OLD way (`>/dev/null 2>&1`, stderr
     dropped) and feeds the resulting empty string to
     `_emit_writeset_refusal`. Asserts the legacy bare `writeset_conflict`
     with NO `blocked_by=` — proving the name's presence in cases 1-3 is
     caused by the fix, not an artifact of the harness.
   - Result: `PASS=4 FAIL=0`.

2. **Environment isolation fix during verification** (in the test, not the
   product code): this session's ambient shell carries
   `LEADV2_WRITESET_PENDING_WINDOW_SEC=1` (a harness value presumably set so
   this very lane's own dispatch doesn't get blocked by a stale registry
   row). Inherited by the test's subshells, it expired the incumbent's
   pending window before the candidate even finished registering, turning
   every `pending_resolution` into `writeset_unknown` and red-ing cases 1 and
   3 for a reason unrelated to the diff — confirmed by reproducing the same
   failure directly against `leadv2-active-registry.sh` outside the test
   harness with the same ambient env. Fixed by exporting
   `LEADV2_WRITESET_PENDING_WINDOW_SEC=900` at the top of the test script
   before any subshell spawns, with a comment recording why.

## Comments left truthful (checked, not touched)

- `leadv2-active-registry.sh:33` (`5 — writeset_conflict (real intersection
  with an alive lane's writes)`): pre-existing, off-limits (registry.sh is
  claimed by DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01). Its own
  nearby comment block (~L39-40) already documents that rc=5 is also used
  unconditionally for the pending-window case — the nuance this task's diff
  doesn't add or remove. Not made a lie by this change (dispatch-code.sh's
  surfaced reason token changed; the registry's own rc=5 semantics did not).
- `tests/test-glm-flash-handle.sh:161`: comment reads "...refuses
  writeset_conflict before the spawn row..." — refers to the registry-level
  refusal (still rc=5, still internally called writeset_conflict at that
  layer); no assertion in that file matches on the string, confirmed via
  grep. Left untouched, still accurate.

## Caller check (mandatory, acceptance item 4)

`grep -rn "writeset_conflict" plugins/leadv2/` returns exactly:
- `leadv2-dispatch-code.sh:3709,3714` — comments in the new helper
- `leadv2-dispatch-code.sh:3757-3759` — the legacy fallback branch (kept,
  still emits the bare token)
- `leadv2-active-registry.sh:33` — pre-existing comment, untouched
- `tests/test-glm-flash-handle.sh:161` — pre-existing comment, untouched,
  no assertion on the string
- `tests/test-writeset-refusal-names-blocker.sh` — new suite, its own
  comments/assertions about the legacy fallback (case 4)

No caller outside this diff asserts on the bare `writeset_conflict` string,
so nothing else breaks.

## Self-check (falsification set)

```
$ ( LEADV2_ALLOW_FG_DISPATCH=1 bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh && echo "OK: dispatch-code syntax" ) &
OK: dispatch-code syntax

$ ( LEADV2_ALLOW_FG_DISPATCH=1 bash -n plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh && echo "OK: test syntax" ) &
OK: test syntax

$ ( LEADV2_ALLOW_FG_DISPATCH=1 bash plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh; echo "EXIT=$?" ) &
[TEST] PASS: 1: pending incumbent (no writes, inside window) refuses as writeset_pending naming blocked_by=WSR-INC-PEND, no paths=, age_s=/window_s present
[TEST] PASS: 2: real path overlap refuses as writeset_overlap naming blocked_by=WSR-INC-OVR with the colliding paths=
[TEST] PASS: 3: the two cases are distinguishable from the refusal text alone (reason + window_s= vs paths=)
[TEST] PASS: 4: negative control — with stderr re-swallowed (old 2>/dev/null), blocked_by disappears and the legacy writeset_conflict fallback fires
----
PASS=4 FAIL=0
EXIT=0
```

No Python file was added or changed (the `age_s` snippet is an inline
heredoc inside the shell script, not a standalone `.py` file), so
`py_compile` has nothing to check.

## Left alone, deliberately

- `leadv2-active-registry.sh` — off-limits per mission (claimed by
  DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01); the registry already prints
  both answers correctly, no change needed there.
- `RECOVERY-ATTACHES-A-BYSTANDER-PID-TO-A-LANE-01` (the resurrecting-row
  root cause) — explicitly out of scope, tracked separately.
- Did not shorten `LEADV2_WRITESET_PENDING_WINDOW_SEC` anywhere in product
  code — only pinned it inside the new test's own subshell scope, which is
  test isolation, not suppression of the underlying window semantics.

## Diff scope

Only the two declared files changed:
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` (82 insertions / 11
deletions carried over from the prior attempt, reviewed and finished) and
new `plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh`.
`git diff --stat -- docs/leadv2/ docs/LEAD_V2_STATE.md
'docs/handoff/dispatch-nw*'` is empty — no runtime-state paths touched.

## Commit

Committed on the lane branch with reasoning in the body, one commit,
revertable via `git revert`.

DELIVERABLE_COMPLETE
