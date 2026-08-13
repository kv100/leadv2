Product implementation task dispatch-9ce00c9d. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# ONE-PATH-EVERYWHERE-01 — architect prepass (scoped implementation design)

Role: architect prepass. **No implementation here.** Binding input:
`/Users/kostiantyn.vlasenko/Projects/persona-engine/docs/handoff/one-review-path-2026-08-06/design.md`
(read in full, 334 lines). This document is its execution order, with corrections where the
design's paths or sequencing do not survive contact with the tree.

Repo under change: `/Users/kostiantyn.vlasenko/Projects/leadv2` (plugin, single source).
All repo-relative paths below are from that root.

---

## 0. Step-0 capability evidence — STATIC (not live)

Mission Step 0, revised round 2: gather statically, do not block. The live probe is owned by
ledger row `SD-ONEPATH-CODEX-LIVE-PROOF-01` (due 2026-08-08).

| # | Question | Answer | Evidence | Status |
|---|---|---|---|---|
| C1 | Can a Codex-led session invoke a plain `bash` script from `plugins/leadv2/scripts/`? | **Yes.** The session is `codex exec` with `--sandbox workspace-write` and, in phase 6/7, `approval_policy="never"`. `codex exec`'s native tool is shell execution; the runner's own prompt instructs the session to "Reuse only per-phase helper scripts and guards (such as `leadv2-gate1-prompt.sh` and `leadv2-phase8-{assert,e2e-gate,close}.sh`)" — i.e. it already routes whole phases through plain bash scripts. | `scripts/leadv2-codex-session-runner.sh:458` (`codex exec --json --model … -C "$PROJECT_ROOT"`), `:463` (`--sandbox workspace-write`), `:468`/`:485` (`approval_policy="never"`), `:457` (prompt naming bash helper scripts as the sanctioned mechanism), `:476-483` (resume preserves `sandbox_mode="workspace-write"`) | **STATIC** |
| C2 | Does a Codex-led session have the Agent tool? | **No.** `Agent` is a Claude Code harness tool; nothing in the runner grants it and the Codex CLI has no equivalent. This is why §3.1's "no in-process Agent tool" constraint is load-bearing. | absence across `leadv2-codex-session-runner.sh` (grep for `agent`/`subagent_type` returns only the anti-recursion prose at `:457`) | **STATIC (absence-of-grant)** |
| C3 | Does it have the Workflow tool? | **No.** Same reasoning as C2. Confirms the design's §0 conclusion from the other direction: a review path that requires `Workflow()` is Claude-lead-only and violates FOUNDER CONSTRAINT 4. | same | **STATIC (absence-of-grant)** |
| C4 | In-session MCP? | **Not granted by the runner.** No `-c mcp_servers…` and no MCP config flag is passed at `:458` or `:476`. Codex can have MCP via its own `~/.codex/config.toml`, which the runner neither sets nor reads — so the engine must not depend on it. | `:458`, `:476-489` (full argv construction; no MCP flag) | **STATIC** |
| C5 | Working directory | `PROJECT_ROOT`, passed explicitly as `-C "$PROJECT_ROOT"` on fresh spawn. Resume inherits the thread's cwd. | `:458` | **STATIC** |
| C6 | Write scope under `docs/handoff/<task>/` | Writable. `TASK_DIR="$PROJECT_ROOT/docs/handoff/$TASK_ID"` is the runner's own artifact directory, and `workspace-write` covers the whole project root. The Phase-8 completion sentinel it waits on is itself a file the session must write there. | `:66`, `:86`, `:457` (`Stop only after docs/handoff/${TASK_ID}/phase8-passed.flag … exists`) | **STATIC** |

**Verdict on the stop condition:** the static evidence *positively supports* bash-script
invocability under a Codex lead (C1) rather than falsifying it. The mission's BLOCKED condition
("static evidence positively shows a plain bash script is NOT invocable") is **not** met.
Proceed to Step 1.

**Residual risk (must be carried into `SD-ONEPATH-CODEX-LIVE-PROOF-01`):** C1 is inference from
sandbox posture + the runner's own prompt, not an observed transcript of a Codex session running
`leadv2-review-run.sh`. Nothing may be enabled until that row closes.

