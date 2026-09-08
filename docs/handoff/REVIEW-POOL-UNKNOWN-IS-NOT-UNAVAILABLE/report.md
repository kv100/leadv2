# Review pool unknown arms — dispatch-b442099d

## Finding and decision

The producer has a probe. `resolve_review_pool._pct_for` maps fable, opus and sonnet to `live_anthropic_pct`; that function calls `bash <quota-live> anthropic` with a ten-second timeout, then reads the active account's percentages. A nonzero transport result, malformed response, non-ok status, or missing active-account percentages returns `None`. This is an unreadable quota result, not missing arm support and not an arbiter failure.

The current CLI observation has an active account with `http=401`, `status=unknown`, and no percentage fields. Evidence: `timeout 25 bash plugins/leadv2/scripts/leadv2-quota-live.sh anthropic`; raw output is in the quota section below and [quota-cli.json](quota-cli.json). The returned document's `fetched_at` identifies its freshness; this invocation used the ordinary cached CLI path, not a forced refresh. UNVERIFIED: the historical 11:17 incident had this exact HTTP cause; its pasted pool proves missing readings but does not identify the underlying transport result.

The consumer has two relevant refusals: arbiter adoption accepted only `:ok:`, and `next_ok_arm_after` also accepted only `:ok:`. The latter exhausts the fixed pool after GLM refuses and reaches `_pc_write_unreviewed`, which records dead/all_arms_unavailable. Fixing the arbiter adoption alone would not repair that fallback.

Review-only Anthropic unknowns now carry `unknown:quota_checked`, emitted after author exclusion, provider lockout checks and the existing quota-read attempt. They do not become `ok` or acquire a fabricated percentage. The consumer admits this exact marker only for fable/opus/sonnet, through the same normal `run_reviewer_arm` launcher path as an ok arm. The initial resolver pick still prefers measured arms and retains the terminal preference among checked unknowns; fallback walks the original order. The existing four-attempt bound remains.

The normal Anthropic launcher contains profile selection, conditional on its multiprofile flag or an explicit requested profile; this change does not enable that flag or add an unconditional launchability probe. Its decision is that an unreadable quota measurement does not itself refuse a normal launch after the other admission checks. Actual launcher refusal still advances the pool. GLM and Kimi cannot use the new marker. No dispatcher, arbiter, quota reader, launcher, runtime-state, merge, or push change is included.

## Evidence — reproduction and test boundaries

The new suite runs the real resolver CLI and full product-close script in temporary git repositories, with fake quota transport, arbiter output and provider launchers. It disables the unrelated E2E phase for these fixtures; the close script's selfcheck and review loop run. Assertions inspect launcher argv identities, the recorded reviewer/status, exit values, and quota transport call counts. No live reviewer launch or service availability is claimed.

The original three-case regression ran red before the production edits: only glm launched, no reviewer was recorded, status was unreviewed and exit was 9. The suite was subsequently expanded with consumer admission cases and paths reaching all three fallback arms. The final green transcript covers those additional cases too. An earlier fixture-only mktemp failure was discarded as invalid red evidence.

## Evidence — leadv2-mutation-control.sh

Three unified patches are committed under `mutation-control/`; every changed line is inside a production function body. `author.patch` disables the resolver's author comparison; `glm-quota.patch` replaces the GLM transport call in `_pct_for` with zero; `unknown-refusal.patch` refuses checked unknowns in the consumer predicate. Each is measured with the required tool against the final committed lane. The generated `.txt` artifacts contain baseline_rc, mutated_rc, first failing value assertion, mutation diff hash and lane diff hash. They are committed after the report so the lane hash remains valid (the tool excludes `**/mutation-control/**`).

Commands (each bounded to 240 seconds, with TMPDIR=/private/tmp):

