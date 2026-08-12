# ONE-REVIEW-PATH — consolidation design

Date: 2026-08-06 · Author: architect (design pass, read-only)
Repo under design: `/Users/kostiantyn.vlasenko/Projects/leadv2` (plugin, single source)
Consumers: persona-engine, m3-market, respiro-ios

All paths below are relative to `/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/`
unless absolute. Everything marked VERIFIED was read or probed in this pass; INFERRED is
flagged inline.

---

## 0. The crux, settled first

The mission said the design hinges on whether the Workflow tool is reachable from the
out-of-process lane (`scripts/claude-subsession.sh` → `claude -p`). **VERIFIED: it is.**

Probe (run from the persona-engine cwd, same settings the lane inherits):

```
claude -p "…list of every tool available to you…" --max-turns 1 \
  --permission-mode bypassPermissions --output-format json --model haiku
```

`result` field contained, verbatim:

```
Agent, Bash, CronCreate, …, TaskUpdate, WebFetch, WebSearch, Workflow, Write,
mcp__claude_ai_Google_Drive__…, mcp__codebase-memory-mcp__…, mcp__shadcn__…
```

Two consequences:

1. `Workflow` **is** in a headless `claude -p` session. "The lane physically cannot call the
   workflow" is false; the lane simply never does.
2. `scripts/claude-subsession.sh:220` tells every worker *"NO MCP access in this subsession
   (headless claude -p mode). Mission file has \"## Graph context\" pre-loaded."* — the probe
   lists 20 MCP tools. That line is **stale/incorrect** and is independently costing every
   subsession its graph access by instruction rather than by capability. Not in scope here, but
   it is the same disease and should get its own row.

There is, however, a **harder** constraint that does bind the design, and it points the opposite
way from what the mission anticipated. VERIFIED at `scripts/leadv2-route-bandit.sh:495`:

> `# Workflow JS is sandboxed (no shell/fs), so bandit must run here before Workflow().`

and `workflows/leadv2-review.js:26`:

> `// WORKFLOW-BASH-FIX-01: the real Workflow runtime provides ONLY agent()/parallel()/pipeline()/…`

So a Workflow **cannot** shell out. It can only reach a script by spawning an agent whose prompt
says "run this bash command" — which `leadv2-review.js:150-152` already does for Codex. That
inverts the obvious consolidation ("make both paths call the workflow"): the workflow is the
*less* capable container. **The script must be canonical, not the workflow.** Section 3.

---

## 1. Census of duplicate paths

### 1.1 Review (Phase 5) — 2 implementations, 0 shared code

| | Agent/Workflow path | Lane path |
|---|---|---|
| Entry | `Agent(subagent_type=critic\|architect\|security-auditor)`, or `Workflow({name:"leadv2-review"})` | `scripts/leadv2-dispatch-code.sh:2048` `spawn_product_close()` → `scripts/leadv2-dispatch-product-close.sh` |
| Implementation | `workflows/leadv2-review.js` (338 lines) | `leadv2-dispatch-product-close.sh:1447-1667` |
| Gated by | `hooks/leadv2-workflow-bypass-guard.sh` (denies unless `docs/handoff/<task>/.workflow-called-review` exists; needs `LEADV2_WORKFLOW_ENABLED=1`) | `E2E_GATE`/`REVIEW_GATE` (`leadv2-dispatch-code.sh:421-422`, default 1) |
| Reviewers | 4: codex-adversarial (`:150`), critic (`:134`), hack-detect haiku (`:137`), security-auditor if safety (`:143`) | **1** — first eligible arm from the pool |
| Adversarial verification | 8 independent per-finding refutation agents (`:195`, `label: verify:<dimension>`) | **none** |
| Reflect / quality score | yes (`:243` quality-scorer, `:319` reflect, `:284` archive-write) | none |
| Providers reachable | Claude models + Codex (via a haiku agent that runs `codex-task.sh`). **No GLM, no Kimi.** | codex (`:1508`), **glm** (`:1520`, + `omp-task.sh` second channel `:1538`), **kimi** (`:1543`), opus/sonnet via `claude-subsession.sh` (`:1565`) |
| Arm selection | hardcoded model literals in the JS | quota-aware resolver `lib/leadv2-glm-policy-resolve.py --job review --base-arm codex --review-pool --author` (`:230-279`), author-excluding, with a forward-only fallback walk (`next_ok_arm_after`, `:1582`) |
| Output contract | workflow return `{blocking_count, verdict, findings_path}` (`docs/phases.md:277-288`) | `docs/handoff/dispatch-<sig8>/review-gate.md`, `REVIEW_VERDICT:` / `REVIEW_FINDINGS: critical= high= medium= low=` parsed at `:365-401` |

