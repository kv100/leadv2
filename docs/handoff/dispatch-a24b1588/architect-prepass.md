# architect — dispatch-a24b1588 (plugin follow-ups: three guards that report safety they do not provide)

Repo: `/Users/kostiantyn.vlasenko/Projects/leadv2` (plugin repo, single source).
Design only. No implementation in this deliverable.

---

## 0. Ground truth established by discovery

| Fact | Evidence |
|---|---|
| v1 path filters the ladder | `leadv2-dispatch-code.sh:3024-3025` — `_load_dispatch_ladder` then `_filter_ladder_to_dispatchable` |
| v2 path does NOT | `leadv2-dispatch-code.sh:3019-3022` — `IFS=',' read -r -a candidate_arms <<< "${v2_eligible}"`, straight from the resolver, no filter |
| Retirement is expressed as config in two places | `config/leadv2-routing.yaml:124-129` (`router.dispatch_ladder` kimi `dispatch: false`) and `:57-65` (`router_v2.arms` kimi block commented out) |
| The enforcing set | `lib/leadv2-glm-policy-resolve.py:46` → `DISPATCHABLE_BUILD_ARMS = {"glm","codex","sonnet"}` |
| v2 reads a DIFFERENT yaml key than v1 | router-v2 `filter`/`resolve` parse `router_v2.arms` (`leadv2-router-v2.sh:126-137`, `:186-192`); v1 parses `router.dispatch_ladder` (`dispatch-code.sh:840-852`) |
| **Vocabulary mismatch between the two keys** | `router_v2.arms` ids are `glm, codex, claude-haiku, claude-sonnet, claude-opus`; ladder ids are `glm, kimi, codex, sonnet, fable`. Only `glm`, `codex`, `kimi` are shared spellings. |
| Spawn cases accept only 4 ids | `dispatch-code.sh:2103 glm) · 2146 kimi) · 2181 sonnet) · 2241 codex)` |
| `ROUTING_YAML` prefers the TENANT yaml | `:304` `ROUTING_YAML="${PROJECT_ROOT}/.claude/ref/leadv2-routing.yaml"`, plugin config only as fallback (`:314`) |
| v2 is inert today only by flag | `:2944` `if [[ "${LEADV2_ROUTER_V2:-0}" == "1" ]]` |

**Therefore the real resurrection vector for Item 1 is:** a tenant
`.claude/ref/leadv2-routing.yaml` that lists `- id: kimi` under `router_v2.arms`. Canonical has it
commented out, but `ROUTING_YAML` resolves tenant-first, and v2 never cross-checks
`DISPATCHABLE_BUILD_ARMS`. This is precisely the case `_filter_ladder_to_dispatchable` was written
for on the v1 side (its own comment at `:904-907` says "stale tenant yaml"), and v2 has no
equivalent.

**Second, previously-unreported defect the same fix must not paper over:** with a *correct*
canonical yaml, v2's `eligible=` today yields `claude-sonnet` / `claude-haiku` — ids with **no spawn
case**. So the v2 path is broken independently of kimi. The design below must NOT let a naive
"intersect eligible with DISPATCHABLE_BUILD_ARMS" filter turn that into a silent empty chain
(`exit 4 all_arms_exhausted`) — that would trade a resurrection bug for a total-outage bug. A
normalization step is mandatory, not optional polish.

---

## 1. Layers affected

| Layer | File | Nature of change |
|---|---|---|
| Dispatch launcher | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | extract shared dispatchable-set reader; add v2 arm-id normalization; route v2 chain through the same filter |
| Drift suite | `plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh` | add v1/v2 cross-key divergence cases |
| New v2 selection test | `plugins/leadv2/scripts/tests/test-router-v2-retired-arm.sh` *(to-create)* | RED-first: retired arm unselectable under `LEADV2_ROUTER_V2=1` |
| Routing-enforcement suite | `plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh` | Test 6 hermeticity + full-file cwd sweep |
| Resume-sentinel suite | `plugins/leadv2/scripts/tests/test-dispatch-resume-sentinel.sh` | S7 assertion tightened |

No DB schema, no migrations, no RLS. Config files are **read-only** in this lane:
`config/leadv2-routing.yaml` and `lib/leadv2-glm-policy-resolve.py` are NOT edited — the retirement
is already correctly expressed there and the whole point is that both code paths must honour the
existing config rather than gain a new list.

