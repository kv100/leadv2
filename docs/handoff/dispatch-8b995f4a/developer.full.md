# LANE-PLACEMENT-PIN-RED-01 — developer report

## Result

`plugins/leadv2/scripts/tests/test-lane-placement-pin.sh` is green: **27 passed, 0 failed**,
on macOS (host bash 3.2) and inside an `ubuntu:24.04` container (GNU bash 5.2.21,
`aarch64-unknown-linux-gnu`), exit code 0 in both.

Two independent, unrelated defects were causing the 13 post-freepool-merge failures plus the
4 pre-existing ones. Both are fixed. Neither fix touches or weakens
`_lane_writes_class`/the fail-closed-on-unknown-writes protection from
FREEPOOL-MUST-ACTUALLY-GET-WORK-01 — that logic is exactly what now correctly routes
unprotected-write-set tasks to the `sonnet` arm, which is *why* cause 2 below was newly
exposed.

## Cause 1 (the 4 pre-existing `P-h` "prompt pin line MISSING" failures): real production bug

**File:line**: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`, inside `_spawn_worker_body()`,
the two `mission="...".."${mission}"` prepend statements now at lines 5276-5277 (originally at
what is now 5276-5277 but in the opposite order).

**Root cause**: mission text is built by repeatedly *prepending* strings:
`mission="${X}"$'\n\n'"${mission}"`. Prepending is LIFO — whichever prepend statement executes
**last** ends up **first** in the final string. The code had the `WORKTREE_PIN_LINE` prepend
(which must be the literal first line — `test-lane-placement-pin.sh`'s P-h assertions do
`head -1`) executing *before* the WORKER-MCP-ALL-ARMS-01 code-intel-preamble prepend
(`_ci_txt`). Whenever `_ci_txt` was non-empty (arm attaches MCP successfully, or fails open with
a non-empty note), its prepend ran last and silently demoted the pin line to wherever the
code-intel text ended — breaking the "pin line is the literal first line of the mission"
invariant on every such dispatch.

**Fix**: swapped the order so the `_ci_txt` prepend runs first and `WORKTREE_PIN_LINE` runs
last (unconditionally staying the true first line regardless of whether `_ci_txt` is empty).

**Is this reachable in production, and did any lane between `2062dbcf` and the fix run in the
wrong directory?** No lane ran in the wrong directory — this bug only ever corrupts the
mission *text* (demotes/hides the `WORKTREE PIN:` advisory line the worker reads), it never
touches `_resolve_pinned_placement`, `_set_worktree_pin_line`'s own value, or the actual `cd`/
`--cwd` the launcher uses. Placement itself (which physical directory the worker's process
runs in) was never wrong; only the advisory pin *line inside the mission prompt* could be
buried. It is reachable on any arm where `worker_mcp_preamble_for_arm()` returns non-empty
text: `glm`/`glm-flash`/`kimi`/`freepool` on a successful MCP attach (`rc=0`). It is **not**
reachable on `sonnet` (see `plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh:220-225` — the
`sonnet` branch always returns `rc=3` with nothing on stdout by design) or `codex`
(`rc=4`, nothing on stdout). Confirmed directly: reverting the order and dispatching through
`glm-flash` (a task with a declared, unprotected `--writes` path) reproduces a mission whose
first line is the code-intel preamble, not the pin line (see Negative control 1 below).

## Cause 2 (the 9 new post-freepool-merge failures — `P-a/P-b/P-g/D3`, and `P-i` when exercised
under the same condition): test fixture gap, not a placement bug

**Evidence it is a fixture gap, not production**: `_resolve_pinned_placement`,
`_set_worktree_pin_line()`, and the sonnet arm's explicit `cd "${WORK_ROOT}"` before invoking
`claude-subsession.sh` (`leadv2-dispatch-code.sh:5486`) are unmodified and correct — confirmed
by reading them and by the isolated repro below, which shows the dispatcher writing the
*correct* cwd to the stub's cwd-capture file even while the dispatch as a whole still returned
rc=4 before the fixture fix landed.

**Root cause**: FREEPOOL-MUST-ACTUALLY-GET-WORK-01 (`2062dbcf`) made an unknown/undeclared
write-set (`--writes` omitted, as every `P-a/P-b/P-g/D3` case in this suite does) fail closed to
`effective_protected=1`, which now legitimately excludes `freepool` *and* `glm` and routes the
task to the `sonnet` arm instead (`plugins/leadv2/scripts/leadv2-dispatch-code.sh`
`_select_base_arm()`/`resolve_arm()`). Before that merge, the same undeclared-writes dispatch
resolved to `glm`. The suite had never stubbed `LEADV2_DISPATCH_SUBSESSION_BIN` (the sonnet
launcher seam) because it never needed to — so the real `claude-subsession.sh` was invoked
inside the sandbox and failed to spawn a worker, producing rc=4 on every case that lost its
free ride on the `glm` stub.

**Fix, iteration 1**: added a `SONNET_STUB` (`test-lane-placement-pin.sh:69,139-165`) wired via
`export LEADV2_DISPATCH_SUBSESSION_BIN="${SONNET_STUB}"` (`test-lane-placement-pin.sh:210`),
matching `claude-subsession.sh`'s real contract: no `--cwd` flag (reads `$PWD`), and a handle
line `PID=<pid> LABEL=... SESSION_ID=...` that the dispatcher's `kill -0 "${pid}"` liveness
check (`leadv2-dispatch-code.sh:5526`) must find genuinely alive.

**Fix, iteration 1 was still red** (`P-a`/`P-b` continued to fail rc=4, though cwd/mission
capture now passed) — a second, distinct bug in the stub itself: the stub backgrounded
`sleep 100 &` (to give `kill -0` a real, live PID) without redirecting its stdout/stderr away
from the fds it inherited. The dispatcher captures the stub's own stdout via
`out="$(cd "${WORK_ROOT}" && ... bash "${SUBSESSION_BIN}" ... )"` (`leadv2-dispatch-code.sh:5486`).
A backgrounded child that still holds that pipe's write end open — even after `disown` — keeps
bash's command substitution blocked until the child's fd closes, i.e. until the `sleep 100`
itself exits ~100 seconds later. By the time the command substitution finally returned, the
`sleep` had *just* exited, so the immediately-following `kill -0 "${pid}"` found it already
dead (`reason=not_live`, confirmed directly via stderr: `spawn(sonnet) pid=... is not alive`).
This is why the earlier partial-fix run was slow (~100s per dispatch) and still red.

**Fix, iteration 2**: redirect the backgrounded sleep's own fds
(`sleep 100 >/dev/null 2>&1 &`, `test-lane-placement-pin.sh:160`) so it no longer holds the
captured pipe open; the command substitution now returns immediately and `kill -0` finds the
still-running, now-detached sleep process alive.

## Definition of Done item 1 — suite green

macOS (host, bash 3.2):
```
[LANE-PLACEMENT-01] passed=27 failed=0
```
Linux (docker run --rm -v <worktree>:/repo -w /repo ubuntu:24.04, after apt-get install git
python3):
```
GNU bash, version 5.2.21(1)-release (aarch64-unknown-linux-gnu)
[LANE-PLACEMENT-01] passed=27 failed=0
DOCKER_EXIT=0
```
No `P-h` assertion was itself wrong — all 4 pre-existing failures were the real production bug
in cause 1, now fixed with evidence, not weakened or silenced.

## Definition of Done item 3 — negative controls

**Control 1 (cause 1, pin-order fix).** Note: the full suite's own `P-h(a/b/g/g2)` assertions
turned out to be a **vacuous pass** for this specific fix under the current (post-freepool-merge)
routing — every successful-spawn case in this suite (`P-a/P-b/P-g/D3/P-i`) now routes
exclusively to `sonnet`, and `sonnet`'s `_ci_txt` is unconditionally empty by design
(`leadv2-worker-mcp.sh:220-225`), so reverting the prepend order in the full suite does **not**
reproduce red (confirmed: reverted-order full-suite run still showed `passed=27 failed=0`).
The bug is real and was reachable pre-merge (when undeclared-writes dispatch went to `glm`);
it is currently only reachable via `glm`/`glm-flash`/`kimi`/`freepool`. Negative control was
therefore built with an isolated one-shot repro that dispatches with `--writes
docs/handoff/x.txt` (an unprotected declared path, routes to `glm-flash`, same sandbox stubs):
- Mutation: swap the two prepend lines back to the original (broken) order.
- Red: `mission-version ... head="CODE-INTEL ROUTING (use before grep/cat on unfamiliar
  code): ..."` — the pin line is not first.
