# Step 4 — `capability_fit.enabled: true` (the flip)

Date: 2026-09-07. Lane: `worktree-F1-ARBITER-SCORING-20260907-step1`. Founder-approved flip;
judge liveness + Step-4 acceptance gate already closed on this lane (see
`judge-revival-diagnosis.md`, commits 35ee99a4/d40dab17/d3b66dd2).

## 1. The exact diff (one line, nothing else in the block)

```diff
--- a/plugins/leadv2/config/leadv2-routing.yaml
+++ b/plugins/leadv2/config/leadv2-routing.yaml
@@ -333,7 +333,7 @@ router_v2:
   # heuristic estimator; revisit at <=0.2 once the judge is live. Rollback from
   # any state is the single env flip `LEADV2_ARBITER_CAPABILITY_FIT=off`.
   capability_fit:
-    enabled: false
+    enabled: true
     prior: 3.0
```

`source_confidence.heuristic` untouched (0.4), no capability tier touched. The only other
file changed on this lane is the test assumption fix in §4 (explicitly authorized by the
mission's step-3 clause).

## 2. Fresh live demonstration, AFTER the flip

All demonstrations below ran post-flip with no `LEADV2_ARBITER_*` env override in the shell
(verified: `env | grep LEADV2_ARBITER` → empty). `fit_mode=on` therefore comes from the yaml,
not from an override.

### 2.1 Real dispatch through the full dispatcher (journaled)

`leadv2-dispatch-code.sh @<mechanical tests-only mission> --no-spawn --task-class Standard
--writes plugins/leadv2/scripts/tests/test-quotastub-rename-demo.sh --task-id
STEP4-FLIP-DEMO-05` — resolve+journal only, no worker. Journal line verbatim
(`~/.claude/leadv2-state/leadv2/tasks/dispatch-2a249190/journal.md`, 2026-09-07T14:17:28Z):

```
route_resolved by=arbiter role=worker arm=codex model=gpt-6-astra tier=volume effort=medium task=2a249190 reason=capability_fit arbiter_pick=codex util_glm=72 util_codex=15 util_claude=48 ... arm_excluded=glm:not_allowed ... complexity=standard duration_class=short complexity_policy=capability_fit ... complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=codex fit_differs=1 fit_bucket=codex:0,codex:0,sonnet:0,glm-flash:1,freepool:1
```

Why this is a REAL pick change, not just tokens printing: `reason=capability_fit` is emitted
only when `FIT_MODE == 'on' and fit_differs` (leadv2-route-arbiter.sh:1063) — the sort used
`_fit_key`, and `fit_differs=1` states `_fit_order[0] != _cost_order[0]` computed on the
same live inputs. Here glm-flash (cost 0.33, cheapest, but `fit_bucket=1` — capability 2
short of req_eff 3.0) would have won under cost-only; the fit key demoted it and codex/volume
(bucket 0) took the dispatch. Three earlier post-flip dispatches (protected/write lanes, e.g.
task=51cb4fd3) printed `fit_mode=on ... fit_pick=glm fit_differs=0` because the ladder's
`untrusted: true` strip had already excluded glm-flash upstream — honest note: on
protected-path code lanes the flip changes nothing today; the differ materializes on
unprotected (tests_docs) lanes, exactly where a cap-2 arm is allowed to contend.

### 2.2 Same descriptor, both modes, live quota (the off-contrast, measured)

CLI consult on the production config with live quota (identical descriptor, only the env
differs; `ROUTE_ARBITER_STATE_FILE=/tmp/arb-state-step4-demo`):

```
$ LEADV2_ARBITER_CAPABILITY_FIT=off bash plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh worker '<descriptor>'
arm=glm-flash reason=cheapest_capable fit_mode=off fit_pick=glm fit_differs=1

$ bash plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh worker '<descriptor>'   # no env -> yaml
arm=glm reason=capability_fit fit_mode=on fit_pick=glm fit_differs=1
```

Same inputs: off picks glm-flash, on picks glm. This is also the rollback preview (§3).

### 2.3 Census (path-excluded, checked=N on every count)

```
journals checked: 403          (find ~/.claude/leadv2-state -path '*/tasks/*/journal.md' | grep -vE 'ephemeral|deadbeef')
arbiter decision lines: 47
fit_mode=on lines: 4           (all post-flip: tasks 51cb4fd3, 6a0e9072, 2a249190 ×2)
  of which fit_differs=1: 1    (the 14:17:28Z line above)
  of which complexity_source=unknown: 0
fit_mode=off lines: 3          (pre-flip history; token always printed)
```

## 3. Rollback is a single flag flip (quoted, not asserted)

- yaml comment directly above the flipped line (unchanged by this diff):
  `# heuristic estimator; revisit at <=0.2 once the judge is live. Rollback from`
  `# any state is the single env flip `LEADV2_ARBITER_CAPABILITY_FIT=off`.`
- The arbiter honors it (leadv2-route-arbiter.sh:780):
  `FIT_MODE=os.environ.get('LEADV2_ARBITER_CAPABILITY_FIT') or ('on' if _cf.get('enabled') else 'off')`
  — env wins over the yaml.
- Measured in §2.2: with the env set to `off` the pick reverts to `arm=glm-flash
  reason=cheapest_capable fit_mode=off` on identical inputs. Reverting the one yaml line in
  §1 is the equivalent no-env rollback.

## 4. Post-flip suite run — all five green (one assumption fixed in a test)

First run, unchanged: `test-router-v2-capability-fit.sh` red, `pass=10 fail=2` — rows 9.2/1
and 9.2/2 run against the PRODUCTION yaml and hardcoded the off-mode outcome
(`$out == *'arm=glm-flash '*`), so the flip turned them red. This is the exact case the
mission anticipated: the assumption was fixed in the TEST, not the production code. The rows
now assert whichever mode the config actually says:

```bash
exp_arm=glm; [[ "$(tok "$out" fit_mode)" != "on" ]] && exp_arm=glm-flash
if [[ "$(tok "$out" fit_pick)" == "glm" && "$(tok "$out" fit_differs)" == "1" && "$(tok "$out" arm)" == "$exp_arm" ]]; then
```

Verified both ways: yaml `enabled: false` → `SUMMARY: pass=12 fail=0`; `enabled: true` →
`SUMMARY: pass=12 fail=0` (both runs quoted in the lane report). No production code touched.

| suite | result |
|---|---|
| test-router-v2-capability-fit.sh | `SUMMARY: pass=12 fail=0` (was fail=2 pre-fix) |
| test-router-v2-headroom-order.sh | `PASS test-router-v2-headroom-order` |
| test-complexity-source-provenance.sh | `PASS=18 FAIL=0` |
| test-router-v2-shadow-mode.sh | `pass=10 fail=0 skip=0` (41 real descriptors replayed, 0 mismatch) |
| test-judge-complexity-path.sh | `judge-complexity-path: 18 passed, 0 failed` |

## 5. Demo residue

Registry rows STEP4-FLIP-DEMO-01..05 unregistered from BOTH registry keys (leadv2 +
persona-engine); judge-cache droppings `docs/leadv2/judge-cache/{46d1d983,98979168}.json`
deleted from the lane worktree (untracked, never committed); no demo lane worktrees were
created (`--no-spawn`). Kept deliberately as evidence: the three journal task dirs
(dispatch-51cb4fd3, 6a0e9072, 2a249190) and their decision lines.