---

## 2. Item 1 — route v2 arm selection through the dispatchable filter

### 2.1 Data flow (numbered, current vs designed)

Current (v2 enabled):
1. `resolve_v2_dispatch` (`:1005-1020`) → router-v2 `filter` → router-v2 `resolve` → `eligible=<csv>`
2. `:2961` `v2_eligible=$(… sed -n 's/^eligible=//p')`
3. `:3020` `candidate_arms` ← split of `v2_eligible` — **no ladder load, no dispatchable filter**
4. `_apply_kimi_admission`, quota precheck, operator exclusion, spawn loop.

Designed:
1. unchanged
2. unchanged
3. `candidate_arms` ← split of `v2_eligible`
3a. **`_normalize_v2_arms`** — map each v2 arm id to launcher vocabulary
3b. **`_filter_arms_to_dispatchable "${sig8}" router=v2`** — drop any id not in
    `DISPATCHABLE_BUILD_ARMS`, journalling each drop with the same event name v1 uses
3c. empty-after-filter → the existing `all_arms_exhausted` refusal, with
    `reason=all_arms_not_dispatchable_v2` so the journal distinguishes "quota killed everything"
    from "config vocabulary killed everything"
4. unchanged

### 2.2 Interface contracts (new/changed shell functions)

| Function | Signature | Returns / mutates | Notes |
|---|---|---|---|
| `_dispatchable_arms` | `() -> stdout: space-separated ids` | pure | **Extracted** from the body currently inlined in `_filter_ladder_to_dispatchable` (`:909-916`). Same importlib read of `DISPATCHABLE_BUILD_ARMS`, same fail-open default `"glm codex sonnet"`. Single reader — no second parser. |
| `_normalize_v2_arm` | `(<v2_arm_id>) -> stdout: launcher arm id` | pure | `claude-<m>` → `<m>`; everything else identity. Table-free prefix strip, so a future `claude-fable` needs no edit. |
| `_filter_arms_to_dispatchable` | `(<sig8> <router_label>) ; mutates candidate_arms` | in-place | Reuses `_dispatchable_arms`. Emits `arm_dropped_not_dispatchable arm=<id> task=<sig8> router=<v1\|v2> reason=not_in_DISPATCHABLE_BUILD_ARMS` per drop. |
| `_filter_ladder_to_dispatchable` | unchanged signature | in-place on `_LADDER_IDS`/`_LADDER_PROVIDERS` | **Refactored to call `_dispatchable_arms`.** Behaviour byte-identical; the existing journal line gains `router=v1` (see risk R4). |

Explicitly rejected alternative: a second hand-kept exclusion list inside the v2 branch, or adding
kimi to a `denied_arms:` key. Founder standing rule — *never hardcode an arm out of routing*. The
retirement stays a property of `DISPATCHABLE_BUILD_ARMS` + `dispatch: false`, and both paths read it.

### 2.3 Ordering constraint

`_normalize_v2_arms` MUST run before `_filter_arms_to_dispatchable` (otherwise `claude-sonnet` is
dropped as non-dispatchable) and before `_apply_kimi_admission` (which matches on the launcher's
`kimi` spelling). Both filters must run before the quota precheck at `:3103`, so a retired arm never
reaches a provider-lockout lookup and never appears in a `quota_precheck_skip` line — an arm that is
not dispatchable should not be reported as "quota-locked".

### 2.4 Test design — Item 1

**T1 (new file) `tests/test-router-v2-retired-arm.sh`** — must FAIL at HEAD.

- Builds a sandbox tenant root with `.claude/ref/leadv2-routing.yaml` that **does** list
  `- id: kimi` under `router_v2.arms` AND under `router.dispatch_ladder` without `dispatch: false`
  (the stale-tenant scenario). Sets `CLAUDE_PROJECT_ROOT` to that sandbox.
- Runs the dispatcher with `LEADV2_ROUTER_V2=1`.
- Asserts: no `candidate_chain` / spawn decision names `kimi`; a
  `arm_dropped_not_dispatchable arm=kimi … router=v2` line is present; rc is a normal dispatch rc,
  not `4` (i.e. the chain did not collapse).
