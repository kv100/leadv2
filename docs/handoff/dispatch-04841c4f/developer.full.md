# ARBITER-DECISION-LOGIC-CENSUS-01 — census + top-ranked fix

File under audit: `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` (385 lines), config
`plugins/leadv2/config/leadv2-routing.yaml`, caller `plugins/leadv2/scripts/leadv2-dispatch-code.sh`.

## Method

For every input the arbiter's decision depends on: (1) grep/read the call site to see whether it's
actually supplied or a hardcoded default, (2) probe `route_arbiter` directly (sourced function,
fake `quota-live`/`freepool-gate` stubs, real `leadv2-routing.yaml`) changing ONLY that one input
and diffing the emitted decision line, (3) classify: measured fact vs static label.

All probes run as `bash -c '...'` (the tool's default shell is zsh; sourcing this bash lib under
zsh silently mis-resolves `BASH_SOURCE`-based paths — noted here because it cost real time and is
a trap for the next person probing this file).

## Census table

| Input | Supplied at call site? | Changes the outcome? | Measured or static label? | Evidence |
|---|---|---|---|---|
| `kind` | Yes — `--kind` flag, normalized via `KNOWN_KINDS` (T17 C1) | Yes — filters `capable` cells | Label (caller-chosen), but normalization is data-driven | `kind=some-future-caller-kind` → normalizes to `code`, resolves an arm (test f) |
| `size`/`class` | Yes — `task_class`, folded via `SIZE_MAP` | Yes — filters cells, gates the freepool floor | Label; `SIZE_MAP` is a hand-typed 6→3 table (M1) | code read: `SIZE_MAP={'standard':...,'trivial':'standard','strategic':'heavy',...}` |
| `protected` | Yes — OR of explicit `--protected` and `_writes_protected` (computed from real `lane_writes` paths) | Yes — `require_trusted` gate | **Measured** (writes-derived) OR explicit label; legitimate mixed input, not a hole | `leadv2-dispatch-code.sh:7382-7384`: `protection_derived ... writes_protected=... manual_protected=... effective_protected=...` |
| `safety`/`ui_judgment` | Yes, explicit flags | Yes — force `require_trusted` regardless of kind | Label (policy), by design | `ARMS-ADMISSION-01` comment, arbiter.sh:69-80 |
| `tags` (capability_matrix) | Static, in `leadv2-routing.yaml` | Yes — drive `effort_matrix` match AND `complexity_penalty` match | **Static label, and it is the load-bearing one** | see Hole 1 below |
| `test_only` | Yes, from a dispatcher-side signal | Yes — exempts the freepool floor | Label but data-driven upstream (docs/tests-only detection) | `floor_applies = ... and not test_only` |
| quota per provider (glm/codex/claude/freepool) | glm/codex: yes, live JSON, always `status:'ok'` reader. **claude: yes, live JSON, but wrong row selected** (see Hole 2). freepool: proxy-gate boolean only | Yes — dominant term in `over_ceiling`/`capped` | **Should be measured; claude effectively degraded to a label ("0 = free") before this fix** | see Hole 2 |
| reset distance (`hours_to_reset`/`period_hours`) | Yes, `hours_to_reset` shipped by `leadv2-quota-read.py`, read by `window_reset()` | Yes — `near_reset_wait()` overrides `capped()` | Measured, with a named pessimistic default (`default_full_period`) when the reset itself is missing | CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01 comment + code, arbiter.sh:86-136 |
| `complexity` | Yes — `_dispatch_complexity_estimate()` calls `leadv2-task-judge.sh` **unconditionally on every dispatch**, degrades to a code-only fallback estimator (never "unknown" unless the judge binary is literally missing) | Only via the ONE existing `complexity_penalty` rule (`complexities:[complex]`) | **Measured** (LLM judge or heuristic fallback), contrary to the mission's framing — see "Hole 3 does not reproduce" below | live probe: `leadv2-task-judge.sh --mission-file ... --class Standard` → `{"complexity":"standard","duration_class":"medium","estimate_source":"fallback",...}` |
| `duration_class` | Yes, same estimate call | **No** — `complexity_penalty` in the shipped config has zero rows with `duration_classes:` set, so `want_duration` is always empty and the filter never discriminates on it | Measured but **dead**: computed, threaded through the whole descriptor and journal line, never consumed | grep `duration_classes` in `leadv2-routing.yaml` → only appears in the schema comment, never in a real rule |
| `effort` | Derived from the **winning capability_matrix cell's own tags/kind/protected** (`effort_matrix`), never from `complexity`/`duration_class` | Yes — printed, and (per doc) meant to set the model's thinking budget | **Static label of the arm, not a measurement of the task** — Hole 1, still open | live probe below |
| `floor_applies` (freepool floor) | Yes — keys on real `size_raw`/`kind`/`test_only` from the descriptor | Yes — +100 effective cost | Measured/config-driven, legitimate | `floor_applies = (size_raw in (...) and kind=='code' and not test_only)` |
| `freepool_gate` (`free_ok`) | Yes — live subprocess call to `leadv2-freepool-gate.sh check`, rc captured | Yes — `util('freepool')` is 0 or 100 purely from this rc | Measured (a real health probe), not a label | arbiter.sh:32-36 |
| `quota_ceilings` (`work_pct`/`review_pct`) | Static in yaml, but **now enforced for all three providers** via `over_ceiling()` reading the SAME `u[provider]` the arbiter itself computed | Yes | Label (policy number) applied to a now-measured input; the yaml comment "codex and claude have no ceiling reader at all" is **stale** — `over_ceiling()` reads `u[provider]` uniformly | live probe: `util_claude=73` (post-fix) triggers `over_ceiling('claude')` against `review_pct/work_pct:95` correctly |
| `allowed_arms` | Yes — always a JSON list, built from the caller's own `candidate_arms` (never `None` from this call site) | Yes, and dangerously: `[]` (empty list) means "admit nothing", not "no restriction" | Measured upstream, but the **empty-list-vs-omitted distinction is unenforced** | see "Additional finding" below |
| fallback chain (`chain=`/rotation) | Computed from `ok` sorted by `ecost` | Yes | Measured (cost sort) + anti-sticky state file read | test (d)/(d2) in `test-route-arbiter.sh`, unchanged by this task |

