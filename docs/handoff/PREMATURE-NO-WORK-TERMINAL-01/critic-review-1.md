# PREMATURE-NO-WORK-TERMINAL-01 — independent critic review round 1 (sonnet, 2026-08-03)

Verdict: BLOCK. Findings against the working-tree diff in this worktree.

## CRITICAL 1 — GLM/Kimi stall-revive becomes permanent false-dead
pc_worker_alive glm|kimi case (leadv2-dispatch-product-close.sh:431-449) only knows meta.yaml status running/complete/failed. finalize_meta legitimately writes `revived` and `revive_blocked_by_gate` for the ORIGINAL run_dir (glm-coder.sh:1353,1361; kimi-coder.sh:1414,1422 — GLM-REVIVE-01, designed mechanism). Also the revive shortcut (glm-coder.sh:1319-1370) returns before the normal finalize clears the job-registry entry (glm-coder.sh:1510), so _pc_job_registry_has_handle stays true forever. Net: every stall-revive spins the full 4200s ceiling then writes `dead/timeout` — and per leadv2-dispatch-ledger.sh:11,30-32 `dead` is a WRITE-ONCE terminal: no later attempt can record landed for that sig8, even though the revived run may have finished real work. Worse than the original bug (retryable no_work → permanent dead).
FIX: treat revived/revive_blocked_by_gate as terminal-for-this-handle (return 1), and/or follow meta's revived_to run_id into a fresh wait.

## CRITICAL 2 — lease-expiry sweep still re-dispatches a live task mid-wait
_pc_exit_handler:152 unclaims via leadv2-tasks-lib.sh:476-481; leadv2-queue-sweep.sh:101-138 UNCONDITIONALLY resets claim/status=pending once now>=lease_expires, ignoring live workers/watchers. LANE_TTL (leadv2-tasks-lib.sh:50): action=90m, recovery=60m, intelligence=120m, human-needed=60m. New wait ceiling 4200s=70m > the two 60m TTLs → for those lanes the sweep re-pends and re-dispatches while this watcher is still correctly waiting — the duplicate-dispatch symptom returns through an untouched mechanism.
FIX: refresh/extend the lease inside pc_await_worker_exit's poll loop (preferred), or make the sweep skip tasks with a live close-owner pidfile, or cap the ceiling below the shortest TTL.

## HIGH 3 — codex liveness test stubs a JSON shape the real script never emits
test-no-work-terminal.sh:238-260 stubs bare {"verdict":...}; real leadv2-lane-liveness.sh --job --json (lane-liveness:452-456) always wraps as {"provider":"codex","jobs":[...]} with NO top-level verdict. The production branch jobs[0].get("verdict") is untested. FIX: stub {"jobs":[{"verdict":"alive"}]} / {"jobs":[{"verdict":"dead:provider_completed"}]}. NOTE (LOW 10): --job vocabulary is strictly {running,done,cancelled,failed,unknown} — alive/starting:* only exist in --lane mode; keep the superset but test the real vocabulary.

## HIGH 4 — sonnet natural-completion branch has zero coverage
pc_worker_alive sonnet arm (:410-415) reached only with non-empty numeric HANDLE; no existing or new test drives author=sonnet with a real PID that exits naturally → loop proceeds to scope+classify. Add that case.

## MEDIUM 5 — prod-ledger pollution (confirmed + reproduced; fix here)
test-no-work-terminal.sh:89-93 and :122-126 (cases 1-2) omit LEADV2_DISPATCH_LEDGER_BIN → 22 nw1sig001/nw2sig002 rows in the REAL ~/.claude/leadv2-state/persona-engine/dispatch-ledger.jsonl; test-asked-into-void.sh:77,97 same (14 av rows). FIX: add LEADV2_DISPATCH_LEDGER_BIN="${d}/ledger.sh" to those env prefixes; in test-asked-into-void.sh add the ledger.sh stub creation to its make_stubs plus the env var at both invocations. (Prod-ledger purge of av*/nw*/h5sig* rows is the LEAD's post-merge step, not yours.)

## MEDIUM 6 — codex probe latency eats the wait budget: each poll can cost up to 20s probe + 10s sleep. Account probe time or document that tightened ceilings must include probe overhead.
## MEDIUM 7 — _pc_job_registry_has_handle (:362) hardcodes /tmp/leadv2-job-registry with no override env; every other dependency is test-seamed. Add LEADV2_JOB_REGISTRY_ROOT seam and use it in tests.
## MEDIUM 8 — test-landing-diff-scoping.sh tripwire flagged ~/.claude/leadv2-state/persona-engine changing during run — attribute it in your report (likely finding 5's pollution; verify after stubs land the tripwire goes quiet).
## LOW 9 — python3 heredoc call leaks tracebacks to stderr; add 2>/dev/null (degrade to unknown is already correct).

## ADDITIONAL REQUIREMENT (lead, same file, second false-empty shape — FALSE-EMPTY-SHAPE-2-COMMITTED-WORK-01)
Live evidence today: M-6 worktree cffc2f86 held COMMIT 355fc9c (+318 lines) ahead of origin/main while pc_scope_diff saw a clean working tree → 3× no_work/empty_diff terminals + re-dispatches of finished work. FIX: pc_scope_diff must measure committed-ahead work too — diff = (merge-base with the lane's recorded base or origin/main)...HEAD plus uncommitted working-tree changes. Empty only when BOTH are empty. Add a test: stub worker commits its change then exits → terminal reflects the committed diff, not empty.

Ruled out (do not touch): nullglob concern; rollback byte-equivalence (holds); legacy-path stale handles (none found); pre-existing failures of test-dispatch-product-close-exit-trap (2), test-e2e-foreign-failure (7), test-lane-writes-scoping L12 — all reproduce on baseline, not yours. run-core-offline: 22/22 with your suite registered.
