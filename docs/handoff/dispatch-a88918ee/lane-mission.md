Product implementation task dispatch-a88918ee. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# ONE-PATH-PLAN-RUN-01 — architect prepass (scoped implementation design)

Task: `dispatch-a88918ee-architect` · Role: architect · Date: 2026-08-12
Mode: design only. No executable code written by this pass.

Inputs actually read (all verified present on disk):

| Input | Status |
|---|---|
| `docs/handoff/one-review-path-2026-08-06/design-plan-diagnose.md` (581 lines) | read in full — authoritative |
| `plugins/leadv2/scripts/leadv2-review-run.sh` (34 629 B) | read §1–§7 headers + arm/fan-out/gate regions |
| `plugins/leadv2/scripts/leadv2-acceptance-shape.sh` (header §SUBCOMMANDS, 1–45) | read |
| `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:47,675` | `DISPATCHABLE_BUILD_ARMS = {"glm","codex","sonnet"}` |
| `plugins/leadv2/hooks/leadv2-workflow-bypass-guard.sh:1–60` | read — plan branch is a declared hard scope fence |
| `git show --stat 43a634e` | the "nothing stranded" precedent for review |
| `docs/handoff/dispatch-a88918ee-architect/context.yaml` | **absent** — no lane-supplied `decisions`/`off_limits`; off-limits taken from the mission text |

---

## 0. Three conflicts between the mission and the authoritative design — resolved here, flag to lead

These are stated up front because each changes what the implementer writes.

### C1 — `glm` in the planner pool (CRITICAL, config contradiction)

The mission scope line 1 says the planner arm pool is *"codex … ; glm; sonnet; opus for Heavy/arch"*.
The authoritative design says the opposite in two places:

- §1.2: *"GLM/Kimi are build-only and never admitted to a planning role"* (PLANNER-MODELS-DECISION-01);
- §6 test 6: `test-plan-arms-role-scoped.sh` — *"assert `DISPATCHABLE_PLAN_ARMS` excludes `glm` and `kimi`"*.

**Resolution taken: the design wins.** `DISPATCHABLE_PLAN_ARMS = {"codex", "sonnet", "opus", "fable"}`.
Reasons: (a) the mission itself names the design as authoritative; (b) PLANNER-MODELS-DECISION-01 is a
recorded governance decision, and the mission line is prose; (c) design test 6 is one of the thirteen
the mission orders satisfied, and it cannot be satisfied under the mission's reading — the two
instructions are not jointly implementable. If the lead intends to reverse PLANNER-MODELS-DECISION-01,
that is a governance change and belongs in its own lane, not silently inside this engine.

### C2 — flag name: `LEADV2_PLAN_RUN` (design §5.1) vs the shipped `LEADV2_REVIEW_ENGINE` convention

Design §5.1 predates the shipped review engine. The shipped engine's flag is `LEADV2_REVIEW_ENGINE`
(`leadv2-review-run.sh:24`, `hooks/leadv2-workflow-bypass-guard.sh:43`).

**Resolution taken:** `LEADV2_PLAN_ENGINE` / `LEADV2_DIAGNOSE_ENGINE`, both default `0`, mirroring the
review name exactly. Documented in the engine header as a deliberate deviation from design §5.1.
Both keep the `LEADV2_*` prefix — no `LEAD_V2_*` variant introduced. (`LEAD_V2_TASK_ID` /
`LEAD_V2_COMMIT` / `LEAD_V2_STATE` do exist at `leadv2-deploy-merge.sh:149,169` and
`leadv2-rag-intake.sh:2,7,21` — **pre-existing, untouched, not extended by this lane.**)

There is no `.claude/settings.json` in this repo (checked — the path does not exist here; it is a
per-project artifact, not a plugin-repo one). Design §5.1's "add both flags to the `env` block"
therefore has **no target in this lane** and is dropped from `LANE_WRITES`. It belongs to the
per-project rollout lane.

### C3 — thirteen tests vs the mission's own off-limits

The mission puts `leadv2-dispatch-code.sh` and the other dispatch scripts off-limits, and defers the
doc flip. Design tests 1, 2, 3 target `_acceptance_guard` **inside `leadv2-dispatch-code.sh`**; test 9
needs the lane call site; tests 11 and 13 need `skills/leadv2-iterative-recovery/SKILL.md` and
`leadv2-task-judge.sh`. Those five cannot be written against the lane in this lane.

**Resolution taken:** tests 1–3 are written, but **re-pointed at the engine's own acceptance path** —
the same three malformed inputs (empty `observable`, multi-line block scalar hiding internal-contract
phrasing, `acceptance:` present only inside a fenced block) are fed to `leadv2-plan-run.sh` and must be
refused. That is the real invariant those three tests exist to protect, and it is fully testable here.
Tests 9, 11, 13 are **explicitly deferred** to the wiring lane and named as such in §7 — not silently
dropped. Section 7 lists exactly which of the thirteen this lane closes and which it does not.

