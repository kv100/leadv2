# A1-CODEX-TIERS-A3 report — sol / luna / terra launchable as themselves (part A + registry tuples)

Task: `CODEX-TIERS-COLLAPSED-ONTO-ASTRA-SOL-LUNA-TERRA-UNREACHABLE-01`, part A.
Repo: `~/Projects/leadv2` (plugin repo, single source). Lane branch:
`worktree-A1-CODEX-TIERS-A3`. Date: 2026-09-08.

## The defect, measured (not assumed)

`plugins/leadv2/scripts/codex-task.sh` mapped ALL THREE tiers to the same
model (`gpt-6-astra`), only the effort differed — the inline tier block
(`:1409-1423` pre-fix) and the timeout-retry helper `_tier_model_effort`
(`:2180-2187` pre-fix) each carried their own all-astra copy of the table,
while the header (`:14-20` pre-fix) still documented the sol/terra/luna
mapping the code had stopped implementing. `~/.codex/models_cache.json`
(verbatim slugs, checked live at lane start):

    gpt-6-astra, gpt-reserve, gpt-5.6-sol, gpt-5.6-terra, gpt-5.6-luna,
    gpt-5.5, gpt-5.3-codex-spark, codex-auto-review

So sol, luna and terra existed on the account but were unreachable through
any tier.

## Provenance of this lane's code