## The three founder-named holes, independently re-measured on this tree

1. **Effort follows the arm — CONFIRMED, still open.**
   ```
   kind=build size=standard protected=false → arm=glm-flash ... effort=low
   ```
   `effort` is resolved from `w` (the winning cell) via `_effort_row_matches`, matching
   `glm-flash`'s own `tags:[cheap,mechanical]` — the task's own `complexity`/`duration_class` never
   enter `effort_matrix` row-matching at all (arbiter.sh:321-331 only checks `tags`/`kinds`/
   `protected` of the winning cell). The NEW `complexity_penalty` mechanism (below) changes which
   ARM wins on a complex task, so effort can change *indirectly* by picking a non-cheap arm — but a
   complex task that still lands on a cheap-tagged cell (e.g. any complex `docs` kind, which
   `complexity_penalty` doesn't touch — its `penalize_tags` are `[cheap,mechanical]` but the rule
   has no `kinds:` filter, so it does apply to docs too... but a complex task under `size:trivial`
   folded to `standard` with the floor inapplicable could still cheapest-sort to glm-flash if glm
   were capped) still gets `effort=low` on pure luck of which cell wins, not by design.

2. **Claude quota reads the wrong number — CONFIRMED, was open, FIXED in this task.**
   Live probe on this tree, unmodified code, real `leadv2-quota-live.sh`:
   ```
   accounts: [{"active":true,"account_label":"max_20x","status":"unknown","http":401,<all pct null>},
              {"active":false,"account_label":"max_5x","status":"ok","seven_day_pct":49},
              {"active":false,"account_label":"max_20x","status":"ok","seven_day_pct":72}]
   ```
   `util('claude')` picked the `active:true` account unconditionally (`x.get('accounts')` →
   `next(...active)`), read its null `five_hour`/`seven_day`, found no window with a numeric pct,
   fell through to `if best_pct is None: return empty` → `pct=0.0`. Decision line before fix:
   `util_claude=0 ... reset_claude=n/a`. Real accounts sitting two entries over showed 49%/72%.
   This is exactly the founder's report (72% max_20x / 48% max_5x vs `util_claude=0`).

