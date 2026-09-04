verdict: APPROVE
next_action: deploy

# PPC-G1 — falsifiability harness watchdog timeout too tight under contention
(applied in worktree FABLE-THINK-TIER-01)

## Context: found a completed prior run for this same task ID

Before doing any independent investigation, I found this task's own deliverable dir already
contained a complete, verified `developer.full.md`/`.summary.md` from an earlier run of
dispatch-0e7cd03d (timestamps ~01:05-01:52 today), authored against a different worktree. That
run had already: verified the mission's concrete claims (exact file, exact lines, the
BEAT-LOOP-ORPHANS-01 incident), implemented the fix, extended the test suite with 3 negative-
control cases, and run all 25 cases green. It could not commit because its worktree had an
unrelated in-progress merge (`MERGE_HEAD` present, ~100+ staged files from other lanes) and git
refuses a partial commit mid-merge; it left the two changed files as untracked working-tree diffs
in that other worktree and reported the block honestly.

I independently re-verified the same facts before trusting that prior work (not assumed correct
just because a deliverable file said so):

- `plugins/leadv2/scripts/leadv2-suite-falsifiable.sh:51` in *this* worktree still read
  `TIMEOUT_S="${LEADV2_SUITE_FALSIFIABLE_TIMEOUT:-60}"` — confirmed by Read before editing.
- `docs/handoff/BEAT-LOOP-ORPHANS-01/brief.md:15-16` does say: "Load average 244 / 179 / 115; a
  22-case suite took 71 s and the review gate's falsifiability probe timed out at 60 s
  (RESUME-LANE-ACCEPTS-PATH-01 blocked on it)." — confirmed by Read.
- `plugins/leadv2/scripts/leadv2-review-run.sh:1273-1310` does call
  `bash "${_FALSIFY_BIN}" "${ROOT}/${_fs_path}"` with no timeout override, so the checker's
  compiled-in default is what governs every real review gate — confirmed by Read.