**Path correction for the capability file.** The mission says to append to
`docs/handoff/one-review-path-2026-08-06/codex-capability.md`. That file does **not** exist in the
canonical leadv2 repo. Two copies exist elsewhere:
`.claude/worktrees/237f8026/docs/handoff/one-review-path-2026-08-06/codex-capability.md` (worktree)
and the design's home directory
`~/Projects/persona-engine/docs/handoff/one-review-path-2026-08-06/` (which has `design.md` +
`mission-build-r1.md` but **no** `codex-capability.md`). The implementer must append to the
persona-engine copy (same directory as the binding `design.md`) and reconcile the worktree copy,
not create a third. **Every row it appends must carry `STATIC` or `LIVE-VERIFIED` verbatim.**

---

## 1. Layers affected

| Layer | Files | Nature of change |
|---|---|---|
| Engine (new) | `plugins/leadv2/scripts/leadv2-review-run.sh` | to-create; sole owner of review orchestration |
| Lane entry | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | `:1447-1667` body → one flag-gated call |
| Lane env | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | delete dead `LEADV2_DISPATCH_REVIEWER_ARMS` (`:2061`, `:2068`, `:3242`) |
| Guard | `plugins/leadv2/hooks/leadv2-workflow-bypass-guard.sh` | review predicate: sentinel → artifact; match widens to Bash |
| Sentinel | `plugins/leadv2/hooks/leadv2-workflow-sentinel-touch.sh` | narrow `case plan\|review` → `case plan` |
| Lead/interactive | `plugins/leadv2/skills/leadv2-review/SKILL.md`, `.../WORKFLOW-PATH.md` | point at the engine over Bash |
| Docs contract | `plugins/leadv2/docs/phases.md` | Phase-5 contract now the engine, not the Workflow |
| Deleted | `plugins/leadv2/workflows/leadv2-review.js` **and** `~/.claude/workflows/leadv2-review.js` | superseded |
| Tests | `plugins/leadv2/scripts/tests/test-review-engine-*.sh`, `test-workflow-bypass-guard-lane.sh` | to-create |

---

## 2. Data flow — the engine, numbered

Caller (lane process **or** lead Bash **or** Codex-led session) →

1. `leadv2-review-run.sh --task <TASK> --root <ROOT> --handoff <DIR> --diff <FILE> --author <ARM>`
2. **Pool resolve.** `resolve_review_pool_call()` lifted verbatim from
   `leadv2-dispatch-product-close.sh:230-279`. Keeps `scripts/lib/leadv2-glm-policy-resolve.py`
   and `scripts/lib/leadv2-review-signals.sh` (**path correction**: the design writes
   `lib/…`; on disk they are `plugins/leadv2/scripts/lib/…` — `:233-236`, `:251`). Keeps
   author-exclusion including the defence-in-depth re-check at `:1469`, and the quota bands
   (GLM 90, Codex 90/95, Claude 95) untouched. **No arm is hardcoded in or out.**
3. **Fan-out.** Take the first `LEADV2_REVIEW_FANOUT` (default 3) `:ok:` entries from the resolved
   pool — which makes the fan-out multi-provider by construction (codex + glm + sonnet, never
   three Claudes). Each runs `run_reviewer_arm <arm>` (moved verbatim, `:1502-1575`: codex `:1508`,
   glm + omp second channel `:1520-1541`, kimi `:1543-1558`, claude-subsession `:1565`) as a
   background job under `timeout`, then `wait`.
4. **Hack-detect.** Always-on cheap pass (today `workflows/leadv2-review.js:137`, haiku), run in
   parallel with 3, never counted as one of the N arms.
5. **Per-arm refusal handling.** `classify_arm_failure` + the forward-only `next_ok_arm_after`
   walk (`:1582-1595`) applies **per job**, so one refusing arm re-selects without stalling the
   others. Partial fan-out still yields a verdict, stamped `arms: 2/3` (design R3).
6. **Verify.** For every Critical/High finding, one refutation job on an arm **≠** the arm that
   raised it (prompt/schema ported from `workflows/leadv2-review.js:195`). If the pool has only
   one live arm, verification is recorded as `verified: 0/<n> reason=single_arm_pool` — degraded,
   never fabricated.
7. **Synthesis.** Union of arm findings, dedup by `(file, line, severity, dimension)`; a finding
   refuted by its verifier drops out of the blocking count but stays in the JSON with
   `verifier_verdict: refuted`.
8. **Write.** `review-gate.md.tmp` → `mv` (atomic, design R2) and `review-findings.json`.

### Artifact contracts