- RED at HEAD because HEAD's v2 branch has no filter, so kimi survives into `candidate_arms`.

**T2** — same harness, canonical-shaped tenant yaml (`claude-sonnet` in `router_v2.arms`): assert the
chain is non-empty and contains `sonnet`. This is the guard against the naive-filter outage described
in §0. Also RED at HEAD (HEAD leaves `claude-sonnet` in the chain, which matches no spawn case).

**T3 (drift suite extension)** in `test-arm-ladder-vocabulary-drift.sh`:
- case4: every `router_v2.arms` id, after `claude-` normalization, is in `DISPATCHABLE_BUILD_ARMS`
  ∪ {non-build advisory ids}; kimi specifically absent.
- case5: **v1/v2 agreement** — the normalized dispatchable set derived from `router.dispatch_ladder`
  equals the one derived from `router_v2.arms`. A divergence between the two keys fails here, which
  is the mission's "a divergence between v1 and v2 fails a test".

### 2.5 No-live-spawn proof (mission hard requirement)

The mission cites a real incident: an unfaked routing test launched a live kimi session. The
machinery to prevent it already exists and the new test MUST adopt all of it:

1. **Poison fence preamble** — copy the block at `test-routing-enforcement-p1.sh:15-28` verbatim:
   `LEADV2_DISPATCH_GLM_BIN`, `LEADV2_DISPATCH_KIMI_BIN`, `LEADV2_DISPATCH_CODEX_BIN`,
   `LEADV2_DISPATCH_SUBSESSION_BIN` all → scripts that print `POISON:` and `exit 99`.
   Note `test-arm-ladder-vocabulary-drift.sh:28-37` sets three of the four and **omits
   `LEADV2_DISPATCH_SUBSESSION_BIN`** — the new file must not copy that gap.
2. **`LEADV2_DISPATCH_SPAWN=0`** where the test only needs chain composition, not a spawn attempt.
3. **Terminal poison-marker assertion** — mirror Test 7 (`:474-483`): grep the whole sandbox for
   `POISON:` at the end and fail if found. This is the assertion that actually *proves* the fence
   held, rather than asserting it by construction.
4. **Implementer obligation (report in the build deliverable, not assumed here):** grep every path
   from the new test to a real binary —
   `grep -n 'KIMI_BIN\|GLM_BIN\|CODEX_BIN\|SUBSESSION_BIN\|kimi-coder\|glm-coder\|codex-task' leadv2-dispatch-code.sh`
   — and show that each is env-overridable and overridden. Any hardcoded absolute path found is a
   BLOCKER to report, not to route around.

---

## 3. Item 2 — Test 6 hermeticity

### 3.1 Root cause

`dispatch-code.sh:264`:
`PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}}"`

Test 6 (`:457-462`) does `env -u CLAUDE_PROJECT_ROOT -u CLAUDE_PROJECT_DIR`, which knocks out the
first two fallbacks. `PROJECT_ROOT` is not exported by the suite, so resolution lands on
`git rev-parse --show-toplevel` **of the caller's cwd** → `:304` then points at that repo's
`.claude/ref/leadv2-routing.yaml`. Run from `/private/tmp`: no repo → degraded, PASS. Run from
persona-engine: config found → `routing_config_degraded` never emitted → FAIL. Same commit, opposite
verdict.

### 3.2 Fix

Pass `PROJECT_ROOT="${TMP_ROOT}/degraded-root"` explicitly in Test 6's `env` invocation (the
directory is created but deliberately contains no `.claude/ref/leadv2-routing.yaml`).
`LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE=/nonexistent/...` already pins the plugin side; this pins the
project side by the same principle. Note `env -u CLAUDE_PROJECT_ROOT … PROJECT_ROOT=…` is coherent —
the third fallback is consulted precisely because the first two are unset.

### 3.3 Sweep of the same file (findings, for the implementer to fix)

