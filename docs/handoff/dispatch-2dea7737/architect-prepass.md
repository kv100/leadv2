# architect — plugin follow-ups round 1b (verify + finish abandoned round 1)

TASK_ID `dispatch-2dea7737-architect` · lane `a24b1588` (worktree
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a24b1588`, HEAD `5e69c0b`) · plugin
`main` = `a1afed9`. Design only — no implementation here.

---

## 0. Headline: the inherited code is better than advertised, the *evidence path* is booby-trapped

Two facts change the shape of this task and neither was known when the mission was written.

### 0.1 All four touched suites already PASS at lane HEAD `5e69c0b`

Run verbatim in the lane worktree, `plugins/leadv2/scripts/tests/`:

| suite | rc | result line |
|---|---|---|
| `test-router-v2-retired-arm.sh` | 0 | `router-v2-retired-arm suite: FAIL=0` (3 PASS) |
| `test-arm-ladder-vocabulary-drift.sh` | 0 | `arm-ladder vocabulary-drift suite: PASS=6 FAIL=0` |
| `test-routing-enforcement-p1.sh` | 0 | 18 PASS, 0 FAIL |
| `test-dispatch-resume-sentinel.sh` | 0 | `=== Results: 4 passed, 0 failed ===` |

So round-1's worker died *after* producing working code, not mid-edit. The default posture is
**keep `5e69c0b`, add the missing evidence**, not rewrite. Discard/rewrite only where §2 names a
concrete defect.

### 0.2 `.claude/worktrees/baseline-check` is a POISONED baseline — do not use it

`git -C .claude/worktrees/baseline-check rev-parse HEAD` reports `a1afed9`, but the working tree
does **not** match that commit:

```
$ git -C .claude/worktrees/baseline-check status --porcelain | head
D  docs/handoff/DISPATCH-KIMI-ARM-MISMATCH-01/deliverable.md
M  plugins/leadv2/config/leadv2-routing.yaml
M  plugins/leadv2/hooks/hooks.json
D  plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh
...
```

```
$ md5 -q .claude/worktrees/baseline-check/plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py
47efd6f6ded99e8fd644d00632fad483
$ git show a1afed9:plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py | md5 -q
50121495cce1c3fb653d236ec4510310
```

That file in `baseline-check` has **no `DISPATCHABLE_BUILD_ARMS` symbol at all**, while the real
`a1afed9` blob defines it at line 46 (`{"glm", "codex", "sonnet"}`). I confirmed by importlib: the
module loads and `[a for a in dir(m) if "DISPATCH" in a.upper()]` is `[]`.

I ran the round-1 tests against a `cp -R` of that worktree and got four confident-looking red runs.
**Every one of them is fabricated red.** `test-arm-ladder-vocabulary-drift.sh` "failed" with
`ERROR: cannot import DISPATCHABLE_BUILD_ARMS` — a baseline-corruption artifact, not a behavioural
difference. `test-dispatch-resume-sentinel.sh` "failed" at `S7-pre` (liveness probe returned
`alive`) — but `a1afed9` **is** the liveness-sentinel fix merge, so it must pass there; that red is
the stale worktree, not the assertion change.

This is the exact failure mode the mission is trying to stamp out — a green/red verdict that depends
on where you stood rather than on the commit. If the finisher reuses `baseline-check`, round 1b
reproduces round 1's disease at the evidence layer instead of the code layer.

**Mandated baseline construction** (the only accepted method for this lane):

```
git -C /Users/kostiantyn.vlasenko/Projects/leadv2 worktree add --detach \
    /tmp/a24b1588-base-a1afed9 a1afed9
git -C /tmp/a24b1588-base-a1afed9 status --porcelain   # MUST be empty — assert this
md5 -q /tmp/a24b1588-base-a1afed9/plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py
#   MUST equal 50121495cce1c3fb653d236ec4510310
```

Then copy only the **new/changed test files** from the lane into that clean baseline's `tests/` dir
and run them there. Clean up with `git worktree remove` at the end. Never `git stash` /
`reset --hard` / `clean`, and never reuse `baseline-check`.

**Integrity precondition, blocking:** if `status --porcelain` on the fresh baseline is non-empty, or
the md5 differs, STOP and report BLOCKED — the repo's worktree state is lying and no evidence
produced on top of it is worth anything.

### 0.3 Secondary hazard found while probing: the suites reach into the real repo

Running `test-routing-enforcement-p1.sh` from a scratch copy under `/tmp` still emitted:

```
[leadv2-dispatch-code] lane_worktree_left task=52a91b29 founder_task= \
  path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a24b1588
```

i.e. a test run from outside the repo resolved a lane-worktree path **inside the live lane's own
worktree directory**. That is item 2's disease (unpinned `PROJECT_ROOT` →
`git rev-parse --show-toplevel` on the caller's cwd, `leadv2-dispatch-code.sh:264`) showing up as a
*mutation* risk, not just a verdict risk. Baseline runs must therefore also pin
`LEADV2_DISPATCH_CACHE_DIR` and a sandbox `PROJECT_ROOT` at the invocation, and the finisher must
`git -C <lane> status --porcelain` before and after each baseline run to prove the lane worktree was
not touched.

---

## 1. Scope

### Layers affected

| layer | file | change class |
|---|---|---|
| dispatcher | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | verify-as-is + one hardening (§2.1) |
| routing config | `plugins/leadv2/config/leadv2-routing.yaml` | **read-only** — retirement stays expressed here |
| policy lib | `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` | **read-only** — sole source of `DISPATCHABLE_BUILD_ARMS` |
| tests | 4 files under `plugins/leadv2/scripts/tests/` | verify + extend |

### Non-goals (explicit — implementer ignores)

1. **Do not fix `test-lane-liveness-authoritative.sh` C2.** Make it visible, verify its status
   against a clean `a1afed9`, answer the "own task?" question. No code change.
2. Do not enable `LEADV2_ROUTER_V2` by default. It stays `0`; this lane makes the v2 path *safe when
   flipped*, it does not flip it.
3. Do not touch `leadv2-router-v2.sh`, `leadv2-task-judge.sh`, `leadv2-route-bandit.sh`. The v2
   resolver's own logic is out of scope — the filter sits in the dispatcher, after the resolver.
4. Do not de-duplicate `.claude/scripts/tests/` (an open thread, separate blast radius).
5. Do not rebase, do not move `worktree-a24b1588` backwards past `5e69c0b`, do not push to `main`.
6. No new env vars. Every knob used here already exists.

---

## 2. Item-by-item design

### 2.1 Item 1 — router_v2 arm selection through the dispatchable filter

**What `5e69c0b` did (verified by reading the diff):** it factored the importlib read of
`DISPATCHABLE_BUILD_ARMS` out of `_filter_ladder_to_dispatchable` into a shared
`_dispatchable_arms()`, added `_normalize_v2_arm()` (prefix strip `claude-<model>` → `<model>`,
table-free), added `_filter_arms_to_dispatchable <sig8> <router_label>` operating on the
`candidate_arms` array, and wired the v2 branch (`router_label == v2`, ~line 3067) to normalize then
filter, refusing with `exit 4` /
`dispatch_rolled_back reason=all_arms_not_dispatchable_v2` when the chain empties.

**Verdict: architecturally correct — keep it.** It satisfies the standing rule (retirement stays in
`leadv2-routing.yaml` + `DISPATCHABLE_BUILD_ARMS`; no second hand-kept exclusion list; no arm id is
hardcoded out of routing anywhere in the diff). The normalization-before-filter ordering is the
non-obvious right call: v2 speaks `claude-sonnet`, the ladder speaks `sonnet`, so a naive intersect
would have silently dropped a *legitimate* arm — and the inherited test suite's T2 exists precisely
to pin that. Both T1 and T2 genuinely fail on real `a1afed9` source (my contaminated probe still
showed the substantive shape: `kimi survives into v2 candidate_chain`, and
`chain='claude-sonnet,claude-haiku'` un-normalized) — re-prove both on the clean baseline.

**One hardening required.** `_dispatchable_arms()` keeps the pre-existing fail-open default:

```
if [[ -z "${_dispatchable}" ]]; then
  _dispatchable="glm codex sonnet"
  emit decision "dispatchable_arms_read_failed ..."
fi
```

That literal **is** a hardcoded arm list, and it is now reachable from the v2 path too. §0.2 proved
the read really can return empty against a real on-disk file — so this is a live branch, not a
theoretical one. It is defensible as fail-open (a broken importlib must not brick the dispatcher)
and the `emit` makes it visible, so **do not change the fallback semantics**. Instead:

- add a test asserting that when the read fails, `dispatchable_arms_read_failed` is journalled
  **and** the fallback set still excludes every retired arm (i.e. `kimi` cannot be resurrected via a
  broken read). Force the failure with `LEADV2_DISPATCH_POLICY_PY` if such an override exists;
  otherwise point `SCRIPT_DIR/lib/...` at a sandbox copy in a temp `scripts/` tree.
- If a retired arm ever appears in the fallback string, the drift suite must fail. Add that as
  `case5` in `test-arm-ladder-vocabulary-drift.sh`: parse the literal out of the shell source and
  assert ⊆ `DISPATCHABLE_BUILD_ARMS`. This is the mechanism that stops the fallback from quietly
  becoming the second exclusion list the mission forbids.

**Provider-spawn proof (mission requirement, must be discharged explicitly).** The inherited
`test-router-v2-retired-arm.sh` fences correctly — poison binaries for
`LEADV2_DISPATCH_{GLM,KIMI,CODEX}_BIN` plus `LEADV2_DISPATCH_SUBSESSION_BIN`, plus
`LEADV2_DISPATCH_SPAWN=0`, plus fakes for `LEADV2_ROUTER_V2_BIN` / `LEADV2_TASK_JUDGE_BIN` /
`LEADV2_ROUTE_BANDIT_BIN` (that last group matters: `leadv2-task-judge.sh` makes a **real
`claude -p --model haiku` call** unfaked). Its own header notes
`test-arm-ladder-vocabulary-drift.sh`'s fence **omits `LEADV2_DISPATCH_SUBSESSION_BIN`** — close
that gap. The proof to report is: after a full run of all four suites, grep every suite's captured
stderr for `POISON:` (must be absent, since nothing should even attempt a spawn) and grep the suite
sources for any unfenced reference to `kimi-coder.sh` / `glm-coder.sh` / bare `codex`. Report both
greps verbatim.

### 2.2 Item 2 — `test-routing-enforcement-p1.sh` hermeticity

`5e69c0b` pinned `PROJECT_ROOT="${TMP_ROOT}/degraded-root"` on Test 6 and — correctly, going beyond
the brief — found and pinned the **same defect in Test 5** (`selfhost-root`). That is the "sweep the
rest of the file" deliverable, partially done. Finish it:

- sweep every `env -u CLAUDE_PROJECT_ROOT` / `env -u CLAUDE_PROJECT_DIR` invocation in the file and
  confirm each either pins `PROJECT_ROOT` or documents why cwd-independence is not required;
- report the sweep as a table (test number → pinned? → why).

**Cross-cwd demonstration (required, currently missing entirely).** Run the whole suite from three
cwds and show all three verdicts:

| # | cwd | property |
|---|---|---|
| 1 | `/private/tmp` | outside any git repo (the cwd where the bug was invisible) |
| 2 | `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a24b1588` | the plugin repo itself |
| 3 | `/Users/kostiantyn.vlasenko/Projects/persona-engine` | **a repo that HAS `.claude/ref/leadv2-routing.yaml`** — the cwd where unpinned Test 5/6 pass for the wrong reason |

Invoke by absolute path so cwd is the only variable. All three must produce identical pass/fail
counts. Then run the **unfixed** (baseline) copy of the file from cwd 1 and cwd 3 to show the
verdicts *diverge* there — that divergence, not a synthetic assertion flip, is item 2's
fail-then-pass evidence.

Before/after `git -C <persona-engine> status --porcelain` around cwd-3's run, per §0.3.

### 2.3 Item 3 — `test-dispatch-resume-sentinel.sh` S7 asserts `rc == 0`

`5e69c0b` tightened both the primary S7 assertion and the placement-pin fallback from `rc != 5` to
`rc == 0`, with a comment explaining why. **Correct and complete — keep as-is.**

The fail-then-pass framing needs care and must be stated honestly in the report: this assertion
change does *not* fail against `a1afed9`, because `a1afed9` genuinely returns `rc=0` (the mission
says so: "the observed rc really was 0"). The tightening removes a *false-PASS class*, not a live
bug. The correct evidence is a **negative-control**: on the clean baseline worktree, inject a fault
that makes dispatch exit with some nonzero code other than 5 (e.g. point
`LEADV2_DISPATCH_SUBSESSION_BIN` at a binary exiting 7), and show the OLD `rc != 5` assertion PASSES
while the NEW `rc == 0` assertion FAILS. Same source commit, same injected fault, opposite verdict —
that is the demonstration. Report it as such and label it explicitly as a negative-control rather
than a fail-against-HEAD run; do not dress it up as the latter.

### 2.4 Full-suite counts + the C2 question

Run **every** suite in `plugins/leadv2/scripts/tests/`, not just the four touched, at lane HEAD and
on the clean `a1afed9` baseline. Report a table: suite → HEAD pass/fail → baseline pass/fail →
classification (`fixed-by-this-lane` / `pre-existing` / `regressed-by-this-lane`). Any
`regressed-by-this-lane` row is a blocking finding.

`test-lane-liveness-authoritative.sh` C2 ("live PID with no artifact floors to silent, not dead"):
verify its status on the clean baseline **yourself** — my probe cannot speak to it, since the only
baseline I had was corrupt, and the corrupt baseline made an unrelated sentinel assertion red. State
whether C2 fails identically on `a1afed9`, and give a yes/no with one paragraph of reasoning on
whether it deserves its own task. Do not fix it.

---

## 3. Risks and mitigations

| # | risk | mitigation |
|---|---|---|
| R1 | Fabricated red from a stale baseline worktree (already happened to me — §0.2) | Fresh `git worktree add --detach a1afed9`; assert empty `status --porcelain` AND the `50121495…` md5 before any run. BLOCKED if either fails. |
| R2 | Baseline/test runs mutate the live lane worktree or a real project repo (§0.3) | Pin `PROJECT_ROOT` + `LEADV2_DISPATCH_CACHE_DIR` per invocation; `status --porcelain` on lane and on persona-engine before/after each cross-cwd run. |
| R3 | A test spawns a real provider (has happened before on this suite) | `LEADV2_DISPATCH_SPAWN=0` + all four `*_BIN` poisons + the three router-v2 dependency fakes; close the `SUBSESSION_BIN` gap in the drift suite; grep all captured stderr for `POISON:` and report it. |
| R4 | The `"glm codex sonnet"` fail-open literal becomes the forbidden second exclusion list | Drift-suite `case5` asserts the literal ⊆ `DISPATCHABLE_BUILD_ARMS` (§2.1). |
| R5 | Item 3 reported as fail-against-HEAD when it structurally cannot be | Report it as a labelled negative-control (§2.3). Overclaiming here is the same disease the lane exists to cure. |
| R6 | Worker dies again mid-task (four deaths today) | Commit after each item — item 1 hardening, item 2 sweep+cross-cwd, item 3 negative-control, full-suite report. Four commits minimum, each with its evidence in the message. Never one commit at the end. |
| R7 | `_normalize_v2_arm`'s `claude-*` prefix strip mis-normalizes a future non-model id (e.g. `claude-code-something`) | Out of scope to fix; note it in the report as an accepted limitation. The drift suite's `case4` already fails if `router_v2.arms` gains an id outside `DISPATCHABLE_BUILD_ARMS ∪ advisory`, which bounds it. |
| R8 | Scope creep into C2 / router-v2 enablement / tests-tree dedup | §1 non-goals are hard stops. |

---

## 4. Sequencing

1. Build + integrity-assert the clean baseline (§0.2). BLOCKED on failure.
2. Full-suite baseline run → counts table.
3. Item 1: `case5` + fail-open test + `SUBSESSION_BIN` fence gap → fail-then-pass → **commit**.
4. Item 2: sweep table + 3-cwd demonstration + baseline divergence → **commit**.
5. Item 3: negative-control run → **commit**.
6. Full-suite run at final HEAD; diff against step 2; C2 answer; spawn-fence greps → **commit**.
7. `git worktree remove` the baseline. Report.

---

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >
      In the round-1b report, the run of test-router-v2-retired-arm.sh against a freshly created
      clean a1afed9 worktree shows the line "FAIL: T1: kimi survives into v2 candidate_chain",
      and the run of the same file at lane HEAD shows "router-v2-retired-arm suite: FAIL=0" —
      both pasted verbatim, with the baseline worktree's empty `git status --porcelain` shown
      immediately above them.
    authored_at: 2026-08-06T10:05:00+03:00
  - surface: log_line
    observable: >
      test-routing-enforcement-p1.sh at lane HEAD, invoked by absolute path from /private/tmp,
      from the lane worktree, and from /Users/kostiantyn.vlasenko/Projects/persona-engine, prints
      the same "18 passed, 0 failed"-shaped result line in all three runs; the same file's
      baseline version prints different result lines from /private/tmp and from persona-engine.
    authored_at: 2026-08-06T10:05:00+03:00
  - surface: log_line
    observable: >
      With a fault injected that makes dispatch exit 7, the old `rc != 5` S7 assertion prints
      "ok/PASS" and the new `rc == 0` assertion prints "FAIL: S7: dispatch did not resume the
      finalized lane (rc=7, expected 0)" — both shown, labelled as a negative-control.
    authored_at: 2026-08-06T10:05:00+03:00
  - surface: file_artifact
    observable: >
      The report contains a table with one row per suite in plugins/leadv2/scripts/tests/, each
      row giving lane-HEAD pass/fail, clean-a1afed9 pass/fail, and one of
      fixed-by-this-lane / pre-existing / regressed-by-this-lane; the
      test-lane-liveness-authoritative.sh row is classified and accompanied by a yes/no answer on
      whether C2 warrants its own task. No row is classified regressed-by-this-lane.
    authored_at: 2026-08-06T10:05:00+03:00
  - surface: log_line
    observable: >
      A grep for "POISON:" across every captured suite stderr from the full-suite run returns no
      matches, shown verbatim alongside a grep of the four suite sources showing no unfenced
      reference to kimi-coder.sh, glm-coder.sh, or a bare codex invocation.
    authored_at: 2026-08-06T10:05:00+03:00
  - surface: log_line
    observable: >
      `git log --oneline` on worktree-a24b1588 shows at least four commits on top of 5e69c0b, and
      `git merge-base --is-ancestor 5e69c0b HEAD` succeeds — the branch never moved backwards.
    authored_at: 2026-08-06T10:05:00+03:00
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-router-v2-retired-arm.sh, plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh, plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh, plugins/leadv2/scripts/tests/test-dispatch-resume-sentinel.sh

DELIVERABLE_COMPLETE