**Which one a lane actually takes today:** the lane path, exclusively. The bypass guard matches on
`.tool_input.subagent_type` (`leadv2-workflow-bypass-guard.sh:24-28`) — a value that exists only
for the in-process `Agent` tool. `spawn_product_close` launches `bash …-product-close.sh`, so the
guard is structurally blind to it. Confirmed by the guard's own case statement and by
`leadv2-dispatch-code.sh:240`: *"supervisor only dispatches: architect, e2e, and review are
agents/scripts."*

**Which one the docs claim is mandatory:** the workflow. `docs/phases.md:277`,
`skills/leadv2-review/WORKFLOW-PATH.md:9`, `skills/leadv2-review/SKILL.md:98`. The guard exists
to *enforce* that claim and enforces it on the one path nobody uses.

Net: **persona-engine's product reviews have been single-reviewer, zero-verifier, for as long as
it has dispatched through lanes** — while the plugin's docs, its guard, and its skill files all
describe a 14-agent adversarial review.

Two smaller review-path artifacts worth naming:

- `LEADV2_DISPATCH_REVIEWER_ARMS` is passed at `leadv2-dispatch-code.sh:2068` and is **dead** —
  the file says so itself at `:3242` (*"the LEADV2_DISPATCH_REVIEWER_ARMS env it feeds is DEAD"*)
  and calls the CSV "vestigial" at `:2061`. A third, half-removed selection mechanism.
- Workflows exist in **two locations**: `plugins/leadv2/workflows/*.js` and
  `~/.claude/workflows/*.js`. `diff` says the five relevant files are currently byte-identical,
  and `ls -la` shows regular files, not symlinks — so this is a real copy that happens to be in
  sync today (VERIFIED byte-identity; INFERRED that they are hand-copied). This violates the
  one-copy rule in `~/.claude/CLAUDE.md` and is a silent-drift surface.

### 1.2 Plan (Phase 2) — 3 implementations

| Path | Implementation | Produces |
|---|---|---|
| Workflow | `workflows/leadv2-plan.js` (437 lines), via `skills/leadv2-plan/SKILL.md:58` and `docs/phases.md:148` | `docs/handoff/<id>/context.yaml`, runs `leadv2-acceptance-shape.sh` validator |
| Lane | `architect_prepass()` in `leadv2-dispatch-code.sh` (~`:1621-1790`); spawns `claude-subsession.sh --role architect` (`:67` of the function body) | `docs/handoff/dispatch-<sig8>/architect-prepass.md` + a `LANE_WRITES:` line harvested at `:1651` |
| Codex | `scripts/leadv2-codex-planner.sh` — a `codex-task.sh` wrapper "for /leadv2 Plan phase" (`:3`), with its own repo-policy off-switch | codex plan artifact |

The lane path documents the divergence in its own comments, `leadv2-dispatch-code.sh:1755-1759`:

> *"…this dispatch flow has no context.yaml to run `leadv2-acceptance-shape.sh` validate against;
> the full leadv2-plan pipeline (Phase 2) is the path that writes context.yaml and runs the real
> validator."*

So the lane substitutes a **heuristic content scan** (`:1757`, and `no_acceptance_block` at
`:1772`) for the real acceptance validator. Same shape as review: the weaker implementation is
the one production takes.

Note the guard again denies `subagent_type=architect` without `.workflow-called-plan` — and the
lane's architect is spawned as `bash claude-subsession.sh --role architect`, so again invisible.

### 1.3 Diagnose / audit / learn — divergent but less acute

- **Diagnose:** `workflows/leadv2-diagnose.js` (161 lines) vs `scripts/leadv2-task-judge.sh` and
  `scripts/leadv2-codex-planner.sh --mode diagnose` (usage block, `:22`). Three call sites,
  no shared verdict contract. No enforcement guard on any of them, so this is duplication
  without a lying-mandatory doc — lower severity, same eventual disease.
- **Audit:** `workflows/leadv2-audit.js` is invoked only from `skills/audit-cluster/SKILL.md:17`.
  No lane equivalent found. Single path today — leave alone.
- **Learn:** `workflows/leadv2-learn.js` invoked from `skills/leadv2-close/SKILL.md:93` and
  nudged by `hooks/leadv2-learn-consume.sh:80`. `scripts/leadv2-phase8-close.sh:434` only *drops
  a signal* for it ("`Learn trigger: every N closes drop a signal`") — it does not reimplement
  it. Single implementation, two triggers. **Not a duplicate path**; do not touch.