`docs/handoff/<task>/review-gate.md` — existing lines unchanged (`REVIEW_VERDICT:`,
`REVIEW_FINDINGS: critical= high= medium= low=`, and the `status:`/`reason:` failure shapes at
`:1480`, `:1631`, `:1658`). **Additive only:**

```
arms: codex,glm,sonnet
verified: 3/4
```

Backward-compatible: the parser at `:365-401` ignores unknown lines.

`docs/handoff/<task>/review-findings.json` — new:

```json
{"task":"<TASK>","arms":["codex","glm","sonnet"],"fanout":3,
 "findings":[{"dimension":"correctness","severity":"Critical","file":"x.sh","line":12,
              "arm":"codex","verifier_arm":"glm","verifier_verdict":"upheld"}]}
```

`verifier_verdict` ∈ `upheld | refuted | unverified`. Invariant asserted by T3: for every
finding, `verifier_arm != arm` or `verifier_verdict == "unverified"`.

---

## 3. Interface contract — engine CLI

| Flag | Required | Meaning |
|---|---|---|
| `--task <sig8>` | yes | task id used for handoff paths + ledger |
| `--root <path>` | yes | repo root (lane passes `${ROOT}`) |
| `--handoff <path>` | yes | `docs/handoff/<task-id>` |
| `--diff <path>` | yes | diff file the arms review |
| `--author <arm>` | yes | excluded from the pool |
| `--fanout <n>` | no | overrides `LEADV2_REVIEW_FANOUT` (default 3) |

Exit codes preserved from the lane so the caller's existing handling is unchanged:
`0` reviewed · `6` blocked (`provider_error`, `review_body_lost`) · `9` unreviewed
(`all_arms_unavailable`). The engine **never** calls `_stamp_review_terminal`, `_dl_note`, or
`emit` — those stay in the lane, driven by the engine's exit code and `review-gate.md`. This keeps
the engine callable from a Codex-led session that has none of the lane's helper functions loaded.

**Engine spawns Claude arms only through `claude-subsession.sh`** — never a bare `claude -p`
(design R5; `claude-subsession.sh:338-342`, `-p` + `stream-json` requires `--verbose` or the
process dies instantly). This is the mandatory-flags check (`--max-turns`,
`--permission-mode bypassPermissions`, `--output-format json`) discharged by *not adding a second
invocation idiom*. **If the implementer adds any bare `claude -p`, that is CRITICAL.**

---

## 4. Guard repointing — precise scope

`hooks/leadv2-workflow-bypass-guard.sh` today: `:23` reads `.tool_input.subagent_type`; `:24-27`
exits 0 for anything not `architect|critic|security-auditor`; `:45-46` passes if the
`.workflow-called-<phase>` sentinel exists.

Changes, **review branch only** (scope fence — plan/`architect` semantics stay exactly as they are):

1. Match predicate widens: in addition to `subagent_type`, match `tool_name == "Bash"` whose
   `.tool_input.command` invokes `leadv2-dispatch-product-close.sh` or `leadv2-dispatch-code.sh`.
   This is the single change that makes the guard see the lane for the first time.
2. Pass predicate for `phase=review` becomes: `docs/handoff/<task>/review-gate.md` exists **and**
   contains a parseable `REVIEW_VERDICT:` line. Sentinel check is removed for review, kept for plan.
3. `hooks/leadv2-workflow-sentinel-touch.sh:32` narrows `case plan|review` → `case plan`.
4. Keep `trap 'exit 0' ERR` and the `LEADV2_WORKFLOW_GUARD=0` kill switch (design R4).

**Gating decision (mine, flagged):** the guard's review branch must be gated on
`LEADV2_REVIEW_ENGINE=1`, **not** on `LEADV2_WORKFLOW_ENABLED=1` (`:14`). Reason: with the
workflow deleted, `LEADV2_WORKFLOW_ENABLED` no longer names anything real for review, and at
`LEADV2_REVIEW_ENGINE=0` the guard must be byte-equivalently inert so no in-flight lane changes
behaviour. The plan branch keeps its `LEADV2_WORKFLOW_ENABLED` gate untouched.

---

## 5. The one place the mission and the binding design disagree

Mission Step 3 orders deletion of `workflows/leadv2-review.js` (both copies) **in this task**.
Design §4 and R7 say delete **only after all three repos are flipped and soaked** — "deleting
earlier strands any repo still on the flag's `0` side." Both cannot be satisfied literally.

