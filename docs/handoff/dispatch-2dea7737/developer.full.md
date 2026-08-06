verdict: APPROVE
next_action: deploy

# dispatch-2dea7737 — plugin follow-ups round 1b — verification report

Lane `a24b1588`, inherited HEAD `5e69c0b` + `80c5a80` (item-1 hardening already committed by a
prior worker instance before it died). This session verified the inherited code, finished items
2 and 3 (verification only — no code change was needed), and produced the fail-then-pass /
negative-control evidence the mission required. Final HEAD after this session's 2 commits:
`9541c16` (see §6 for full commit list).

## 0. Baseline integrity (§0.2, blocking precondition)

```
$ git worktree add --detach /tmp/a24b1588-base-a1afed9 a1afed9
$ git -C /tmp/a24b1588-base-a1afed9 status --porcelain
(empty)
$ md5 -q /tmp/a24b1588-base-a1afed9/plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py
50121495cce1c3fb653d236ec4510310
```
Matches the mandated md5. NOT BLOCKED. `.claude/worktrees/baseline-check` was never used (per
§0.2's warning that it is poisoned).

## 1. Item 1 — router_v2 dispatchable filter (kept as-is, re-proved)

Already implemented and committed at `5e69c0b` + `80c5a80` by a prior worker instance in this same
round; this session re-verified rather than re-implementing (per the architect design, "keep
5e69c0b, add the missing evidence").

Fail-then-pass, `test-router-v2-retired-arm.sh`, clean `a1afed9` baseline vs lane HEAD:
```
=== BASELINE (a1afed9 source) ===
FAIL: T1: kimi survives into v2 candidate_chain -- output=...
FAIL: T2: candidate_chain does not contain normalized "sonnet" -- chain='claude-sonnet,claude-haiku' ...
  router-v2-retired-arm suite: FAIL=1
rc=1

=== LANE HEAD ===
PASS: T1: retired arm kimi dropped from v2 chain (router=v2), no collapse (rc=0)
PASS: T2: claude-sonnet normalizes to sonnet and survives the filter (chain='sonnet')
PASS: poison fence held -- no real provider bin invoked across T1/T2
  router-v2-retired-arm suite: FAIL=0
rc=0
```

`test-arm-ladder-vocabulary-drift.sh` (case6/case7, the fail-open-fallback hardening) at HEAD:
```
PASS: case7: forced importlib-read failure journals dispatchable_arms_read_failed and returns
fallback (glm codex sonnet) ⊆ DISPATCHABLE_BUILD_ARMS, kimi absent
  arm-ladder vocabulary-drift suite: PASS=8 FAIL=0
```

Spawn-fence proof:
```
$ grep -c 'POISON:' <full-suite HEAD log>
0
$ grep -nE 'kimi-coder\.sh|glm-coder\.sh|bare codex invocation' <4 changed suites>
Only hits: (a) the poison-fence setup loop itself (`for _arm in glm kimi codex`), (b) a
config-literal string inside a routing.yaml fixture heredoc (`channel: kimi-coder.sh`, never
executed), (c) assertion strings like `worker_spawned by=router model=codex` (grepping journal
output, not invoking a binary). No unfenced executable path.
```

## 2. Item 2 — routing-enforcement-p1 hermeticity (verification only, no code change)

**Sweep.** Every `env -u CLAUDE_PROJECT_ROOT` / `env -u CLAUDE_PROJECT_DIR` invocation in the file:

| test # | uses env -u? | PROJECT_ROOT pinned? | why |
|---|---|---|---|
| 1–4, 7–9 | no | n/a (use `CLAUDE_PROJECT_ROOT=` directly) | explicit var always wins over the fallback chain, cwd-independent by construction |
| 5 (selfhost) | yes | **yes** (`PROJECT_ROOT="${TMP_ROOT}/selfhost-root"`) | already fixed at 5e69c0b |
| 6 (degraded) | yes | **yes** (`PROJECT_ROOT="${TMP_ROOT}/degraded-root"`) | already fixed at 5e69c0b |

Sweep found nothing left to fix — both `env -u` call sites were already pinned by the inherited
code. Documented this in-file (commit `16afb83`) rather than re-doing the fix.

**Cross-cwd demonstration**, lane HEAD, invoked by absolute path, ambient `PROJECT_ROOT` env var
unset per-invocation (my own shell had a stray `PROJECT_ROOT=/Users/.../leadv2` export that would
have masked the bug — unset it explicitly so the test genuinely exercises the git-rev-parse-on-cwd
fallback path; `LEADV2_PROJECT_ROOT`, a *different* var used by an unrelated active-registry
subsystem, was left alone since unsetting it breaks tests 1–4/7–9 for reasons outside item 2's
scope):

```
FIXED cwd=/private/tmp                                                      rc=0 pass=18 fail=0
FIXED cwd=<lane worktree>                                                   rc=0 pass=18 fail=0
FIXED cwd=/Users/kostiantyn.vlasenko/Projects/persona-engine                 rc=0 pass=18 fail=0
```
All three identical.

Same demonstration against the **unfixed a1afed9 source** of this file (extracted via
`git show a1afed9:...`, run inside the clean baseline worktree so `DISPATCH_BIN` is also
unfixed):
```
UNFIXED cwd=/private/tmp                                                    rc=0 pass=18 fail=0
UNFIXED cwd=/Users/kostiantyn.vlasenko/Projects/persona-engine               rc=1 pass=17 fail=1
FAIL: degraded mode announcement -- rc=0 output=... dispatch_classified ... reason=explicit_mission_fast_path
```
Divergence confirmed: same source, cwd is the only variable, opposite verdict on Test 6 — because
unpinned `PROJECT_ROOT` resolves via `git rev-parse --show-toplevel` on the caller's cwd, and from
persona-engine that finds persona-engine's own `.claude/ref/leadv2-routing.yaml`, so the degraded
path is never exercised.

**Mutation check.** `git -C persona-engine status --porcelain` before and after every cross-cwd run
across this whole session: byte-identical (192 lines, pre-existing unrelated dirty state from other
work, untouched by these runs). Lane worktree: **was mutated** during an earlier probe pass — cwd=
lane-worktree runs with `PROJECT_ROOT` unset resolved via `git rev-parse --show-toplevel` on the
lane's own root and wrote ~15 real `docs/handoff/dispatch-*/` directories plus a stray
`plugins/leadv2/scripts/tests/.claude/scripts/lv2` file directly into the lane. This is exactly the
§0.3 mutation-risk hazard the architect flagged in advance. Cleaned up immediately (`rm -rf` on the
untracked pollution, confirmed via `git status --porcelain` back to only the pre-existing
`docs/leadv2/tasks/`) before any commit. No lane-tracked file was touched — all pollution was
untracked and has been removed; nothing survives in the final commits.

## 3. Item 3 — S7 `rc == 0` (negative-control, no code change)

The `rc == 0` tightening does **not** fail against `a1afed9` — `a1afed9` genuinely returns `rc=0`
for this scenario (the mission itself says so), so a literal fail-against-HEAD run is structurally
impossible for this item. Produced the mandated negative control instead: on the clean `a1afed9`
baseline, `LEADV2_DISPATCH_GLM_BIN` fault-injected to hard-fail (prints a crash line to stderr, no
`PID=.../SESSION_ID=...` handle, `exit 7`) instead of the fixture's normal successful spawn stub.

```
=== OLD assertion (rc != 5), fault-injected launcher ===
[TEST] PASS: S7: dispatch did NOT refuse with rc 5 (got rc=4)
=== Results: 4 passed, 0 failed ===   (suite rc=0)

=== NEW assertion (rc == 0), fault-injected launcher ===
[TEST] FAIL: S7: dispatch did not resume the finalized lane (rc=4, expected 0)
=== Results: 3 passed, 1 failed ===   (suite rc=1)
```
Real dispatch rc is 4 (`dispatch_rolled_back reason=all_arms_unavailable...glm_failed_launcher`) —
same source, same injected fault, opposite verdict between old and new assertions. This is a
**labelled negative-control demonstration**, not a fail-against-HEAD run (documented as such
in-file, commit `9541c16`, to prevent future re-framing as the latter).

## 4. Full-suite counts (all 128 suites under plugins/leadv2/scripts/tests/, lane HEAD vs clean a1afed9)

Only non-identical-outcome rows shown (full 128-row table in
`/tmp/lv2-r1b-evidence/counts-table-full2.txt`, not committed — ephemeral evidence):

| suite | HEAD | baseline | classification |
|---|---|---|---|
| test-arm-ladder-vocabulary-drift.sh | pass | fail | fixed-by-this-lane |
| test-router-v2-retired-arm.sh | pass | fail | fixed-by-this-lane |
| test-review-silence-gate.sh | fail (in the concurrent double-run) | pass | **flake, not a regression** — see below |

All other 125 suites: identical outcome at HEAD and baseline (93/125 pass, 32/125 fail, both
sides — same failures, same rcs, including three suites hitting the 60s per-suite timeout,
`rc=124`, on both sides identically). None of those failures were introduced or fixed by this lane;
they are pre-existing and out of this lane's scope.

**`test-review-silence-gate.sh` flake, resolved:** it failed once, in the run where HEAD's 128-suite
sweep and baseline's 128-suite sweep were executing concurrently on the same machine (CPU
contention). Test 6 of that suite (`crash_backstop`, SIGTERM mid-review, exit-trap timing-sensitive)
lost the race. Re-ran it 3× in isolation at HEAD immediately after: **15 passed, 0 failed, all 3
times.** Reclassified from `regressed-by-this-lane` to **flake** — no `regressed-by-this-lane` row
survives.

Total: HEAD 94 pass / 34 fail across 128 suites; baseline 93 pass / 35 fail across 128 suites
(the ±1 delta on each side is exactly the two `fixed-by-this-lane` suites plus the one flake).

## 5. C2 — `test-lane-liveness-authoritative.sh` ("live PID, no artifact")

Ran on the clean `a1afed9` baseline directly (not inferred from the earlier corrupted
`baseline-check` probe, per the architect's explicit instruction to re-verify myself):
```
$ bash test-lane-liveness-authoritative.sh   # inside /tmp/a24b1588-base-a1afed9
[TEST] FAIL: C2: live PID with no artifact floors to silent, not dead
rc=1
```
Identical failure at lane HEAD. **C2 fails identically on `a1afed9` — it is pre-existing, not
introduced by this lane.**

Does it warrant its own task? **Yes.** A live PID with no discoverable artifact resolving to
`dead:no_handoff_dir` instead of `silent:` means a genuinely-running-but-quiet lane can be
misclassified as dead by the same liveness probe this whole round-1b effort exists to harden — the
exact failure mode ("confidently wrong about work it never looked at") the repo's own operating
brief calls out. It is orthogonal to all three items in this mission (routing/dispatch, not
liveness classification) and touches `leadv2-lane-liveness.sh`, a file explicitly out of this
lane's `LANE_WRITES`. Not fixed here per the non-goals list (§1.1 of the design).

## 6. Commits on this branch (on top of inherited `5e69c0b`)

```
5e69c0b wip(plugin-followups): all three items touched; worker died before reporting   [inherited]
80c5a80 test(arm-ladder): case6/case7 pin fail-open fallback ... [inherited, prior worker]
b62299d wip(plugin-followups): round 1b partial — worker died again   [inherited, then reverted]
9f0a333 Revert "wip(plugin-followups): round 1b partial — worker died again"   [inherited]
16afb83 verify(routing-enforcement-p1): item2 sweep + cross-cwd divergence proof   [this session]
9541c16 verify(dispatch-resume-sentinel): item3 S7 negative-control evidence   [this session]
```
`git merge-base --is-ancestor 5e69c0b HEAD` succeeds — branch never moved backwards. This session
contributed 2 new commits (items 2 and 3 required no functional code change, only verification —
the design's own §2.2/§2.3 established that both fixes were already complete and correct; this
session's job was producing the missing evidence, which is now embedded in-file at each commit so
it survives with the code rather than living only in this report).

## 7. What was kept / changed / discarded from the inherited state

- **Kept as-is**: `leadv2-dispatch-code.sh`'s v2-filter wiring, `_dispatchable_arms()`,
  `_normalize_v2_arm()`, the case6/case7 fail-open-fallback pins, the Test 5/6 `PROJECT_ROOT` pins
  in `test-routing-enforcement-p1.sh`, and the S7 `rc == 0` tightening in
  `test-dispatch-resume-sentinel.sh`. All independently re-verified in this session, all correct.
- **Changed**: added evidence comments (not logic) to `test-routing-enforcement-p1.sh` and
  `test-dispatch-resume-sentinel.sh` documenting the verification results in-file.
- **Discarded**: nothing from `5e69c0b`/`80c5a80`. The `b62299d` commit (an earlier dead worker's
  stray output — a `.claude/scripts/lv2` sandbox artifact and duplicate deliverable files) was
  already reverted by `9f0a333` before this session started; left as-is.
- **Cleaned up mid-session**: ~15 stray `docs/handoff/dispatch-*/` directories and a
  `plugins/leadv2/scripts/tests/.claude/` tree that this session's own cwd-demo runs accidentally
  wrote into the lane worktree (the exact §0.3 mutation hazard the architect predicted). Removed
  before any commit; confirmed via `git status --porcelain`.

## 8. Non-goals honored

Did not touch `leadv2-router-v2.sh` / `leadv2-task-judge.sh` / `leadv2-route-bandit.sh`, did not
enable `LEADV2_ROUTER_V2` by default, did not fix C2, did not de-duplicate `.claude/scripts/tests/`,
did not rebase or move the branch backwards, introduced no new env vars.

DELIVERABLE_COMPLETE