```bash
bash plugins/leadv2/scripts/leadv2-mutation-control.sh plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py docs/handoff/REVIEW-POOL-UNKNOWN-IS-NOT-UNAVAILABLE/mutation-control/author.patch docs/handoff/REVIEW-POOL-UNKNOWN-IS-NOT-UNAVAILABLE
bash plugins/leadv2/scripts/leadv2-mutation-control.sh plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py docs/handoff/REVIEW-POOL-UNKNOWN-IS-NOT-UNAVAILABLE/mutation-control/glm-quota.patch docs/handoff/REVIEW-POOL-UNKNOWN-IS-NOT-UNAVAILABLE
bash plugins/leadv2/scripts/leadv2-mutation-control.sh plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh plugins/leadv2/scripts/leadv2-dispatch-product-close.sh docs/handoff/REVIEW-POOL-UNKNOWN-IS-NOT-UNAVAILABLE/mutation-control/unknown-refusal.patch docs/handoff/REVIEW-POOL-UNKNOWN-IS-NOT-UNAVAILABLE
```

Raw tool output is committed as `mutation-control/author-output.txt`, `mutation-control/glm-quota-output.txt` and `mutation-control/unknown-refusal-output.txt`; full structured run artifacts are adjacent. Each control must show a green baseline and a red mutant. The author mutant grades reviewer identity; the GLM mutant grades quota-call count; the refusal mutant grades admission return value and the real close-gate fallback identities.

## Evidence — changed-scope selection

Both selection proof and execution moved `$GIT_DIR/leadv2-run-all-last-checked-sha` aside if present and restored it afterward (or removed the newly created checkpoint if none existed). The range was merge-base `7351b1769e85752ebff287ddeb7f802c2353b000` through the lane HEAD, plus dirty files. Selection was recorded at `1a9ef672`; the initial-pick compatibility follow-up is `6feaa1d6` and touches the same resolver stem. The suite declares `# run-all-triggers: leadv2-dispatch-product-close leadv2-glm-policy-resolve`. Selection returned 54 suites including this suite. Execution began at `1a9ef672`; the compatibility follow-up landed while the core runner was active, so this is not a clean final-HEAD E2E proof. The final focused suite and controls separately exercise the committed final code.

## Evidence — timeout 25 bash leadv2-quota-live.sh anthropic

```text
{"provider": "anthropic", "status": "ok", "accounts": [{"entry_suffix": "default", "service": "Claude Code-credentials", "subscription_type": "max", "tier": "default_claude_max_20x", "http": 401, "account_label": "max_20x", "active": true, "status": "unknown", "account_state": "unknown", "error": "http 401", "five_hour": {"pct": null, "reset_iso": null, "remaining_pct": null, "hours_to_reset": null, "usable_now": null}, "seven_day": {"pct": null, "reset_iso": null, "remaining_pct": null, "hours_to_reset": null, "usable_now": null}, "binding_window": null}, {"entry_suffix": "5a3c2328", "service": "Claude Code-credentials-5a3c2328", "subscription_type": "team", "tier": "default_claude_max_5x", "http": 200, "account_label": "max_5x", "active": false, "status": "ok", "account_state": "ok", "five_hour_pct": 96.0, "five_hour_reset_iso": "2026-09-08T14:59:59.686927+00:00", "seven_day_pct": 38.0, "seven_day_reset_iso": "2026-09-08T18:59:59.686947+00:00", "five_hour": {"pct": 96.0, "reset_iso": "2026-09-08T14:59:59.686927+00:00", "remaining_pct": 4.0, "hours_to_reset": 2.4187861944444444, "usable_now": 1.6537220235452579}, "seven_day": {"pct": 38.0, "reset_iso": "2026-09-08T18:59:59.686947+00:00", "remaining_pct": 62.0, "hours_to_reset": 6.418786171111112, "usable_now": 9.659147126452353}, "binding_window": "five_hour", "limits": [{"kind": "session", "group": "session", "percent": 96, "severity": "critical", "resets_at": "2026-09-08T14:59:59.686927+00:00", "scope": null, "is_active": true}, {"kind": "weekly_all", "group": "weekly", "percent": 38, "severity": "normal", "resets_at": "2026-09-08T18:59:59.686947+00:00", "scope": null, "is_active": false}, {"kind": "weekly_scoped", "group": "weekly", "percent": 24, "severity": "normal", "resets_at": "2026-09-08T18:59:59.687142+00:00", "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}]}, {"entry_suffix": "eb6c5b97", "service": "Claude Code-credentials-eb6c5b97", "subscription_type": "max", "tier": "default_claude_max_20x", "http": 200, "account_label": "max_20x", "active": false, "status": "ok", "account_state": "ok", "five_hour_pct": 10.0, "five_hour_reset_iso": "2026-09-08T13:20:00.014558+00:00", "seven_day_pct": 54.0, "seven_day_reset_iso": "2026-09-11T22:00:00.014581+00:00", "five_hour": {"pct": 10.0, "reset_iso": "2026-09-08T13:20:00.014558+00:00", "remaining_pct": 90.0, "hours_to_reset": 0.7522105044444445, "usable_now": 90.0}, "seven_day": {"pct": 54.0, "reset_iso": "2026-09-11T22:00:00.014581+00:00", "remaining_pct": 46.0, "hours_to_reset": 81.41887717694445, "usable_now": 0.5649795427665996}, "binding_window": "seven_day", "limits": [{"kind": "session", "group": "session", "percent": 10, "severity": "normal", "resets_at": "2026-09-08T13:20:00.014558+00:00", "scope": null, "is_active": false}, {"kind": "weekly_all", "group": "weekly", "percent": 54, "severity": "normal", "resets_at": "2026-09-11T22:00:00.014581+00:00", "scope": null, "is_active": true}, {"kind": "weekly_scoped", "group": "weekly", "percent": 9, "severity": "normal", "resets_at": "2026-09-11T22:00:00.014823+00:00", "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}]}], "active_account": "max_20x", "account_resolution": "session_credential", "account_resolution_journal": "account=session_credential", "binding_window": null, "fetched_at": "2026-09-08T12:34:47Z"}

```