**Resolution (adopt this; it satisfies both intents):** scope `LEADV2_REVIEW_ENGINE` to the
**lane call site only**. The lead/interactive path (Step 2, SKILL.md + WORKFLOW-PATH.md) calls the
engine over Bash **unconditionally** — the engine script exists on disk regardless of the flag, so
there is no `0`-side lead path left to strand once the skills are repointed. The flag then governs
exactly what §4 cared about: a mid-flight lane that spawns `product-close` after the edit still
runs today's inline body. Deletion in this task is then safe, because:

- the lane never called the workflow (guard is structurally blind to it — design §1.1);
- the lead's only remaining reference is the skill files, rewritten in the same commit;
- `~/.claude/workflows/leadv2-review.js` is a real-file copy, so both must go together or the
  copy stays live.

If the implementer is not willing to make the lead path unconditional, then Step 3 must be
deferred and reported as such — **do not delete the workflow while the lead still routes to it.**

`~/.claude/workflows/leadv2-review.js` is outside the repo, so it cannot appear in `LANE_WRITES`.
Its deletion must be reported explicitly in the return, with `ls` evidence.

---

## 6. Env vars

| Var | Default | Scope | Collision check |
|---|---|---|---|
| `LEADV2_REVIEW_ENGINE` | `0` | lane call site + guard review branch | grep over `plugins/` and `.claude/settings.json`: **no existing usage** — clean |
| `LEADV2_REVIEW_FANOUT` | `3` | engine | same: **no existing usage** — clean |

Both follow the `LEADV2_*` convention (no `LEAD_V2_*` drift). Neither may be set to `1` anywhere
in this task. `LEADV2_DISPATCH_REVIEWER_ARMS` is deleted (dead by its own comment,
`leadv2-dispatch-code.sh:3242`).

---

## 7. Tests — each must fail against pre-fix code

Location: `plugins/leadv2/scripts/tests/`. Run the full suite and report actual output.

| # | Test file (to-create) | Asserts | Fails today because |
|---|---|---|---|
| T1 | `test-review-engine-fanout-multiprovider.sh` | `review-gate.md` lists ≥2 **distinct providers** in `arms:` (not 2 Claude models) | lane emits exactly one arm and no `arms:` line |
| T2 | `test-review-engine-verify-coverage.sh` | every Critical/High finding in `review-findings.json` has a `verifier_verdict` | no verifier data, no findings file |
| T3 | `test-review-engine-verifier-distinct-arm.sh` | `verifier_arm != arm` for every verified finding | no verifiers exist |
| T4 | `test-workflow-bypass-guard-lane.sh` | Bash event invoking `leadv2-dispatch-product-close.sh`, no `review-gate.md` → `permissionDecision=deny` | guard matches only `subagent_type`, exits 0 at `:27` |
| T5 | `test-review-engine-pool-degrades.sh` | `codex_enabled=false` (m3-market shape) + GLM over band → non-empty pool, **no** `all_arms_unavailable` | untested; fail-closed path at `:1473-1486` |
| T6 | `test-review-single-owner-census.sh` (static) | exactly one file owns review orchestration (`--role critic`, `adversarial-review`, `agentType: 'critic'`) | three own it today |

T5 is the m3-market rollout blocker and is mandatory per the mission's degrade requirement.
Stub every provider binary via the existing `LEADV2_DISPATCH_{CODEX,GLM,KIMI,ARCHITECT}_BIN`
override hooks (`:1508`, `:1520`, `:1552`, `:1565`) — no live provider call in any test.

---

## 8. Risks

| # | Risk | Mitigation |
|---|---|---|
| A1 | `review-gate.md` write race between engine and the lane EXIT trap (`:148-156`) | engine writes `.tmp` + `mv`; trap already writes only when absent (`:154`). State the ordering in the engine header. |
| A2 | Fan-out multiplies a hung arm 3× | per-job `timeout`; forward-only pool walk per job; partial fan-out still verdicts as `arms: 2/3` |
| A3 | Verbatim lift of `run_reviewer_arm` drifts from the lane copy | delete the lane copy in the same commit — no two-copy window; T6 census catches a reintroduction |
| A4 | Concurrent access: engine writes `review-{arm}.md/.err` per arm in parallel | filenames already keyed on `${arm}` (`:1504-1505`) — collision-free **provided** the same arm never appears twice in one fan-out; the engine must dedup the pool slice. **Implementer: assert this.** |
| A5 | Guard repointing fails open unnoticed | T4 asserts the deny path in CI |
| A6 | Codex-lead invocability is STATIC, not LIVE | `LEADV2_REVIEW_ENGINE=0` everywhere; `SD-ONEPATH-CODEX-LIVE-PROOF-01` gates any flip |
| A7 | Mission/design deletion-order conflict | §5 above; if unresolved, defer Step 3 rather than strand a path |

