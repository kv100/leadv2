Product implementation task dispatch-54aaa0bf. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# ONE-PATH-PLAN-RUN-01 — architect prepass: scoped implementation design

Task: `dispatch-54aaa0bf-architect` · Role: architect · Mode: design only, no code written.
Inputs read (all three, §0 gap of `design-plan-diagnose.md` is now CLOSED):

- `docs/handoff/one-review-path-2026-08-06/design-plan-diagnose.md` (581 lines) — authoritative
- `docs/handoff/one-review-path-2026-08-06/design.md` (333 lines) — recovered
- `docs/handoff/one-review-path-2026-08-06/mission-build-r1.md`
- `plugins/leadv2/scripts/leadv2-review-run.sh` (740 lines) — the shipped engine to mirror
- `plugins/leadv2/scripts/leadv2-acceptance-shape.sh` header (subcommand contract)
- `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:47,762-869` (arm sets + argparse)
- `git show --stat 43a634e` (the "nothing stranded" review-test precedent)

---

## 0. §7 conditionals of design-plan-diagnose.md, resolved against the real design.md

`design-plan-diagnose.md` §7.1 stated three positions conditionally, because `design.md` was
unreadable at the time. All three are now resolved — **none is a contradiction**:

| §7.1 conditional | What `design.md` §3.4 actually says (lines 215–225) | Verdict |
|---|---|---|
| "If §3.4 says make `_acceptance_guard`'s heuristic stricter" | *"extract `leadv2-plan-run.sh` owning `context.yaml` + the real `leadv2-acceptance-shape.sh` validation; `architect_prepass()` calls it **instead of** its heuristic scan"* | **Agrees.** Delete the heuristic, do not harden it. |
| "If §3.4 says `leadv2-plan.js` becomes the merged engine" | *"`workflows/leadv2-plan.js` and its `~/.claude` copy are deleted"*; and §0 lines 42–54 prove the Workflow sandbox cannot shell out, so *"the script must be canonical, not the workflow"* | **Agrees.** Script canonical. |
| "If §3.4 says Plan needs its own arm-selection logic" | *"`leadv2-codex-planner.sh` survives as an **arm** inside the engine's pool, not as a parallel entry point"* — no new selection mechanism proposed | **Agrees.** One new role-scoped *set*, not a new mechanism. |

One genuine divergence to record, and this mission settles it in favour of the mission:
`design.md` §3.4 says plan.js is **deleted**; `design-plan-diagnose.md` §3.3 says it becomes a
**shim**. This mission's scope item 5 says **neither** — leave `workflows/leadv2-plan.js` byte-
untouched in this lane, so mid-flight lanes and `test-leadv2-codemap.sh` (which executes the real
plan.js through `fixtures/codemap-plan-harness.mjs`) stay green. Deletion-or-shim is the
follow-up lane's call.

Also binding, from `design.md` FOUNDER CONSTRAINTS (lines 307–333): the engine must be callable
from a **Codex-led or bare-bash session** — no Agent tool, no Workflow tool, no in-session MCP on
the critical path. This rules out the engine calling `Workflow()` or `Agent()` for any purpose.

---

## 1. Layers affected

| Layer | File | Change |
|---|---|---|
| Engine (new) | `plugins/leadv2/scripts/leadv2-plan-run.sh` | **to-create** — sole owner of Phase 2 Plan + Diagnose |
| Arm-set resolver | `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` | additive: `DISPATCHABLE_PLAN_ARMS`, `resolve_plan_pool()`, `--plan-pool` flag |
| Tests | `plugins/leadv2/scripts/tests/test-plan-run-*.sh` + `tests/fixtures/plan-run/*` | **to-create** |
| Read-only reference | `leadv2-review-run.sh`, `leadv2-codex-planner.sh`, `leadv2-acceptance-shape.sh` | **not modified** |
| Off-limits this lane | `leadv2-dispatch-code.sh`, `leadv2-dispatch-product-close.sh`, `workflows/leadv2-plan.js`, `workflows/leadv2-diagnose.js`, `routing.yaml` semantics, `skills/leadv2-iterative-recovery/SKILL.md` | untouched |