### 1.4 E2E — one implementation, correctly shaped (use as the model)

`leadv2-dispatch-product-close.sh:1353` resolves the command through
`scripts/leadv2-e2e-entrypoint.sh` and runs it, then attributes ownership through
`scripts/leadv2-e2e-ownership.sh:1388`. One script, called from wherever. This is exactly the
shape section 3 proposes for review — the plugin already knows how to do this and did it once.

---

## 2. What actually has to be true of the target

Neither existing implementation is a superset of the other. That is the whole reason this is a
design problem and not a deletion.

| Property | Workflow has it | Lane has it |
|---|---|---|
| Multi-reviewer fan-out | ✅ 4 | ❌ 1 |
| Per-finding adversarial refutation | ✅ 8 verifiers | ❌ |
| GLM / Kimi as review arms | ❌ | ✅ |
| Quota-aware, author-excluding arm resolution | ❌ (hardcoded models) | ✅ `--review-pool --author` |
| Survives parent context death | ❌ (in-process) | ✅ (separate process) |
| Machine-checkable artifact on every exit path | partial | ✅ (`review-gate.md`, EXIT trap `:148-156`) |
| Can shell out to `codex-task.sh` / `glm-coder.sh` | only via an agent proxy | ✅ directly |

Target must hold **every** ✅ in both columns.

---

## 3. Recommended target design — the script is canonical

### 3.1 One implementation

New file (to-create): `plugins/leadv2/scripts/leadv2-review-run.sh` — the review engine. Plain
bash, no Workflow runtime, no in-process Agent tool. It owns, in one place, what is today split
across `leadv2-review.js` and `leadv2-dispatch-product-close.sh:1447-1667`:

1. **Arm pool resolution** — lift `resolve_review_pool_call()` (`…product-close.sh:230-279`)
   verbatim into the engine. Keeps `lib/leadv2-glm-policy-resolve.py`, keeps
   `lib/leadv2-review-signals.sh`, keeps author-exclusion, keeps quota bands (GLM reviews to its
   own 90% band; Codex 90/95; Claude 95).
2. **Reviewer fan-out, N arms in parallel** — background jobs + `wait`, N from
   `LEADV2_REVIEW_FANOUT` (default 3), each arm taken from the resolved pool so the fan-out is
   *automatically multi-provider*: codex + glm + sonnet, not three Claudes. Plus the always-on
   cheap `hack-detect` pass (today `leadv2-review.js:137`, haiku). The existing per-arm launchers
   move over unchanged: codex `:1508`, glm/omp `:1520-1538`, kimi `:1543`, claude-subsession
   `:1565`.
3. **Verifier fan-out** — for each Critical/High finding, one refutation job whose only task is
   to *refute that finding*, on a **different arm than the one that raised it**. This is the
   capability the lane has never had. Port the prompt/schema from `leadv2-review.js:195`.
4. **Synthesis + contract** — the engine is the sole writer of both artifacts:
   - `docs/handoff/<task>/review-gate.md` — existing contract, extended with
     `arms: <csv>` and `verified: <n>/<n>` lines (additive; the existing parser at `:365-401`
     ignores unknown lines, so this is backward-compatible).
   - `docs/handoff/<task>/review-findings.json` — new, one object per finding with
     `{dimension, severity, arm, verifier_arm, verifier_verdict}`.

### 3.2 Both entry points converge on it

- **Lane:** `leadv2-dispatch-product-close.sh:1447-1667` is replaced by a single call to the
  engine. The lane keeps its process model, its EXIT trap, its `_stamp_review_terminal`
  (`:210`), its `review_crashed` fallback (`:154`). It gains 3 reviewers and verifiers.
- **Lead / interactive:** the `/leadv2` review phase calls the engine over `Bash`.
  `skills/leadv2-review/SKILL.md` and `WORKFLOW-PATH.md` are rewritten to point at the engine.

### 3.3 What gets deleted

A path kept "for compatibility" is how this happened. Delete, in this order:

| Delete | Why |
|---|---|
| `workflows/leadv2-review.js` **and** `~/.claude/workflows/leadv2-review.js` | superseded; deleting only one leaves the copy live |
| `hooks/leadv2-workflow-sentinel-touch.sh` review branch, `.workflow-called-review` sentinel | the sentinel proved a *tool call*; the artifact proves the *work* |
| `LEADV2_DISPATCH_REVIEWER_ARMS` (`…dispatch-code.sh:2061,2068,3242`) | already dead by its own comment |
| `leadv2-dispatch-product-close.sh:1447-1667` body | becomes one call |

