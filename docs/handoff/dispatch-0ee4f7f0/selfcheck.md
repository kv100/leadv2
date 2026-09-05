# builder selfcheck — dispatch-0ee4f7f0
generated_at: 2026-08-31T11:43:25Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-ONE-MECHANISM-01
diff_hash: c63add629089ac1898e5add6a79d804749716908bbb5a67b63d5afd51bc78d85
checks: 101   failed: 5   skipped: 3

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| resolve | plugins/leadv2/scripts/.claude/scripts/lv2 | SKIP (unresolved_path) |
| bash -n | plugins/leadv2/hooks/leadv2-codex-first-nudge.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-one-copy-drift.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-promise-guard.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-task-anchor.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-truth-card-inject.sh | 0 |
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
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-control-prover.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh | 0 |
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
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-ONE-MECHANISM-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-admission-class.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-arm-admission.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-renderer-truth.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-control-prover.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh | ADVISORY (no_falsification_marker) |
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

## raw — plugins/leadv2/scripts/tests/test-arm-admission.sh (falsification proof) (rc=1)
[TEST] PASS: bash -n scripts/leadv2-dispatch-code.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/lib/leadv2-route-arbiter.sh (incl. 3.2)
[TEST] PASS: case1 (ladder): protected + kind=code excludes cheap-arm/free-arm — got 'trusted-arm'
[TEST] PASS: case1 (arbiter): protected + kind=code picks trusted-arm — arm=trusted-arm model=t1 tier=standard reason=cheapest_capable chain=trusted-arm util_glm=10 util_codex=0 util_claude=10 util_freepool=0 floor_mode=bulk_only floor_mode_source=default
[TEST] FAIL: case2 (ladder): expected free-arm in chain, got 'trusted-arm'
[TEST] PASS: case2 (arbiter): protected + kind=review reaches free-arm — arm=free-arm model=f1 tier=standard reason=cheapest_capable chain=free-arm,trusted-arm util_glm=10 util_codex=0 util_claude=10 util_freepool=0 floor_mode=bulk_only floor_mode_source=default
[TEST] PASS: case3: ladder and arbiter agree free-arm is admissible at light (ladder='trusted-arm cheap-arm free-arm' arbiter='arm=cheap-arm model=c1 tier=standard reason=cheapest_capable chain=cheap-arm,free-arm,trusted-arm util_glm=10 util_codex=0 util_claude=10 util_freepool=0 floor_mode=bulk_only floor_mode_source=default')
[TEST] PASS: case4: mechanical build task resolves base-arm=cheap-arm (cheapest capable) — got 'cheap-arm'
[TEST] PASS: case4b: protected mechanical task still resolves base-arm=trusted-arm — got 'trusted-arm'
[TEST] PASS: case5: resolve_arm's own resolver invocation carries base-arm=cheap-arm — argv='--routing-yaml /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//arm-admission-fixture.I81Lwu/routing.yaml --job build --base-arm cheap-arm --signals {"mission_kind": "code", "protected_path": false, "safety_touched": false, "subsystem_count": 0.0, "needs_midflight_interaction": false, "ui_design_judgment": false, "glm_failure_count": 0.0, "glm_lock_busy": false}'
[TEST] PASS: NC(red) mutationA: reverting the writes_prod split re-excludes free-arm from review work — got 'trusted-arm'
[TEST] PASS: NC(red) mutationB: hardcoding the base-arm pick loses cheap-arm — got 'trusted-arm'
[TEST] PASS: NC(red) mutationC: dropping 'light' from free-arm's when: makes the ladder disagree with the arbiter again — ladder='trusted-arm cheap-arm'
[TEST] FAIL: post-mutation GREEN: case2 regressed
[TEST] PASS: post-mutation GREEN: case3 (ladder) still passes
[TEST] PASS: post-mutation GREEN: case4 still passes
[TEST] PASS: post-mutation GREEN: case5 still passes
[TEST] PASS: repo hygiene: this suite left every repo path byte-identical (fixture-only mutation)

[SUMMARY] PASS=16 FAIL=2

## raw — plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh (falsification proof) (rc=1)
PASS: bash syntax: dispatch
FAIL: (green) router exclusion line missing (log: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//arm-cap-honoured.gtluee/green.log) -- 
FAIL: (green) arbiter picked freepool despite router exclusion (log: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//arm-cap-honoured.gtluee/green.log) -- 
PASS: (red) with allowed_arms wiring stripped, the exact live bug reproduces -- arbiter re-picks the router-excluded arm
---
PASS=2 FAIL=2

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
FAIL: C4: expected default 0 rc=0 out=[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-ONE-MECHANISM-01 cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
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
