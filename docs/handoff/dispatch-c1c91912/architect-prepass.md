# architect prepass — V3-GLM-LADDER-01 ROUND 3 FINISHER (lane eb2d7143)

Scope: **finish** the r2 lane, do not redo it. Lane branch `worktree-eb2d7143` @ `389820a`
(on top of canonical `b9959aa`), worktree at
`~/Projects/leadv2/.claude/worktrees/eb2d7143`, 23 tracked files dirty of which exactly
**4 are lane-owned code/test files**:

```
 M .gitignore
 M plugins/leadv2/scripts/leadv2-broad-status.sh                  (  5 +/-)
 M plugins/leadv2/scripts/leadv2-dispatch-code.sh                 (201 +/-)
 M plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh       (252 +/-)
```
(probe: `cd .claude/worktrees/eb2d7143 && git status --short` + `git diff --stat`, 2026-08-20)

Everything else dirty in that worktree is leadv2 runtime state (`docs/leadv2/bus.jsonl`,
`active.yaml`, `.bus-offsets`, `*.lock`, `docs/handoff/**`) — **not lane output, must not be
staged**. This is itself a landing risk (R4 below).

---

## 1. Correction to the mission's RED-1 premise — read before debugging

The mission asks: *"why do fixture missions now classify `explicit_mission_fast_path`
kind=unknown → rc=4"*. That framing is wrong and will burn the implementer's budget.

`classify_product_work()` (`plugins/leadv2/scripts/leadv2-dispatch-code.sh:1940-1951`) fast-paths
any mission whose text starts with `plugin-only`. Every RED-1 fixture invocation passes exactly
such a string:

```
:287  bash "${DISPATCH_WRAPPER}" 'plugin-only quota refusal advances chain'
:339  bash "${DISPATCH_WRAPPER}" 'plugin-only codex dead-arm no-first-byte spills chain'
:521  bash "${DISPATCH_WRAPPER}" 'plugin-only lockout skips glm'
```
(probe: `sed -n '270,300p;325,365p;505,525p' plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh`)

So `dispatch_classified class=non_product reason=explicit_mission_fast_path kind=unknown` is the
**designed and correct** line for these fixtures. It appears in the FAIL text only because
`fail()` dumps the whole captured output. It is not the defect and it did not change in `210a439`.

**The actual signal is `rc=4`.** In `leadv2-dispatch-code.sh` rc=4 on the router path means the
arm ladder ended with nothing dispatched — `:3829` `dispatch_rolled_back reason=all_arms_exhausted
… exit 4`, plus the sibling `exit 4` sites at `:3839 :3895 :3926 :3943 :3971`. All three failing
cases expect a *successful* arm (`worker_spawned … model=codex`, `spawn_failed … model=sonnet`).
**Diagnosis target: why are the arms benched/exhausted, not why the mission classified.**

---

## 2. Root-cause hypotheses for RED-1, ranked, each with its discriminating probe

The implementer must reach a **per-case verdict** (main-regression | lane | suite-leak) with a raw
probe. Do not accept one verdict for all three cases — lead already verified the "quota lockout
write side" case is red on canonical `b9959aa` too, so at minimum the set is mixed.

**H-A (highest prior) — `DISPATCH_LEDGER_DIR` is inherited-overridable, so per-case cache
sandboxing can be silently bypassed.**
`:398  DISPATCH_LEDGER_DIR="${DISPATCH_LEDGER_DIR:-${CACHE_BASE}/dispatch-ledger}"` — the `:-`
honours an already-exported value from the parent environment. The suite sandboxes
`LEADV2_DISPATCH_CACHE_DIR` per case (`:282 :304 :333 :356 :376 :411 :484 :514`) but never clears
`DISPATCH_LEDGER_DIR`. `QUOTA_LOCKOUT_DIR` then inherits it (`:1057
QUOTA_LOCKOUT_DIR="${LEADV2_QUOTA_LOCKOUT_DIR:-${DISPATCH_LEDGER_DIR}}"`), so one stale exported
value benches glm/codex for every case in the run and across runs — exactly the reported
nondeterminism (lockout records carry a TTL, so the same run flips verdict as the clock moves).
Probe: `DISPATCH_LEDGER_DIR=/tmp/poison bash plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh`
vs `env -u DISPATCH_LEDGER_DIR …`; and `grep -rn 'export DISPATCH_LEDGER_DIR' plugins/leadv2/scripts/`.
Verdict if confirmed: **main-regression + suite-leak** (fix both sides — see §3.1).