---

## 1. Layers affected

| Layer | Change |
|---|---|
| `plugins/leadv2/scripts/` | **new** sole-owner engine `leadv2-plan-run.sh` |
| `plugins/leadv2/scripts/lib/` | **new** `leadv2-context-merge.py` (deterministic-field merge + `REQUIRED_FIELDS` check); **edit** `leadv2-glm-policy-resolve.py` (+`DISPATCHABLE_PLAN_ARMS`, `--job plan` role scoping) |
| `plugins/leadv2/scripts/tests/` | **new** suites (§7) |
| `plugins/leadv2/workflows/leadv2-plan.js` | **untouched this lane** (mission item 5) |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | **untouched this lane** (off-limits; design step 3) |
| `plugins/leadv2/scripts/leadv2-codex-planner.sh` | **untouched** — called as an arm, read-only reference |
| `plugins/leadv2/scripts/leadv2-acceptance-shape.sh` | **untouched** — called as the single validator |

Nothing outside `plugins/leadv2/` changes. No Supabase / Qdrant / Next.js surface is involved.

---

## 2. Interface

```
leadv2-plan-run.sh --task <sig8> --root <repo-root> --handoff <dir>
                   --mode <prepass|plan|diagnose>
                   (--mission "<text>" | --mission-file <path>)
                   [--writes <csv>] [--class <trivial|light|standard|heavy>]
                   [--fanout <n>]                       # default 2 (architect + critic)
                   [--log-path <file>] [--diff-paths <str>]   # diagnose only
                   [--timeout-sec <n>] [--no-cache]
```

Arg names `--task / --root / --handoff` mirror `leadv2-review-run.sh:37-47` verbatim rather than the
design's `--task-id`, so a caller that already builds a review-engine invocation builds this one the
same way. `--task-id` is accepted as a silent alias for `--task` because `leadv2-codex-planner.sh`
uses that spelling and the recovery skill's contract (`SKILL.md:45`) already types it.

Termination: `0` produced · `1` refused/park (reason on stderr **and** in `plan-gate.md`) ·
`2` usage · `4` config error. Same four-value scheme as design §3.1.

`--mission-file` is read into memory **before** any arm dispatch (P3's race protection,
`leadv2-codex-planner.sh:178`); `--mission` and `--mission-file` are mutually exclusive.

---

## 3. Data flow (numbered)

1. **Parse + validate args.** Missing required arg → usage, `2`. `mkdir -p "${HANDOFF}"`.
2. **Engine-local `emit()`** — stderr-only logger, `[leadv2-plan-run] <verb> <kv...>`. The engine
   **never** calls the lane's journal `emit`, never sources `leadv2-dispatch-product-close.sh`, and
   never sources `leadv2-dispatch-code.sh`. This is what makes it callable from a bare Codex- or
   GLM-led bash session with none of the lane's helpers loaded (the `OWNERSHIP` note at
   `leadv2-review-run.sh:11-16`, carried over verbatim in spirit).
3. **Cache probe** (`prepass`/`plan` only; skipped under `--no-cache` or `LEADV2_PREPASS_CACHE=0`).
   `sig = compute_sig(full mission text)`; compare against `<handoff>/context.yaml.sig`.
   **H4 carried over:** a cached `context.yaml` that does not pass `leadv2-acceptance-shape.sh validate`
   is a **miss**, not a hit — the plan-mode analogue of "a cached artifact carrying no `LANE_WRITES:`
   line is a miss". Hit → `emit decision "plan_run task=<sig8> status=cached mode=<m>"`, write a
   `status: pass / reason: cached` gate, terminate `0`. Miss → `status=cache_miss`, continue.
4. **`provably_one_file` skip** — carried over from `architect_prepass` (design §3.2.4): when
   `--writes` holds exactly one non-empty entry **and** `--mode prepass`, skip the arm work and stamp
   `status=skipped reason=provably_one_file`. Does **not** apply to `--mode plan` (Phase 2 owes a
   `context.yaml` regardless of write breadth) and not to `--mode diagnose`.
5. **Kill switch** — `LEADV2_ARCHITECT_GATE=0` (existing name, unchanged semantics) yields
   `status=disabled`. **It cannot bypass lane isolation** — the H6 fix at
   `leadv2-dispatch-code.sh:1855-1863` is carried over: when a lane worktree exists, the gate still runs.