- **Test 5 (`:435-451`, plugin self-host)** has the identical shape: `env -u CLAUDE_PROJECT_ROOT -u
  CLAUDE_PROJECT_DIR` with no `PROJECT_ROOT` pin. Its *intent* is different — it wants
  self-host resolution from the plugin repo — but it is still cwd-dependent: run from persona-engine
  it resolves *that* repo's config and passes for the wrong reason, so it does not prove self-host
  resolution at all. **Fix: pin `PROJECT_ROOT` to a config-less sandbox root** so the only way the
  test can pass is via the plugin-preferred probe it claims to exercise. Report this as a second
  instance of the same disease, not a drive-by.
- Tests 1–4 and 8–9 all pin `CLAUDE_PROJECT_ROOT` — hermetic, no change.
- Test 7 is a sandbox grep — cwd-independent.
- The `PLUGIN_SCRIPTS`/`DISPATCH_BIN` resolution at `:5-7` is `BASH_SOURCE`-relative — correct.

### 3.4 Test design — Item 2

Demonstration harness (mission-required, and it is the acceptance surface): run
`test-routing-enforcement-p1.sh` from **at least three cwds**, one of which is a repo that HAS
`.claude/ref/leadv2-routing.yaml`:

1. `/private/tmp` (no git repo)
2. `/Users/kostiantyn.vlasenko/Projects/leadv2` (plugin repo)
3. `/Users/kostiantyn.vlasenko/Projects/persona-engine` (has a routing config) — **read-only
   traversal only; the suite writes nothing outside its own `mktemp -d`.** If persona-engine is
   unavailable, synthesise an equivalent: a scratch `git init` repo containing
   `.claude/ref/leadv2-routing.yaml`. The synthetic option is preferred — it makes the proof
   reproducible and touches no live tree.

Report the three PASS/FAIL counts before the fix (expect divergence) and after (expect identical).
That divergence-then-agreement *is* the RED-first proof for Item 2; a separate assertion file is not
needed and should not be invented.

---

## 4. Item 3 — S7 assertion + suite-count honesty

### 4.1 Fix

`test-dispatch-resume-sentinel.sh:145-148`: replace
`if [[ ${dispatch_rc} -ne 5 ]]` with `if [[ ${dispatch_rc} -eq 0 ]]`, message updated to
`S7: dispatch resumed the finalized lane (rc=0)`.

The same weak predicate appears a second time in the fallback branch at `:165-169`
(`if [[ ${dispatch_rc} -ne 5 ]]` → "placement accepted"). Tighten both, else the file still contains
a `!= 5` that can false-PASS.

RED-first proof: exit 5 covers six refusal reasons; the strengthened assertion must be shown failing
against an artificially non-zero rc (e.g. a scratch copy of the suite where the dispatcher stub exits
7) and passing against real HEAD behaviour (rc=0). This is a *test-strength* change, not a behaviour
change — the honest framing is "the assertion now matches what was observed", and the deliverable
must say so rather than dressing it as a bug fix.

### 4.2 Suite reporting obligation

Run and report ACTUAL PASS/FAIL counts for the full lane-liveness + dispatch set, not just the
changed files:

```
tests/test-lane-liveness-authoritative.sh   tests/test-lane-liveness-sentinel.sh
tests/test-dispatch-resume-sentinel.sh      tests/test-dispatch-arm-vocabulary.sh
tests/test-dispatch-silent-arm.sh           tests/test-dispatch-architect-degrades.sh
tests/test-dispatch-duplicate-caller-race.sh tests/test-dispatch-ledger-partial-close.sh
tests/test-dispatch-ledger-task-id.sh       tests/test-dispatch-product-close-exit-trap.sh
tests/test-routing-enforcement-p1.sh        tests/test-arm-ladder-vocabulary-drift.sh
tests/test-t-core-dispatch-ledger.sh        tests/test-leadv2-dispatch-outcome-ledger.sh
tests/test-fanout-lease-dispatchable.sh     tests/test-fg-dispatch-guard.sh
tests/test-leadv2-review-routing.sh
tests/test-smart-routing-v2-{t1-t3,t6,t11,t12-t13}.py
```

**Pre-existing-failure verification protocol** (the mission explicitly forbids taking the C2 claim on
authority): create a **temp worktree at the parent commit** —
`git worktree add /tmp/leadv2-parent-<sig> HEAD~1` — run
`test-lane-liveness-authoritative.sh` there, and quote the C2 line verbatim from both runs. Never
`git stash` / `reset --hard` / `clean`; never move a branch backwards. Remove the worktree when done.

