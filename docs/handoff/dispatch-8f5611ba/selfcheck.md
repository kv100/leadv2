# builder selfcheck — dispatch-8f5611ba
generated_at: 2026-09-04T13:23:18Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01
diff_hash: 2c8186a83f2f7c1cc6ea293bd16f2cf2e0bd2e3f8d16e0a80f2d138fa3f6b56b
checks: 58   failed: 8   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 29 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-admission-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-claude-profile-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-fp07-codex-rg-no-match.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-fp07-simple.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-fp07-verification.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-glm-peak-flash-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-code-intel-rate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-freepool-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-land.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-lane-state.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-worker-mcp.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-mythicalgames-overrides-gen.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-quota-read-anthropic-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-skill-telemetry.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-stale-script-tree.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-status-collector-facts.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-status-surface-terminal-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-tracked-evidence-paths.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-admission-class.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-claude-profile-select.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-fp07-codex-rg-no-match.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-fp07-simple.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-fp07-verification.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-glm-peak-flash-gate.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-code-intel-rate.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-freepool-gate.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-land.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-lane-state.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-worker-mcp.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-mythicalgames-overrides-gen.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-plugin-repo-backlog.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-quota-read-anthropic-liveness.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-skill-telemetry.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-stale-script-tree.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-status-collector-facts.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-status-surface-terminal-ledger.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-tracked-evidence-paths.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh (falsification proof) (rc=1)
[TEST] PASS: S1: foreign live lane in the table with repo=foreignrepo
[TEST] PASS: S4: own-repo mirror slug skipped by the -ef filter, foreign repo still read
[TEST] PASS: S2: single-repo output byte-identical with --all-repos on (consumer safety)
env: snap: No such file or directory
[TEST] FAIL: S3: 
[TEST] PASS: R1: foreign lane rendered with slug prefix, no false empty board
[TEST] PASS: R1b: foreign row carries its stream age
[TEST] FAIL: R2: founder-status.md wrong: 2026-08-25T11:00:00Z [BROAD_STATUS] dispatched=1
13:05

| Линия | Что делает | Состояние |
|---|---|---|
| foreignrepo/dispatch-fee00001 | — | тихо 0 мин |

С прошлого удара: +1 линии подняты, 0 закрыто.
Решений не ждёт.
(скрыто: 3 строк очереди — docs/leadv2/founder-status-full.md)
[BROAD_STATUS_END]
[TEST] FAIL: R3: unexpected prefix: | Линия | Что делает | Состояние |
|---|---|---|
| foreignrepo/dispatch-fee00001 | — | тихо 0 мин |

[broad-status-foreign-lanes] PASS=5 FAIL=3