## Evidence — bash -n and python3 -m py_compile

```text
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
rc=0
$ bash -n plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh
rc=0
$ python3 -m py_compile plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py
rc=0

```

## Evidence — test-review-pool-unknown-is-not-unavailable.sh RED before fix

```text
PASS: GLM selected after quota check: actual='glm' expected='glm'
PASS: GLM quota calls before selection: actual=1 expected=1
PASS: resolver excludes author codex: actual='fable' expected='fable'
PASS: resolver excludes author glm: actual='fable' expected='fable'
PASS: resolver excludes author fable: actual='opus' expected='opus'
PASS: resolver excludes author opus: actual='fable' expected='fable'
PASS: resolver excludes author sonnet: actual='fable' expected='fable'
PASS: known hot pool has no reviewer: actual='' expected=''
PASS: locked unknown pool has no reviewer: actual='' expected=''
FAIL: close codex launcher identities: actual=['glm'] expected=['glm', 'fable']
FAIL: close codex reviewer identity: actual=None expected='fable'
FAIL: close codex gate status: actual='unreviewed' expected='pass'
FAIL: close codex exit: actual=9 expected=0
PASS: close codex GLM quota checked: actual=True expected=True
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=unknown01 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=unknown01 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=unknown01 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=unknown01 status=green checks=4 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=unknown01 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=unknown01 source=tenant
[leadv2-dispatch-product-close] review_signals task=unknown01 protected_path=1 source=no_patterns_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=unknown01 reason=cheapest_capable 
[leadv2-dispatch-product-close] review_pool_resolve task=unknown01 rc=0 reviewer=glm pool_n=6
[leadv2-dispatch-product-close] review_gate task=unknown01 status=arm_refused arm=glm reason=refused_quota
[leadv2-dispatch-product-close] review_gate task=unknown01 status=unreviewed reason=all_arms_unavailable author=codex pool=codex:author:,glm:ok:80,kimi:excluded:safety,fable:unknown:,opus:unknown:,sonnet:unknown: tried=glm refusal=all_arms_unavailable resolver_rc=0

FAIL: close fable launcher identities: actual=['glm'] expected=['glm', 'opus']
FAIL: close fable reviewer identity: actual=None expected='opus'
FAIL: close fable gate status: actual='unreviewed' expected='pass'
FAIL: close fable exit: actual=9 expected=0
PASS: close fable GLM quota checked: actual=True expected=True
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=unknown01 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=unknown01 worker_liveness=unknown author=fable handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=unknown01 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=unknown01 status=green checks=4 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=unknown01 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=unknown01 source=tenant
[leadv2-dispatch-product-close] review_signals task=unknown01 protected_path=1 source=no_patterns_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=unknown01 reason=cheapest_capable 
[leadv2-dispatch-product-close] review_pool_resolve task=unknown01 rc=0 reviewer=glm pool_n=6
[leadv2-dispatch-product-close] codex_dead_reroute task=unknown01 from=codex to=glm codex=codex:blocked:100 pool=codex:blocked:100,glm:ok:80,kimi:excluded:safety,fable:author:,opus:unknown:,sonnet:unknown:
[leadv2-dispatch-product-close] review_gate task=unknown01 status=arm_refused arm=glm reason=refused_quota
[leadv2-dispatch-product-close] review_gate task=unknown01 status=unreviewed reason=all_arms_unavailable author=fable pool=codex:blocked:100,glm:ok:80,kimi:excluded:safety,fable:author:,opus:unknown:,sonnet:unknown: tried=glm refusal=all_arms_unavailable resolver_rc=0

FAIL: close sonnet launcher identities: actual=['glm'] expected=['glm', 'fable']
FAIL: close sonnet reviewer identity: actual=None expected='fable'
FAIL: close sonnet gate status: actual='unreviewed' expected='pass'
FAIL: close sonnet exit: actual=9 expected=0
PASS: close sonnet GLM quota checked: actual=True expected=True
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=unknown01 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=unknown01 worker_liveness=unknown author=sonnet handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=unknown01 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=unknown01 status=green checks=4 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=unknown01 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=unknown01 source=tenant
[leadv2-dispatch-product-close] review_signals task=unknown01 protected_path=1 source=no_patterns_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=unknown01 reason=cheapest_capable 
[leadv2-dispatch-product-close] review_pool_resolve task=unknown01 rc=0 reviewer=glm pool_n=6
[leadv2-dispatch-product-close] codex_dead_reroute task=unknown01 from=codex to=glm codex=codex:blocked:100 pool=codex:blocked:100,glm:ok:80,kimi:excluded:safety,fable:unknown:,opus:unknown:,sonnet:author:
[leadv2-dispatch-product-close] review_gate task=unknown01 status=arm_refused arm=glm reason=refused_quota
[leadv2-dispatch-product-close] review_gate task=unknown01 status=unreviewed reason=all_arms_unavailable author=sonnet pool=codex:blocked:100,glm:ok:80,kimi:excluded:safety,fable:unknown:,opus:unknown:,sonnet:author: tried=glm refusal=all_arms_unavailable resolver_rc=0

RESULT: 12 failures

```