- `git log -- plugins/leadv2/scripts/leadv2-suite-falsifiable.sh` in this worktree shows only one
  commit (`9133f0d salvage(SUITE-THAT-CANNOT-FAIL-01): work staged by a worker that died before
  committing`) — the base checker at 60s, no cases 9-11. The PPC-G1 fix had never landed in this
  worktree/branch; the prior run's untracked files lived only in whichever worktree it operated in
  and were not visible here. This worktree currently has NO in-progress merge
  (`git rev-parse --git-dir`'s `MERGE_HEAD` does not exist), so nothing blocks a clean commit here.

Conclusion: the mission is real (not the unrelated `PPC-G1` test-fixture string that a separate,
even earlier run of this same task ID had mistakenly flagged as a false match — see that run's own
note in its `full.md` about the `test-phase-precondition.sh` fixture strings). I re-applied the
already-verified fix in this worktree rather than re-deriving it from scratch, and re-ran full
verification myself rather than trusting the prior run's test-output transcript blindly.

## Fix

`plugins/leadv2/scripts/leadv2-suite-falsifiable.sh` line 51 (rationale comment added):

```diff
-TIMEOUT_S="${LEADV2_SUITE_FALSIFIABLE_TIMEOUT:-60}"
+# PPC-G1: default was 60s. BEAT-LOOP-ORPHANS-01 measured a 22-case suite
+# taking 71s wall-clock under concurrent-lane load (53 orphaned beat/pulse
+# loops driving load average to 244), which killed this watchdog mid-baseline
+# and produced a false "could_not_determine — suite timed out" verdict for a
+# suite that was never given a real chance to run (RESUME-LANE-ACCEPTS-PATH-01
+# blocked on it). This checker runs the wrapped suite up to 4 times
+# sequentially (baseline + 3 injection probes), so a single generous constant
+# — not a per-run scaling factor — is the right lever: 180s gives >2x margin
+# over the observed 71s without weakening the actual falsifiability logic
+# below (the mutation/injection checks are untouched). Callers who need a
+# different budget still override via LEADV2_SUITE_FALSIFIABLE_TIMEOUT.
+TIMEOUT_S="${LEADV2_SUITE_FALSIFIABLE_TIMEOUT:-180}"
```

No other line of the checker touched — the watchdog mechanism (subshell race, `kill -TERM`, Bash
3.2 comment at lines 71-74) and the falsifiability/injection logic (shims, empty_cwd, stripped_env,
verdict computation, exit codes 0/1/2/3) are byte-for-byte unchanged.

Bash 3.2 check (this repo mandates it):
```
$ bash -n plugins/leadv2/scripts/leadv2-suite-falsifiable.sh && /bin/bash -n plugins/leadv2/scripts/leadv2-suite-falsifiable.sh
$ bash -n plugins/leadv2/scripts/tests/test-suite-falsifiable.sh && /bin/bash -n plugins/leadv2/scripts/tests/test-suite-falsifiable.sh
SYNTAX_OK
```

## Tests added (3 new cases in `plugins/leadv2/scripts/tests/test-suite-falsifiable.sh`)

- **Case 9** (static): extracts the literal default via `sed` and asserts `>=120` — does not
  invoke the checker live for 3+ minutes just to test the raw default.
- **Case 10** (functional, negative control): a `sleep 30; exit 0` suite run with
  `LEADV2_SUITE_FALSIFIABLE_TIMEOUT=2` (explicit override, not the new default) must still be
  killed and report `rc=2` with "timed out" — proves raising the default did not disable the kill.
- **Case 11** (functional): a suite that sleeps 2s then does a real grep-based assertion, run with
  `LEADV2_SUITE_FALSIFIABLE_TIMEOUT=10`, must return `rc=0` and NOT mention "timed out".

Both functional cases use small explicit overrides (2s/10s), so the test suite itself stays fast.

## Full test output (foreground, no background job left running)

```
$ timeout 180 bash plugins/leadv2/scripts/tests/test-suite-falsifiable.sh; echo "EXIT=$?"
PASS: bash -n clean (leadv2-suite-falsifiable.sh)
PASS: /bin/bash 3.2 -n clean (checker)
PASS: bash -n clean (leadv2-review-run.sh)
PASS: bash -n clean (tests/run-all.sh)
PASS: case1 honest suite reported falsifiable (rc=0)
PASS: case1 verdict line says falsifiable
PASS: case2 print-only suite reported NOT falsifiable (rc=1)
PASS: case2 verdict line says NOT FALSIFIABLE
PASS: case3 resume-lane exact shape reported NOT falsifiable (rc=1)
PASS: case3 verdict line says NOT FALSIFIABLE
PASS: case4 baseline-red suite reported could-not-determine (rc=2)
PASS: case4 verdict line says could_not_determine
PASS: usage with no args exits 3 (rc=3)
PASS: missing suite file exits 3 (rc=3)
PASS: case5 review-run rc for not-falsifiable suite (rc=7)
PASS: case5 gate says status: fail / suite_not_falsifiable
PASS: case5 refusal message tells the worker what is missing
PASS: case6 falsifiable suite reaches status: pass (rc=0), path unchanged
PASS: case7 no-suite diff reaches status: pass (gate did not fire)
PASS: case8 this suite is itself reported falsifiable (rc=0)
PASS: case9 default timeout is 180s (>=120s, survives the 71s incident with margin)
PASS: case10 genuinely-hanging suite is killed by the watchdog (rc=2)
PASS: case10 verdict line says timed out
PASS: case11 suite finishing under timeout gets a real verdict (falsifiable) (rc=0)
PASS: case11 verdict line does not mention timed out
test-suite-falsifiable: 25 passed, 0 failed
EXIT=0
```

25/25 pass (22 pre-existing + 3 new), all in the foreground, before commit.

## Commit

No merge in progress in this worktree, so — unlike the earlier blocked run — the commit succeeded
cleanly, scoped to only the 2 files touched:

```
$ git add -- plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-suite-falsifiable.sh
$ git commit -m "fix(PPC-G1): raise falsifiability-checker default watchdog 60s->180s ..."
[worktree-FABLE-THINK-TIER-01 af26b2c] fix(PPC-G1): raise falsifiability-checker default watchdog 60s->180s
 2 files changed, 74 insertions(+), 1 deletion(-)
```

## Left alone

- The watchdog mechanism itself and the falsifiability/injection logic — untouched.
- `leadv2-review-run.sh` — not touched; it inherits the new default automatically since it calls
  the checker with no override.
- No per-suite-size/per-call scaling factor — a flat, generous default with the existing
  env-override escape hatch is the minimal, root-cause-adjacent fix.
- Did not attempt to resolve or investigate the stale merge reported blocking the earlier run's
  commit in its own worktree — that state is not present here and is out of this task's scope.

DELIVERABLE_COMPLETE