## raw — plugins/leadv2/scripts/tests/test-claude-profile-select.sh (falsification proof) (rc=1)
[TEST] PASS: T21c: no probe ran
[TEST] PASS: T21: exit 0
=== T15: label/expect vs derived identity -> WARN label_mismatch, bucket by identity ===
[TEST] PASS: T15a: label_mismatch warn carries expected + derived
[TEST] PASS: T15b: reported/bucketed identity is the DERIVED one, not the label claim
[TEST] PASS: T15: exit 0 (fail-open)
=== T16: missing .claude.json -> WARN identity_email_unresolved, fail-open ===
[TEST] PASS: T16a: identity_email_unresolved warn
[TEST] PASS: T16b: entry still selectable (fail-open)
[TEST] PASS: T16: exit 0
=== T17: default token expired -> WARN default_token_expired, selection unchanged ===
[TEST] PASS: T17a: default_token_expired warn
[TEST] PASS: T17b: selection itself unchanged
[TEST] PASS: T17: exit 0
=== T18: default credential absent -> WARN default_token_absent, fail-open ===
[TEST] PASS: T18a: default_token_absent warn
[TEST] PASS: T18b: selection proceeds
[TEST] PASS: T18: exit 0
=== T19: WARN lines reach the journal (ISO-prefixed) ===
[TEST] PASS: T19a: journal carries ISO-prefixed same_account WARN
[TEST] PASS: T19b: journal has no token
=== T20 (C2): two no-.claude.json slots, same sub -> distinct buckets, no same_account ===
[TEST] PASS: T20a: distinct quota buckets for two pro/na slots (config-dir key)
[TEST] PASS: T20b: no same_account warn when the email half is unresolved
[TEST] PASS: T20c: both slots warned identity_email_unresolved
[TEST] PASS: T20d: selection still works (fail-open, lowest window wins)
[TEST] PASS: T20: exit 0
=== T21: binding_window (reset-aware) beats blind worst-of-both ===
[TEST] PASS: T21: picks case1 (binding window 20%) over case2 (binding window 90%), reason=binding_window
[TEST] PASS: T21: exit 0
=== T22 (D3, TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01): stale expiresAt does not stop a genuinely live account from winning ===
[TEST] PASS: T22a: WARN fires but does not exclude
[TEST] PASS: T22b: the stale-per-field, live-per-probe account still wins -- the field is not the liveness test
[TEST] PASS: T22: exit 0
=== T23 (D3): same_account still fires when one sibling's expiresAt looks stale ===
[TEST] FAIL: T23a: same_account fires even though one sibling looked expired -- closes the coverage hole -- no match for 'WARN: same_account label=same-fresh label=same-stale identity=team/shared2@fixture\.test' in: [claude-profile-select] WARN: registry line 2: expiresAt_stale label=same-stale identity=team/shared2@fixture.test -- probing live anyway
[claude-profile-select] WARN: same_account label=same-fresh label=same-stale sub=team account=unresolved -- one real account behind two slots
[TEST] FAIL: T23b: both slots stay candidates (fail-open, as with T14) -- no match for '^profile=same-fresh .*candidates=2 ' in: profile=- reason=same_account
[TEST] PASS: T23: exit 0
[TEST] Results: PASS=79 FAIL=2