**H-B — the lane's park writer escapes the sandbox via `LEDGER_REPO_ROOT`.**
Lane code writes park state through `PROJECT_ROOT="${LEDGER_REPO_ROOT}"` (`:732`) and resolves the
queue at `:705 _leadv2_glm_deferred_path() { printf '%s/docs/leadv2/glm-deferred.jsonl' "${PROJECT_ROOT}"; }`
/ `:708` for the mission copy. `LEDGER_REPO_ROOT` is derived at `:284` from `git rev-parse
--git-common-dir` of `WORK_ROOT`, **not** from `CLAUDE_PROJECT_ROOT`. If a fixture root is not a
git repo the `:285` fallback saves it; if it is (or if cwd leaks), park rows and
`glm-deferred.d/<sig8>.md` land in the **real canonical repo** and persist across runs.
Probe: run one RED-1 case, then `git -C ~/Projects/leadv2 status --short docs/leadv2/glm-deferred*`
and `ls docs/leadv2/glm-deferred.d/`. Any file there = confirmed **lane** leak.
Verdict if confirmed: **lane** — sandbox the park path on `PROJECT_ROOT`, not `LEDGER_REPO_ROOT`,
or gate it behind the same cache-dir env the ledger uses.

**H-C — C1's park/count-on-`quota_precheck_skip` change benches an arm it used to advance.**
r2's C1 fix adds park+count when glm is skipped as `provider_quota_locked`. If that path also
removes glm from `candidate_arms` earlier than before, or returns non-zero into the ladder, the
"quota lockout write side" case ends `all_arms_exhausted`. Probe: `git diff 389820a --
plugins/leadv2/scripts/leadv2-dispatch-code.sh` around the `quota_precheck_skip` block, then run
that single case with `bash -x`. Verdict if confirmed: **lane**.

**H-D — real cross-case leak inside one run.** Cases at `:282 :304 :333 :356` set
`CLAUDE_PROJECT_ROOT` + `LEADV2_DISPATCH_CACHE_DIR` but **not** `LEADV2_QUOTA_LOCKOUT_DIR`; only
the lockout case at `:515` sets it. Any lockout written by an earlier refusal case is visible to
later ones through the shared default. Probe: after the refusal case, `find "${TMP_ROOT}" -name
'quota-lockout-*.json'` and check which cache dir it landed in. Verdict: **suite-leak**.

**Order of work:** H-A first (cheapest, explains nondeterminism and the main-red case), then H-D,
then H-B, then H-C. Stop as soon as forward `run-core-offline.sh` is FAIL=0 *and* two consecutive
runs agree — a single green run does not clear a nondeterministic suite (see acceptance).

**RED-2 (`test-plan-followups-01.sh`)** is lead-verified 21/0 on canonical `b9959aa` and red only
in-lane ⇒ regression from one of the 4 dirty lane files. Bisect by `git stash`-ing each of the 4 in
turn, or by `git diff 389820a -- <file>` review; the dispatch-code hunks are the only plausible
carrier (`leadv2-broad-status.sh` is 5 lines and `.gitignore`/the ladder suite cannot reach it).

---

## 3. Scoped changes — exact files

### 3.1 `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
- **Fail-closed the ledger dir.** `:398` — stop honouring an inherited `DISPATCH_LEDGER_DIR`;
  derive it from `CACHE_BASE` unconditionally, or from a *new-namespaced* read of an existing
  env var. **No new env vars** (off_limits) — so prefer the unconditional derivation.
- **Sandbox the park path.** `:705 :708 :732` — resolve the glm-deferred queue and its
  `glm-deferred.d/` mission copies from the same root the ledger uses, so a test with
  `CLAUDE_PROJECT_ROOT` set cannot write into the canonical repo.
