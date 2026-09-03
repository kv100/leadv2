# SUITES-MUTATE-LIVE-CONTROL-PLANE-01 — report

## Mechanism (investigation finding)

A fixture suite that `git init`s a temp repo and then calls
`leadv2-dispatch-code.sh` with `CLAUDE_PROJECT_ROOT`/`PROJECT_ROOT`/
`LEADV2_PROJECT_ROOT` set as an **env-only** override — never `cd`-ing the
test process into the fixture first — hits `FOREIGN-PROJECT-ROOT-GUARD-01`
(`leadv2-dispatch-code.sh:299-456`): cwd's git toplevel (the real checkout
the suite happens to run from) and the env root (the fixture) disagree, no
`--resume-lane`/`--worktree` pin proves the fixture legitimate, so the guard
silently **discards** the fixture root and reroots the whole run at cwd,
emitting only a stderr `WARN: foreign project root detected ... (FOREIGN-
PROJECT-ROOT-GUARD-01)` line — no exit code, no test failure. `leadv2-
state-path.sh` then resolves the control-plane root via
`git-common-dir`-based repo-slug of that real cwd repo, so every write
(`active.yaml`, `bus.jsonl`, `merge-queue.jsonl`, journal) lands in the same
shared `~/.claude/leadv2-state/<repo-slug>/` used by every concurrent live
`/leadv2` session — while the suite itself still reports green.

`leadv2-state-path.sh`'s own B1 safety net (SUPERVISOR-AUDIT-01) only fires
when `LEADV2_STATE_ROOT` is explicitly set but `LINK_ROOT` still resolves to
a real checkout. It has **no equivalent net** for the more common shape: a
suite sets only `CLAUDE_PROJECT_ROOT`/`PROJECT_ROOT` (no
`LEADV2_STATE_ROOT`/`LEADV2_STATE_BASE` at all) and forgets the `cd`.

## Contaminated-dimension audit — honest result

The brief cites one confirmed instance (1773 `all_arms_capped` journal rows,
430/450 of a sampled window, traced to e2e-gate sandbox rows leaking into
the shared journal this way) and asks what else this leak class has
contaminated.

I manually audited ~14 named candidate suites plus ran a full static sweep
(the detector below) across the entire `plugins/leadv2/scripts/tests/`
fleet (332 `test-*.sh` files). **Every suite I could check is currently
safe** against this specific bug — each one either:
- wraps the dispatch-code.sh call in `( cd "$fixture" && ... )`,
- sets `LEADV2_STATE_ROOT`/`LEADV2_STATE_BASE` inline on the same call, or
- exports one of those two earlier in the file, or
- never actually `git init`s its fixture (so the guard's foreign-mismatch
  branch can't fire regardless of cd/override — a few suites are
  accidentally safe this way, e.g. `test-glm-first-recovery.sh` and
  `test-lock-busy-reresolve.sh`, which only `mkdir` their fixture root).

I could **not** locate a currently-broken suite instance within this
session's budget. That means either (a) the concretely-broken suites the
brief refers to were already repaired by other concurrent lanes before I
started (the live task list shows several adjacent in-flight lanes:
`CI-RUNS-THE-SUITES-01`, `WORKER-DOD-GATE-01`,
`E2E-GATE-CANNOT-SEE-THE-ALLOWLIST-01`), or (b) the actual leak source for
the cited 1773-row measurement is the e2e-gate's own sandbox/dry-run
mechanism (`leadv2-phase8-e2e-gate.sh`) rather than a `tests/` fixture, a
thread I started but did not finish tracing to its exact origin line. I am
reporting this gap rather than asserting suites were "found and fixed" when
they were not.

## Fix delivered: a durable static regression net

Since I could not substantiate "N broken suites to patch," I built
`plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh`: a
self-contained suite that

1. embeds a Python detector (`find_hazards`) implementing the exact
   precondition for the bug — a `bash "${DC}"` call, in a segment that sets
   a project-root env var, whose enclosing function `git init`s a fixture,
   with no `cd`, no inline state-root override, and no earlier file-level
   `export LEADV2_STATE_(ROOT|BASE)=`;
2. unit-tests the detector itself against five synthetic fixtures (one
   hazardous shape that must be flagged, four safe shapes that must not);
3. runs the same detector as an **integration scan** over the real
   `plugins/leadv2/scripts/tests/` fleet and asserts zero hazards — turning
   today's "checked and clean" snapshot into a standing, CI-enforced
   invariant instead of a one-time claim.

## Mutation negative control (in-function mutation, not top-level)

Mutated the condition inside `find_hazards`'s body (not a top-level file
insertion):

```python
-        if not has_cd and not has_state_override and not has_earlier_export:
+        if False and not has_cd and not has_state_override and not has_earlier_export:
```

- `baseline_rc=0` (before mutation, `bash plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh`)
- `mutated_rc=1` (after mutation)
- Red line: `[TEST] FAIL: hazardous shape was NOT flagged (detector blind to the live incident shape)`
- Reverted → `bash -n` OK, suite green again: `reverted_rc=0`

## Registration

`plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh` is picked up
by `tests/run-all.sh`'s self-select convention (any changed
`plugins/leadv2/scripts/tests/test-*.sh` file selects itself). Confirmed
via the runner's own `LEADV2_RUN_ALL_SELECT_ONLY=1` seam:

```
[SELECT] .../plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh
run-all: 5 selected, scope=changed, select_only=1
```

Also added two `EXTRA_SUITE_MAP` rows (belt-and-suspenders, matching this
task's acceptance wording) so any future change to either carrier this
class of bug depends on re-triggers the scan even if the suite file itself
doesn't change:

```
leadv2-dispatch-code.sh:plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh
leadv2-state-path.sh:plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh
```

Re-ran the select-only seam after the `EXTRA_SUITE_MAP` addition — still
selects both the suite (via self-select) and the pre-existing
`test-run-all-carrier-map.sh` (which validates `EXTRA_SUITE_MAP`'s own
format and passed unchanged, 5/5, `rc=0`, confirming the new rows didn't
break the map).

## Dual-OS proof

- **macOS** (this host, bash 3.2 host default but suite run under bash 5
  invocation): `bash plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh`
  → `rc=0`, `6 passed, 0 failed`.
- **Linux container** (`docker run --rm -v $(pwd):/repo -w /repo python:3-slim
  bash plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh`):
  → `rc=0`, `6 passed, 0 failed`.

## Scope note

Diff touches only `plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh`
(new) and `tests/run-all.sh` (two new `EXTRA_SUITE_MAP` rows). No runtime-state
paths (`docs/leadv2/`, `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*`)
touched. `leadv2-dispatch-code.sh` was read-only, never edited (lead-owned
file, per mission constraint). `git diff --diff-filter=D --name-only
main...HEAD` → empty, no accidental deletions.