## raw — plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh (falsification proof) (rc=1)
[TEST] PASS: bash -n leadv2-dispatch-code.sh
[TEST] PASS: bash -n test-dispatch-ledger-task-id.sh
[TEST] PASS: dispatch with --task-id exits 0
[TEST] PASS: pending dispatch ledger file exists
[TEST] PASS: ledger row's task_id equals the bound --task-id (N4-TESTRUNNER-FALSE-RED)
[TEST] PASS: ledger row's mission_path is empty for an inline (non-@file) mission, as expected
[TEST] PASS: C1: no --task-id -> reserve row task_id is EMPTY (identity absent, not the H1)
[TEST] PASS: C1: no --task-id, mission has H1 -> reserve row lane_label == H1 name-token (N7F-C1)
[TEST] PASS: C2: no --task-id, mission has no H1 -> reserve row task_id is empty (no invented name)
[TEST] FAIL: C3: --task-id AND mission-H1 both present -> reserve row task_id == bound --task-id (got rc=2, row: {"task_sig":"e06410ead1ee3ead7acc14514dca723dc1f6acd323ac9a7c51e61bda61f9ced6","arm":"sonnet","rule":"safety_gate_publish_payments","repo":"repo","ts":"2026-09-04T13:09:19Z","token":"40433-1788527359-C006FEE0-E530-45B4-B2DD-81BCA3893F60","state":"confirmed","created_epoch":1788527359,"task_id":"","mission_path":"","lane_label":"","handle":"40675"}, out: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01/plugins/leadv2/scripts/leadv2-dispatch-code.sh: line 8182: syntax error near unexpected token `fi'
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01/plugins/leadv2/scripts/leadv2-dispatch-code.sh: line 8182: `      fi')
[TEST] PASS: C4: write-terminal with empty founder + display-name 7th arg -> task_id from display name, founder_task_id empty
[TEST] PASS: C5: write-terminal with 6 args (no display name) -> task_id falls back to founder (back-compat)
[TEST] PASS: F4: no --task-id, mission H1  -> renders OPS-42 (not the tasks.yaml title)
[TEST] PASS: F4b: --task-id OPS-42 -> renders the tasks.yaml title (identity lookup preserved)
[TEST] === 13 passed, 1 failed ===

## raw — plugins/leadv2/scripts/tests/test-fp07-verification.sh (falsification proof) (rc=1)
FAIL: FP-07 fix not found in leadv2-review-run.sh

## raw — plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh (falsification proof) (rc=1)
  "backend": "terminal",
  "pid": 47369
}) rc_dead=0 ({
  "task_id": "DEAD",
  "status": "dead",
  "reason": "heartbeat age 60.0m > 25m AND pid=999999 confirmed gone (kill -0 failed)",
  "backend": "terminal",
  "pid": 999999
}) rc_unknown=4 ({"error": "not_found", "message": "task_id NEVER-REGISTERED not in active.yaml"})
[TEST] PASS: T2: absent-record rc=4 differs from both alive(rc=0) and dead(rc=0) in the RETURN VALUE, not only in text
[TEST] T2-NC: mutating the not_found exit code must collapse it onto rc=0
[lv2_durable_pid] WARNING: no claude process found in PPID chain; using fallback pid=47369
[TEST] T2-NC: baseline_rc=4 (from T2, unmutated) mutated_rc=0
[TEST] PASS: T2-NC: mutated not_found path now (wrongly) returns rc=0, indistinguishable from a real verdict -- the negative control is red as required
[TEST] T3: static scan -- no pgrep -f / ps|grep in the two canonical liveness libs
[TEST] PASS: T3: no process-name-pattern liveness check found in scan scope
[TEST] T3-NC: inserting a pgrep -f line inside a real function body must be caught
[TEST] T3-NC: baseline_rc=0 (from T3, unmutated) mutated_rc=1
[TEST] PASS: T3-NC: scanner caught the injected pgrep -f and named file:line -- /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01/plugins/leadv2/scripts/lib/.nc-pattern-leadv2-lane-state.sh:61: process-name-pattern liveness check: pgrep -f "$1" >/dev/null 2>&1 && return 0  # NC-MUTATION
[TEST] T4: static scan -- no $? captured after head/tail/wc/sort/uniq in the two canonical liveness libs
[TEST] PASS: T4: no post-filter-pipe $? capture found in scan scope
[TEST] T4-NC: inserting a piped-through-head command + trailing $? read must be caught
[TEST] T4-NC: baseline_rc=0 (from T4, unmutated) mutated_rc=1
[TEST] PASS: T4-NC: scanner caught the post-filter-pipe $? read and named file:line -- /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01/plugins/leadv2/scripts/lib/.nc-pipe-leadv2-lane-state.sh:61: $? read after a value-losing pipe stage instead of from the command itself: ps -eo pid,comm | head -3  # NC-MUTATION
[TEST] T5: static scan -- no ps/pgrep//proc enumeration + text row-select in the two canonical liveness libs
[TEST] FAIL: T5: text-matched process-table liveness decision(s) found (expected: the known lane-state.sh reconcile violator; any OTHER line is a new finding for the report):\n/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01/plugins/leadv2/scripts/lib/leadv2-lane-state.sh:222: liveness by process-table enumeration + TEXT row-select (ps table-wide enumeration; text select: if worktree not in line: continue)
[TEST] T5-NC: inserting ps -axo + 'not in' row-select inside a real function body must be caught
[TEST] T5-NC: baseline_rc=0 (watch-lifecycle.sh unmutated) mutated_rc=1
[TEST] PASS: T5-NC: scanner caught the injected ps -axo + not-in row-select and named file:line -- /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01/plugins/leadv2/scripts/lib/.nc-substr-leadv2-watch-lifecycle.sh:71: liveness by process-table enumeration + TEXT row-select (ps table-wide enumeration; text select: [[ "$1" =~ ^[0-9]+$ ]] || return 1)
[TEST] T5-NCb: injected pgrep -f must still be caught by the class scanner
[TEST] T5-NCb: baseline_rc=0 mutated_rc=1
[TEST] PASS: T5-NCb: class scanner still catches pgrep -f -- /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01/plugins/leadv2/scripts/lib/.nc-pgrepf-leadv2-watch-lifecycle.sh:71: liveness by process-table enumeration + TEXT row-select (named idiom (pgrep -f / ps|grep); text select: [[ "$1" =~ ^[0-9]+$ ]] || return 1)
[TEST] T5-NCc: injected ps | grep must still be caught by the class scanner
[TEST] T5-NCc: baseline_rc=0 mutated_rc=1
[TEST] PASS: T5-NCc: class scanner still catches ps | grep -- /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01/plugins/leadv2/scripts/lib/.nc-pipegrep-leadv2-watch-lifecycle.sh:71: liveness by process-table enumeration + TEXT row-select (named idiom (pgrep -f / ps|grep); text select: ps -Ao command= | grep -q "$2"  # NC-MUTATION)
[TEST] T5-FP: per-pid ps -p/-o lookups in watch-lifecycle.sh must stay green
[TEST] PASS: T5-FP: no false positive on wl_cmdline_match / wl_pidfile_live (per-pid ps -p ... -o command= + == *needle*)

=== test-liveness-tristate-01.sh: 13 passed, 1 failed ===
FAIL: T5: text-matched process-table liveness decision(s) found (expected: the known lane-state.sh reconcile violator; any OTHER line is a new finding for the report):\n/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01/plugins/leadv2/scripts/lib/leadv2-lane-state.sh:222: liveness by process-table enumeration + TEXT row-select (ps table-wide enumeration; text select: if worktree not in line: continue)

## raw — plugins/leadv2/scripts/tests/test-skill-telemetry.sh (falsification proof) (rc=1)
[TEST] PASS: rollup syntax (/bin/bash)
[TEST] PASS: collector exits 0 on fixture tree
[TEST] PASS: one row for fixture-skill-ok
[TEST] PASS: one row for fixture-skill-err
[TEST] PASS: one row for fixture-skill-noresult
[TEST] PASS: three rows for fixture-skill-injected (S1b)
[TEST] PASS: two rows for fixture-skill-failing (S1b)
[TEST] PASS: subagent transcript glob is scanned
[TEST] PASS: row older than --since window is not collected
[TEST] PASS: slash command without skill-format tag is never collected
[TEST] PASS: S1a success resolves outcome=ok
[TEST] PASS: S1a failure resolves outcome=error
[TEST] PASS: S1a with no matching tool_result is n_a, never guessed ok
[TEST] PASS: S1b injection outcome is always n_a (no result record exists)
[TEST] PASS: lane derived from cwd worktree basename
[TEST] PASS: lane is 'main' for a non-worktree cwd
[TEST] PASS: phase resolved from nearest preceding real journal event (worker_spawned)
[TEST] PASS: phase is 'unknown' on the main lane, never guessed
[TEST] PASS: second collector run exits 0
[TEST] PASS: rerun appends zero duplicate rows (event_id dedup)
[TEST] PASS: rollup exits 0
[TEST] PASS: universe (TSV data rows) matches the 9 fixture skill dirs
[TEST] PASS: MD prints universe=9
[TEST] PASS: MD prints the correlation-not-proof header
[TEST] PASS: all-landed skill buckets INVOKED
[TEST] PASS: all-failed-resolved skill buckets INVOKED_NO_LANE_SUCCESS
[TEST] PASS: zero-rows-ever skill buckets NEVER_INVOKED
[TEST] PASS: SKILL.md-less dir is reported, not dropped
[TEST] PASS: history-only-outside-window skill is never mislabeled NEVER_INVOKED (got: INVOKED_PAST_ONLY)
[TEST] PASS: lane_success computed from real dispatch_terminal=landed
[TEST] PASS: lane_success computed from real dispatch_terminal=dead (0%, not n/a — it IS resolved)
[TEST] PASS: lane_success is n/a (never 0%) when no row's lane resolved
[TEST] PASS: dynamically-picked NEVER_INVOKED skill (fixture-skill-never) has zero JSONL rows
[TEST] FAIL: tests/run-all.sh EXTRA_SUITE_MAP missing a row for this suite
[NC] M1 baseline(GREEN) bucket=NEVER_INVOKED  mutated(RED) rc=0 bucket=INVOKED
[TEST] PASS: M1 mutation flips NEVER_INVOKED classification (suite would go red)
[NC] M2 baseline(GREEN) rows_stable  mutated(RED) rc=0 n1=9 n2=18
[TEST] PASS: M2 mutation breaks idempotency (suite would go red)

SUMMARY: PASS=38 FAIL=1

## raw — plugins/leadv2/scripts/tests/test-tracked-evidence-paths.sh (falsification proof) (rc=1)
PASS: tracked: docs/handoff/LAND-PATH-IS-BROKEN-01/worker-report.md
PASS: tracked: docs/handoff/LANE-TRUTH-BATCH-01/summary.md
PASS: tracked: docs/handoff/LEAD-USES-ITS-OWN-TOOLS-01/brief.md
PASS: tracked: docs/handoff/PHASE-REFUSAL-LEAVES-A-LANE-REGISTERED-01/report.md
PASS: tracked: docs/handoff/PLUGIN-REPO-HAS-NO-BACKLOG-01/persona-engine-close-commands.txt
PASS: tracked: docs/handoff/PLUGIN-REPO-HAS-NO-BACKLOG-01/source-rows.json
PASS: tracked: docs/handoff/PROCESS-AUDIT-20260821/codex-findings.md
PASS: tracked: docs/handoff/PROMISE-GUARD-BIND-01/fixtures/leadv2-promise-guard.pre-bind01.sh
PASS: tracked: docs/handoff/PULSE-IS-A-PLUGIN-DUTY-01/report.md
PASS: tracked: docs/handoff/QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01/brief.md
PASS: tracked: docs/handoff/REGISTRY-MUST-LEAVE-GIT-01/report.md
PASS: tracked: docs/handoff/REPORT-ONLY-GATE-01/report.md
PASS: tracked: docs/handoff/RESEARCH-HERDR-DAEMON-01/brief.md
PASS: tracked: docs/handoff/RESUME-20260903/_shared.md
PASS: tracked: docs/handoff/ROUTER-BRAIN-01/design.md
PASS: tracked: docs/handoff/SMART-ARBITER-01/brief.md
PASS: tracked: docs/handoff/SUBSCRIPTION-MIX-DECISION-01/assessment-claude.md
PASS: tracked: docs/handoff/SUBSCRIPTION-MIX-DECISION-01/data-pack.md
PASS: tracked: docs/handoff/TWELVE-LINUX-ONLY-SUITES-01/report.md
PASS: tracked: docs/handoff/TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01/brief.md
PASS: tracked: docs/handoff/WAVE4/shared-constraints.md
PASS: tracked: docs/handoff/WHEN-TO-FORK-01/mission-round2.md
PASS: tracked: docs/handoff/WHEN-TO-FORK-01/report.md
PASS: tracked: docs/handoff/dispatch-16fbe872/architect-prepass.md
PASS: tracked: docs/handoff/dispatch-2b6c3f01/review-gate.md
PASS: tracked: docs/handoff/dispatch-2e675c98-review/critic.full.md
PASS: tracked: docs/handoff/dispatch-65d12844/context.yaml
PASS: tracked: docs/handoff/dispatch-810129d0/review-codex.md
PASS: tracked: docs/handoff/dispatch-a2b844cf/architect-prepass.md
PASS: tracked: docs/handoff/dispatch-eb2d7143-review/critic.full.md
PASS: tracked: docs/handoff/one-path-plan-run-01/build-summary.md
PASS: tracked: docs/handoff/one-review-path-2026-08-06/design-plan-diagnose.md
PASS: tracked: docs/handoff/one-review-path-2026-08-06/design.md
PASS: tracked: docs/handoff/one-review-path-2026-08-06/mission-build-r1.md
RED control: baseline_rc=0 mutated_rc=1
RED control: baseline_out=PASS: tracked: plugins/leadv2/scripts/fake-carrier.sh
RED control: mutated_out=FAIL: NOT tracked: plugins/leadv2/scripts/fake-carrier.sh
PASS: RED control: baseline_rc=0 (fixture file tracked, check green before mutation)
PASS: RED control: mutated_rc=1 with a red line naming the untracked path (git rm --cached caught)
test-tracked-evidence-paths: 65 passed, 1 failed

## raw — plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh (falsification proof) (rc=1)
[TEST] FAIL: codex-task.sh emits documented MCP-gap NOTE
[TEST] PASS: worker-code-intel-preamble.md exists
[TEST] PASS: worker-code-intel-preamble.md <= 25 lines (      16)
[TEST] PASS: worker-code-intel-preamble.md covers graph/repowise/distill routing
[TEST] PASS: preamble gate: kimi attached (default gate) -> rc=0 + preamble text
[TEST] PASS: preamble gate: freepool attached (default gate) -> rc=0 + preamble text
[TEST] PASS: preamble gate: glm attached (default gate) -> rc=0 + preamble text
[TEST] PASS: preamble gate: kimi LEADV2_WORKER_MCP=0 -> rc=3 + empty output
[TEST] PASS: preamble gate: kimi fail-open (nothing resolvable) -> rc=3 + empty output
[TEST] PASS: preamble gate: codex unwired -> rc=4 + empty output
[TEST] PASS: preamble gate: sonnet default (no SLIM_MCP) -> rc=3 + empty output
[TEST] PASS: preamble gate: sonnet LEADV2_SUBSESSION_SLIM_MCP=1 -> rc=0 + preamble text
[TEST] PASS: preamble gate: fail-open branch stays silent (no inverted 'MCP unavailable' claim)
[TEST] PASS: leadv2-dispatch-code.sh: preamble injection is gated by worker_mcp_preamble_for_arm(arm)
[TEST] PASS: leadv2-dispatch-code.sh: unconditional-injection marker _LEADV2_CODE_INTEL_PREAMBLE stays deleted (round-2 H2 regression)
[TEST] PASS: leadv2-dispatch-code.sh: sources the shared worker-MCP lib (no second resolver)
[leadv2-dispatch-code] code_intel_preamble arm=kimi task=wiretest8 mode=attached
[leadv2-dispatch-code] effort_dropped by=router arm=kimi task=wiretest8 effort=medium reason=no_effort_control
[leadv2-dispatch-code] worker_spawned by=router model=kimi task=wiretest8 attempt=wiretest8-1788528184-83215 handle=wmbh8
worker_spawned model=kimi task=wiretest8 attempt=wiretest8-1788528184-83215 handle=wmbh8
[leadv2-dispatch-code] mission-version task=- sig=wiretest8 rev=? head="CODE-INTEL ROUTING (use before grep/cat on unfamiliar code): - Who calls X / trace a call "
[TEST] PASS: leadv2-dispatch-code.sh: _spawn_worker_body puts the resolved preamble text INSIDE the mission the child bg call receives
[TEST] negative control (mission fold): structural dispatch_gate_check still PASSES on the mutant, as predicted (R4 finding 2) -- the behavioural case below must be the one that catches it
[leadv2-dispatch-code] code_intel_preamble arm=kimi task=wiretest8 mode=attached
[leadv2-dispatch-code] effort_dropped by=router arm=kimi task=wiretest8 effort=medium reason=no_effort_control
[leadv2-dispatch-code] worker_spawned by=router model=kimi task=wiretest8 attempt=wiretest8-1788528185-84739 handle=wmbh8
worker_spawned model=kimi task=wiretest8 attempt=wiretest8-1788528185-84739 handle=wmbh8
[leadv2-dispatch-code] mission-version task=- sig=wiretest8 rev=? head="DEFINITION-OF-DONE GATE: before any model reviews your diff, a deterministic bash gate che"
[TEST] PASS: negative control (mission fold): mutated dispatcher goes RED -- preamble text absent from the mission the child receives (mutation caught)
[TEST] PASS: negative control: mutation applied to scratch copy
[TEST] PASS: negative control: mutated freepool-coder.sh correctly goes RED (no --mcp-config)
[TEST] PASS: negative control (freepool-bg): mutated bg run finalized
[TEST] PASS: negative control (freepool-bg): mutated cmd_run_child goes RED (no --mcp-config reaches the child)
[TEST] PASS: negative control (kimi-bg): mutated bg run finalized
[TEST] PASS: negative control (kimi-bg): mutated cmd_run_child goes RED (no --mcp-config reaches the child)
[TEST] PASS: negative control (tee -a): mutated kimi goes RED — attached record destroyed by truncation, journal case catches it
[TEST] PASS: negative control (dispatch gate): unconditional injection goes RED — dispatch gate check catches it

[TEST] TOTAL: PASS=48 FAIL=1
[TEST] FAIL: codex-task.sh emits documented MCP-gap NOTE

verdict: RED
