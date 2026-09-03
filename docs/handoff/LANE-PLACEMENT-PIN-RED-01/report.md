# LANE-PLACEMENT-PIN-RED-01 report

Continuing from `b794a736` (rescued, uncommitted, unreviewed worker diff). That diff is verified
correct below and is now the committed fix; nothing in it was altered.

## Cause status

| Cause | Status | Mechanism |
| --- | --- | --- |
| (1) pre-existing P-h(a,b,g,g2) reds (real, before the freepool merge, arm=glm) | Fixed in `b794a736`, verified this round | `_spawn_worker_body` (`leadv2-dispatch-code.sh` ~5250-5280) builds `mission` by prepending twice: the code-intel preamble block, then `WORKTREE_PIN_LINE`. Prepending is LIFO — whichever runs **last** ends up first in the string. The pre-fix code ran the `WORKTREE_PIN_LINE` prepend first and the code-intel block after, so whenever `worker_mcp_preamble_for_arm()` returned non-empty text (arm=glm, MCP attach resolves — see `leadv2-worker-mcp.sh:227-236`, the default branch calls `resolve_role_mcp_config()` and can succeed even in the test sandbox since the preamble file is a real file under the plugin tree, not sandboxed), that text landed on top and demoted the pin line — breaking the `head -1` invariant `test-lane-placement-pin.sh`'s P-h cases assert. The fix reorders the two prepends so the code-intel block runs first and the pin line is prepended last, unconditionally landing first. |
| (2) nine new reds since the freepool merge (`2062dbcf`) — `dispatch exited 3/4`, `worker cwd=''` | **Fixture gap, not a production bug.** Fixed in `b794a736`, verified this round | `FREEPOOL-MUST-ACTUALLY-GET-WORK-01` changed the default: an unknown/undeclared write-set (every P-a/P-b/P-g/D3 case in this suite — none declares `--writes`) now fails CLOSED to `protected=1`, and `resolve_arm()`/`_select_base_arm()` route a protected task to the cheapest TRUSTED-capable arm — `sonnet`, not `glm`, before this merge unprotected dispatch always resolved to glm and the suite never needed a sonnet stub. `claude-subsession.sh` (the real sonnet launcher) is invoked for real in the fixture (no `LEADV2_DISPATCH_SUBSESSION_BIN` stub was set), so `bash "${DC}" ...` tried to exec the real binary in a scratch sandbox repo and failed — `dispatch exited 3` (`arm=opus`, lead-judgment path) or `4` (spawn failed), and since dispatch never wrote a mission file, `worker cwd=''` and the P-h(a/b/g/g2) `head -1` reads also failed on that same missing file — i.e. those 4 of the 13 post-merge reds are a **symptom of cause 2, not cause 1**, on this run. The fix adds `SONNET_STUB` (records cwd + mission file content, backgrounds a real `sleep 100` so the caller's `kill -0` liveness check sees a genuinely live process) and wires it via `LEADV2_DISPATCH_SUBSESSION_BIN` — a real, existing override seam (`leadv2-dispatch-code.sh:4987`), not an invented one. No placement or cwd-pin logic on `main` needed to change; no lane dispatched between `2062dbcf` and this fix ran in the wrong directory — dispatch simply never got far enough to place a worker, for every one of those nine (plus four derivative) failures. |

## Why the two causes look identical at 72546734 but are not the same bug

At `a28b16a2` (pre-merge, arm=glm, dispatch succeeds via `GLM_STUB`), P-h(a,b,g,g2) failed for
the ordering reason above — real bug, independent of the merge. At `72546734` (post-merge,
pre-fix), P-h(a,b,g,g2) ALSO failed, but because dispatch itself failed outright (missing sonnet
stub) before any mission file was ever written — a different mechanism producing the same
assertion shape. Both are real and both needed fixing; negative controls below isolate each.

## Full green — macOS

```
$ bash test-lane-placement-pin.sh; echo "EXITCODE=$?"
[TEST] PASS: P-a: dispatch exited 0
[TEST] PASS: P-a: worker cwd == RESUME-ME-01 worktree
[TEST] PASS: P-h(a): prompt pin line present with --resume-lane
[TEST] PASS: P-b: dispatch exited 0
[TEST] PASS: P-b: worker cwd == RESUME-ME-01 worktree (via --worktree)
[TEST] PASS: P-h(b): prompt pin line present with --worktree
[TEST] PASS: P-c: dispatch exited 5 (placement refused)
[TEST] PASS: P-c: stderr contains REFUSE placement line
[TEST] PASS: P-c: no worker spawned (no cwd recorded)
[TEST] PASS: P-c: no reservation ledger row for this dispatch
[TEST] PASS: P-d: dispatch exited 5 (foreign repo refused)
[TEST] PASS: P-d: stderr contains foreign_repo reason
[TEST] PASS: P-d: no worker spawned
[TEST] PASS: P-e: dispatch exited 5 (live lane refused)
[TEST] PASS: P-e: stderr contains lane_is_live reason
[TEST] PASS: P-e: no worker spawned
[TEST] PASS: P-f: dispatch exited 1 (usage error for both flags)
[TEST] PASS: P-f: no worker spawned
[TEST] PASS: P-g: dispatch exited 0 (no flag, regression)
[TEST] PASS: P-g: worker cwd is a fresh tree, != RESUME-ME-01
[TEST] PASS: P-h(g): prompt pin line present on default ensure-created path
[TEST] PASS: P-h(g2): pin line names the ensure-created worktree path
[TEST] PASS: D3: ensure-created lane receives context.yaml without --worktree
[TEST] PASS: D3: worker mission references the lane-local plan
[TEST] PASS: P-i: dispatch exited 0 (shared-tree fallback)
[TEST] PASS: P-i: no pin line on shared-tree dispatch
[TEST] PASS: contract: leadv2-lane-liveness.sh --json emits a JSON object with verdict/reason/age_s

[LANE-PLACEMENT-01] passed=27 failed=0
EXITCODE=0
```

## Full green — Linux container (ubuntu:24.04, via docker/colima)

```
$ docker run --rm -v "$HOST_REPO":"$HOST_REPO" -w "$HOST_REPO/.../tests" ubuntu:24.04 \
  bash -c 'apt-get update -qq && apt-get install -y -qq git python3 && \
           git config --global --add safe.directory "*" && \
           bash test-lane-placement-pin.sh; echo "EXITCODE=$?"'
...
[LANE-PLACEMENT-01] passed=27 failed=0
EXITCODE=0
```

## Negative controls (one per claimed cause)

**Cause 1 mutation** — reverted the LIFO prepend order in `_spawn_worker_body` back to its
pre-`b794a736` shape (`WORKTREE_PIN_LINE` prepended before the code-intel block).
Full-suite red could **not** be reproduced this way under the *current* routing: post
`FREEPOOL-MUST-ACTUALLY-GET-WORK-01` every dispatch in this suite (none declares `--writes`)
routes to arm=sonnet, and `worker_mcp_preamble_for_arm()` returns empty unconditionally for
`sonnet` (`leadv2-worker-mcp.sh:220-225`, rc=3, "no `--mcp-config` is appended on this path... say
nothing") — so the two prepend orders are behaviourally identical whenever ci_txt is empty, and a
full-suite run of the mutated file still passed 27/0. That is itself informative, not a dodge: it
confirms the ordering bug is currently unreachable through this fixture (it was reachable at
`a28b16a2` only because routing was still arm=glm there). To prove the mechanism directly instead
of asserting it, isolated the exact two-line prepend logic with a synthetic non-empty `_ci_txt`
(standing in for the arm=glm/MCP-attached case):

```
$ bash /tmp/pin-order-mechanism-check.sh
=== BUGGY order (pin prepended BEFORE ci block; pre-b794a736 shape) ===
first line: CODE-INTEL PREAMBLE: call mcp__* tools for this task.
RESULT: pin line DEMOTED (bug reproduced)

=== FIXED order (ci block BEFORE pin prepend; committed b794a736 shape) ===
first line: WORKTREE PIN: all edits go in /some/lane; do NOT cd to the main checkout even if the mission text names it.
RESULT: pin line first (fix confirmed)
```

Reverted the file mutation immediately after (`git diff` empty before proceeding).

**Cause 2 mutation** — commented out `export LEADV2_DISPATCH_SUBSESSION_BIN="${SONNET_STUB}"` in
`setup_env()` (the real fixture gap, restoring the pre-`b794a736` fixture). Full suite:

```
$ bash test-lane-placement-pin.sh
[TEST] FAIL: P-a: dispatch exited 4 (expected 0)
[TEST] FAIL: P-a: worker cwd='' != RESUME='.../RESUME-ME-01'
[TEST] FAIL: P-h(a): prompt pin line MISSING with --resume-lane
[TEST] FAIL: P-b: dispatch exited 4 (expected 0)
[TEST] FAIL: P-b: worker cwd='' != RESUME='.../RESUME-ME-01'
[TEST] FAIL: P-h(b): prompt pin line MISSING with --worktree
[TEST] FAIL: P-g: dispatch exited 4 (expected 0)
[TEST] FAIL: P-g: worker cwd='' == RESUME or empty (regression)
[TEST] FAIL: P-h(g): prompt pin line MISSING on default ensure-created path
[TEST] FAIL: P-h(g2): pin line does NOT name the worktree (expected '')
[TEST] FAIL: D3: ensure-created plan missing (rc=4, cwd='')
[TEST] FAIL: D3: worker mission omitted lane-local plan instruction
[TEST] FAIL: P-i: dispatch exited 4 (expected 0)

[LANE-PLACEMENT-01] passed=14 failed=13
```

`passed=14 failed=13` is an **exact match** to the brief's independently-measured post-merge,
pre-fix number at `72546734` — strong confirmation this mutation reproduces the real fixture gap,
not a fabricated one. Reverted (`export LEADV2_DISPATCH_SUBSESSION_BIN="${SONNET_STUB}"` restored)
and re-ran green: `passed=27 failed=0` (see macOS section above, re-run after revert).

## Self-check

```
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-lane-placement-pin.sh && echo OK
OK
```

No `.py` files changed — `py_compile` N/A.

## known-red-suites.txt

Untouched (`git diff --stat -- tests/known-red-suites.txt` empty; `grep lane-placement
tests/known-red-suites.txt` no match).

## Blind-spot exposure (brief item 6)

`tests/run-all.sh`'s `EXTRA_SUITE_MAP` (the mechanism this suite itself is reached through under
`--scope changed`, mapped from stem `leadv2-dispatch-code`) currently has **198** `<stem>:<suite>`
rows, covering **96** distinct trigger stems and **92** distinct suites reachable only through this
map (not through filename-stem self-select). Of those 92 suites, **43** are mapped from exactly
ONE distinct trigger stem — meaning a change to any file *other than* that one specific name
leaves the suite unexercised under `--scope changed` indefinitely, exactly the blind spot that let
`test-lane-placement-pin.sh` itself sit red for an unknown period before this task. Full list of
the 43 single-trigger suites (includes `test-lane-placement-pin.sh` itself, gated solely on
`leadv2-dispatch-code`):

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

(Method: parsed the `EXTRA_SUITE_MAP` heredoc-style variable in `tests/run-all.sh`, deduped
`<suite, stem>` pairs, counted distinct stems per suite. This is a count/list per the brief — the
fix for widening `--scope changed` coverage is explicitly out of scope here.)

## Left alone

- The freepool merge's write-set protection/routing logic itself — off-limits per the brief, and
  its behavior (routing unprotected dispatch to sonnet) is the correct, wanted change; only the
  test fixture needed to catch up.
- The `--scope changed` narrow-selection mechanism (`EXTRA_SUITE_MAP` / stem self-select) — item 6
  asked for a count, not a fix; widening it is a separate task per the brief.
- `docs/leadv2/*`, `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*` — pre-existing dirty state
  from other concurrent lanes sharing this checkout, confirmed present at session start via `git
  status`, not touched or staged by this lane.