## Evidence — test-review-pool-unknown-is-not-unavailable.sh GREEN after fix

```text
PASS: GLM selected after quota check: actual='glm' expected='glm'
PASS: GLM quota calls before selection: actual=1 expected=1
PASS: resolver excludes author codex: actual='fable' expected='fable'
PASS: resolver excludes author glm: actual='fable' expected='fable'
PASS: resolver excludes author fable: actual='opus' expected='opus'
PASS: resolver excludes author opus: actual='fable' expected='fable'
PASS: resolver excludes author sonnet: actual='fable' expected='fable'
PASS: known hot pool has no reviewer: actual='' expected=''
PASS: locked unknown pool has no reviewer: actual='' expected=''
PASS: consumer glm:unknown:quota_checked author=codex admission rc: actual=1 expected=1
PASS: consumer kimi:unknown:quota_checked author=codex admission rc: actual=1 expected=1
PASS: consumer fable:unknown: author=codex admission rc: actual=1 expected=1
PASS: consumer fable:unknown:quota_checked author=fable admission rc: actual=1 expected=1
PASS: consumer sonnet:ok:10 author=sonnet admission rc: actual=1 expected=1
PASS: consumer fable:unknown:quota_checked author=codex admission rc: actual=0 expected=0
PASS: close codex launcher identities: actual=['glm', 'fable'] expected=['glm', 'fable']
PASS: close codex reviewer identity: actual='fable' expected='fable'
PASS: close codex gate status: actual='pass' expected='pass'
PASS: close codex exit: actual=0 expected=0
PASS: close codex GLM quota checked: actual=True expected=True
PASS: close codex launcher identities: actual=['glm', 'fable', 'opus'] expected=['glm', 'fable', 'opus']
PASS: close codex reviewer identity: actual='opus' expected='opus'
PASS: close codex gate status: actual='pass' expected='pass'
PASS: close codex exit: actual=0 expected=0
PASS: close codex GLM quota checked: actual=True expected=True
PASS: close codex launcher identities: actual=['glm', 'fable', 'opus', 'sonnet'] expected=['glm', 'fable', 'opus', 'sonnet']
PASS: close codex reviewer identity: actual='sonnet' expected='sonnet'
PASS: close codex gate status: actual='pass' expected='pass'
PASS: close codex exit: actual=0 expected=0
PASS: close codex GLM quota checked: actual=True expected=True
PASS: close fable launcher identities: actual=['glm', 'opus'] expected=['glm', 'opus']
PASS: close fable reviewer identity: actual='opus' expected='opus'
PASS: close fable gate status: actual='pass' expected='pass'
PASS: close fable exit: actual=0 expected=0
PASS: close fable GLM quota checked: actual=True expected=True
PASS: close sonnet launcher identities: actual=['glm', 'fable'] expected=['glm', 'fable']
PASS: close sonnet reviewer identity: actual='fable' expected='fable'
PASS: close sonnet gate status: actual='pass' expected='pass'
PASS: close sonnet exit: actual=0 expected=0
PASS: close sonnet GLM quota checked: actual=True expected=True
RESULT: 0 failures

```