Nothing in Supabase / Qdrant / Next.js is in scope — this is entirely inside the plugin.

---

## 2. Data flow (numbered)

### 2.1 `--mode plan` (and `--mode prepass`, which is a narrower instance of it)

1. **Arg parse + validate.** Mirror `leadv2-review-run.sh:37-55`: long flags only, unknown flag →
   exit 2, required-set check → exit 2.
2. **Engine creates `docs/handoff/<id>/context.yaml` FIRST**, before any arm runs, writing only the
   deterministic fields it owns: `id`, `mission`, `reads`, `writes`, `lane_writes`,
   `acceptance.authored_at` (stamped `date -u +%Y-%m-%dT%H:%M:%SZ` at this moment). This ordering
   is load-bearing: `leadv2-acceptance-shape.sh assert-precedence` compares `authored_at` against
   the earliest mtime of the `LANE_WRITES` files, so the stamp must predate every byte of code.
   An LLM-authored timestamp is precisely what that check exists to distrust.
3. **Prepass cache probe** (prepass mode, or plan mode with `--cache`): `compute_sig` of the full
   mission text → `<artifact>.sig`. Carry P1's two corrections verbatim: **H4** — a cached artifact
   carrying no `LANE_WRITES:` line is a **miss**, not a hit; **M7** — a park still stamps the cache
   so a byte-identical retry does not pay the architect twice. Hit → emit
   `plan_run task=<sig8> status=cached`, exit 0.
4. **Pool resolve** — `resolve_plan_pool_call()`, structurally identical to
   `leadv2-review-run.sh:71-110` but `--job plan --plan-pool` (no `--author`; plan has no
   author-exclusion concept). Returns `planner=`/`pool=`/`refusal=` on the same three-line
   contract. Empty planner → write `plan-gate.md` `status: blocked` /
   `reason: all_plan_arms_unavailable`, emit, **exit 9**.
5. **Fan-out list** — first `LEADV2_PLAN_FANOUT` (default 2) distinct `:ok:` arms via
   `_engine_pool_ok_arms()` (lifted from `leadv2-review-run.sh:359-372`), with the same A4
   duplicate guard and the same `${arr[@]}`-not-`${arr[@]:-}` bash-3.2 note.
6. **Architect pass, N arms in parallel.** Background jobs + `wait`, per-arm watcher-subshell
   timeout (`_engine_run_arm_with_timeout`, `leadv2-review-run.sh:386-397`,
   `LEADV2_PLAN_ARM_TIMEOUT_S` default 900). Each arm receives the mission plus the context
   envelope (§2.3) and must answer with one fenced block:

   ```
   PLAN_YAML:
   ```yaml
   decisions: [...]
   off_limits: [...]
   plan: {steps: [...]}
   acceptance: {surface: <enum>, observable: <text>}
   risk: <low|medium|high>
   ```
   ```

   The arm **never writes `context.yaml`**. This inverts today's `leadv2-plan.js` arrangement
   (agent writes the whole file, code checks it after) and is what makes the deterministic fields
   untamperable.
7. **Critic pass**, one arm ≠ the architect arm, on the merged draft. Its only job is to raise
   blocking objections in the same `FINDING:` one-line contract the review engine already uses
   (`leadv2-review-run.sh:434`). Objections merge into `decisions[]` with
   `source: critic(<arm>)`. Skipped in `--mode prepass` (single-arm, cheap, lane-inline).
8. **Merge.** `python3` + `yaml` reads the draft `context.yaml`, overlays only the judgment keys
   from the winning `PLAN_YAML:` block, and re-serialises to `context.yaml.tmp` → `mv`
   (atomic). The engine refuses any overlay that tries to set `id`, `mission`, `lane_writes`, or
   `acceptance.authored_at` — those are engine-owned; an attempt is a `decisions[]` note, not a
   silent overwrite.