---

## 9. Out of scope — implementer must not touch

- **Plan** consolidation (design §3.4) and **Diagnose** — sequenced after review proves out in all
  three repos. Not in this task even if they look easy.
- `workflows/leadv2-learn.js`, `workflows/leadv2-audit.js` — single implementations.
- The E2E gate — already the correct shape.
- `claude-subsession.sh:220`'s false "NO MCP access" claim — real bug, own row.
- Supervisor/fanout mode — paused by founder order.
- Enabling `LEADV2_REVIEW_ENGINE` anywhere. It stays `0` in all three repos.
- `git reset --hard`, `git clean`, `git stash` in this shared tree.
- Creating a real copy of any plugin-owned file inside persona-engine / m3-market / respiro-ios.

---

acceptance:
  - surface: file_artifact
    observable: "A reviewed lane's docs/handoff/<task>/review-gate.md shows an `arms:` line naming at least two different providers (e.g. `codex,glm,sonnet`) above the existing REVIEW_VERDICT: line, where today a human sees a single arm and no arms: line at all."
    authored_at: 2026-08-06T20:15:00+03:00
  - surface: file_artifact
    observable: "docs/handoff/<task>/review-findings.json exists and, for every finding a human reads at Critical or High severity, shows a verifier_arm different from the arm that raised it plus a verifier_verdict of upheld or refuted."
    authored_at: 2026-08-06T20:15:00+03:00
  - surface: rendered_line
    observable: "When a lane review is attempted with the engine on and no review-gate.md present, the reviewer sees the workflow-bypass-guard denial message in the session transcript naming the Bash dispatch invocation — where today the same attempt produces no guard message at all."
    authored_at: 2026-08-06T20:15:00+03:00
  - surface: file_artifact
    observable: "In a repo configured like m3-market (Codex disabled), the review-gate.md a human opens shows a normal REVIEW_VERDICT: with a pool of glm/kimi/claude arms, not `status: unreviewed` / `reason: all_arms_unavailable`."
    authored_at: 2026-08-06T20:15:00+03:00
  - surface: log_line
    observable: "The full plugin test-suite run printed to the operator's terminal reports the review-engine suites among its passing lines, with the same total-failure count as before the change or lower."
    authored_at: 2026-08-06T20:15:00+03:00

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/hooks/leadv2-workflow-bypass-guard.sh, plugins/leadv2/hooks/leadv2-workflow-sentinel-touch.sh, plugins/leadv2/skills/leadv2-review/SKILL.md, plugins/leadv2/skills/leadv2-review/WORKFLOW-PATH.md, plugins/leadv2/docs/phases.md, plugins/leadv2/workflows/leadv2-review.js, plugins/leadv2/scripts/tests/test-review-engine-fanout-multiprovider.sh, plugins/leadv2/scripts/tests/test-review-engine-verify-coverage.sh, plugins/leadv2/scripts/tests/test-review-engine-verifier-distinct-arm.sh, plugins/leadv2/scripts/tests/test-review-engine-pool-degrades.sh, plugins/leadv2/scripts/tests/test-review-single-owner-census.sh, plugins/leadv2/scripts/tests/test-workflow-bypass-guard-lane.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# ONE-PATH-EVERYWHERE-01 — build the review engine (step 1 of the consolidation)

**Read `docs/handoff/one-review-path-2026-08-06/design.md` in full before writing anything.** It is
the approved design; this mission is its execution order, not a re-litigation. In particular §3
(target design), §4 (blast radius / migration order), §5 (test strategy) and the FOUNDER
CONSTRAINTS section at the end are binding.

Plugin repo: `/Users/kostiantyn.vlasenko/Projects/leadv2` — this is the single source. The founder
ordered this work explicitly, so editing the plugin repo is authorized for this task. **Never
create a real copy of a plugin-owned file inside a consuming project** (persona-engine, m3-market,
respiro-ios); those are per-file symlinks and a copy silently drifts.

## Step 0 — capability evidence. **Do NOT block on this** (revised 2026-08-06, round 2).