3. **Complexity is always unknown — DOES NOT REPRODUCE on this tree.**
   `_dispatch_complexity_estimate()` (leadv2-dispatch-code.sh:2888) is called **unconditionally**
   on every dispatch (not gated by `LEADV2_ROUTER_V2`), and `leadv2-task-judge.sh` exists, is
   executable, and returns a real, non-"unknown" estimate even when the model call itself fails —
   live probe:
   ```
   $ bash leadv2-task-judge.sh --mission-file /tmp/mission.txt --task-id census-probe --class Standard
   {"complexity":"standard","duration_class":"medium","estimate_source":"fallback","work_kind":"build",...}
   ```
   and the arbiter descriptor carries it through (`complexity=standard duration_class=medium` in
   the four-kind probe below, not `unknown`). The mission cites a separate lane
   `worktree-COMPLEXITY-ESTIMATOR-IS-OFF-01` with an empty anchor commit as evidence this is
   unfixed — that branch is a different, never-started lane; it is not evidence about the state of
   `main`/`481c0be7`, where this mechanism is already wired and working (with the code-only
   fallback covering the no-model-access case, by the judge's own design). **Flagging this
   explicitly for the founder**: hole 3 as described does not match current code. What IS still
   true and IS a real gap: `duration_class` is computed and threaded everywhere but the shipped
   `complexity_penalty` config never keys on it (zero rules set `duration_classes:`), so it is
   dead weight today — a config gap, not a code gap.

## Additional finding: `allowed_arms: []` refuses everything, silently

Reproduced by difference, same call, only the field changed:
```
allowed_arms omitted  → arm=glm-flash ... reason=cheapest_capable chain=glm-flash,glm,sonnet,freepool
allowed_arms: []      → arm=refuse reason=no_capable_cell chain=
```
`allowed={str(a) for a in allowed_raw} if isinstance(allowed_raw, list) else None` treats an empty
list the same as "restrict to nothing" rather than "no restriction supplied". The real caller
(`leadv2-dispatch-code.sh:7633`) always sends a list (built from its own `candidate_arms`), so this
only bites if `candidate_arms` is ever empty at the call site — not confirmed reachable in this
census, flagged as a footgun rather than ranked, since I could not find a live path that produces
an empty `candidate_arms` array feeding this call.

## Ranking (consequence, not count)

1. **Hole 2 (claude quota) — highest consequence.** Silently misprices claude as free in every
   ceiling check and every cost comparison; on the day the founder measured it, claude was near
   its 95% ceiling and the arbiter would never have switched away from it. Real work goes to an
   over-budget provider or, worse, a task waits on claude's `near_reset_wait` window using a false
   "far" reset (`reset_basis=n/a` degraded, never even reaching the wait logic). **Fixed in this
   task.**
2. **Hole 1 (effort follows arm) — second.** Sends real work with a low thinking budget whenever
   the cheapest capable cell happens to be tagged `cheap`/`mechanical`, independent of the task's
   actual difficulty; the new complexity_penalty can rescue this indirectly for `complex`-flagged
   code work only, not for any other kind or for effort computed on a non-cheap winning cell that
   still under-thinks a hard task. Left open — real fix needs `effort_matrix` rows keyed on
   `complexity`/`duration_class`, which is a config-and-doc-policy decision (what should "hard doc
   task" resolve to?) I did not want to make unilaterally inside this task's scope.
3. **duration_class dead in config — third, but "merely prints a wrong number" in today's shipped
   config** (no rule reads it, so it changes nothing today) — future rules that add
   `duration_classes:` will start working immediately, no code change needed; this is a config gap
   not a code gap.
4. **`allowed_arms: []` footgun — fourth**, unconfirmed reachability, lowest consequence of the
   four; noted for the founder, not fixed.

## Fix delivered (Hole 2)

`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`, `util()`'s claude/anthropic branch: select
the `active`-flagged account only when it itself reports `status=='ok'`; otherwise fall back to a
DIFFERENT account with `status=='ok'`, preferring one with the same `account_label` (the true
measurement for the account actually in use), else any ok account; only if NO account is ok does it
fall to the existing pessimistic `unknown_capped` path (same fail-closed shape as the pre-existing
T17 C3 glm/codex guard — never the old optimistic `pct=0.0`).

Diff: `git diff --stat` → `lib/leadv2-route-arbiter.sh | 26 +++++++++++++++++++++-`,
`tests/test-route-arbiter.sh | 20 +++++++++++++++++`.

### Suite output (green, post-fix)

```
$ bash tests/test-route-arbiter.sh
PASS: codex 99% routes to a capable non-codex arm
PASS: all capped refuses all_arms_capped
PASS: protected chain excludes freepool and admits glm
PASS: anti-sticky identical tasks rotate arms
PASS: standard cell deterministically picks glm-flash (cost, not stickiness)
FAIL: fallback output=[leadv2-dispatch-code] WARN: foreign project root detected (...) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
      ... dispatch_refused reason=writeset_conflict task=... writes=src/x.py
      LEADV2_DISPATCH_REFUSED: writeset_conflict
PASS: unknown --kind normalizes to code and resolves
PASS: fanout-class-funnel kind resolves an arm
PASS: backlog-pump kind resolves an arm
PASS: broken glm probe (status!=ok) is fail-closed, never selected
PASS: broken-active claude account falls back to the real ok account, not pct=0
SUMMARY: pass=10 fail=1
```
Test (e) ("fallback ... arbiter_broken/route_resolved") fails on this tree **before any change of
mine** — it is a `git diff --name-only`-scoped worktree/foreign-root-guard interaction in
`leadv2-dispatch-code.sh`'s writeset guard, unrelated to `leadv2-route-arbiter.sh` (my diff touches
only `util()`'s claude branch and adds a new test case). Not in `LEADV2_RUN_ALL_SELECT_ONLY` /
LANE_WRITES scope for this task, not added to `known-red-suites.txt` (would only shrink that file,
never grow it) — reporting as a pre-existing, environment-sensitive finding per the constraint on
never weakening a fixture to get green.

### Negative control (mutation INSIDE the function body, per the 2026-09-04 rule against top-level
mutations)

Mutation: dropped the `and active.get('status')=='ok'` guard so the active-flagged (broken)
account is used unconditionally again — restores the exact pre-fix bug, inside `util()`, not at
top level:
```
-        if active is not None and active.get('status')=='ok':
+        if active is not None: # NEGATIVE-CONTROL-MUTATION: drop the status=='ok' guard
```
Red output with the mutation applied:
```
FAIL: fallback output=... (same pre-existing, unrelated failure)
FAIL: broken-active-claude output=arm=glm ... util_claude=0 ... reset_claude=n/a ...
SUMMARY: pass=9 fail=2
```
Mutation reverted, suite green again (see block above, `pass=10 fail=1`, same single pre-existing
failure both times — proving the mutation is what flipped test (h) and nothing else).

### CI selection proof (both directions, `--scope changed`, never a full `tests/run-all.sh` run)

```
$ git diff -- lib/leadv2-route-arbiter.sh tests/test-route-arbiter.sh > /tmp/census-fix.patch
$ git checkout -- lib/leadv2-route-arbiter.sh tests/test-route-arbiter.sh   # revert to HEAD
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed | grep -i route-arbiter
NO_MATCH_AFTER_REVERT
$ git apply /tmp/census-fix.patch                                          # reapply
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed | grep -i route-arbiter
[SELECT] .../plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-route-arbiter.sh
```
Both directions shown; the working tree ends in the fixed (patched) state, verified by re-running
`bash tests/test-route-arbiter.sh` (green, `pass=10 fail=1`, matching the block above) and
`bash -n lib/leadv2-route-arbiter.sh` (no output = syntax OK).

### Four kinds, verbatim, live quota (real `leadv2-quota-live.sh`, real `leadv2-freepool-gate.sh`),
post-fix

```
kind=build ->
arm=glm-flash model=glm-5.3-flash tier=standard effort=low reason=cheapest_capable chain=glm-flash,glm,sonnet,freepool util_glm=29 util_codex=92 util_claude=73 util_freepool=0 reset_glm=104.29h_live reset_codex=67.07h_live reset_claude=8.33h_live reset_freepool=n/a floor_applied=1 floor_reason=standard/code floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown remaining=71.0 reset_in=104.29h reset_basis=live

kind=recon ->
arm=glm-flash model=glm-5.3-flash tier=standard effort=low reason=cheapest_capable chain=glm-flash,glm,sonnet,freepool util_glm=29 util_codex=92 util_claude=73 util_freepool=0 reset_glm=104.29h_live reset_codex=67.07h_live reset_claude=8.33h_live reset_freepool=n/a floor_applied=1 floor_reason=standard/code floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown remaining=71.0 reset_in=104.29h reset_basis=live

kind=review ->
arm=glm model=glm-5.3 tier=standard effort=medium reason=cheapest_capable chain=glm,sonnet,opus util_glm=29 util_codex=92 util_claude=73 util_freepool=0 reset_glm=104.28h_live reset_codex=67.07h_live reset_claude=8.33h_live reset_freepool=n/a floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown remaining=71.0 reset_in=104.28h reset_basis=live

kind=plan ->
arm=glm model=glm-5.3 tier=standard effort=high reason=cheapest_capable chain=glm,haiku,sonnet,opus util_glm=29 util_codex=92 util_claude=73 util_freepool=0 reset_glm=104.28h_live reset_codex=67.07h_live reset_claude=8.33h_live reset_freepool=n/a floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown remaining=71.0 reset_in=104.28h reset_basis=live
```
Note: `complexity=unknown` here because these four probes called `route_arbiter` directly (bypassing
`leadv2-dispatch-code.sh`'s `_dispatch_complexity_estimate`, which is what actually populates it in
real dispatch — Hole 3's independent live probe above used the real judge script directly and got
`standard`/`medium`, not `unknown`). `util_claude=73` on all four lines is the fix, confirmed live
against the real (currently-degraded, 401-affected) `leadv2-quota-live.sh` output on this machine.

## Self-check (falsification set)

```
$ bash -n plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
(no output = OK)
$ bash -n plugins/leadv2/scripts/tests/test-route-arbiter.sh
(no output = OK)
```
No Python files changed. No py_compile needed.

## Left open, explicitly

- Hole 1 (effort-follows-arm): not fixed. Real fix requires new `effort_matrix` rows keyed on
  `complexity`/`duration_class`, a policy decision (what effort should a hard `docs` task get?)
  outside this task's single-fix scope.
- `duration_class` dead in `complexity_penalty` config: not fixed, zero-risk to leave (adding a
  `duration_classes:` row to any future rule activates it with no code change).
- `allowed_arms: []` empty-vs-omitted footgun: not fixed, unconfirmed reachable in production.
- Test (e) in `test-route-arbiter.sh` (writeset_conflict/foreign-project-root): pre-existing,
  unrelated to this file, not touched.

DELIVERABLE_COMPLETE