6. **Skeleton write (deterministic, engine-owned).** The engine — not any model — writes
   `<handoff>/context.yaml` containing `id`, `mission`, `reads`, `writes`, `lane_writes`, and
   `acceptance.authored_at` stamped from the clock **now**, before any arm is dispatched. This is the
   load-bearing inversion of today's arrangement (design §3.2.1) and the reason design §7.2's last
   bullet holds: `assert-precedence` compares `authored_at` against file mtimes, so a model-authored
   timestamp is exactly what that check exists to distrust.
7. **Pool resolution.** `resolve_plan_pool_call()`, structurally identical to
   `resolve_review_pool_call()` (`leadv2-review-run.sh:71-110`): same resolver discovery order
   (`$LEADV2_GLM_POLICY_RESOLVER` → `${SCRIPT_DIR}/lib/…` → `${LEADV2_CANONICAL_ROOT}` fallback), same
   fail-closed strings on a missing or erroring resolver (`refusal=resolver_missing_failclosed` /
   `resolver_error_failclosed`), same `--quota-live` pass-through. Two differences and no others:
   `--job plan` instead of `--job review`, and the resolver filters against `DISPATCHABLE_PLAN_ARMS`.
   The engine does **not** re-derive quota; it reads the resolver's `pool=` line.
8. **Arm chain.** `_engine_pool_ok_arms` (deduped, `leadv2-review-run.sh:359-372`) yields the ordered
   `:ok:` arms. `next_ok_arm_after` advances on refusal. **No arm is ever named in or out at a call
   site** — set membership decides, per design §3.2.3.
9. **Fan-out — architect pass, then critic pass.** `--fanout` (default 2):
   - **Pass A (architect)** on `arm[0]`: given the mission + context envelope, produces
     `<handoff>/plan-arm-<arm>.yaml` holding **only** the judgment fields —
     `decisions[]`, `off_limits[]`, `plan.steps[]`, `acceptance.surface`, `acceptance.observable`, `risk`.
     The prompt states explicitly that `id`, `mission`, `reads`, `writes`, `lane_writes` and
     `acceptance.authored_at` are engine-owned and any value the arm emits for them is discarded.
   - **Pass B (critic)** on `next_ok_arm_after(arm[0])` — a *different* arm where the pool allows,
     falling back to the same arm with a critic framing when the pool holds one entry: reads pass A's
     draft and emits `PLAN_FINDING:` lines plus a revised judgment block. Passes are **sequential**,
     not parallel: B reads A. (This is the one deliberate divergence from the review engine's parallel
     fan-out, and it is forced by the dependency, not by preference.)
   - Both passes run under `_engine_run_arm_with_timeout` — the bash-3.2-safe watcher-subshell pattern
     at `leadv2-review-run.sh:387-397`, **not** GNU `timeout` (absent on macOS).
     `LEADV2_PLAN_ARM_TIMEOUT_S`, default `900`.
10. **Arm implementations** (`run_planner_arm <arm> <role>`), one branch each, mirroring
    `run_reviewer_arm` (`leadv2-review-run.sh:241-297`):
    - `codex` → `bash leadv2-codex-planner.sh --task-id <id> --mode <plan|diagnose> --tier <resolved>`
      (+`--reason` whenever the resolved tier is `top`, per CODEX-QUOTA-GUARDRAILS-01). Tier
      resolution, the spark ban, and the `codex_enabled:false` short-circuit stay **inside**
      codex-planner.sh; the engine neither reimplements nor second-guesses them.
    - `sonnet` / `opus` / `fable` → `claude-subsession.sh --role <architect|critic> --model <arm>
      --task-id <id> --mission-file <f> --wait`. **Never a bare `claude -p`** — that combination needs
      `--verbose` or the process dies instantly (`leadv2-review-run.sh:286-288`). See §8 item 3.
    - Output is read from the artifact **on disk**, never from captured stdout. Read order
      `plan-arm-<arm>.yaml` → `architect.full.md` → `architect.md` → `architect.summary.md`, carrying
      the 2026-07-29 incident fix where a `2>&1` capture wrote log metadata over a correct 21 KB design.
11. **Failure classification.** `classify_arm_failure` lifted verbatim
    (`leadv2-review-run.sh:302-335`): `rc=77 → refused_channel_down`; a
    `LEADV2_DISPATCH_REFUSED:` marker with rc∈{1,2,75} → `refused_peak_hours` / `refused_quota`;
    `[glm-quota-gate] REROUTE` → `refused_quota`; `rc=75 → refused_quota`; else `ran`.
    **One addition:** stdout containing `codex_skipped_by_policy` with rc `0` →
    `arm_unavailable`. The engine emits
    `plan_run arm_unavailable arm=codex reason=policy task=<sig8>` and advances the chain.
    It is **not** an error and **not** a park (design §3.4, §5.3). Nothing anywhere hardcodes
    "m3-market has no codex" — the fact is learned from the policy file through the arm's own exit,
    at run time.