A first attempt at this mission correctly returned BLOCKED here: Codex's quota is exhausted until
2026-08-08 08:48, so the live probe could not run. That stop condition is now lifted, because the
live proof has its own ledger row — `SD-ONEPATH-CODEX-LIVE-PROOF-01`, due 2026-08-08 — and nothing
gets enabled until that row closes (`LEADV2_REVIEW_ENGINE` stays 0 everywhere).

So: gather what you can **statically**, record it, and move on to Step 1.

Read `leadv2-codex-session-runner.sh`, its tool grants, its sandbox/permission config, and any
existing codex session transcripts on disk, and answer with file:line evidence:

- Can a Codex-led session invoke a plain `bash` script from the plugin's `scripts/` directory?
- Does it have the Agent tool? The Workflow tool? In-session MCP?
- What is its working directory and its write scope under `docs/handoff/<task>/`?

Append to the existing `docs/handoff/one-review-path-2026-08-06/codex-capability.md`, and mark each
row **STATIC** or **LIVE-VERIFIED** so a later reader cannot mistake one for the other.

**If the static evidence positively shows a plain bash script is NOT invocable under a Codex lead,
then stop and return BLOCKED** — that would falsify the design and the founder needs to know before
code is written. Quota being unavailable is NOT such a finding; it is an absence of evidence, and
the ledger row covers it.

## Step 1 — build the engine

`plugins/leadv2/scripts/leadv2-review-run.sh`, per design §3.1: arm-pool resolution lifted verbatim
from `resolve_review_pool_call()`, N-arm multi-provider fan-out (`LEADV2_REVIEW_FANOUT`, default 3),
the always-on cheap hack-detect pass, per-finding refutation on a DIFFERENT arm than the one that
raised it, and synthesis writing both `review-gate.md` (existing contract + additive `arms:` /
`verified:` lines) and the new `review-findings.json`.

Keep: `lib/leadv2-glm-policy-resolve.py`, `lib/leadv2-review-signals.sh`, author-exclusion, and the
quota bands exactly as they are (GLM 90, Codex 90/95, Claude 95). Do not hardcode an arm in or out
of the pool — quota, task and complexity decide, never a hand-kept list.

## Step 2 — converge both entry points

- Lane: replace the `leadv2-dispatch-product-close.sh:1447-1667` body with one call to the engine.
  The lane keeps its process model, EXIT trap, `_stamp_review_terminal`, and `review_crashed`
  fallback.
- Lead/interactive: the review phase calls the engine over Bash; rewrite
  `skills/leadv2-review/SKILL.md` and `WORKFLOW-PATH.md` to point at it.
- Repoint `hooks/leadv2-workflow-bypass-guard.sh`: predicate changes from "was the Workflow tool
  called" to "does `docs/handoff/<task>/review-gate.md` exist with a parsed `REVIEW_VERDICT:`", and
  the match widens from `subagent_type` to also cover Bash invocations of the dispatch scripts.

## Step 3 — delete the duplicates (design §3.3), in the order given there

Both copies of `workflows/leadv2-review.js` (plugin **and** `~/.claude/workflows/`) — deleting one
leaves the other live. Plus the sentinel branch, the `.workflow-called-review` sentinel, and the
already-dead `LEADV2_DISPATCH_REVIEWER_ARMS`.

## Scope fence

**Review only.** Do NOT touch Plan (§3.4) or Diagnose — they are sequenced after review proves out
in all three repos. Do not start them even if they look easy.

## Rollout

Behind `LEADV2_REVIEW_ENGINE`, default **0** (off). Do not enable it anywhere in this task. The
rollout order is persona-engine → respiro-ios → m3-market, and m3-market has Codex disabled, so the
arm pool must **degrade** there, never fail closed — cover that with a test.

## Tests (design §5)

Every fix carries a test that FAILS against the pre-fix code. At minimum: the bypass guard sees a
lane review (fails today — the lane is invisible to it); the fan-out is genuinely multi-provider,
not three Claudes; a verifier never runs on the arm that raised the finding; the pool degrades when
Codex is unavailable. Run the full suite and report the actual output, not a claim.

## Constraints

- Shared tree: never `git reset --hard`, `git clean`, or `git stash`.
- Commit incrementally with a clear message per step.
- If Step 0 blocks, stop there — do not build against an unverified premise.

## Return

`PASS|FAIL|BLOCKED` + commit shas + the Step-0 capability findings with their evidence + the full
test run + which parts of §3.3 were deleted + confirmation that `LEADV2_REVIEW_ENGINE` is still 0
everywhere.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-9ce00c9d" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.