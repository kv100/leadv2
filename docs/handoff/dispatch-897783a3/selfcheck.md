# builder selfcheck — dispatch-897783a3
generated_at: 2026-08-31T14:58:44Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-VERDICT-COUNTER-03
diff_hash: ca571cea7c756684627fcf87f7ebd3c13f708bcd5294df8a8fbdaca597a646d6
checks: 109   failed: 6   skipped: 3

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| resolve | plugins/leadv2/scripts/.claude/scripts/lv2 | SKIP (unresolved_path) |
| bash -n | plugins/leadv2/hooks/leadv2-codex-first-nudge.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-one-copy-drift.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-promise-guard.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-task-anchor.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-truth-card-inject.sh | 0 |
| bash -n | plugins/leadv2/scripts/codex-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/codex-task.sh | 0 |
| bash -n | plugins/leadv2/scripts/freepool-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-active-registry.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-broad-status.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-glm-quota-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-status-line.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-status-collector.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-status-surface.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-admission-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-control-prover.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-lane-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-red-proof.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worker-output-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-admission-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-arm-admission.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-control-prover.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-effort-routing.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-model-selector.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-hook-output-cap.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-containment.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-placement-pin.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lib-source-guarded.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-mission-writeset.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-one-copy-drift-hook-postsync.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-plan-in-lane.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-action-binding.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-red-proof-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-body-recovery.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-status-surface.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-statusline-readable.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-t13-slice1.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-output-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh | 0 |
| bash -n | plugins/leadv2/tests/test-promise-guard.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| bash -n | tests/test-status-surface-bash32.sh | 0 |
| py_compile | plugins/leadv2/scripts/leadv2-lane-class.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-VERDICT-COUNTER-03/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-admission-class.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-arm-admission.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-control-prover.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-effort-routing.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-model-selector.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-hook-output-cap.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-containment.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-placement-pin.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lib-source-guarded.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-mission-writeset.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-one-copy-drift-hook-postsync.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-plan-in-lane.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-promise-action-binding.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-red-proof-gate.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-review-body-recovery.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-status-surface.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-statusline-readable.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-t13-slice1.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-worker-output-gate.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh | 0 |
| falsification | plugins/leadv2/tests/test-promise-guard.sh | ADVISORY (no_falsification_marker) |
| falsification | tests/test-status-surface-bash32.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh (falsification proof) (rc=1)
PASS: bash syntax: dispatch
FAIL: (green) router exclusion line missing (log: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//arm-cap-honoured.5Ki7CX/green.log) -- 
FAIL: (green) arbiter picked freepool despite router exclusion (log: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//arm-cap-honoured.5Ki7CX/green.log) -- 
PASS: (red) with allowed_arms wiring stripped, the exact live bug reproduces -- arbiter re-picks the router-excluded arm
---
PASS=2 FAIL=2

## raw — plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh (falsification proof) (rc=1)
[TEST] PASS: T1: happy path — ready-line at= == artifact line-1 stamp
[TEST] PASS: T2: degraded path — ready-line at= == artifact line-1 stamp
[TEST] FAIL: T3a: stamp mismatch: at= line1=
[TEST] PASS: T3b: unwritable artifact — FAILED line, no path= token
[TEST] PASS: T4: degraded beat names live lanes, not just staleness
[TEST] PASS: T5: zero live lanes — beat still emits a truthful fact
----------------------------------------
test-beat-stamp-agreement: 5 passed, 1 failed
FAIL: T3a: stamp mismatch: at= line1=

## raw — plugins/leadv2/scripts/tests/test-effort-routing.sh (falsification proof) (rc=1)
PASS: adversarial-review kind resolves effort=high
PASS: mechanical/docs kind resolves effort=low
PASS: ordinary heavy code build resolves effort=medium
PASS: new yaml-only effort_matrix rule flips the outcome (no script edit)
PASS: unmodified routing.yaml still resolves medium (control for the anti-hardcode case)
PASS: codex arm receives --effort high in its own launch args (distinct from --tier)
FAIL: sonnet argv=<no argv captured> dispatch_out=[leadv2-dispatch-code] ERROR: dispatch refused: missing mandatory phases: diverge,plan,gate1
[leadv2-dispatch-code] ERROR:   remedy: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-VERDICT-COUNTER-03/plugins/leadv2/scripts/leadv2-phase-record.sh record 9929fa65 diverge --artifact <path>
[leadv2-dispatch-code] ERROR:   remedy: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-VERDICT-COUNTER-03/plugins/leadv2/scripts/leadv2-phase-record.sh record 9929fa65 plan --artifact <path>
[leadv2-dispatch-code] ERROR:   remedy: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-VERDICT-COUNTER-03/plugins/leadv2/scripts/leadv2-phase-record.sh record 9929fa65 gate1 --artifact <path>
[leadv2-dispatch-code] active_lane_released task=9929fa65 id=dispatch-9929fa65 where=exit_trap
PASS: glm arm (no effort control) journals effort_dropped and does not crash
PASS: decision line names both arm and effort (codex run)
SUMMARY: pass=8 fail=1
rm: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.t0dJJlneFq: Directory not empty

## raw — plugins/leadv2/scripts/tests/test-freepool-model-selector.sh (falsification proof) (rc=1)
[TEST] PASS: bash syntax: selector + gate
[TEST] PASS: rank order: primary chosen when all routes live
[TEST] PASS: rank order: config order drives the pick, not a hardcoded default (negative control)
[TEST] PASS: probe-fail advances rank: primary dead -> secondary chosen
[TEST] PASS: probe-fail advances rank: two dead ranks -> tertiary chosen (negative control)
[TEST] PASS: selector rc!=0 on missing config, prints nothing to stdout
[TEST] PASS: freepool_select_model() falls open to "sonnet" on selector failure
[TEST] PASS: FREEPOOL_SKIP_MODEL_SELECT=1 short-circuits to "sonnet" (negative control)
[TEST] PASS: P0: freepool_select_model() falls open to "sonnet" under set -e (selector failure does not kill the caller)
[TEST] PASS: mutation applied: P0 if/else fallback reverted to bare `chosen=...; rc=$?` (scratch copy)
[TEST] PASS: MUTATION KILLED: reverting the P0 fix makes set -e kill the script before the sonnet fallback
[TEST] FAIL: P1a: checked-in config against real-shaped fixture (rc=0 chosen=anthropic/groq/openai/gpt-oss-120b)
[TEST] PASS: MUTATION KILLED: bare pre-fix prefixes still match via the with/without-anthropic/ tolerant fallback (P1a fix also makes stale configs recoverable)
[TEST] FAIL: FP-01/02 role separation (implement=anthropic/groq/openai/gpt-oss-120b/0 bulk=anthropic/groq/openai/gpt-oss-120b/0)
[TEST] PASS: FP-01: unset FREEPOOL_ROLE defaults to implement
[TEST] PASS: FP-02 negative control: commented role_rank falls back to flat model_rank
[TEST] PASS: gate TTL: all-stale window + healthy live probe -> gate passes
[TEST] PASS: gate TTL negative control: all-stale window + dead live probe -> refused arm_down
[TEST] PASS: gate TTL: genuinely empty window + healthy live probe -> gate passes
[TEST] PASS: gate TTL: fresh breach still refuses gate_broken (fresh data not swallowed by TTL filter)
[TEST] PASS: gate P1b: all-stale window issues exactly ONE live /health probe
[TEST] PASS: mutation applied: second live /health probe reintroduced on the rc==4 branch
[TEST] PASS: MUTATION KILLED: reintroducing the second probe reproduces the pre-fix double-probe (count=2)
[TEST] PASS: mutation applied: TTL filter predicate replaced with True (always-fresh)
[TEST] PASS: MUTATION KILLED: reverting the TTL filter reproduces the stale-window bug (gate wrongly refuses gate_broken)
[TEST] === 23 passed, 2 failed ===

## raw — plugins/leadv2/scripts/tests/test-mission-writeset.sh (falsification proof) (rc=1)
PASS: extract: Done-means backtick path captured
PASS: extract: second Done-means backtick path captured
PASS: extract: citation-only path excluded (see/described in)
PASS: extract: 'write ... to' instruction captured
PASS: extract: 'leave the logs in' instruction captured
PASS: missing: uncovered path named
PASS: missing: citation-only mission has nothing missing
PASS: missing: directory-prefix LANE_WRITES covers nested Done-means paths
PASS: missing: glob LANE_WRITES covers Done-means paths
PASS: suggest_line: appends missing paths to existing LANE_WRITES
PASS: CLI: refuses with exit non-zero and names the missing path
PASS: CLI: a citation-only mission dispatches normally (exit 0)
PASS: control CITE: mutated lib leaks citation path into required -> caught (would be red)
PASS: control COVERAGE: mutated lib always reports covered -> caught (would be red)
PASS: C1: per-file consumer symlink starts with canonical mission/red-proof libraries
FAIL: C4: expected default 0 rc=0 out=[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-VERDICT-COUNTER-03 cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
0
PASS: wiring: architect_prepass itself refuses a non-covering mission
PASS: control WIRING: removing all 3 call sites -> architect_prepass no longer refuses (caught, would be red)
PASS: specimen: fix-round-4.md (real corrected mission) dispatches normally
PASS: specimen: pre-correction fix-round-5.md refused, names lib/leadv2-lane-guard.sh
PASS: usage: --help stderr has no unescaped-backtick command-not-found artifact
PASS: control USAGE: reverting the backtick escaping reproduces the error -> caught (would be red)
SUMMARY: pass=21 fail=1

## raw — plugins/leadv2/scripts/tests/test-worker-output-gate.sh (falsification proof) (rc=1)
PASS: bash syntax: gate
PASS: clean sh+py: gate exits 0 with no reject lines
PASS: broken sh: gate rejects with bash-n error attached (behavioural, real bash -n run)
PASS: broken py: gate rejects with py_compile error attached
PASS: non-code file: ignored, gate exits 0
PASS: empty git diff: gate passes under bash 3.2 with no unbound-array crash
PASS: --from-git-diff: staged broken .sh caught from real git diff output
PASS: committed range: clean tree still rejects broken origin/main...HEAD file
FAIL: missing origin/main: expected explicit nonzero range error, got rc=0 out=worker_output_gate_base_attempt ref=origin/main result=unresolved
worker_output_gate_base_attempt ref=origin/master result=unresolved -- 
mutation anchor must match exactly once -- zero-match or ambiguous
FAIL: missing-range mutation: production anchor missing -- zero-match
FAIL: (green) restored production gate did not restore range rejection -- rc=0 out=worker_output_gate_base_attempt ref=origin/main result=unresolved
worker_output_gate_base_attempt ref=origin/master result=unresolved
PASS: production call path: freepool-coder rejects committed bash-n failure as parse_error
PASS: MUTATION KILLED: production freepool-coder without gate call falsely accepts committed broken output
PASS: (green) restored production freepool-coder rejects committed bash-n failure
---
PASS=11 FAIL=3

verdict: RED