9. **Validate, in code, not by LLM judgment.**
   a. `REQUIRED_FIELDS` presence check (port `leadv2-plan.js:402`'s list:
      `id, mission, reads, writes, acceptance, decisions, off_limits, plan, risk`).
   b. `leadv2-acceptance-shape.sh validate <context.yaml>` — the **real** validator, exit 0 required.
   c. `leadv2-acceptance-shape.sh assert-precedence --task-id <id>` — run whenever `lane_writes`
      names at least one file that exists. Vacuously true otherwise, by that script's own contract.
10. **Exactly one retry** on validation failure (matching `leadv2-plan.js:410-419`): a repair
    prompt carrying the validator's stderr reasons, re-run on the next arm in the pool, then
    re-merge and re-validate. Second failure is terminal → `status: fail`.
11. **Gate write** (§3) → `plan-gate.md.tmp` → `mv`. Emit journal line. Exit per §3.2.

### 2.2 `--mode diagnose`

Same engine, three parameters different (design-plan-diagnose §2.4):

- **Input assembly branch**: `--log-path` tail bounded at 100 lines (matching
  `leadv2-codex-planner.sh:172-177`) + `--diff-paths`. **No persona-engine constants anywhere** —
  if `--log-path` is absent, the log slice is empty, not a `journalctl -u persona-engine` default.
  This is the one thing `workflows/leadv2-diagnose.js:17-18` gets wrong and must not be ported.
- **No `acceptance:` and no `LANE_WRITES`** — diagnose produces a hypothesis, not a diff. Steps
  2, 9b, 9c of §2.1 are skipped; the gate's `reason:` records `mode=diagnose` so a reader never
  mistakes a skipped acceptance check for a passed one.
- **Output artifact**: `docs/handoff/<id>/root-cause.md` with
  `root_cause / confidence / evidence_files / fix_hint / alternates`, plus `plan-gate.md` with the
  same `status:`/`reason:` keys. Journal verb is `diagnose_run`, not `plan_run`.

### 2.3 Context envelope (carried over from `leadv2-plan.js`, as engine logic)

- `shared-memory.yaml` + `solutions-archive.yaml` top-1 exemplar (same source files the
  `leadv2-intake-enrich` skill reads).
- Flag-gated `code_map` injection, **capped at 2000 chars including the truncation note** —
  the exact invariant `test-leadv2-codemap.sh` case 7 asserts against plan.js.