**Repointed, not deleted:** `hooks/leadv2-workflow-bypass-guard.sh`. Its guard predicate changes
from *"was the Workflow tool called"* to *"does `docs/handoff/<task>/review-gate.md` exist with a
parsed `REVIEW_VERDICT:`"*, and its match predicate widens from `subagent_type` to also cover
`Bash` invocations of the dispatch scripts. That single change is what makes the guard see the
lane for the first time.

### 3.4 Plan — the same move, one step behind

Same treatment, sequenced after review lands and proves out: extract
`plugins/leadv2/scripts/leadv2-plan-run.sh` owning `context.yaml` + the real
`leadv2-acceptance-shape.sh` validation; `architect_prepass()` calls it instead of its heuristic
scan (`…dispatch-code.sh:1755-1772`); `workflows/leadv2-plan.js` and its `~/.claude` copy are
deleted; `leadv2-codex-planner.sh` survives as an *arm* inside the engine's pool, not as a
parallel entry point. Do not start this until review is green in all three repos.

Diagnose: fold `leadv2-codex-planner.sh --mode diagnose` and `leadv2-task-judge.sh` into one
engine later; unguarded and low-severity, so it is last.

---

## 4. Blast radius and migration order

**What breaks if this lands mid-flight.** The plugin is one inode viewed from three repos, so an
edit is live in all three the instant it is written — there is no propagation step to stage
behind. A lane in flight has already `bash`-spawned `leadv2-dispatch-product-close.sh` as a
separate process; POSIX keeps the running process on the old inode content for an in-place
rewrite (INFERRED for the editor's actual write mode — most editors replace rather than truncate,
which is the safe case), but **any lane that spawns product-close after the edit runs the new
code**. Since `spawn_product_close` is called at `…dispatch-code.sh:3261` and `:3467` — i.e. at
the *end* of a build — a lane that is mid-build right now will hit the new code at its review
gate.

Therefore: **land behind `LEADV2_REVIEW_ENGINE`, default `0`.** At `0` the call site is
byte-identical to today. Flip per repo, in `.claude/settings.json`.

Migration order:

1. **persona-engine** — biggest gap (lane-only, so it has *never* had adversarial review) and
   the repo that dispatches. Flip first, soak one full lane close.
2. **respiro-ios** — also `LEADV2_WORKFLOW_ENABLED=1`; flip after persona-engine's soak.
3. **m3-market** — last, and needs care: `codex_enabled: false` in its
   `.claude/leadv2-overrides/codex-policy.yaml` (`leadv2-codex-planner.sh:5-6`), so the engine's
   pool must degrade to glm/kimi/claude without a fail-closed `all_arms_unavailable`. Verify the
   resolver's refusal path (`:225-228`) before flipping.

Only after all three are green: delete `leadv2-review.js` (both copies) and the sentinel machinery.
Deleting earlier strands any repo still on the flag's `0` side.

---

## 5. Test strategy — a test that fails today

The regression class is "a path silently skips the mandated review". Tests must assert on
**artifacts the lane produces**, never on which tool was called.

| # | Test | Fails today because |
|---|---|---|
| T1 | Drive a stub lane through `spawn_product_close` with fake arms; assert `review-gate.md` lists **≥2 distinct arms** in `arms:` | lane emits exactly one arm |
| T2 | Same run; assert `review-findings.json` carries a `verifier_verdict` for **every** Critical/High finding | lane produces no verifier data and no findings file at all |
| T3 | Assert the verifier arm ≠ the arm that raised the finding | no verifiers exist |
| T4 | Guard test: feed `leadv2-workflow-bypass-guard.sh` a `Bash` event invoking `leadv2-dispatch-product-close.sh` with no `review-gate.md` present; assert `permissionDecision=deny` | guard only matches `subagent_type`, returns exit 0 at `:27` |
| T5 | Census test (static): grep the tree for review-orchestration constructs outside the engine — `agent(… agentType: 'critic'`, `--role critic`, `adversarial-review` — assert exactly one owning file | at least three own it today |
| T6 | Pool-degradation: with `codex_enabled=false` and GLM over its band, assert a non-empty pool and no `all_arms_unavailable` | untested today; the exact bug fixed at `:215-228` for a single-arm resolver |
| T7 | One-copy test: assert `~/.claude/workflows/*.js` are symlinks to the plugin (or absent) | they are regular-file copies |

T1/T2 are the ones the mission asked for: they fail today precisely because the lane skips the
fan-out. T5 is the one that keeps this from recurring — it fails the moment someone adds a fourth
path.

---