## Evidence — tests/run-all.sh --scope changed SELECT_ONLY

```text
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/tests/test-status-surface-bash32.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/tests/test-status-surface-single-lead.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/tests/test-status-surface-fast-names.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-arm-advance-real.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-asked-into-void.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-close-gate-nowork-abandoned.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-dispatch-product-close-exit-trap.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-dwr-resume.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-empty-writes-autocommit-loud-skip.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-leadv2-merge-safety-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-no-work-terminal.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-parked-worker-resume.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-plugin-reliability-02.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-plugin-review-arms.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-produced-nothing-cause.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-question-delivery-ownership-01.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-report-only-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-review-arm-no-verdict.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-review-body-persist.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-review-gate-scope-evidence.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-review-pool-empty-rootcause.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-review-pool-never-empty.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-review-silence-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-review-single-owner-census.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-review-verdict-recovery.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-silent-arm-index-and-cross-repo.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-stop-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-worker-ended-on-wait.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-workflow-bypass-guard-lane.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/tests/test-review-arm-pool.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/tests/test-arm-pool-reachability.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-fable-think-tier.sh
run-all: 54 selected, scope=changed, select_only=1
rc=0

```

## Evidence — Standalone environment checks

```text
$ TMPDIR=/private/tmp /usr/bin/mktemp -d
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.nlgiq7ZdS7: Operation not permitted
rc=1
$ TMPDIR=/private/tmp ps -p 2227 -o pid=
[Errno 1] Operation not permitted: 'ps'

```

## Evidence — tests/run-all.sh registered triggers

```text
leadv2-dispatch-product-close:plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh
leadv2-glm-policy-resolve:plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh

```

## Evidence — tests/run-all.sh --scope changed execution

Command: `TMPDIR=/private/tmp timeout 600 bash tests/run-all.sh --scope changed`. The wrapper recorded the child exit status below. This run timed out inside the core runner; it did not complete all 54 selected suites.

```text
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh

changed_scope_rc=124

```

Core shard snapshots taken before timeout preserve output the outer runner had not yet streamed. These are partial logs, not completed-suite totals. They show both actual sandbox errors and the new suite passing inside the core run; they do not establish that every other failure is unrelated to this diff. Full snapshots are committed alongside this report.

### Evidence — core-shard-0.log.txt (raw tail)