- Bandit models via `--models` with a **byte-identical flag-off guarantee** (BANDIT-WIRE-01):
  when the flag is absent, no `code_map` key, no `models` key, and no mention of either in any
  prompt — omitted, never emitted as `false`/empty (that was codemap fix-round-1 finding #1).
- Model policy per PLANNER-MODELS-DECISION-01: Heavy → `fable`, else `opus` for the architect
  role; Codex is the same-tier second planning brain; **GLM and Kimi are never admitted** — and
  that exclusion lives in `DISPATCHABLE_PLAN_ARMS` (set membership), never at a call site.

---

## 3. Interface contracts

### 3.1 CLI

| Flag | Modes | Required | Notes |
|---|---|---|---|
| `--task <sig8\|id>` | all | yes | mirrors review engine's `--task` |
| `--root <path>` | all | yes | repo root |
| `--handoff <dir>` | all | yes | `docs/handoff/<id>` |
| `--mode <plan\|prepass\|diagnose>` | all | yes | default `plan` |
| `--mission <text>` / `--mission-file <path>` | plan, prepass, diagnose | one of | mutually exclusive; `--mission-file` read **early** (race protection, P3 idiom) |
| `--class <trivial\|light\|standard\|heavy>` | plan, prepass | no | selects `fable` vs `opus` tier |
| `--writes <csv>` | plan, prepass | no | seeds `writes:`/`lane_writes:` |
| `--fanout <n>` | plan, diagnose | no | default `LEADV2_PLAN_FANOUT` = 2 |
| `--log-path <f>`, `--diff-paths <s>` | diagnose | no | tail bounded at 100 lines |
| `--no-cache` | prepass, plan | no | bypasses the sig cache |

**Exit codes** (mirroring `leadv2-review-run.sh` exactly, so the lane's future call site can reuse
one classifier): `0` pass · `2` usage · `7` fail (gate written, `status: fail`) ·
`9` blocked (gate written, `status: blocked`).

### 3.2 `plan-gate.md` — the only thing the lead reads besides `context.yaml`

Written to `<handoff>/plan-gate.md` via `.tmp` + `mv`, on **every** exit path including the EXIT
trap. Keys, mirroring `review-gate.md` (`leadv2-review-run.sh:449-452, 725-739`):

```
mode: plan|prepass|diagnose
status: pass|fail|blocked
reason: <token>
arms: <csv of arms that actually ran>
artifact: docs/handoff/<id>/context.yaml   # or root-cause.md in diagnose
acceptance: valid|invalid|skipped          # 'skipped' only when mode=diagnose
```

`reason:` vocabulary — closed set, one token, never free text:

| status | reason | Means |
|---|---|---|
| pass | `ok` | validated `context.yaml` on disk |
| fail | `acceptance_invalid` | real validator refused after the one retry |
| fail | `required_fields_missing` | `REQUIRED_FIELDS` check failed after the one retry |
| fail | `precedence_violated` | `authored_at` postdates a `LANE_WRITES` file |
| blocked | `all_plan_arms_unavailable` | empty pool after quota filter |
| blocked | `provider_error` | every arm exited non-zero / timed out |
| blocked | `empty_response` | arm exited 0 but produced no parseable `PLAN_YAML:` block |
| blocked | `body_lost` | arm ran and was paid for, but its artifact body is missing |

**Never-silent-pass rule, stated as an invariant:** `provider_error`, `empty_response` and
`body_lost` are `blocked`, never `pass`. This is the direct port of REVIEW-BODY-PERSIST-01
(`leadv2-review-run.sh:549-568`): a paid arm whose body was lost surfaces as blocked. A missing
`plan-gate.md` is itself a blocked signal for the caller — absence is never consent.

### 3.3 Arm invocation contracts

| Arm | Invocation | Unavailability signal |
|---|---|---|
| `codex` | `bash leadv2-codex-planner.sh --task-id <id> --mode <plan\|diagnose> --tier <resolved>` | stdout token `codex_skipped_by_policy` + exit 0 → engine emits `plan_run arm_unavailable arm=codex reason=policy task=<sig8>`, advances the chain. **Not** an error, **not** a park. |
| `sonnet`/`opus`/`fable` | `bash claude-subsession.sh --role architect\|critic --model <arm> --task-id <id> --mission-file <f> --wait` | non-zero rc → `classify_arm_failure` (lifted) |

The engine **never** invokes a bare `claude -p` (design.md R5: `-p` + `stream-json` requires
`--verbose` or the process dies instantly — one idiom only, through `claude-subsession.sh`).
Tier resolution, the `--tier top` `--reason` requirement, the spark ban and the
`codex_enabled: false` short-circuit stay **inside** `leadv2-codex-planner.sh`; the engine calls
the arm and reads the result, and does not second-guess any of it.

**Artifact-not-stdout discipline** (P1, the 2026-07-29 incident where `2>&1` wrote log metadata
over a correct 21 KB design): read the arm's body from
`docs/handoff/<id>/architect.full.md` → `architect.md` → `architect.summary.md`, newer than the
start stamp, with the `critic.stream.jsonl` last-assistant-text fallback
(`materialize_subsession_body`, `leadv2-review-run.sh:131-184`). Never parse stdout for the body.

### 3.4 Resolver change (additive, review path byte-identical)

`plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py`:

```python
DISPATCHABLE_PLAN_ARMS = {"codex", "sonnet", "opus", "fable"}   # new, beside line 47
```
plus `resolve_plan_pool()` (mirroring `resolve_review_pool`, no author-exclusion) and
`ap.add_argument("--plan-pool", action="store_true")` beside `--review-pool` (line 767), with the
same `--job plan` branch shape at 788/838/852. `DISPATCHABLE_BUILD_ARMS` is **not** modified, so
`test-arm-ladder-vocabulary-drift.sh` and `test-router-v2-retired-arm.sh` stay green unchanged.

GLM and Kimi are excluded by **absence from the set**, never by a literal in routing or at a call
site. That is the whole point of the change.

---

## 4. Journal vocabulary

`plan_run task=<sig8> mode=<m> status={ran,cached,cache_miss,skipped,disabled,failed,blocked,retrying,parked} arm=<a> artifact=<rel-path>`
plus `plan_run arm_unavailable arm=<a> reason=<policy|quota|timeout|channel_down> task=<sig8>`.
Diagnose mode uses `diagnose_run` with the identical field set. Like the review engine, this file
defines its **own** stderr-only `emit()` and never calls the lane's journal `emit` — that is what
keeps it callable from a bare bash session with none of the lane's helpers loaded
(`leadv2-review-run.sh:11-22, 59-61`).

---

## 5. Test plan — the 13 assertions, honestly scoped

`43a634e` is the precedent: it did not add a parallel suite, it **re-pointed the existing suites**
that asserted `leadv2-review.js` invariants at `leadv2-review-run.sh`, so nothing was stranded.
The same discipline applies here, with one difference that must be stated plainly: **this lane
does not delete `leadv2-plan.js`** (mission scope item 5), so `test-leadv2-codemap.sh` and
`test-leadv2-phase8-learn-counter.sh` must keep passing against plan.js **as they are today**. The
mirroring here is *additive*: the same invariants get a second assertion against the engine.

| # | Design §6 assertion | This lane | Why |
|---|---|---|---|
| 1 | acceptance guard refuses empty `observable` + `authored_at: yesterday` | ✅ `test-plan-run-acceptance-real.sh` case 1 — asserted against the **engine's** gate (`status: fail reason=acceptance_invalid`) | the invariant is "real validator, not heuristic"; the engine is where it now lives |
| 2 | multi-line `observable:` whose 2nd line says "the function returns 0" | ✅ same suite, case 2 | ditto |
| 3 | `acceptance:`/`surface:` only inside a fenced markdown block | ✅ same suite, case 3 | ditto |
| 4 | after a successful prepass, `context.yaml` exists and `validate` exits 0 | ✅ `test-plan-run-contract.sh` | core deliverable |
| 5 | `--mode plan` from a bare bash env with no Workflow/Agent tool yields a valid `context.yaml` | ✅ `test-plan-run-contract.sh` (env-scrubbed subshell, stub arms) | founder constraint 4 |
| 6 | `DISPATCHABLE_PLAN_ARMS` excludes glm/kimi, includes codex/sonnet, read from the resolver not a literal | ✅ `test-plan-run-arms-role-scoped.sh` (importlib, mirroring `test-arm-ladder-vocabulary-drift.sh:44-51`) | |
| 7 | `codex_enabled: false` → exit 0, `arm_unavailable arm=codex reason=policy`, still a valid `context.yaml` | ✅ `test-plan-run-codex-disabled-degrades.sh` | m3-market degrade case |
| 8 | `~/.claude/workflows/*.js` are symlinks | ❌ **deferred** | mutates the founder's home directory and is coupled to the plan.js deletion this lane is told not to do (design §4 step 0 — independent, its own commit) |
| 9 | `LEADV2_PLAN_RUN=0` → byte-identical dispatch journal | ❌ **deferred** | the flag gates the **lane call site** in `leadv2-dispatch-code.sh`, which is off-limits here. Introducing a flag nothing reads would be dead config. |
| 10 | `--mode diagnose` prompt contains no persona-engine constants | ✅ `test-plan-run-diagnose-mode.sh` case 1 | |
| 11 | no file outside the engine invokes `--mode diagnose`; `leadv2-iterative-recovery/SKILL.md` routes through it | ❌ **deferred** | requires editing `skills/leadv2-iterative-recovery/SKILL.md:45` — the reroute belongs with the doc flip (mission scope item 5) |
| 12 | diagnose degrade proof with `diagnose_run` verbs | ✅ `test-plan-run-diagnose-mode.sh` case 2 | |
| 13 | `work_kind=diagnose` from `leadv2-task-judge.sh:120-125` reaches the engine | ❌ **deferred** | requires editing a dispatch-adjacent script (off-limits) |

Plus one suite the design does not list but `43a634e`'s "nothing stranded" rule demands:

| # | Suite | Asserts |
|---|---|---|
| 14 | `test-plan-run-codemap.sh` | the CODEMAP-CONTEXT-01 invariants that `test-leadv2-codemap.sh` asserts against plan.js, now also against the engine: flag-off emits **no** `code_map` key and no "Code map" text anywhere (omitted, never `false`); cap ≤ 2000 chars including the truncation note; flag-on reaches both the architect prompt and `context.yaml`; both prompts fence the data as UNTRUSTED; `code_map` survives the one-retry path |

**9 of 13 land here; 4 are deferred with a named reason, each blocked on a file this lane is
explicitly told not to touch.** The follow-up lane (plan.js deletion + `dispatch-code.sh` swap +
doc flip) owns 8, 9, 11, 13 — they are exactly that lane's diff.

Test harness conventions: mirror the existing suites — `set -euo pipefail`, `PASS/FAIL` counters,
`mktemp -d` fixture repo with `git init -q`, `trap 'rm -rf …' EXIT`, arms stubbed via
`LEADV2_DISPATCH_ARCHITECT_BIN` / `LEADV2_DISPATCH_CODEX_BIN` pointing at fixture scripts (the
same override seams `run_reviewer_arm` already honours — no new injection mechanism).

---

## 6. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Engine and arm race on `context.yaml`.** The engine writes it at step 2; a `claude-subsession.sh --role architect` arm, given a handoff dir, may write `context.yaml` itself out of habit (that is what plan.js trained it to do). | The arm's mission must state that `context.yaml` is engine-owned and that its answer is the `PLAN_YAML:` block only. The merge step overlays **only** the judgment keys and refuses engine-owned keys. Belt: engine re-reads its own deterministic fields after merge and restores any that changed, recording the attempt in `decisions[]`. |
| R2 | **`plan-gate.md` written twice.** | `.tmp` + `mv` (atomic within a filesystem), single writer, EXIT trap writes only when the file is **absent** — the exact ordering `leadv2-review-run.sh:4-9` documents. State it in the engine header. |
| R3 | **`authored_at` stamped after code exists** → `assert-precedence` fails on a legitimate plan. | Stamp at step 2, before any arm runs; never let the arm supply it. Test 4 covers the ordering. |
| R4 | **Fan-out amplifies a stuck arm** (2 planners + 1 critic + 1 retry = 4 spawn surfaces). | Per-arm watcher-subshell timeout, `LEADV2_PLAN_ARM_TIMEOUT_S` default 900. A partial fan-out (1 of 2 returned) must still yield a verdict, with `arms:` recording what actually ran. |
| R5 | **Duplicate arm in the fan-out** (A4). | Lift `_engine_pool_ok_arms` dedup + the guard, including the `${arr[@]}` vs `${arr[@]:-}` bash-3.2 note verbatim — that quirk already caused one false-positive "duplicate ''" on a degraded pool. |
| R6 | **Env-var drift.** `LEADV2_PLAN_FANOUT` / `LEADV2_PLAN_ARM_TIMEOUT_S` are new. There is **no `.claude/settings.json` in this repo** (checked: `FileNotFoundError`), so the env registry lives elsewhere. | Before adding either name, `grep -rn 'LEADV2_REVIEW_FANOUT' plugins/leadv2 ~/.claude` and register the two new names in **every** location that one appears in, in the same commit. Both use the `LEADV2_*` prefix; no `LEAD_V2_*` variant is introduced. **Do not introduce `LEADV2_PLAN_RUN` in this lane** — its only reader is the off-limits dispatch call site, so it would land as dead config. |
| R7 | **Resolver change breaks the review path.** | `--plan-pool` is a new flag, `DISPATCHABLE_PLAN_ARMS` a new constant; `DISPATCHABLE_BUILD_ARMS` and `resolve_review_pool` are untouched. Run `test-arm-ladder-vocabulary-drift.sh`, `test-router-v2-retired-arm.sh` and `test-leadv2-review-routing.sh` as the regression proof, not as an assumption. |
| R8 | **`leadv2-plan.js` and the engine drift** while both are alive (this lane keeps both). | Accepted and time-boxed: the engine is not wired into any call site in this lane, so plan.js remains the only *running* Plan path and there is no live divergence. The follow-up lane closes the window. Record it in `open-threads.md` the day this merges. |
| R9 | **`--mode prepass` is built but unreachable** (its consumer, `architect_prepass()`, is off-limits). | Intentional. It is tested standalone (test 4) and wired by the follow-up lane. Say so in the engine header so a later reader does not delete it as dead code. |

---

## 7. Constraint checklist

1. **Env-var naming** — all new names `LEADV2_*`: `LEADV2_PLAN_FANOUT`, `LEADV2_PLAN_ARM_TIMEOUT_S`.
   Reused unchanged: `LEADV2_REQUIRE_ACCEPTANCE`, `LEADV2_PREPASS_CACHE`, `LEADV2_ARCHITECT_GATE`,
   `LEADV2_GLM_POLICY_RESOLVER`, `LEADV2_ROUTING_YAML`, `LEADV2_DISPATCH_CODEX_BIN`,
   `LEADV2_DISPATCH_ARCHITECT_BIN`, `LEADV2_CANONICAL_ROOT`. No `LEAD_V2_*` anywhere.
   ⚠️ `.claude/settings.json` does **not** exist in this repo — see R6 for the substitute check.
2. **File paths** — every path above exists on disk except those marked **to-create**
   (`leadv2-plan-run.sh`, the six test files, `tests/fixtures/plan-run/`). Verified present:
   `leadv2-review-run.sh`, `leadv2-codex-planner.sh`, `leadv2-acceptance-shape.sh`,
   `lib/leadv2-glm-policy-resolve.py`, `workflows/leadv2-plan.js`, `tests/test-leadv2-codemap.sh`,
   `tests/test-arm-ladder-vocabulary-drift.sh`.
3. **`claude -p` flags** — the engine issues **no** `claude -p`. All Claude arms go through
   `claude-subsession.sh`, which owns the `--max-turns` / `--permission-mode bypassPermissions` /
   `--output-format` / `--verbose` idiom. Any `claude -p` appearing in the implementation diff is
   **CRITICAL** and must be rejected in review.
4. **Concurrent access** — `docs/handoff/<id>/context.yaml` is read+written by the engine and
   potentially written by an arm (R1); `plan-gate.md` by the engine and its EXIT trap (R2). Both
   resolved by single-writer + `.tmp`/`mv` + engine-owned-key restoration. No lock needed: the
   engine is the sole orchestrator within one task id.
5. **Config contradiction** — `DISPATCHABLE_PLAN_ARMS` is a genuinely new symbol (grep: zero hits
   repo-wide). `DISPATCHABLE_BUILD_ARMS` semantics are unchanged. No contradiction found.

---

## 8. Out of scope (the implementing agent must ignore these)

- Deleting or shimming `workflows/leadv2-plan.js` / `workflows/leadv2-diagnose.js`.
- Any edit to `leadv2-dispatch-code.sh` — including `architect_prepass()` and `_acceptance_guard`.
- Any edit to `leadv2-dispatch-product-close.sh` or `leadv2-review-run.sh` (read-only reference).
- `routing.yaml` semantics, `leadv2-router-v2.py`, `leadv2-router.sh`.
- `leadv2-phase8-assert.sh` (A11 already calls the real validator and is correct).
- `skills/leadv2-iterative-recovery/SKILL.md`, `docs/phases.md`, `commands/leadv2.md` — the doc
  flip is the follow-up lane.
- `~/.claude/workflows/*.js` symlinking (design §4 step 0, independent commit, founder's home dir).
- `LEADV2_PLAN_RUN` rollout flag and the per-repo staging order.
- Any Supabase / Qdrant / Next.js concern.

---

## 9. Deliverable definition of done

1. `plugins/leadv2/scripts/leadv2-plan-run.sh` exists, `bash -n` clean, all three modes runnable.
2. The nine in-lane suites of §5 pass: `bash plugins/leadv2/scripts/tests/test-plan-run-*.sh`
   → `PASS`, `rc=0`, zero FAIL.
3. Regression proof, run and pasted, not assumed: `test-arm-ladder-vocabulary-drift.sh`,
   `test-router-v2-retired-arm.sh`, `test-leadv2-review-routing.sh`, `test-leadv2-codemap.sh`,
   `test-acceptance-shape.sh` all still pass.
4. `docs/handoff/one-path-plan-run-01/build-summary.md` written.

---

acceptance:
  surface: file_artifact
  observable: >
    A reader running `bash plugins/leadv2/scripts/leadv2-plan-run.sh --mode plan --task demo
    --root <repo> --handoff docs/handoff/demo --mission-file <f>` in a bare shell with no Claude
    lead, no Workflow tool and no MCP, then opening the two files it leaves behind, sees:
    docs/handoff/demo/context.yaml carrying id, mission, reads, writes, lane_writes, decisions,
    off_limits, plan.steps, risk and an acceptance block whose surface is one of the five enum
    values and whose authored_at timestamp is earlier than the modification time of every file
    named in lane_writes; and docs/handoff/demo/plan-gate.md whose first lines read
    `mode: plan`, `status: pass`, `reason: ok`, `arms: <the arms that ran>`,
    `acceptance: valid`. With Codex disabled by repo policy the same reader sees
    `status: pass` still, never `status: fail`, and the run's stderr carries the line
    `plan_run arm_unavailable arm=codex reason=policy`. With an arm that exits zero but
    returns an empty body, the same reader sees `status: blocked` and
    `reason: empty_response` — never `status: pass`.
  authored_at: 2026-08-12T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-plan-run.sh, plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py, plugins/leadv2/scripts/tests/test-plan-run-contract.sh, plugins/leadv2/scripts/tests/test-plan-run-acceptance-real.sh, plugins/leadv2/scripts/tests/test-plan-run-arms-role-scoped.sh, plugins/leadv2/scripts/tests/test-plan-run-codex-disabled-degrades.sh, plugins/leadv2/scripts/tests/test-plan-run-diagnose-mode.sh, plugins/leadv2/scripts/tests/test-plan-run-codemap.sh, plugins/leadv2/scripts/tests/fixtures/plan-run/*

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# ONE-PATH-PLAN-RUN-01 — build leadv2-plan-run.sh (Plan consolidation)

Goal: implement the Plan half of ONE-PATH-EVERYWHERE-01 — a sole-owner bash engine
`plugins/leadv2/scripts/leadv2-plan-run.sh`, mirroring the shipped review engine
`plugins/leadv2/scripts/leadv2-review-run.sh` (read it first; reuse its arm-pool /
quota-filter / journal patterns, do not fork new conventions).

Authoritative design: `docs/handoff/one-review-path-2026-08-06/design-plan-diagnose.md`
(census rebuilt from source). Its §0 "missing prerequisite" gap is now CLOSED — the files
were recovered into the same dir: read `design.md` (one-review-path consolidation design)
and `mission-build-r1.md` too; where design-plan-diagnose.md §7 raised conditional
questions against the unseen design.md, resolve them against the real file.

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
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-54aaa0bf" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.