- Revert: restore the fixed order.
- Green: `mission-version ... head="WORKTREE PIN: all edits go in .../RESUME-ME-01..."` — pin
  line is first again.

**Control 2 (cause 2, sonnet-stub fixture fix).**
- Mutation: comment out the `LEADV2_DISPATCH_SUBSESSION_BIN` export in `setup_env()`.
- Red (full suite): `passed=14 failed=13` — `P-a/P-b/P-g/D3/P-i` all fail exactly as originally
  measured post-merge (rc=4, empty cwd, missing pin line), an exact reproduction of the
  original failure signature including `P-i`, which the original 9-failure count from the
  truncated run had not directly shown but was consistent with.
- Revert: restore the export.
- Green (full suite): `passed=27 failed=0`.

## Definition of Done item 5 — known-red-suites.txt

Untouched (`git diff --stat tests/known-red-suites.txt` empty before and after all edits).

## Definition of Done item 6 — suites selected only when one specific file changes

`tests/run-all.sh`'s `EXTRA_SUITE_MAP` contains 198 unique `stem:suite_path` rows. **43 suites**
have exactly one distinct triggering stem in that map (i.e. under `--scope changed` they run
only if that one specific file changed — there is no stem-convention self-select fallback for
them):

```
plugins/leadv2/scripts/tests/test-admission-class.sh
plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh
plugins/leadv2/scripts/tests/test-backlog-pump.sh
plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh
plugins/leadv2/scripts/tests/test-broad-status-duty.sh
plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh
plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh
plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh
plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh
plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh
plugins/leadv2/scripts/tests/test-close-chain.sh
plugins/leadv2/scripts/tests/test-codex-longrun.sh
plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh
plugins/leadv2/scripts/tests/test-freepool-model-selector.sh
plugins/leadv2/scripts/tests/test-gate1-discipline.sh
plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh
plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh
plugins/leadv2/scripts/tests/test-lane-outcome.sh
plugins/leadv2/scripts/tests/test-lane-placement-pin.sh
plugins/leadv2/scripts/tests/test-lib-source-guarded.sh
plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh
plugins/leadv2/scripts/tests/test-model-select-telemetry.sh
plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh
plugins/leadv2/scripts/tests/test-phase-record.sh
plugins/leadv2/scripts/tests/test-plan-in-lane.sh
plugins/leadv2/scripts/tests/test-plugin-cache-sync.sh
plugins/leadv2/scripts/tests/test-promise-action-binding.sh
plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh
plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh
plugins/leadv2/scripts/tests/test-promise-guard-unknown-kind.sh
plugins/leadv2/scripts/tests/test-pulse-empty-board.sh
plugins/leadv2/scripts/tests/test-pulse-readable-rendering.sh
plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh
plugins/leadv2/scripts/tests/test-review-body-recovery.sh
plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh
plugins/leadv2/scripts/tests/test-single-lead-beat.sh
plugins/leadv2/scripts/tests/test-status-repo-scoped.sh
plugins/leadv2/scripts/tests/test-status-surface.sh
plugins/leadv2/scripts/tests/test-suite-lock-scope.sh
plugins/leadv2/scripts/tests/test-t13-slice1.sh
plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh
plugins/leadv2/tests/test-promise-guard.sh
tests/test-run-all-carrier-map.sh
```
`test-lane-placement-pin.sh` itself is one of them (single row:
`leadv2-dispatch-code:plugins/leadv2/scripts/tests/test-lane-placement-pin.sh`) — exactly why
its 4 pre-existing `P-h` failures were invisible to `--scope changed` until the freepool merge
also changed `leadv2-dispatch-code.sh` and force-selected it. A fix for this exposure gap
(e.g. a stem-convention fallback check, or a coverage lint) is out of scope here per the brief.