An earlier dispatch of this same mission (lane A1-CODEX-TIERS-A2, commits
`f8998a4d` feat + `f5b4c26c` docs) completed the work but was never merged —
its dispatch siblings were refused `duplicate_task_signature`, which from the
outside reads as "the worker produced nothing" (dispatch note 2026-09-08 in
this lane's brief). This lane did NOT re-derive it blindly: the A2 feat
commit was verified line-by-line against the mission rules, cherry-picked
(`-x`, provenance recorded in the commit message; `git diff` base-vs-base on
the three LANE_WRITES files was empty, so the pick was conflict-free), then
re-verified from scratch in this worktree — suite, both mutation controls,
and all three live runs below are THIS lane's own artifacts, on THIS lane's
committed HEAD. One real defect A2 carried was found and fixed here (see
"check() fix").

## What changed

| File | Change |
|------|--------|
| `plugins/leadv2/scripts/codex-task.sh` | ONE shared table `_resolve_tier_model_effort` (presence-checked per tier via `jq` on `models_cache.json`, journaled by-name fallback DOWN the chain); the `--tier` block and `_tier_model_effort` both delegate to it, so the two sites can no longer drift. Header `:14-20` rewritten to state exactly the implemented mapping. |
| `plugins/leadv2/scripts/lib/leadv2-launch-registry.py` | `CODEX_MODEL_TIERS`: one entry per launchable (model, tier) pair — (sol,top), (terra,top), (terra,standard), (luna,volume), (astra,top/standard/volume) — each with a per-TASK-CLASS effort table (`codex_effort_for`); `lookup()` refuses a codex matrix row whose pair is not registered (`codex_model_tier_not_registered`) — narrowing only. `_argv_codex` for task-wire kinds pins `--model X --effort Y` explicitly (explicit flags win in codex-task.sh), `review`/`plan` keep the frozen tier-only argv. Plus this lane's `check()` fix (below). |
| `plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh` | New suite, self-registered `# run-all-triggers: codex-task` (+ `leadv2-launch-registry`); extracts the resolver VERBATIM from the live file; embeds both negative controls as mutated sibling copies. |

### Tier table and its sources (per mission rule: derived, not taste)

| tier | primary | fallback chain (journaled by name) | effort | source |
|------|---------|-----------------------------------|--------|--------|
| top | gpt-5.6-sol | sol→terra→astra | high | historical header mapping (`codex-task.sh:14-20` pre-fix); cost 7 / capability 4 row in `config/leadv2-routing.yaml:215` |
| standard | gpt-5.6-terra | terra→astra | medium | historical header (EFFORT-RECAL 2026-07-10); cost 4 / capability 4 row `:214` |
| volume | gpt-5.6-luna | luna→astra | low | historical header (EFFORT-RECAL 2026-07-10); cost 3 / capability 3 row `:213` |

Effort stays PER TIER on fallback (model = hardness, effort = marginal
thinking value — `leadv2-routing.yaml:236`'s own split), so top's terra
fallback is terra/HIGH, deliberately not the pre-bump terra/xhigh. Astra is
the terminal fallback because the matrix already prices astra at every tier
and it is the one model proven live on this account. An unreadable cache
never fails a dispatch: terminal astra + journal line
`models_cache unreadable at <path> -> gpt-6-astra (presence unverified)`.

### check() fix (this lane's addition, commit `ee859453`)

A2's `_canonical_model` returned the FIRST codex matrix row's model as a
scalar. Once part B lands three per-tier codex rows (luna/volume first),
`check("codex", "gpt-5.6-sol")` would have answered `refuse` — the refusal
helper vetoing exactly the models part A makes launchable. Now
`_canonical_models` returns every codex model whose (model, tier) pair is in
`CODEX_MODEL_TIERS`. On the live all-astra matrix the verdict set is
unchanged (`check codex/gpt-6-astra -> ok`), so nothing widens.

## Live acceptance (surface: log_line — one real run per model, 2026-09-08)

Each run: `bash plugins/leadv2/scripts/codex-task.sh task "<probe>" --tier <t> --wait`
from this worktree. Resolution lines verbatim from stderr; status from the
companion transport; probe line from stdout.

    tier=top:      [codex-task] tier=top -> model=gpt-5.6-sol effort=high (sub=task)
                   status=completed app_server_pid=8130   stdout: SOL-PROBE-OK    rc=0
    tier=standard: [codex-task] tier=standard -> model=gpt-5.6-terra effort=medium (sub=task)
                   status=completed app_server_pid=87299  stdout: TERRA-PROBE-OK  rc=0
    tier=volume:   [codex-task] tier=volume -> model=gpt-5.6-luna effort=low (sub=task)
                   status=completed app_server_pid=63838  stdout: LUNA-PROBE-OK   rc=0

The top run's tier ledger row (`~/.claude/cache/codex-tier-log.jsonl`,
CODEX-TIER-ENFORCER-01) records the resolved model:
`{'ts': '2026-09-08T18:15:11Z', 'tier': 'top', 'sub': 'task', 'model': 'gpt-5.6-sol', 'effort': 'high'}`.
No fallback journal line fired in any run — all three models are present in
`models_cache.json`, so each tier resolved its primary.

## Falsification set (raw outputs)

- `bash -n` codex-task.sh, suite: `syntax-ok` (py_compile below)
- `python3 -m py_compile leadv2-launch-registry.py`: `py_compile-ok`
- New suite: `== test-codex-tier-model-table: PASS=26 FAIL=0 ==` (g1 per-tier
  model+argv ×3, g2 named fallback journal ×3 + ledger model, g3 unreadable
  cache, g4 effort-not-folded, g5 registry pairs/effort/refusal/part-B
  fixture/check()-multi-model ×2, m1+m2 embedded controls)
- Sibling suite `plugins/leadv2/tests/test-launch-registry-argv.sh`: `PASS=13 FAIL=0`
  (frozen `_argv_codex` review/legacy shapes intact)
- Trigger map (`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`):
  `codex-task:plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh`
  and `leadv2-launch-registry:...` — registered without touching run-all.sh
- Changed-scope runner `bash tests/run-all.sh --scope changed`: see
  "run-all result" below.

### run-all result (honest, including a measurement lesson)

Run 1 (after commit `ee859453`): `21 passed, 7 failed, scope=changed`. The
invocation piped through `| tail -25`, so the per-suite PASS list was
truncated and the recorded rc (0) was TAIL's, not run-all's — the exact
exit-code-measurement artifact this repo's memory warns about. Re-run
unpiped: `runall-rc=1` (blocking failures present, per run-all's contract).
My suite and `test-launch-registry-argv.sh` both in the passed set; the full
log shows `== test-codex-tier-model-table: PASS=26 FAIL=0 ==` executed
inside core-offline as `scope-selected ad-hoc`.

The 7 blocking failures of run 1 were: `run-core-offline.sh` (wrapper) +
6 standalone suites. Every one of the 6 is byte-identically red on the
PRE-CHANGE file (verified by `git checkout 9401f0ff -- codex-task.sh`,
re-run, restore — same failing test names, same tallies, e.g. lockout
`9 passed, 1 failed` both states; survives-nonzero-exit fails in its OWN
fixture `drive.sh:158: _CODEX_SCRIPT_DIR: unbound variable` in both states):

    test-codex-lockout-agreement   base 9/1  new 9/1  (same failing test)
    test-codex-survives-nonzero-exit  identical AssertionError both states
    test-codex-task-spawn-failure  same FAIL line both states
    test-codex-transport-attribution  same FAIL line both states
    test-plugin-papercuts          base 11/3  new 11/3  (same 2 tests)
    test-st2-question-protocol     identical failure lines both states

The wrapper `run-core-offline.sh` itself: solo `--scope changed` runs were
executed in BOTH code states (selection identical, from the lane checkpoint):

    NEW codex-task.sh: solo-rc=1, 9 nested FAILED
    OLD codex-task.sh: solo-rc=1, the SAME 9 nested FAILED
                       + test-codex-tier-model-table.sh (correctly red on
                         the collapsed table — the suite doing its job)

The nested red set is code-INDEPENDENT (identical old vs new), varies
run-to-run in composition (spawn-failure appeared in one run, longrun+dedup
in another), and every nested-red suite passes standalone seconds later in
BOTH states (longrun, timeout-tier-resolution, phase-policy-document,
dedup-release-01 all rc=0 standalone old AND new). All 7 codex-family suites
inside core-offline's own map also pass standalone with the new code
(child-session-boundary, dead-reroute, instant-complete, lead-intake,
quota-guardrails, session-runner, review-codex-base — rc=0 each).
Nested example: timeout-tier-resolution Tests 3/4 report `got ''` inside
core-offline (mock marker never surfaces) while Tests 1/2 pass and the whole
suite passes standalone — consistent with core-offline's parallel-shard
execution interfering across sibling suites. No lock contention in my solo
runs (no `waiting for lock` lines; no concurrent holder).
UNVERIFIED: the precise root cause of the nested-only reds — not reproduced
outside core-offline in either code state, so root-causing them is out of
this lane's scope. Classification (pre-existing/environmental, not this
diff) rests on the identical-old-vs-new nested set above.

## Negative controls (E2E-KILLRATE-01) — red shown

Both applied by `leadv2-mutation-control.sh` in a scratch copy against this
lane's committed HEAD (artifacts in `mutation-control/`, lane_diff_hash
`6de530beed51e403300020194ffb5f6258db9ab53aa95ba952c72a0623654688`):

    m1 (re-collapse every tier onto gpt-6-astra, inside
        _resolve_tier_model_effort's body — the three _chain assignments):
      MUTATION-CONTROL ok ... red_line=[TEST] FAIL: g1: tier=top resolution
      line missing 'gpt-5.6-sol/high': [codex-task] tier=top -> model=gpt-6-astra
      effort=high (sub=task)
      Red ON THE RESOLVED MODEL NAME; the suite's own m1 gate requires the
      collapse to be caught on >=2 tiers and reported 3/3 in-suite.

    m2 (absent model silently resolves to astra, journal echo replaced,
        inside the fallback branch of the same function):
      MUTATION-CONTROL ok ... red_line=[TEST] FAIL: g2: sol-absent journal
      line missing:
      Red ON THE MISSING JOURNAL LINE.

Both mutations live INSIDE the function body, never at top level. rc=0 =
mutation applied AND suite red as required.

## Part B copy-paste: capability_matrix rows (NOT applied here — held lane)

Replace the three codex rows at `config/leadv2-routing.yaml:213-215` (all
currently `model: gpt-6-astra`) with these — only `model:` (and tags)
differs from the live rows; the suite's part-B fixture proves these resolve
luna/terra end-to-end through `lookup()` with no registry edit:

    - { arm: codex, provider: codex, model: gpt-5.6-luna, tier: volume, cost: 3, kinds: [code, docs, review, plan, audit, fanout-class-funnel, backlog-pump], sizes: [standard], tags: [mechanical], review: true, protected: true, capability: 3 }
    - { arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, cost: 4, kinds: [code, docs, review, plan, audit, fanout-class-funnel, backlog-pump], sizes: [standard, heavy], tags: [review, adversarial], review: true, protected: true, capability: 4 }
    - { arm: codex, provider: codex, model: gpt-5.6-sol, tier: top, cost: 7, kinds: [code, review, plan, audit, fanout-class-funnel, backlog-pump], sizes: [heavy], tags: [adversarial, exhaustive], review: true, protected: true, capability: 4 }

Proven by the suite (g5): `part-B rows: code/standard -> "--model",
"gpt-5.6-luna", "--effort", "low"` and `code/heavy -> "--model",
"gpt-5.6-terra", "--effort", "high"`. After landing, `check()` (this lane's
fix) accepts sol/terra/luna and refuses astra — matrix-narrowed, correct.
Part B must ALSO adopt the planner's table (`leadv2-codex-planner.sh` still
maps every tier to astra — its own ASTRA-BUMP-01 table; the codex-task.sh
header documents that the tables are no longer identical).

## Commits on this lane

- `9401f0ff` lane anchor
- `f5ec9feb` feat: un-collapse the codex tier table (cherry-pick `-x` of A2's `f8998a4d`)
- `ee859453` fix: check() accepts every registered codex model
- (final docs commit: this report + mutation-control artifacts)

## Honesty notes

- `config/leadv2-routing.yaml`, `leadv2-dispatch-code.sh`,
  `lib/leadv2-route-arbiter.sh`, `lib/leadv2-glm-policy-resolve.py`,
  `tests/run-all.sh` were read, never edited — held by a live lane.
- Without new matrix rows the arbiter still cannot PICK sol/luna/terra by
  itself — expected; that is part B (config change, not redesign).
- A2's prior report exists at `docs/handoff/A1-CODEX-TIERS-A2/report.md` on
  the A2 branch; this lane re-ran every claim it relies on.