**C2 own-task question:** the deliverable must answer it with evidence in hand. The architect's
position, to be confirmed or overturned by the observed output: C2 ("live PID with no artifact floors
to silent, not dead") is a liveness-classification defect independent of every mechanism in this
lane, and fixing it here would mix an unrelated behaviour change into a test-hardening lane whose
whole premise is that weak guards hide real state. **Recommend: separate task, filed in
`docs/leadv2/open-threads.md`, not fixed here** — unless the run shows C2 failing *because* of a
change made in this lane, in which case it is this lane's regression and must be fixed here.

---

## 5. RED-first proof mechanism (all items)

Mission forbids `git stash` / `reset --hard` / `clean` (shared trees). Use:

```
git worktree add /tmp/leadv2-head-<sig> HEAD      # pristine HEAD, no index mutation
```

Copy each new/changed test file into the worktree, run it there → expect FAIL. Run in the lane after
the fix → expect PASS. Show both verbatim. `git worktree remove` at the end. This satisfies "prove
FAIL-against-HEAD with a scratch copy or a temp worktree".

---

## 6. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Naive filter empties the v2 chain.** Canonical `router_v2.arms` yields `claude-sonnet`/`claude-haiku`, none in `DISPATCHABLE_BUILD_ARMS` → filter drops everything → `exit 4 all_arms_exhausted` on every v2 dispatch. A resurrection bug traded for an outage bug. | `_normalize_v2_arm` runs first (§2.2). T2 (§2.4) asserts non-empty chain containing `sonnet` and fails if this regresses. |
| R2 | **`claude-haiku`/`claude-opus` normalize to ids with no spawn case** (`haiku`, `opus`). `opus` is intercepted earlier at `:2986` (`arm == opus` → parked, exit 3); `haiku` is not, and would fall through the spawn `case` silently. | In scope only as far as the filter is concerned: `haiku` ∉ `DISPATCHABLE_BUILD_ARMS`, so the new filter drops it and journals the drop — a strict improvement. Do **not** add a haiku spawn case in this lane; note it as a follow-up thread. |
| R3 | **Both drops journal under the same event name**, so a lead reading the journal cannot tell v1 from v2. | `router=v1\|v2` field added to `arm_dropped_not_dispatchable`. Additive field; no consumer parses positionally (verify with a grep for `arm_dropped_not_dispatchable` across `scripts/` before landing). |
| R4 | **Refactoring `_filter_ladder_to_dispatchable` changes v1 behaviour.** | The extraction is mechanical: same importlib invocation, same fail-open default string. Existing Test 8 (`p1:485-504`) asserts v1's chain is exactly `glm,codex,sonnet` and is the regression guard. Run it before and after the refactor. |
| R5 | **A test spawns a real provider session** (the documented prior incident). | Four-layer fence, §2.5, including the terminal `POISON:` grep — assertion, not construction. |
| R6 | **Test 5's fix changes what it proves.** Pinning `PROJECT_ROOT` to a config-less root could make Test 5 fail if plugin-preferred resolution is weaker than assumed. | That would be a *true* finding, not a broken test. If Test 5 goes red after pinning, report it as a discovered defect and stop — do not weaken the pin to make it green. |
| R7 | **Running the suite from inside persona-engine touches a live tree.** | Prefer the synthetic `git init` repo (§3.4); if persona-engine is used, it is cwd only — the suite's writes are confined to its own `mktemp -d`, verified by reading the `TMP_ROOT` trap at `p1:9-10`. |
| R8 | **A parallel session edits `leadv2-dispatch-code.sh`.** | `git diff <file>` immediately before `git add` (global rule), not earlier in the turn. |
| R9 | **`_filter_arms_to_dispatchable` fail-open default masks a broken resolver import.** | Keep the existing fail-open (never fail closed on config read), but emit a distinct journal line when the importlib read fails so the fallback is visible rather than silent. |

## 6b. Mandatory constraint checklist

1. **Env var naming** — all vars referenced are existing `LEADV2_*` (`LEADV2_ROUTER_V2`,
   `LEADV2_DISPATCH_{GLM,KIMI,CODEX,SUBSESSION}_BIN`, `LEADV2_DISPATCH_SPAWN`,
   `LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE`, `LEADV2_QUOTA_LOCKOUT_DIR`, `LEADV2_DISPATCH_CACHE_DIR`,
   `LEADV2_DISPATCH_ARCHITECT_GATE`). **No new env var is introduced.** `PROJECT_ROOT` /
   `CLAUDE_PROJECT_ROOT` are pre-existing, non-`LEADV2_` by design (`dispatch-code.sh:264`) — not
   drift. PASS.
2. **File paths** — every path in §1 verified on disk except
   `tests/test-router-v2-retired-arm.sh` **(to-create)**. PASS.
3. **`claude -p` commands** — this lane introduces none. N/A.
4. **Concurrent access** — no two steps in this plan write the same file. `dispatch-code.sh` is
   touched by Item 1 only. R8 covers the cross-session case.
5. **Config contradiction** — no env var semantics changed. The one contradiction *found* is a data
   contradiction, not a config one: `router.dispatch_ladder` and `router_v2.arms` are two
   independently-maintained arm registries with different id vocabularies and no consistency check.
   Flagged **CRITICAL**; drift case5 (§2.4 T3) is the proposed guard. A full unification of the two
   keys into one registry is larger than this lane and belongs in its own task.

### decisions[] (source: architect(self-check))
- `two_arm_registries_no_consistency_check` — CRITICAL. `router.dispatch_ladder` vs
  `router_v2.arms`. Mitigation in-lane: drift case5. Full unification: separate task.
- `v2_arm_ids_have_no_spawn_case` — HIGH. `claude-sonnet`/`claude-haiku` cannot spawn. In-lane
  mitigation: normalization + filter. Follow-up thread for `haiku`.
- `test5_same_cwd_defect_as_test6` — MEDIUM. Fix in-lane (mission's "sweep the rest of that file").

---

## 7. Out of scope (implementer: do not do these)

- Fixing `test-lane-liveness-authoritative.sh` C2 — make it visible, do not fix.
- Editing `config/leadv2-routing.yaml` or `lib/leadv2-glm-policy-resolve.py`. The retirement is
  already correctly expressed; the bug is that one code path does not read it.
- Adding a `haiku` spawn case, or any other new arm.
- Unifying `router.dispatch_ladder` and `router_v2.arms` into one registry.
- Enabling `LEADV2_ROUTER_V2` by default. It stays `0`; this lane makes it *safe* to enable, not
  enabled.
- Any change to `.claude/scripts/tests/` (the stale duplicate tree — separate open thread).
- Touching persona-engine or any other consuming repo.

---

## 8. Acceptance

acceptance:
- surface: log_line
  observable: In the dispatch decision journal for a run made with LEADV2_ROUTER_V2=1 against a
    project whose .claude/ref/leadv2-routing.yaml still lists kimi, a human reads a line naming
    kimi as dropped for not being dispatchable, and finds no later line in that run's journal
    naming kimi as a selected or spawned arm.
  authored_at: 2026-08-06T00:00:00Z
- surface: log_line
  observable: In that same journal, the candidate chain line a human reads names sonnet and does
    not name claude-sonnet, and the run does not end with an all-arms-exhausted refusal.
  authored_at: 2026-08-06T00:00:00Z
- surface: rendered_line
  observable: The final summary line printed by test-routing-enforcement-p1.sh reads the same
    pass/fail totals when a human runs it from an empty temp directory, from the plugin repo, and
    from a repository that contains its own routing config.
  authored_at: 2026-08-06T00:00:00Z
- surface: rendered_line
  observable: The S7 line printed by test-dispatch-resume-sentinel.sh states that the dispatch
    resumed the finalized lane and names the exit code it saw as zero, rather than stating only
    that the exit code was not five.
  authored_at: 2026-08-06T00:00:00Z
- surface: file_artifact
  observable: The lane's returned report lists, for every suite in the lane-liveness and dispatch
    set, its own pass and fail totals from before and after the change, and names each failure
    that a human can also see failing in a worktree checked out at the parent commit.
  authored_at: 2026-08-06T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-router-v2-retired-arm.sh, plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh, plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh, plugins/leadv2/scripts/tests/test-dispatch-resume-sentinel.sh

DELIVERABLE_COMPLETE