- Whatever H-C turns up in the `quota_precheck_skip` park/count block.
- Verify (don't re-do) the remaining r2 findings against the on-disk diff: C1 park+count on
  precheck-skip, C2 mission content parked + retry dispatches a **new** sig8, C3 real `--retry-all`
  leg, H2 all four bare `flock 8` replaced by `lv2_lock_wait` (macOS has no `flock(1)` — a bare
  `flock 8` runs unlocked), H3 mark-retried only after rc==0 and inside the lock, M1 dead
  `_glm_deferred_is_retried`, M2 real `glm_refused_*` variant in `reason`, M3 park gate = quota
  refusals only, M4 counter counts distinct sig8/day, M5 the 3 SC2034 locals.
  Any finding already satisfied → note "already landed in 389820a+wt" with the diff hunk; do not
  re-implement.

### 3.2 `plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh`
- Neutralise inherited state at the top of the suite (alongside the existing `:22 TMP_ROOT`/`:47`
  block): `unset`/`env -u` for `DISPATCH_LEDGER_DIR` and any sibling the run can inherit.
- Give the three failing cases their own `LEADV2_QUOTA_LOCKOUT_DIR` under their own cache dir, the
  way `:515` already does for the lockout case.
- Where a fix is a *suite* fix, the case must still be able to fail — do not widen an assertion to
  make it pass. A case whose only change is a loosened `grep` is a lying-green and will be rejected.

### 3.3 `plugins/leadv2/scripts/tests/test-plan-followups-01.sh`
Touch **only** if root-cause lands in the suite. Default expectation: the fix is in
`leadv2-dispatch-code.sh` and this file is untouched.

### 3.4 `plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh` / `.gitignore` / `leadv2-broad-status.sh`
Already carrying the r2 work in the worktree. Change only if a §3.1 fix moves a path the ladder
suite asserts on. `.gitignore` must be **committed** in this lane (r2 finding H1).

---

## 4. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Nondeterministic suite declared green off one lucky run | Acceptance requires **two consecutive** forward `run-core-offline.sh` runs with FAIL=0, in that order, in the same shell |
| R2 | "Fix the suite" degenerates into loosening assertions | Every suite edit must be accompanied by a probe showing the case still fails against the pre-fix code path |
| R3 | Sandboxing the park path changes the *production* location of `glm-deferred.jsonl` | Root must remain the real repo when `CLAUDE_PROJECT_ROOT` is unset — assert the unset case explicitly |
| R4 | 19 dirty runtime files (`docs/leadv2/bus.jsonl`, `active.yaml`, `*.lock`, `docs/handoff/**`) get swept into the commit | Stage the 4 lane files **explicitly by path**; never `git add -A`. Re-`git diff <file>` immediately before `git add` (a parallel session shares this worktree's parent repo) |
| R5 | Tests write into the canonical repo during the run (H-B) | After the green run, `git -C ~/Projects/leadv2 status --short docs/leadv2/glm-deferred*` must be empty |
| R6 | Fix drifts into off_limits | Routing order/ceilings unchanged; no new env vars; `leadv2-dispatch-product-close.sh`, `supervise*`, `lib/leadv2-builder-selfcheck.sh` untouched — `git diff --name-only` at commit time must not list them |

## 5. Non-goals (explicit — implementer ignores)

- Changing routing order, arm ceilings, or the ladder's provider sequence.
- Introducing any new `LEADV2_*` env var.
- Touching `leadv2-dispatch-product-close.sh`, `supervise*`, or
  `lib/leadv2-builder-selfcheck.sh` (another live lane owns it).
- De-duplicating `.claude/scripts/tests/` vs `plugins/leadv2/scripts/tests/` (a separate
  open thread with its own blast radius).
- Re-implementing any r2 finding already satisfied on disk.
- Fixing other suites that are red on canonical `main` but outside RED-1/RED-2.
- Committing the dirty leadv2 runtime state.

## 6. acceptance

```yaml
acceptance:
  authored_at: 2026-08-20T01:52:00Z
  items:
    - surface: log_line
      observable: >-
        The tail of the forward run-core-offline.sh output reads a suites line whose
        failed count is 0, and the run is repeated immediately a second time in the same
        shell and again reads failed 0 — including the lines naming
        test-routing-enforcement-p1 and test-plan-followups-01 as passing in both runs.
    - surface: log_line
      observable: >-
        In the test-routing-enforcement-p1 output, the three previously-failing cases
        print their PASS lines — "quota refusal journals refusal and advances GLM -> Codex",
        "codex dead-arm (no first byte) declares no_first_byte and spills to sonnet", and
        the quota-lockout write-side case — with no FAIL line anywhere in that suite's output.
    - surface: log_line
      observable: >-
        test-glm-deferred-ladder.sh prints a passing line for the one-shared-cache-dir
        two-refusal case and a passing line for the real --retry-all leg, and
        test-lane-placement-pin.sh reports 24 passed 0 failed.
    - surface: file_artifact
      observable: >-
        git status on the canonical repo after the green run shows no glm-deferred.jsonl
        and no glm-deferred.d entries — the test run left nothing behind outside its sandbox.
    - surface: file_artifact
      observable: >-
        git show --stat on the new lane commit lists exactly the lane-owned files
        (.gitignore, leadv2-dispatch-code.sh, the routing-enforcement and glm-deferred-ladder
        suites, leadv2-broad-status.sh) and lists no docs/leadv2 runtime file, no
        docs/handoff entry, and no off_limits path.
    - surface: log_line
      observable: >-
        bash -n over each changed shell file prints nothing, and shellcheck -S warning over
        the same files prints no findings.
    - surface: file_artifact
      observable: >-
        The lane's terminal artifact states, for each of the three RED-1 cases separately,
        a verdict of main-regression, lane, or suite-leak, each followed by the raw command
        and its output that established that verdict.
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh, plugins/leadv2/scripts/tests/test-plan-followups-01.sh, plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh, plugins/leadv2/scripts/leadv2-broad-status.sh, .gitignore

DELIVERABLE_COMPLETE