```text
: actual='fable' expected='fable'
PASS: resolver excludes author sonnet: actual='fable' expected='fable'
PASS: known hot pool has no reviewer: actual='' expected=''
PASS: locked unknown pool has no reviewer: actual='' expected=''
PASS: consumer glm:unknown:quota_checked author=codex admission rc: actual=1 expected=1
PASS: consumer kimi:unknown:quota_checked author=codex admission rc: actual=1 expected=1
PASS: consumer fable:unknown: author=codex admission rc: actual=1 expected=1
PASS: consumer fable:unknown:quota_checked author=fable admission rc: actual=1 expected=1
PASS: consumer sonnet:ok:10 author=sonnet admission rc: actual=1 expected=1
PASS: consumer fable:unknown:quota_checked author=codex admission rc: actual=0 expected=0
PASS: close codex launcher identities: actual=['glm', 'fable'] expected=['glm', 'fable']
PASS: close codex reviewer identity: actual='fable' expected='fable'
PASS: close codex gate status: actual='pass' expected='pass'
PASS: close codex exit: actual=0 expected=0
PASS: close codex GLM quota checked: actual=True expected=True
PASS: close codex launcher identities: actual=['glm', 'fable', 'opus'] expected=['glm', 'fable', 'opus']
PASS: close codex reviewer identity: actual='opus' expected='opus'
PASS: close codex gate status: actual='pass' expected='pass'
PASS: close codex exit: actual=0 expected=0
PASS: close codex GLM quota checked: actual=True expected=True
PASS: close codex launcher identities: actual=['glm', 'fable', 'opus', 'sonnet'] expected=['glm', 'fable', 'opus', 'sonnet']
PASS: close codex reviewer identity: actual='sonnet' expected='sonnet'
PASS: close codex gate status: actual='pass' expected='pass'
PASS: close codex exit: actual=0 expected=0
PASS: close codex GLM quota checked: actual=True expected=True
PASS: close fable launcher identities: actual=['glm', 'opus'] expected=['glm', 'opus']
PASS: close fable reviewer identity: actual='opus' expected='opus'
PASS: close fable gate status: actual='pass' expected='pass'
PASS: close fable exit: actual=0 expected=0
PASS: close fable GLM quota checked: actual=True expected=True
PASS: close sonnet launcher identities: actual=['glm', 'fable'] expected=['glm', 'fable']
PASS: close sonnet reviewer identity: actual='fable' expected='fable'
PASS: close sonnet gate status: actual='pass' expected='pass'
PASS: close sonnet exit: actual=0 expected=0
PASS: close sonnet GLM quota checked: actual=True expected=True
RESULT: 0 failures
[CORE-OFFLINE] SHARD_RESULT idx=0 pass=7 fail=6 missing=0

```

### Evidence — core-shard-1.log.txt (raw tail)

```text
.js: No such file or directory
FAIL: leadv2-learn.js JS channel (unresolved 'fable' pin + killing yaml -> opus) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='opus' agent_calls=1)
cat: /leadv2-learn-think-block.js: No such file or directory
FAIL: leadv2-learn.js JS channel (yaml allows -> fable (router round-trip, not a hardcoded default)) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='fable' agent_calls=1)
cat: /leadv2-learn-think-block.js: No such file or directory
FAIL: leadv2-learn.js JS channel (explicit a.model override wins outright, agent() never called) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='sonnet' agent_calls=0)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 727: /leadv2-po-feedback-loop-think-block.js: Operation not permitted
cat: /leadv2-po-feedback-loop-think-block.js: No such file or directory
FAIL: leadv2-po-feedback-loop.js JS channel (unresolved 'fable' pin + killing yaml -> opus) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='opus' agent_calls=1)
cat: /leadv2-po-feedback-loop-think-block.js: No such file or directory
FAIL: leadv2-po-feedback-loop.js JS channel (yaml allows -> fable (router round-trip, not a hardcoded default)) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='fable' agent_calls=1)
cat: /leadv2-po-feedback-loop-think-block.js: No such file or directory
FAIL: leadv2-po-feedback-loop.js JS channel (explicit a.model override wins outright, agent() never called) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='sonnet' agent_calls=0)
mkdir: /noyaml: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 758: /noyaml/yaml.py: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 759: /cap-available.yaml: Operation not permitted
PASS: resolver fails CLOSED when PyYAML missing: fable available -> opus (via unavailable:true degradation)
PASS: resolver stays CLOSED when PyYAML missing + fable unavailable -> opus
PASS=39 FAIL=19
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-fable-think-tier.sh (scope-selected ad-hoc)
[CORE-OFFLINE] SHARD_RESULT idx=1 pass=1 fail=10 missing=0

```

### Evidence — core-shard-2.log.txt (raw tail)