## 6. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Cost/latency.** 1 reviewer → 3 reviewers + N verifiers, on every lane close. | `LEADV2_REVIEW_FANOUT` default 3, verifiers capped at Critical/High only and run on cheap arms (haiku/glm/kimi). Founder's standing note is that LLM budget is abundant; latency is the real cost, and the fan-out is parallel. |
| R2 | **`review-gate.md` write race.** Both the engine and product-close's EXIT trap (`:148-156`) can write it. | Engine writes to `review-gate.md.tmp` and `mv`s (atomic within a filesystem); the trap writes only if the file is absent, which it already checks at `:154`. State the ordering constraint in the engine header. |
| R3 | **Fan-out amplifies a stuck arm.** Today one hung arm hangs one review; with 3+N jobs the hang surface triples. | Per-job `timeout`, and reuse the forward-only pool walk (`next_ok_arm_after`, `:1582`) so a dead arm is skipped, never retried. Partial fan-out (2 of 3 returned) must still yield a verdict, marked `arms: 2/3`. |
| R4 | **Guard repointing fails open and nobody notices.** The guard already has `trap 'exit 0' ERR` and fails open by design. | T4 runs in CI on the plugin repo; the guard's deny path is asserted, not assumed. |
| R5 | **`claude -p` flag drift in the engine.** Any new `claude -p` the engine adds must carry `--max-turns`, `--permission-mode`, `--output-format`. Note `claude-subsession.sh:338-342`: `-p` + `stream-json` **requires `--verbose`** or the process dies instantly, which silently killed the sonnet channel once. | Engine spawns Claude arms only through `claude-subsession.sh`, never with a bare `claude -p`. No second invocation idiom. |
| R6 | **Mid-flight lane.** Covered in §4. | `LEADV2_REVIEW_ENGINE=0` default; flip after the in-flight lane closes. |
| R7 | **Deleting `leadv2-review.js` breaks a repo still on the old flag.** | Delete only after all three repos are flipped and soaked. |
| R8 | **Env-var drift.** `LEADV2_REVIEW_ENGINE`, `LEADV2_REVIEW_FANOUT` follow the `LEADV2_*` convention and do not collide with any existing name in `hooks/hooks.json` or the dispatch scripts (checked by grep). | Add both to the plugin's env registry in the same commit that introduces them. |

---

## 7. Out of scope (for the implementing agent)

- Learn (`workflows/leadv2-learn.js`) — single implementation, do not touch.
- Audit (`workflows/leadv2-audit.js`) — single call site, do not touch.
- Plan consolidation — designed in §3.4, but **do not start it in the same change**.
- Diagnose consolidation — last, separate task.
- Fixing `claude-subsession.sh:220`'s false "NO MCP access" claim — real bug, own row.
- Any change to the E2E gate — it is already the correct shape.
- Supervisor/fanout mode — paused by founder order; do not re-enable to test anything here.

---

## FOUNDER CONSTRAINTS (stated 2026-08-06, after reading this design)

Verbatim intent: "мне не важно через воркфлоу или нет оно будет, лишь бы везде одинаково и
работало как можно лучше, и поддерживало и GLM и Codex как синг воркеров, и Codex как
полноправного лида."

This settles three things and adds one the design did not cover:

1. **The container is not the point.** Workflow-vs-script is an implementation detail the founder
   explicitly does not care about. The script-canonical recommendation stands on its own merits
   (the Workflow sandbox cannot reach `codex-task.sh` / `glm-coder.sh` without an agent proxy),
   not on anyone's preference. Do not relitigate it — but equally, do not defend it as a value.
2. **One path everywhere is the hard requirement.** Same behaviour from the lane, from the lead,
   and from any of the three consuming repos. A second path kept "for compatibility" fails this.
3. **GLM and Codex as single workers must both keep working.** Not a Claude-only fan-out with the
   others bolted on. Pool degradation (m3-market has Codex disabled) must degrade, never fail closed.
4. **NEW — Codex as a full lead, not just a worker or reviewer.** The design as written treats Codex
   as one arm in a review pool. The founder wants Codex able to run a whole task the way the Claude
   lead does — the `leadv2-codex-session-runner.sh` full-cycle path. So the consolidation must not
   assume the lead is Claude: whatever `leadv2-review-run.sh` becomes has to be callable from a
   Codex-led session too, with no Claude-only dependency on the critical path (no Agent tool, no
   Workflow tool, no in-session MCP).

Point 4 is the one that can invalidate parts of this design. Before building, confirm what
`leadv2-codex-session-runner.sh` can actually invoke today, and whether a Codex-led session can
reach the same review engine. If it cannot, that gap is the first thing to fix — a "single path"
that only exists when Claude is the lead is not a single path.