## Self-check

```
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh   → SYNTAX_OK
$ bash -n plugins/leadv2/scripts/tests/test-lane-placement-pin.sh → SYNTAX_OK
```
No Python files were changed (`py_compile` not applicable).
`tests/run-all.sh --scope changed` self-check: see chat/last output for pass/fail counts.

## Files changed

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — reordered the `_ci_txt` / `WORKTREE_PIN_LINE`
  prepends in `_spawn_worker_body()` (~lines 5253-5277).
- `plugins/leadv2/scripts/tests/test-lane-placement-pin.sh` — added `SONNET_STUB` (lines
  69, 139-165), wired via `LEADV2_DISPATCH_SUBSESSION_BIN` in `setup_env()` (line 210).
- `docs/handoff/LANE-PLACEMENT-PIN-RED-01/report.md` — new lane report with the full evidence
  set (both causes, both negative controls, macOS+Linux pasted output, blind-spot list).

## Final verification (this round)

Re-ran the full evidence set against the rescued `b794a736` commit (no further source edits were
needed — both mutations below were applied and fully reverted, `git diff` empty on both files
afterward):

- Mutation B (comment out `LEADV2_DISPATCH_SUBSESSION_BIN` export) reproduced
  `passed=14 failed=13` — an exact match to the brief's independently-measured `72546734` numbers,
  not just "consistent with."
- DoD gate self-check against the real gate script (not an informal check):
  `bash plugins/leadv2/scripts/lib/leadv2-dod-gate.sh "$(pwd)" docs/handoff/LANE-PLACEMENT-PIN-RED-01
  <diff vs merge-base 974932a7> /tmp/dod-gate-out.md` → `RC=0`, all checks `dod_pass`/`dod_skip`,
  two non-blocking `dod_note check=unverified_claim` notes reviewed and judged non-blocking.
- Lane report committed as `a8d1e2e4` (docs/handoff/LANE-PLACEMENT-PIN-RED-01/report.md only —
  the two script files needed no changes beyond what `b794a736` already carried).

DELIVERABLE_COMPLETE