12. **Merge (deterministic).** `python3 lib/leadv2-context-merge.py --skeleton <ctx> --arm
    <plan-arm-*.yaml>… --out <ctx>.tmp` folds judgment fields into the skeleton with **engine-owned
    keys always winning**, then checks `REQUIRED_FIELDS = [id, mission, reads, writes, acceptance,
    decisions, off_limits, plan]` (design §3.2.5 / `leadv2-plan.js:402`) — **in code, not in model
    judgment**. `mv -f` for atomicity.
13. **Validate.** `leadv2-acceptance-shape.sh validate <handoff>/context.yaml` — the **real**
    validator, no second heuristic anywhere in this engine (design §7.2). Then
    `assert-precedence --task-id <id>` whenever `lane_writes` names at least one file that exists.
    `LEADV2_REQUIRE_ACCEPTANCE=0` makes a failing verdict non-blocking; the validator always evaluates
    and always reports its true verdict, per its own header at `leadv2-acceptance-shape.sh:33-37`.
14. **Exactly one retry** on a `REQUIRED_FIELDS` or `validate` failure (design §3.2.5): re-dispatch
    pass A on the next `:ok:` arm with the concrete failure reasons appended to the prompt,
    `emit … status=retrying`, then re-run steps 12–13. A second failure is terminal — `fail`, never a
    third attempt.