```text

[TEST] PASS: Case F: no silent_probe_base_unresolved line for a provably-zero lane
[TEST] PASS: Case G: linked worktree that committed is NOT classified arm_produced_nothing
[TEST] PASS: Case G: degradation line emitted (unresolved) OR a resolved non-zero count logged

[TEST] 15 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-asked-into-void.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.FqkzfPy3j8: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-asked-into-void.sh: line 39: /result.md: Operation not permitted
[TEST] FAIL: trailing '?' should be detected
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-asked-into-void.sh: line 41: /result.md: Operation not permitted
[TEST] PASS: normal result not flagged
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-asked-into-void.sh: line 43: /result.md: Operation not permitted
[TEST] FAIL: fullwidth '？' should be detected
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-asked-into-void.sh: line 45: /result.md: Operation not permitted
[TEST] PASS: empty result not flagged
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.MAz5Arf5uh: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-asked-into-void.sh: line 60: /resolver.py: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-asked-into-void.sh: line 63: /codex.sh: Operation not permitted
chmod: /codex.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-asked-into-void.sh: line 68: /journal.sh: Operation not permitted
chmod: /journal.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/scripts/tests/test-asked-into-void.sh: line 70: /ledger.sh: Operation not permitted
chmod: /ledger.sh: No such file or directory
mkdir: /cache: Operation not permitted
touch: /cache/kimi-runs/h-empt/.asked_into_void: No such file or directory

```

### Evidence — core-shard-3.log.txt (raw tail)

```text
(got reviewer=opus pool=codex:unknown:,glm:unknown:,kimi:unknown:,fable:unknown:quota_checked,opus:unknown:quota_checked,sonnet:author:)
PASS: (k4) safety_touched -> kimi:excluded:safety
FAIL: (k5) review_arm_order absent -> default order includes kimi (got reviewer=opus pool=codex:unknown:,glm:unknown:,kimi:unknown:,fable:unknown:quota_checked,opus:unknown:quota_checked,sonnet:author:)
PASS: (k6) kimi-bin nonexistent -> kimi:unknown:, not selected (later arm exists)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/tests/test-review-arm-pool.sh: line 323: /routing-signals.yaml: Operation not permitted
PASS: (s0) leadv2-review-signals.sh lib present
mktemp: mkstemp failed on /sig.8cD5XB: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/tests/test-review-arm-pool.sh: line 317: : No such file or directory
sed: : No such file or directory
sed: : No such file or directory
FAIL: (s1) protected-path diff -> kimi:excluded:safety (json= src= matched= reviewer=opus pool=codex:unknown:,glm:unknown:,kimi:unknown:,fable:unknown:quota_checked,opus:unknown:quota_checked,sonnet:author:)
mktemp: mkstemp failed on /sig.48eQ1M: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/tests/test-review-arm-pool.sh: line 317: : No such file or directory
sed: : No such file or directory
sed: : No such file or directory
FAIL: (s2) ordinary path -> kimi:ok: (json= src= pool=codex:unknown:,glm:unknown:,kimi:unknown:,fable:unknown:quota_checked,opus:unknown:quota_checked,sonnet:author:)
mktemp: mkstemp failed on /sig.9rIDcz: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/tests/test-review-arm-pool.sh: line 317: : No such file or directory
sed: : No such file or directory
sed: : No such file or directory
FAIL: (s3) no patterns -> fail-closed (json= src=)
mktemp: mkstemp failed on /sig.kN3lHQ: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/plugins/leadv2/tests/test-review-arm-pool.sh: line 317: : No such file or directory
sed: : No such file or directory
sed: : No such file or directory
FAIL: (s4) empty lane writes -> fail-closed (json= src=)

10 passed, 11 failed
[CORE-OFFLINE] FAILED: plugins/leadv2/tests/test-review-arm-pool.sh (scope-selected ad-hoc)
[CORE-OFFLINE] SHARD_RESULT idx=3 pass=2 fail=9 missing=0

```

## Closure

Production fix, suite, report and evidence are committed on the lane branch. No merge or push was performed; delivery to main remains the lead's action. The focused suite and syntax checks are green. Required value-based mutation measurements are recorded in the adjacent tool-generated artifacts.

BLOCKED: changed-scope verification has no green completion: the 600-second run exited 124 after sandbox-denied mktemp/process operations in existing suites. The final-HEAD full gate must be rerun in a permitted environment before closure.
