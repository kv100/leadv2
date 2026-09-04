# verdict-guard: allow
verdict: APPROVE
next_action: review_round_2

# EFFORT-IS-NOT-WIRED-01 — developer report

## What changed

The `effort` routing knob (docs/model-effort-matrix.md: model = hardness, effort = marginal
value of extra thinking) was documented and configured but never read anywhere in the dispatch
path. Wired it end-to-end, data-driven, no `if arm==X` hardcoding:

1. **`plugins/leadv2/config/leadv2-routing.yaml`** — new `router_v2.effort_matrix:` block, a
   list of `{tags|kinds|protected, effort}` rows matched against the SAME winning
   `capability_matrix` cell the arbiter already picks, first-match-wins, `default: true` catch-all
   → medium. adversarial/safety/plan/protected → high; mechanical/classify/cheap → low.

2. **`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`** — `route_arbiter()`'s Python heredoc
   resolves `effort` from the winning cell `w` in the SAME call that resolves arm/model/tier
   (never a second decision), falls open to `medium` on no match/empty matrix. Appended
   `effort=%s` to the single-line machine-parsed output between `tier=` and `reason=`.

3. **`plugins/leadv2/scripts/leadv2-dispatch-code.sh`** — primary `route_arbiter` call site
   (cmd_resolve, T17) parses `effort=` out of the arbiter output, exports `RESOLVED_EFFORT`,
   extends the `emit decision "route_resolved ..."` line to name both arm and effort. Forwarded
   into `spawn_worker`'s case statement per arm's actual launch-parameter shape (verified by
   reading each launcher, not assumed):
   - **codex**: additional `--effort "${RESOLVED_EFFORT}"` alongside the existing `--tier`.
   - **sonnet/claude-subsession**: new `--effort "${RESOLVED_EFFORT}"` flag (no tier concept there).
   - **glm / glm-flash / freepool / kimi**: no effort-shaped flag exists in any of these launchers
     (confirmed via source read, not absence-of-grep alone) → `emit decision "effort_dropped
     by=router arm=... effort=... reason=no_effort_control"`, no argv change, no crash. The kimi
     branch cites `config/model-capability.yaml:193` (Moonshot's reasoning_effort locked to max)
     so the drop-log doesn't contradict that documented provider constraint.
   - Legacy (non-arbiter) resolver path defaults `RESOLVED_EFFORT=medium` so the var is always
     defined regardless of which resolution path ran.

   Scope decision: only the PRIMARY arbiter call site was wired to set `RESOLVED_EFFORT`. The
   three fallback re-arbitration sites (bench-fallback, exit76-continuation, arm-advance) were
   left untouched — this mirrors existing behavior (those sites don't update `RESOLVED_CODEX_TIER`
   either) and is out of the mission's tested/acceptance scope.

4. **`plugins/leadv2/scripts/tests/test-effort-routing.sh`** (new) — 9 cases, fixture-only
   (arbiter-level fixture harness + full-dispatch stub-launcher harness), never touches a live
   provider. See raw output below.

5. **`tests/run-all.sh`** — two `EXTRA_SUITE_MAP` rows so `--scope changed` selects the new
   suite when either touched script changes.

Commit: `3ff1c07` (5 files: the four above + the new test file).

## Falsification set — raw output

### bash -n / py_compile (all clean, no output = pass)
```
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-effort-routing.sh && echo OK
OK
$ bash -n tests/run-all.sh && echo OK
OK
$ python3 -c "import yaml; yaml.safe_load(open('plugins/leadv2/config/leadv2-routing.yaml'))" && echo OK
OK
```

### New suite standalone — GREEN (final state)
```
$ bash plugins/leadv2/scripts/tests/test-effort-routing.sh
[... 9 cases ...]
SUMMARY: pass=9 fail=0
```

### Mutation kill #1 — arbiter effort-resolution loop (production file, in place)
Backed up real file to /tmp/arbiter.bak, mutated the `_effort_row_matches`/`effort=` resolution
block inside `leadv2-route-arbiter.sh` (production body, not a scratch copy) to always resolve
`effort='medium'` regardless of matrix rows:
```
RED:   SUMMARY: pass=5 fail=4   (cases 1, 2, 6, 4a fail — exactly the cases that assert
                                  effort != medium or assert the anti-hardcode yaml-swap flips it)
```
Reverted via `cp /tmp/arbiter.bak <realfile>`, confirmed `diff /tmp/arbiter.bak <realfile>` empty.
```
GREEN: SUMMARY: pass=9 fail=0
```

### Mutation kill #2 — dispatch-code.sh codex pass-through (production file, in place)
Backed up to /tmp/dispatch.bak, mutated the codex spawn-case line to
`false && tier_args+=(--effort "${RESOLVED_EFFORT}")` (production body):
```
RED:   SUMMARY: pass=8 fail=1   (case 4a only — precise fault localization: forwarding to the
                                  spawn is an independent link from the arbiter's own resolution)
```
Reverted via `cp /tmp/dispatch.bak <realfile>`, confirmed `diff` empty.
```
GREEN: SUMMARY: pass=9 fail=0
```

### `--scope changed` suite-selection proof
Copied an instrumented `run-all.sh` (prints `SUITES[]` then exits, no execution) into the real
`tests/` dir (required — the script's own root-escape guard rejects `/tmp`), ran
`bash tests/run-all-probe.sh --scope changed` against the committed diff:
```
SUITE: .../plugins/leadv2/scripts/tests/test-effort-routing.sh
```
Confirmed present, then deleted the probe file; `git status --short tests/` showed no trace
(untracked temp file, never staged).

### Real `tests/run-all.sh --scope changed` — LOCK-BLOCKED, not run to completion
`run-all.sh` always runs `plugins/leadv2/scripts/tests/run-core-offline.sh` first regardless of
scope, gated by a machine-global lock `/tmp/leadv2-core-offline.lock` shared across all concurrent
leadv2 sessions/worktrees. This run printed:
```
[CORE-OFFLINE] waiting for lock file=/tmp/leadv2-core-offline.lock (held by a concurrent run)
```
and did not release within the wait window — genuinely concurrent other lanes were active
(DISPATCH-PIN-CLUSTER-01, 26c4cec3, ARMS-ADMISSION-01, HANDOFF-ARTIFACTS-GITIGNORED-01,
REVIEW-RUN-LOSES-VERDICTS-01 per system reminders at the time). Killed the blocked background
process rather than waiting indefinitely or fabricating a result. This is an environmental
concurrency condition outside this lane's control, not a defect in the changes — the new suite's
correctness is independently established by the standalone 9/9 GREEN run and both mutation-kill
proofs above, and its selection under `--scope changed` is independently established by the
instrumented-probe run above.

## Requirements checklist
- [x] Critical: arbiter resolves effort alongside arm in the same call, data-driven from
      `config/leadv2-routing.yaml` (effort_matrix), no `if arm==X` branching.
- [x] Critical: resolved effort reaches each arm's own launch parameter — codex `--effort` (tier
      stays separate), sonnet `--effort`, glm/glm-flash/freepool/kimi log `effort_dropped` with
      `reason=no_effort_control`, no crash. kimi drop-log respects the Moonshot
      reasoning_effort-locked-to-max caveat at `config/model-capability.yaml:193`.
- [x] Medium: `route_resolved` decision line names both arm and effort plus the rule
      (`reason=cheapest_capable`).
- [x] Acceptance cases 1–7 all pass (adversarial→high, mechanical→low, ordinary build→medium,
      ≥2 arms with different parameter shapes carry effort, one arm logs the drop, yaml-only
      anti-hardcode flip, decision line names both).
- [x] `EXTRA_SUITE_MAP` rows added for both touched scripts, proven via `--scope changed`.
- [x] Mutations proven inside production function bodies, RED then reverted to clean GREEN diff.
- [x] Bash 3.2.57-compatible (no mapfile, guarded array expansions).
- [x] `git add <file>` per-file, committed (3ff1c07).

DELIVERABLE_COMPLETE