15. **Gate write** — §4.
16. **Diagnose deltas only** (`--mode diagnose`). Same steps 1–2, 7–11, 15. Differences:
    no `acceptance:` block, no `LANE_WRITES`, no `context.yaml`, no cache; input assembly reads
    `--log-path` (`tail -100`, bounded exactly as `leadv2-codex-planner.sh:224`) and `--diff-paths`;
    output artifact is `<handoff>/root-cause.md` carrying `root_cause`, `confidence`,
    `evidence_files`, `fix_hint`, `alternates` (D1's schema); journal verb is `diagnose_run`;
    validation is presence-and-non-empty of `root_cause` + `confidence`, since the acceptance
    validator has nothing to validate against a hypothesis. **No persona-engine constants** — no
    `journalctl -u persona-engine` default, no PE table names; when `--log-path` is absent the prompt
    simply carries no log section (design §2.1's portability defect, closed by construction).

---

## 4. Contract — `plan-gate.md`

Written to `<handoff>/plan-gate.md` via `.tmp` + `mv -f` (atomic), by the same write-race discipline
the review engine documents at `leadv2-review-run.sh:4-9`. The engine writes it on **every**
termination path including refusals — a run that produced no gate file is itself a detectable defect.

```
status: pass|fail|blocked
reason: <token>
mode: prepass|plan|diagnose
arm: <arm|->
artifact: docs/handoff/<id>/context.yaml        # root-cause.md in diagnose mode
```

| status | reason tokens | meaning |
|---|---|---|
| `pass` | `validated`, `cached`, `skipped_one_file`, `disabled` | the artifact exists and cleared validation |
| `fail` | `acceptance_invalid`, `required_fields_missing` | an artifact exists and is wrong, after the one retry |
| `blocked` | `provider_error`, `empty_response`, `all_arms_unavailable`, `plan_body_lost`, `resolver_missing_failclosed`, `resolver_error_failclosed` | no trustworthy artifact — **never a silent pass** |

The three blocked-branch semantics are lifted from the review engine's own gate writes so the two
gates read the same way: `plan_body_lost` mirrors `review_body_lost`
(`leadv2-review-run.sh:560-562` — an arm terminated cleanly but its artifact body was lost);
`provider_error` mirrors `:598`; `empty_response` mirrors `:601`.
**The rule the mission names explicitly holds by construction: a `provider_error` or an
`empty_response` can only ever produce `blocked`. There is no code path from either to `pass`.**

The lead reads `plan-gate.md` and `context.yaml`, and nothing else the engine writes. Every
`plan-arm-*.yaml`, `.err`, `.rc` and `.sig` is engine-internal scratch.

Journal vocabulary (stderr, `emit decision`), the full `architect_prepass` set carried over:

```
plan_run task=<sig8> status={ran,skipped,disabled,cached,cache_miss,failed,retrying,parked} mode=<m> arm=<a>
plan_run arm_unavailable arm=<a> reason={policy,quota,peak_hours,channel_down} task=<sig8>
plan_gate task=<sig8> status={pass,fail,blocked} reason=<token>
diagnose_run …   # same three shapes, diagnose verb
```

---

## 5. `DISPATCHABLE_PLAN_ARMS` — the one resolver change

`lib/leadv2-glm-policy-resolve.py:47` today:

```python
DISPATCHABLE_BUILD_ARMS = {"glm", "codex", "sonnet"}
```

Add, adjacent, with the governance reference in a comment:

```python
# PLANNER-MODELS-DECISION-01: glm and kimi are build-only and are never admitted
# to a planning role. Role decides the SET; the ladder still decides the ORDER.
DISPATCHABLE_PLAN_ARMS = {"codex", "sonnet", "opus", "fable"}
```

and role-scope the single membership test at `:675` on `--job`. The ladder remains the one source of
order; quota, task and complexity still decide the pick. This is a **new set**, not a new mechanism —
design §7.1's third bullet.

Drift risk: `tests/test-arm-ladder-vocabulary-drift.sh` asserts the build set against the legacy
fallback `(glm codex sonnet)` at `leadv2-dispatch-code.sh:861-869`. That assertion must keep passing
untouched; the new test asserts the plan set **by reading the resolver**, never against a literal list
copied into the test (design §6 test 6, explicit on this point).

---

## 6. Sequencing

This lane is design step 1 only, and it is unblocked today (design §4): it creates a new file, adds one
symbol to the resolver, and adds tests. It touches `leadv2-dispatch-code.sh` **zero** times, so it
cannot collide with the review lane, and it cannot break a mid-flight lane because nothing calls it yet.

Deferred, each to its own lane, in this order: step 3 (swap the two `dispatch-code.sh` function bodies
behind `LEADV2_PLAN_ENGINE`, serialized behind the review lane's merge — and `git diff` that file
immediately before staging, because a concurrent session in this repo can write it from its own state);
step 4 (`leadv2-plan.js` / `leadv2-diagnose.js` → shims, then deletion + `phases.md §Phase 2` +
`commands/leadv2.md` flip); step 0 (`~/.claude/workflows/` copies → symlinks).

---

## 7. Tests

New suite `tests/test-plan-run-engine.sh` (assertions 1–7, 10, 12 below) plus the two standalone
suites named in the design. Every assertion fails against current `HEAD`.

| # (design) | Assertion | Closed here? |
|---|---|---|
| 1 | `observable:` empty and `authored_at: yesterday` → engine refuses, `plan-gate.md` reads `status: blocked` / `reason: acceptance_invalid` | ✅ re-pointed at the engine (C3) |
| 2 | `observable:` as a multi-line block scalar whose 2nd line reads `the function returns 0` → refused | ✅ re-pointed |
| 3 | `acceptance:` + a valid `surface:` present **only** inside a fenced markdown block → refused | ✅ re-pointed |
| 4 | after a successful `--mode prepass`, `docs/handoff/dispatch-<sig8>/context.yaml` exists and `leadv2-acceptance-shape.sh validate` clears it | ✅ |
| 5 | `--mode plan` from a bare bash environment with Workflow/Agent tools unavailable produces a valid `context.yaml` | ✅ |
| 6 | `DISPATCHABLE_PLAN_ARMS` excludes `glm`+`kimi`, includes `codex`+`sonnet`; asserted **by reading the resolver** | ✅ `test-plan-arms-role-scoped.sh` |
| 7 | `codex_enabled: false` → `--mode plan` still produces a valid `context.yaml`, journals `arm_unavailable arm=codex reason=policy`, no `status=failed` and no `status=parked` line | ✅ `test-plan-run-codex-disabled-degrades.sh` |
| 8 | `~/.claude/workflows/leadv2-{plan,diagnose}.js` are symlinks into `plugins/leadv2/workflows/` | ⚠️ written; target is **outside this repo** (`$HOME`) and the fix is design step 0 — see decision D3 |
| 9 | `LEADV2_PLAN_ENGINE=0` → dispatch journal lines byte-identical to pre-change `HEAD` | ❌ **deferred** — needs the `dispatch-code.sh` call site (off-limits here) |
| 10 | `--mode diagnose` against a non-persona-engine `LEADV2_PROJECT_ROOT`: the assembled prompt contains neither `journalctl -u persona-engine` nor PE table names | ✅ |
| 11 | no file outside the engine invokes `--mode diagnose` directly; `leadv2-iterative-recovery/SKILL.md` routes through the engine | ❌ **deferred** — editing that SKILL.md is the wiring lane |
| 12 | `codex_enabled: false` → `--mode diagnose` degrades the same way (`diagnose_run` verbs, `root-cause.md`) | ✅ |
| 13 | a brief classified `work_kind=diagnose` by `leadv2-task-judge.sh:120-125` reaches the diagnose engine | ❌ **deferred** — needs a `leadv2-task-judge.sh` consumer |

**Nothing stranded (the 43a634e precedent).** 43a634e deleted `workflows/leadv2-review.js` and in the
same commit re-pointed `test-leadv2-review-routing.sh`, `test-review-single-owner-census.sh`,
`test-codex-doc-pointer.sh` and `test-leadv2-phase8-learn-counter.sh` at the engine. Here,
`leadv2-plan.js` **survives** (mission item 5), so its existing assertions stay valid and must **not**
be re-pointed yet. Two suites reference it and both are handled:

- `tests/test-leadv2-codemap.sh:37,115-121` — pins `WORKFLOW_JS=…/workflows/leadv2-plan.js` and runs a
  pre-diff golden against `git show HEAD:…`. **Unchanged.** Equivalent code_map assertions (flag-off
  no-op; 2000-char cap *including* the truncation note) are **added** to
  `test-plan-run-engine.sh` against the engine. When the follow-up lane deletes the JS, that suite's
  JS half is deleted and its engine half already exists — that is what keeps it from stranding.
- `tests/test-leadv2-phase8-learn-counter.sh:262` — a comment naming plan.js among JS consumers. No
  code dependency. No change.

Run command for the whole set: `bash plugins/leadv2/scripts/tests/test-plan-run-engine.sh` and the
four standalone suites, each independently.

---

## 8. Mandatory constraint checklist

1. **Env var naming — PASS.** New names `LEADV2_PLAN_ENGINE`, `LEADV2_DIAGNOSE_ENGINE`,
   `LEADV2_PLAN_ARM_TIMEOUT_S`, `LEADV2_PLAN_FANOUT`; reused unchanged: `LEADV2_REQUIRE_ACCEPTANCE`,
   `LEADV2_REQUIRE_LANE_WRITES`, `LEADV2_ARCHITECT_GATE`, `LEADV2_PREPASS_CACHE`,
   `LEADV2_GLM_POLICY_RESOLVER`, `LEADV2_ROUTING_YAML`, `LEADV2_CANONICAL_ROOT`,
   `LEADV2_PROJECT_ROOT`, `GLM_POLICY_QUOTA_LIVE`. All `LEADV2_*`. Pre-existing `LEAD_V2_*` at
   `leadv2-deploy-merge.sh:149,169` and `leadv2-rag-intake.sh:2,7,21` is untouched and not extended.
   No `.claude/settings.json` exists in this repo, so design §5.1's env-block sync has no target here
   — flagged, not silently skipped (C2).
2. **File paths — PASS.** Verified present: `leadv2-review-run.sh`, `leadv2-codex-planner.sh`,
   `leadv2-acceptance-shape.sh`, `lib/leadv2-glm-policy-resolve.py`, `workflows/leadv2-plan.js`,
   `hooks/leadv2-workflow-bypass-guard.sh`, `tests/test-leadv2-codemap.sh`,
   `tests/test-leadv2-phase8-learn-counter.sh`, `tests/test-arm-ladder-vocabulary-drift.sh`.
   Marked `(to-create)`: `leadv2-plan-run.sh`, `lib/leadv2-context-merge.py`, all new `tests/…`.
   Verified **absent** and named as such: `docs/handoff/dispatch-a88918ee-architect/context.yaml`,
   `.claude/settings.json`.
3. **`claude -p` — PASS by construction, and it is a CRITICAL invariant.** The engine issues **no**
   `claude -p` anywhere; model arms go through `claude-subsession.sh --wait`, which owns the flag set.
   A bare `claude -p` without `--verbose` dies instantly (`leadv2-review-run.sh:286-288`).
   **If the implementer adds a direct `claude -p` to this engine, that is a CRITICAL review finding**
   and it must instead carry `--max-turns`, `--permission-mode bypassPermissions`,
   `--output-format json`.
4. **Concurrent access — three race surfaces, each with an ordering constraint.**
   - `<handoff>/context.yaml`: written by the engine (step 6 skeleton, step 12 merge) and, until the
     follow-up lane lands, potentially by `leadv2-plan.js` for the same task. Both must use
     `.tmp` + `mv -f`. Constraint: **never both engines on one `task-id`** — enforced by
     `LEADV2_PLAN_ENGINE` being the single switch, and by the JS shim (follow-up lane) delegating
     rather than writing.
   - `<handoff>/plan-gate.md`: single writer, this engine, `.tmp` + `mv -f`.
   - `<handoff>/plan-arm-<arm>.yaml` / `.err` / `.rc`: keyed by arm name, which is unique per fan-out
     by the `_engine_pool_ok_arms` dedup — the identical A4 guard the review engine documents at
     `leadv2-review-run.sh:236-239`. Passes A and B are sequential, so even a one-arm pool cannot
     collide (B writes `plan-arm-<arm>-critic.yaml`).
5. **Config contradiction — one CRITICAL (C1, `glm` in the planner pool: mission prose vs
   PLANNER-MODELS-DECISION-01 + design test 6, resolved in favour of the design) and one advisory
   (C2, flag naming).** Grepped: `DISPATCHABLE_` appears only at
   `lib/leadv2-glm-policy-resolve.py:47,675` — the new set is additive and cannot change build-arm
   semantics. `LEADV2_REVIEW_ENGINE` is read at `leadv2-review-run.sh:24`,
   `hooks/leadv2-workflow-bypass-guard.sh:43`, `docs/phases.md:275,313` — the plan flag is a distinct
   name and does not overload it.

---

## 9. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | A model stamps `acceptance.authored_at` itself, defeating `assert-precedence` | Engine stamps it deterministically at skeleton write (step 6), **before** any arm runs; the merge helper discards any arm-supplied value. Design §7.2, last bullet. |
| R2 | A `provider_error` or empty artifact silently reads as `pass` — the exact failure this lane exists to prevent | The gate writer has **no** path from either token to `pass` (§4); the blocked branches are lifted from the review engine's shipped ones. Asserted by test 1. |
| R3 | The cache pins a bad `context.yaml` forever | Validate-before-cache: a cached artifact that fails `validate` is a **miss** (step 3, the H4 analogue). M7 also carried over — a park stamps the sig so a byte-identical retry does not pay the arm twice. |
| R4 | A second acceptance heuristic grows inside the engine and drifts from `leadv2-acceptance-shape.sh` | The engine shells out to that script and holds **no** `grep -q '^acceptance:'` chain of its own. Design §7.2. A grep chain in review = a finding. |
| R5 | Two lanes write `leadv2-dispatch-code.sh` and one silently reverts the other | This lane does not touch that file at all. The deferred step-3 lane re-diffs immediately before staging (§6). |
| R6 | `hooks/leadv2-workflow-bypass-guard.sh`'s plan branch denies an architect spawn when the lead calls the engine instead of the Workflow (the `.workflow-called-plan` sentinel never gets touched) | Out of scope here — the engine spawns via `Bash`/`claude-subsession.sh`, and the hook's Bash branch is gated on `LEADV2_REVIEW_ENGINE` + phase `review`, so it is inert for plan. The branch is a declared **hard scope fence** (`:5-8`). **Raised for the wiring lane**, which must decide sentinel handling before flipping `LEADV2_PLAN_ENGINE=1`. |
| R7 | `bash` 3.2 on macOS has no `timeout`, and a descendant holding stdout hangs the wait | Watcher-subshell pattern lifted verbatim (`leadv2-review-run.sh:387-397`); `.rc` persisted to a file because subshell locals do not propagate past `wait`. |
| R8 | Adding `DISPATCHABLE_PLAN_ARMS` perturbs build-arm resolution | Additive set, role-scoped at the one membership test; `test-arm-ladder-vocabulary-drift.sh` must stay green **unmodified** — that is the regression guard. |
| R9 | The follow-up lane forgets the deferred tests 9/11/13 | Named individually in §7 with the reason and the owning lane, not summarised as "some tests deferred". |

---

## 10. Out of scope (implementer: ignore all of these)

- `leadv2-review-run.sh` — read-only reference; **no edit, not one line**.
- `leadv2-dispatch-code.sh` and every other dispatch script — `_acceptance_guard` and
  `architect_prepass` keep their current bodies in this lane.
- `routing.yaml` semantics; `leadv2-router-v2.py` / `leadv2-router.sh` arm resolution beyond adding
  the role-scoped set.
- Deleting `workflows/leadv2-plan.js` or `leadv2-diagnose.js`, and the doc flip
  (`docs/phases.md §Phase 2`, `commands/leadv2.md`) — mission item 5, follow-up lane.
- `leadv2-acceptance-shape.sh` internals, `leadv2-codex-planner.sh` internals,
  `leadv2-phase8-assert.sh` A11 — all three are already correct callers/callees.
- `~/.claude/workflows/` symlink chore (design step 0) and per-project `.claude/settings.json` env
  wiring — outside this repo.
- Any Supabase, Qdrant, or Next.js concern.

---

## 11. Decisions for the lead

| id | Decision | Taken | source |
|---|---|---|---|
| D1 | Planner pool excludes `glm`/`kimi` — mission prose contradicts PLANNER-MODELS-DECISION-01 and design test 6 | design wins; reverse only via a governance lane | `architect(self-check)` |
| D2 | Flag named `LEADV2_PLAN_ENGINE`, not design §5.1's `LEADV2_PLAN_RUN` | mirror the shipped `LEADV2_REVIEW_ENGINE` | `architect(self-check)` |
| D3 | Design test 8 asserts symlinks under `$HOME`, outside this repo | test written; it passes only after the step-0 chore, so the lane must either run that chore or accept one red assertion — **lead's call**, do not paper over it | `architect(self-check)` |
| D4 | Design tests 9, 11, 13 are not closable without off-limits files | deferred to the wiring lane, named individually | `architect(self-check)` |
| D5 | Tests 1–3 re-pointed from `_acceptance_guard` to the engine's own acceptance path | preserves the invariant without touching `dispatch-code.sh` | `architect(self-check)` |

---

acceptance:
  surface: file_artifact
  observable: >
    After a human runs the engine for a task on a repo where the Codex policy file says codex is
    disabled, two files are readable in that task's handoff directory: plan-gate.md, whose first line
    a reader sees as "status: pass" and whose second line reads "reason: validated"; and context.yaml,
    which a reader opens and finds carrying the mission text, a decisions list, an off_limits list,
    plan steps, and an acceptance block naming one of the five surfaces with a non-empty observable
    sentence and an ISO-8601 timestamp. The stderr the human sees carries the line
    "plan_run arm_unavailable arm=codex reason=policy" and then a "plan_run ... status=ran" line naming
    an arm other than codex, and carries no "status=failed" and no "status=parked" line for that task.
    Feeding the same engine a plan whose acceptance observable is blank instead yields a plan-gate.md
    a reader sees as "status: blocked" with "reason: acceptance_invalid", and no context.yaml a reader
    would mistake for a passing plan.
  authored_at: 2026-08-12T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-plan-run.sh, plugins/leadv2/scripts/lib/leadv2-context-merge.py, plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py, plugins/leadv2/scripts/tests/test-plan-run-engine.sh, plugins/leadv2/scripts/tests/test-plan-arms-role-scoped.sh, plugins/leadv2/scripts/tests/test-plan-run-codex-disabled-degrades.sh, plugins/leadv2/scripts/tests/test-diagnose-no-pe-constants.sh, plugins/leadv2/scripts/tests/test-diagnose-codex-disabled-degrades.sh, plugins/leadv2/scripts/tests/test-workflows-copies-are-symlinks.sh

(Note: `LANE_WRITES:` is the second-to-last line rather than the last, because the subagent protocol
requires `DELIVERABLE_COMPLETE` to be the final line. Both are matched by line-grep, not by position.)

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# ONE-PATH-PLAN-RUN-01 — build leadv2-plan-run.sh (Plan consolidation)

Goal: implement the Plan half of ONE-PATH-EVERYWHERE-01 — a sole-owner bash engine
`plugins/leadv2/scripts/leadv2-plan-run.sh`, mirroring the shipped review engine
`plugins/leadv2/scripts/leadv2-review-run.sh` (read it first; reuse its arm-pool /
quota-filter / journal patterns, do not fork new conventions).

Authoritative design: `docs/handoff/one-review-path-2026-08-06/design-plan-diagnose.md`
(census rebuilt from source; §0 documents the missing-prerequisite gap — trust its
file:line census, treat §7 as open questions, not verdicts).

Scope:
1. `leadv2-plan-run.sh` owns Phase 2 Plan end-to-end: resolves a planner arm pool
   (codex via leadv2-codex-planner.sh as one arm; glm; sonnet; opus for Heavy/arch),
   quota-filtered like run_reviewer_arm; fans out architect + critic passes; synthesizes
   into `docs/handoff/<id>/context.yaml` with REAL `leadv2-acceptance-shape.sh` validation.
2. Diagnose folds in as `--mode diagnose` per the design (same engine, different prompt set).
3. Contract: writes `plan-gate.md` (`status: pass|fail|blocked` + `reason:`) next to
   context.yaml; lead reads only the gate + context.yaml. Never silently pass on
   provider_error/empty_response — mirror review-gate.md semantics.
4. Tests: extend the existing test suites that asserted leadv2-plan.js invariants to
   assert the same invariants against leadv2-plan-run.sh (mirror what 43a634e did for
   review — nothing stranded). The design lists 13 failing assertions to satisfy.
5. Do NOT delete `workflows/leadv2-plan.js` in this lane — deletion + doc flip
   (phases.md §Phase 2, commands/leadv2.md) is a follow-up lane after the engine passes
   its tests, to keep mid-flight lanes unbroken.

Off-limits: leadv2-review-run.sh (read-only reference), routing.yaml semantics,
dispatch scripts.

Deliverable: the engine + tests green (`bash plugins/leadv2/scripts/tests/<suite>`),
summary in docs/handoff/one-path-plan-run-01/build-summary.md, DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-a88918ee" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.