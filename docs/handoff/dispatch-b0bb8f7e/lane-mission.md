Product implementation task dispatch-b0bb8f7e. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# ONE-PATH-EVERYWHERE-01 — Plan + Diagnose consolidation design

Author: architect prepass (`dispatch-b0bb8f7e-architect`)
Date: 2026-08-06
Status: design only — no executable code written by this pass.

---

## 0. Input gap — read this first

The mission instructed me to read, in order:

1. `docs/handoff/one-review-path-2026-08-06/design.md`
2. `docs/handoff/one-review-path-2026-08-06/mission-build-r1.md`

**Neither file exists.** The entire directory `docs/handoff/one-review-path-2026-08-06/`
was absent before this document created it, and `git log -- docs/handoff/one-review-path-2026-08-06`
returns nothing — it was never committed, so it is not an uncommitted-worktree artifact either.
Checked from `/Users/kostiantyn.vlasenko/Projects/leadv2` (the plugin repo, confirmed by `pwd`),
plus a repo-wide `find` for `design.md` and `mission-build-r1.md`: zero hits outside
`node_modules`.

Consequences, stated plainly rather than papered over:

- The §1.2/§1.3 census I was told to extend does not exist. **I rebuilt the census from source**,
  with file:line for every claim below. That part of the deliverable is complete and independently
  verifiable.
- The §3.4 four-line Plan sketch I was told to deepen, and the review lane's engine shape I was
  told to reuse, are **unreadable**. I therefore cannot honestly report "what in §3.4 I am
  contradicting" — I can only report what I would contradict *if* the sketch says certain things.
  §7 does that as a conditional list. Treat §7 as questions for the review lane, not as verdicts.
- The engine shape in §3 is derived from the **structural slots that actually exist in the code
  today** (`_lane_writes_guard` / `_acceptance_guard` / `_phase_precondition_guard` as sibling
  pre-dispatch guards; `_load_ladder` / `_build_candidate_chain` / `_filter_dispatchable` as the
  arm pool; `emit decision <verb> task=<sig8> status=… reason=…` as the journal vocabulary).
  Any engine the review lane builds will have to live in those same slots, so the shape below is
  a reasonable convergence target — but it is inferred, not confirmed against `mission-build-r1.md`.

**Action for the lead:** if `design.md` exists somewhere I could not see (another checkout, an
uncommitted worktree, a different machine), re-run this pass with the file present. §7 is the only
section whose conclusions would move.

---

## 1. Plan — census of the three implementations

### 1.1 P1 — `architect_prepass()` in the dispatch flow

**File:** `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
**Function:** `architect_prepass()` — lines 1852–1985
**Guard:** `_acceptance_guard()` — lines 1760–1774
**Call site:** lines 2861–2866 (retry loop → park)

The comment the mission asked me to find and quote verbatim, at `leadv2-dispatch-code.sh:1752-1759`:

```
# _acceptance_guard <sig8> <design_file> -> 0 ok, 1 park
# RED-FIRST-GATE-01 R2: refuses a design whose acceptance is missing, not one
# of the five surface types, or reads as an internal contract (the exact
# phrasing skills/leadv2-plan/SKILL.md used to mandate, and the root cause of
# tautological review). Heuristic content scan of the prepass artifact itself
# -- this dispatch flow has no context.yaml to run leadv2-acceptance-shape.sh
# validate against; the full leadv2-plan pipeline (Phase 2) is the path that
# writes context.yaml and runs the real validator.
```

The heuristic itself, lines 1764–1770:

```bash
  if grep -q '^acceptance:' "${design_file}" \
     && grep -qE '^[[:space:]]*surface:[[:space:]]*(rendered_line|prod_db_row|log_line|http_response|file_artifact)[[:space:]]*$' "${design_file}" \
     && grep -qE '^[[:space:]]*observable:' "${design_file}" \
     && grep -qE '^[[:space:]]*authored_at:' "${design_file}" \
     && ! grep -qiE '^[[:space:]]*observable:.*(function |returns |exit code|variable|is set to)' "${design_file}"; then
    return 0
  fi
```

Compare against what `leadv2-acceptance-shape.sh` (207 lines) actually validates, per its own
header at lines 16–31:

| Check | `_acceptance_guard` heuristic | `leadv2-acceptance-shape.sh validate` |
|---|---|---|
| `acceptance:` block present | `grep -q '^acceptance:'` — matches anywhere, including inside a fenced code block or a prose quotation | structured read of the top-level key |
| `surface` in the five-value enum | yes, but matched **anywhere in the file** — not scoped to inside the `acceptance:` block | scoped to `acceptance.surface` |
| `observable` non-empty | **not checked** — `grep -qE '^\s*observable:'` matches a bare `observable:` with nothing after it | non-empty required |
| `observable` free of internal-contract phrasing | 5 phrases, and only when they appear on the *same line* as `observable:` — a multi-line YAML scalar evades it entirely | same 5 phrases, evaluated against the parsed value |
| `authored_at` parses as ISO-8601 | **not checked** — presence only; `authored_at: yesterday` passes | ISO-8601 parse required |
| `authored_at` precedes the diff | **not checked at all** | `assert-precedence` subcommand: `authored_at` ≤ earliest mtime of the `LANE_WRITES` files |

So the guard is not merely "a heuristic instead of the validator" — it is a **strict subset that
misses the two checks that carry RED-FIRST-GATE-01's actual purpose**: that `observable` says
something, and that it was authored *before* the code existed. A design with
`acceptance:` / `surface: log_line` / `observable:` / `authored_at: later` passes today.

The only other caller of the real validator is `leadv2-phase8-assert.sh:535-552` (assertion A11),
which runs it at close — i.e. after the work is done. The gate that could have *prevented* the
bad design never runs it.

**What P1 uniquely does** (the merged engine must not lose any of these):

- It is the only Plan path that runs **inside a lane dispatch**, before a worker spawns.
- Sig-keyed prepass cache: `<artifact>.sig` holds `compute_sig` of the full mission text
  (1875–1896), with the H4 correction that a cached artifact carrying no `LANE_WRITES:` line is
  treated as a **miss**, not a hit (1884–1894), and the M7 correction that a park still stamps the
  cache so a byte-identical retry does not pay the architect twice (1970–1976).
- Short-mission prompt variant (<15 non-blank lines → terser framing, 1899–1908).
- Artifact-not-stdout discipline (1939–1950): reads `architect.full.md` / `architect.md` /
  `architect.summary.md` from the architect's handoff dir. The comment records the 2026-07-29
  incident where capturing `2>&1` wrote log metadata into `architect-prepass.md` and a correct
  21 KB design was never read.
- Process-group timeout via inline Python (1912–1936) — macOS has no portable `timeout`;
  `os.killpg` on `TimeoutExpired` so a descendant holding stdout cannot hang `communicate()`.
- `LANE_WRITES:` extraction (`_prepass_writes`) feeding `_lane_writes_guard` (1732–1750), which
  accepts *any one of*: row-declared writes, the artifact's own `LANE_WRITES:` line, or an existing
  lane worktree (isolation substitutes for declaration).
- Kill-switch `ARCHITECT_GATE=0` that still cannot bypass isolation (1855–1863, the H6 fix).
- `provably_one_file` skip when the writes CSV has exactly one non-empty entry (1864–1872).
- Full journal vocabulary: `architect_prepass task=… status={ran,skipped,disabled,cached,cache_miss,failed,retrying,parked}`.

### 1.2 P2 — `leadv2-plan.js` (Workflow)

**Canonical:** `plugins/leadv2/workflows/leadv2-plan.js`
**Second copy:** `/Users/kostiantyn.vlasenko/.claude/workflows/leadv2-plan.js` — 28 854 bytes,
mtime `Aug 3 12:31`. This is a **real copy, not a symlink**, and it is exactly the drift hazard the
global shared-trees policy forbids. It is one of the three Plan implementations in the sense that
matters: it is a separately-mutable file that the Workflow runtime may load instead of canonical.

Structure (`meta.phases`, lines 5–9): Classify (haiku capability-match) → Plan (dynamic role
fan-out + context envelope) → Synthesize (merge into `context.yaml`).

**What P2 uniquely does:**

- It is the **only path that writes a real `context.yaml`** (`CTX`, line 19) — the artifact
  `leadv2-acceptance-shape.sh validate` and phase8-assert A11 both consume.
- Deterministic post-write validation of `REQUIRED_FIELDS = ['id','mission','reads','writes','acceptance', …]`
  (line 402) in **code, not LLM judgment**, with exactly one retry (410–419) that re-runs the
  deterministic persist because the retry rewrites `context.yaml` wholesale.
- Model policy per PLANNER-MODELS-DECISION-01 (lines ~30–40): `ARCH_MODEL = HEAVY ? 'fable' : 'opus'`;
  Codex is the same-tier second planning brain; GLM/Kimi are build-only and never admitted to a
  planning role.
- Bandit model wiring (`args.models`, BANDIT-WIRE-01) with a byte-identical flag-off guarantee.
- Flag-gated code_map injection (CODEMAP-CONTEXT-01) capped at 2000 chars including the truncation
  note.
- Context envelope from `shared-memory.yaml` + `solutions-archive.yaml`.
- Ledger emission.

**Why P2 disqualifies itself as the single path:** it is a Workflow script. It runs only under the
Workflow tool, which exists only under a Claude lead. A Codex lead, a GLM lead, or a bare
`bash`-driven dispatch cannot reach it. Per the mission's own hard constraint — *"a path that works
only under a Claude lead is not a single path"* — P2's **orchestration** cannot be the target. Its
**content decisions** (required fields, model policy, envelope, validation-then-one-retry) are
exactly what must be preserved.

Note also the WORKFLOW-BASH-FIX-01 comment block (lines 55–70): four bare `await bash(...)` calls
crashed at runtime because the Workflow runtime provides no `bash()` global, and the fix was to
fold every shell operation into an agent prompt that runs the command via its own Bash tool. That
is a standing tax the JS host imposes and a bash engine does not.

### 1.3 P3 — `leadv2-codex-planner.sh --mode plan`

**File:** `plugins/leadv2/scripts/leadv2-codex-planner.sh` (325 lines)
Self-described at line 3 as "wrapper around codex-task.sh for /leadv2 Plan phase".

**What P3 uniquely does:**

- **Repo-level Codex policy short-circuit** (lines 5–17): when `_lv2_codex_enabled` is false
  (m3-market's `codex-policy.yaml`), it prints a clear stderr message, emits
  `codex_skipped_by_policy` on stdout, and **exits 0**. This is already the exact
  degrade-not-fail-closed primitive the rollout needs — see §5.3.
- Tier→(model, effort) resolution from `~/.codex/models_cache.json` (lines 90–117):
  `top → gpt-5.6-sol/high` with a gov-gated fallback to `gpt-5.6-terra/ultra`;
  `standard → gpt-5.6-terra/medium`; `volume → gpt-5.6-luna/low`. Spark is banned at every tier,
  with `codex-task.sh` as a second gate.
- `--tier top` **requires `--reason`** (CODEX-QUOTA-GUARDRAILS-01, lines 77–88) — refuses otherwise.
- `--print-model` dry-run that resolves and prints without calling Codex or validating
  `--task-id`/`--mission`.
- `--mission-file` read early for race protection; mutually exclusive with `--mission`.
- Four modes on one entry point: `plan | quick-verify | diagnose | reconfirm` (line 131).
- `LEADV2_TEST_MODE=1` short-circuit that loads the mission and skips dispatch.

P3 is **not** a competing orchestrator. It is a single-provider executor with a policy gate and a
quota gate. That is precisely the shape of an *arm*, which is why §3.4 of this document keeps it.

### 1.4 Summary of the split

| Concern | P1 prepass | P2 plan.js | P3 codex-planner |
|---|---|---|---|
| Reachable without a Claude lead | ✅ bash | ❌ Workflow tool only | ✅ bash |
| Writes `context.yaml` | ❌ | ✅ | ❌ |
| Runs the real acceptance validator | ❌ (heuristic) | ❌ (own field list) | ❌ |
| Multi-arm / quota-aware | ❌ (single architect) | partial (bandit models) | ✅ (tier + policy) |
| Caching | ✅ sig-keyed | ❌ | ❌ |
| Runs pre-dispatch inside a lane | ✅ | ❌ | ❌ |

No single row is complete. That is the consolidation case, stated as data.

---

## 2. Diagnose — census of the three implementations

### 2.1 D1 — `leadv2-diagnose.js` (Workflow)

`plugins/leadv2/workflows/leadv2-diagnose.js`, plus a **real copy** at
`/Users/kostiantyn.vlasenko/.claude/workflows/leadv2-diagnose.js` — 8 755 bytes, mtime `Jul 11 02:47`,
i.e. ~3.5 weeks staler than the plan.js copy. Same one-inode violation, worse drift.

Shape (`meta.phases`, lines 5–9): Classify (haiku symptom-classifier, ≤3 clusters) → Trace
(parallel evidence-gather per cluster, haiku, max 3) → Reduce (sonnet merges into one root_cause
verdict). Returns `root_cause, confidence, evidence_files, fix_hint, alternates`.
Defaults `logsHint` to a `journalctl -u persona-engine` tail and `dbHint` to persona-engine table
names (lines 17–18) — **PE-domain constants hardcoded in a plugin-wide workflow**, which is its own
latent portability defect for respiro-ios and m3-market.

Claude-lead-only, same as P2.

### 2.2 D2 — `leadv2-codex-planner.sh --mode diagnose`

`plugins/leadv2/scripts/leadv2-codex-planner.sh:172-177`:

```bash
    diagnose)
      LOG_CONTENT=""
      [[ -n "$LOG_PATH" && -f "$LOG_PATH" ]] && LOG_CONTENT="$(tail -100 "$LOG_PATH" 2>/dev/null || true)"
      DIFF_CONTENT="$(_read_or_literal "$DIFF_PATHS")"
      MISSION="independent root-cause hypothesis. Log: ${LOG_CONTENT}. Diff: ${DIFF_CONTENT}. Max 3 hypotheses, one sentence each"
      ;;
```

One provider, ≤3 hypotheses, log tail bounded at 100 lines. Inherits P3's tier/quota/policy gates
for free.

### 2.3 D3 — the recovery skill's own invocation contract

`plugins/leadv2/skills/leadv2-iterative-recovery/SKILL.md:45` invokes
`leadv2-codex-planner.sh --task-id <id> --mode diagnose --effort medium`. This is the third
implementation in the only sense that matters operationally: it is a **separately-authored
invocation contract** with its own effort choice and its own framing, maintained in a skill file,
that no test covers and that drifts independently of both D1 and D2.

Adjacent and worth naming even though it dispatches nothing: `leadv2-task-judge.sh:120-125` derives
`work_kind = 'diagnose'` from keyword matching (`'root cause', 'root-cause', 'diagnose', 'debug',
'bug report'`), and `leadv2-task-judge-prompt.tmpl:13` puts `diagnose` in the classifier enum. The
system **classifies** work as diagnose and then routes it nowhere in particular — the classification
has no consumer. There is no `skills/leadv2-diagnose/` directory (checked).

### 2.4 Recommendation — fold Diagnose into the Plan engine, do not give it its own

**Recommendation: Diagnose does not deserve its own engine. Fold it into `leadv2-plan-run.sh` as
`--mode diagnose`.** This is a recommendation, not a hedge; here is why, and here is what would
change my mind.

Why:

1. **The control flow is the same shape.** Plan is classify → role fan-out → synthesize one
   artifact. Diagnose is classify → cluster fan-out → synthesize one artifact. D1's own
   `meta.phases` (Classify/Trace/Reduce) is P2's `meta.phases` (Classify/Plan/Synthesize) with the
   nouns changed. A second engine would duplicate the arm pool, the quota degrade, the journal
   vocabulary, the timeout wrapper, and the artifact-not-stdout discipline to vary two prompts and
   one output schema.
2. **The differences are parameters, not architecture.** Diagnose has no `acceptance:` block and no
   `LANE_WRITES:` (it produces a hypothesis, not a diff), it takes log/diff inputs, and it emits
   `root_cause/confidence/evidence/fix_hint/alternates` instead of `plan.steps[]`. Those are a
   mode flag, an input-assembly branch, and an output schema — three parameters.
3. **Volume does not justify the maintenance surface.** Plan runs on every dispatch above Trivial.
   Diagnose runs on defect intake and inside iterative-recovery. Two engines means every future
   fix (a quota gate, a journal verb, a timeout correction) gets applied twice, and history says
   the second copy is the one that rots — see the two `~/.claude/workflows/` copies, 3.5 weeks and
   3 days stale respectively.
4. **It is unguarded and lower severity, as the mission notes.** That is an argument for *less*
   machinery, not for a parallel one. Folding it in gives it the arm pool and the quota degrade it
   does not have today, at near-zero incremental cost.

What would change my mind: if the review lane's engine turns out to be structured such that
"mode" is not a first-class parameter — e.g. if it hard-binds one output schema per engine
instance. In that case Diagnose becomes a second *instantiation* of the same engine rather than a
mode of one, which is still one engine's worth of code, just configured twice. Either way the
answer is not "Diagnose gets its own engine."

---

## 3. Target — `leadv2-plan-run.sh`

### 3.1 Placement and reachability

`plugins/leadv2/scripts/leadv2-plan-run.sh`, a bash entry point, invoked identically by:

- **the lane**, from `leadv2-dispatch-code.sh`'s `architect_prepass()` — which shrinks to a call;
- **the lead**, whatever the lead is — Claude, Codex, GLM, or a human at a terminal — because a
  bash script needs no Agent tool, no Workflow tool, and no in-session MCP.

Interface:

```
leadv2-plan-run.sh --task-id <id> --mode <prepass|plan|diagnose>
                   (--mission "<text>" | --mission-file <path>)
                   [--writes <csv>] [--class <trivial|light|standard|heavy>]
                   [--log-path <file>] [--diff-paths <str>]   # diagnose only
                   [--timeout-sec <n>] [--no-cache]
```

Exit codes: `0` produced | `1` refused (park, reason on stderr and in the journal) |
`2` usage | `4` config error.

### 3.2 What it owns

1. **`context.yaml`.** The engine — not an LLM — creates
   `docs/handoff/<task-id>/context.yaml` and writes the deterministic fields (`id`, `mission`,
   `reads`, `writes`, `lane_writes`, `acceptance.authored_at`). The arm fills the judgment fields
   (`decisions[]`, `off_limits[]`, `plan.steps[]`, `acceptance.surface`, `acceptance.observable`,
   `risk`). This inverts today's P2 arrangement where an agent prompt writes the whole file and
   deterministic code checks it afterwards.

   This is the load-bearing change. **The prepass's excuse disappears**: once the prepass writes a
   `context.yaml`, the comment at `leadv2-dispatch-code.sh:1757` — *"this dispatch flow has no
   context.yaml to run leadv2-acceptance-shape.sh validate against"* — is no longer true, because
   the flow now has one. The fix is not to improve the heuristic; it is to remove the condition
   that forced a heuristic.

2. **Real acceptance validation.** `leadv2-acceptance-shape.sh validate <context.yaml>` gates the
   result, and `assert-precedence --task-id <id>` runs as well when `LANE_WRITES` names files that
   exist. `_acceptance_guard` in dispatch-code.sh becomes a shim that calls this, deleting the
   grep chain at 1764–1770 outright. Same flag semantics as today:
   `LEADV2_REQUIRE_ACCEPTANCE=0` makes a failing verdict non-blocking; the validator always
   evaluates and always reports the true verdict, per its own header (lines 33–37).

3. **The arm pool for planning roles.** Reuse `_load_ladder` / `_build_candidate_chain` /
   `_filter_dispatchable` rather than inventing selection. This requires one generalization: the
   dispatchable set is currently `DISPATCHABLE_BUILD_ARMS` (`lib/leadv2-glm-policy-resolve.py`,
   read at `leadv2-dispatch-code.sh:904-955`, with the legacy fallback `(glm codex sonnet)` at
   861–869 asserted equal by `tests/test-arm-ladder-vocabulary-drift.sh`). Plan needs a
   **role-scoped** set — `DISPATCHABLE_PLAN_ARMS` — so PLANNER-MODELS-DECISION-01's rule that
   GLM/Kimi are build-only survives as *set membership*, not as a hardcode in routing. The ladder
   stays the single source of order; the role decides the set; quota, task and complexity decide
   the pick. **No arm is ever named in or out at a call site.**

4. **Everything P1 already got right**, carried over unchanged in behaviour: the sig-keyed cache
   including H4 (a cached artifact with no `LANE_WRITES:` is a miss) and M7 (stamp before parking);
   the short-mission prompt variant; the process-group timeout; the artifact-not-stdout read order;
   the `provably_one_file` skip; the `ARCHITECT_GATE=0` kill switch that still cannot bypass
   isolation; the full `emit decision` vocabulary.

5. **Everything P2 already got right**, carried over as engine logic rather than prompt text:
   `REQUIRED_FIELDS` validation in code with exactly one retry; the model policy
   (`opus` for Standard, `fable` for Heavy, Codex as same-tier second brain); the shared-memory +
   solutions-archive envelope; the capped code_map; bandit model consumption with a byte-identical
   flag-off guarantee.

### 3.3 What gets deleted

| Deleted | Replaced by |
|---|---|
| `_acceptance_guard` body, `leadv2-dispatch-code.sh:1764-1770` | a call to `leadv2-acceptance-shape.sh validate` |
| `architect_prepass` body, `leadv2-dispatch-code.sh:1873-1984` | a call to `leadv2-plan-run.sh --mode prepass` |
| `plugins/leadv2/workflows/leadv2-plan.js` — orchestration only | `leadv2-plan-run.sh --mode plan`; the JS file becomes a thin shim that shells out, so an existing Claude-lead `Workflow({name:'leadv2-plan'})` call keeps working |
| `plugins/leadv2/workflows/leadv2-diagnose.js` | `leadv2-plan-run.sh --mode diagnose` (same shim treatment) |
| `~/.claude/workflows/leadv2-plan.js` (real copy) | per-file symlink to canonical |
| `~/.claude/workflows/leadv2-diagnose.js` (real copy) | per-file symlink to canonical |

The two `~/.claude/workflows/` copies are the highest-value deletions here and they are
independent of everything else — they can land first, alone, as their own commit.

### 3.4 How `leadv2-codex-planner.sh` survives

It survives **as the implementation of the `codex` arm inside the plan pool**, not as a parallel
entry point. Concretely:

- `leadv2-plan-run.sh` resolves `candidate_arms` from the ladder filtered by
  `DISPATCHABLE_PLAN_ARMS`. When the chain reaches `codex`, the engine invokes
  `leadv2-codex-planner.sh --task-id <id> --mode <plan|diagnose> --tier <resolved>`.
- Tier resolution, the `--tier top` `--reason` requirement, the spark ban, and the
  `codex_enabled: false` short-circuit all stay **inside codex-planner.sh**. The engine does not
  reimplement or second-guess them — it calls the arm and reads the result.
- `codex_skipped_by_policy` on stdout with exit 0 is the arm's "I am unavailable" signal. The
  engine treats it as `arm_unavailable`, emits a journal line, and advances the chain. It is
  **not** an error and **not** a park.
- The direct CLI entry point stays callable for the recovery skill and for humans; it simply stops
  being a *planning orchestrator* and becomes an executor that the engine happens to also call.

Net effect: one orchestrator, N arms, and the arm that knows the most about Codex quota keeps
owning that knowledge.

---

## 4. Sequencing and file collisions

Both engines want `leadv2-dispatch-code.sh`. The review lane holds it right now. The collision is
narrower than it looks:

- **Plan's footprint in that file is two contiguous function bodies**: `_acceptance_guard`
  (1760–1774) and `architect_prepass` (1852–1985). Both are replaced wholesale by short calls.
- The review lane's work is in the reviewer/spawn region — `spawn_worker` and the
  `reviewer_arms` handling from ~2052 onward (`leadv2-dispatch-code.sh:2052`).
- These regions do not overlap. But "does not overlap" is a merge-conflict argument, not a
  correctness argument, and both lanes editing one 3 483-line file concurrently is how a lane
  silently reverts another lane's edit (see the global re-diff-before-staging rule).

**Safe order:**

| Step | Work | Touches `dispatch-code.sh`? | Parallel with review? |
|---|---|---|---|
| 0 | Symlink the two `~/.claude/workflows/` copies to canonical | no | ✅ yes, immediately |
| 1 | Create `leadv2-plan-run.sh` + its tests, with `--mode prepass\|plan\|diagnose` fully working standalone; add `DISPATCHABLE_PLAN_ARMS` | no | ✅ yes, immediately |
| 2 | Review lane merges | yes (review's own hunks) | — |
| 3 | Swap the two function bodies in `dispatch-code.sh` to call the new script | **yes** | ❌ serialize behind step 2 |
| 4 | Turn `leadv2-plan.js` / `leadv2-diagnose.js` into shims | no | ✅ after step 1 |
| 5 | Delete `_acceptance_guard`'s grep chain (subsumed by step 3) | yes | ❌ same commit as step 3 |

Steps 0, 1 and 4 are genuinely parallel with the review lane today — that is the bulk of the work,
and it is unblocked. Only step 3 must wait, and it is a small, mechanical, reviewable commit.
Immediately before staging step 3, `git diff plugins/leadv2/scripts/leadv2-dispatch-code.sh` —
a concurrent session in the same repo can write that file from its own state.

---

## 5. Rollout

### 5.1 Flags

| Flag | Default | Effect at 0 |
|---|---|---|
| `LEADV2_PLAN_RUN` | `0` | `architect_prepass` and `leadv2-plan.js` behave byte-identically to today |
| `LEADV2_DIAGNOSE_RUN` | `0` | `leadv2-diagnose.js` behaves byte-identically to today |

Existing flags keep their meanings unchanged: `LEADV2_REQUIRE_ACCEPTANCE`,
`LEADV2_REQUIRE_LANE_WRITES`, `LEADV2_ARCHITECT_GATE`, `LEADV2_PREPASS_CACHE`.
All new flags follow the `LEADV2_*` prefix — no `LEAD_V2_*` variant is introduced anywhere. Both
new flags must be added to `.claude/settings.json`'s `env` block at the same value they default to
in code, so the two never disagree.

### 5.2 Stages

persona-engine (highest volume, fastest signal) → respiro-ios → m3-market (Codex disabled; the
degrade case, deliberately last).

### 5.3 Degrade, not fail closed, on m3-market

m3-market sets `codex_enabled: false` in `.claude/leadv2-overrides/codex-policy.yaml`. The engine
must produce a plan there anyway.

Mechanism (all of it already exists; the engine only has to honour it):
`leadv2-codex-planner.sh` lines 10–17 detect the policy, print
`[leadv2-codex-planner] codex_enabled=false … — skipping Codex`, emit `codex_skipped_by_policy`,
and exit **0**. `leadv2-plan-run.sh` matches that token, emits
`plan_run arm_unavailable arm=codex reason=policy task=<sig8>`, and advances `candidate_arms`.

How each engine proves it — a human reads two things in the m3-market journal and one on disk:

- the line `plan_run arm_unavailable arm=codex reason=policy task=<sig8>`, followed by
- the line `plan_run task=<sig8> status=ran arm=<non-codex> artifact=docs/handoff/<id>/context.yaml`,
  and
- `docs/handoff/<id>/context.yaml` exists and passes `leadv2-acceptance-shape.sh validate`.

There must be **no** `status=failed` and no `status=parked` line for that task. The same three
observations, with `diagnose_run` in place of `plan_run` and `root-cause.md` in place of
`context.yaml`, prove the Diagnose mode.

Anti-requirement, restated because it is the easiest thing to get wrong: **nothing anywhere may
hardcode "m3-market has no codex".** The engine learns it from the policy file, through the arm's
own exit, at run time.

---

## 6. Tests that fail today

Concrete assertions, each of which fails against current `HEAD`.

### Plan

1. `test-acceptance-guard-uses-validator.sh` — write a `context.yaml` whose
   `acceptance.observable` is **empty** and whose `authored_at` is the literal string `yesterday`.
   Run the dispatch prepass guard. **Today:** passes (the grep chain checks presence only).
   **Required:** refuses with `reason=no_acceptance_block`.
2. `test-acceptance-guard-multiline-observable.sh` — `observable:` as a multi-line YAML block
   scalar whose second line reads `the function returns 0`. **Today:** passes — the negative regex
   is anchored to the `observable:` line itself. **Required:** refuses.
3. `test-acceptance-guard-fenced-block.sh` — a design containing `acceptance:` and a valid
   `surface:` line only inside a fenced markdown example. **Today:** passes. **Required:** refuses.
4. `test-prepass-writes-context-yaml.sh` — after a successful prepass,
   `docs/handoff/dispatch-<sig8>/context.yaml` exists and `leadv2-acceptance-shape.sh validate`
   exits 0 against it. **Today:** the file does not exist at all.
5. `test-plan-run-no-claude-lead.sh` — invoke `leadv2-plan-run.sh --mode plan` from a bare bash
   environment with the Workflow/Agent tools unavailable; a valid `context.yaml` is produced.
   **Today:** the only `context.yaml`-producing path is `leadv2-plan.js`, which cannot run there.
6. `test-plan-arms-role-scoped.sh` — assert `DISPATCHABLE_PLAN_ARMS` excludes `glm` and `kimi`
   and includes `codex` and `sonnet`, and that the assertion reads the resolver rather than a
   literal list. **Today:** the symbol does not exist; the build set is the only set.
7. `test-plan-run-codex-disabled-degrades.sh` — with `codex_enabled: false`, `--mode plan`
   exits 0, journals `arm_unavailable arm=codex reason=policy`, and still writes a valid
   `context.yaml`. **Today:** no engine consumes `codex_skipped_by_policy`.
8. `test-workflows-copies-are-symlinks.sh` — `~/.claude/workflows/leadv2-plan.js` and
   `leadv2-diagnose.js` are symlinks resolving into `plugins/leadv2/workflows/`. **Today:** both
   are real files, 3 days and 3.5 weeks stale respectively.
9. `test-plan-run-flag-off-identical.sh` — with `LEADV2_PLAN_RUN=0`, the journal lines emitted by
   a dispatch are byte-identical to pre-change `HEAD`. (Fails today only in the trivial sense that
   the flag does not exist — it is the guard that keeps step 3 safe.)

### Diagnose

10. `test-diagnose-no-pe-constants.sh` — run `--mode diagnose` with `LEADV2_PROJECT_ROOT` pointing
    at a non-persona-engine repo; assert the assembled prompt contains neither
    `journalctl -u persona-engine` nor persona-engine table names. **Today:**
    `leadv2-diagnose.js:17-18` hardcodes both as defaults.
11. `test-diagnose-single-entry-point.sh` — assert no file outside
    `plugins/leadv2/scripts/leadv2-plan-run.sh` invokes `--mode diagnose` directly; in particular
    `skills/leadv2-iterative-recovery/SKILL.md` routes through the engine. **Today:**
    `SKILL.md:45` calls `leadv2-codex-planner.sh` directly.
12. `test-diagnose-codex-disabled-degrades.sh` — the §5.3 proof with `diagnose_run` verbs.
    **Today:** no bash diagnose engine exists.
13. `test-task-judge-diagnose-routes.sh` — a brief classified `work_kind=diagnose` by
    `leadv2-task-judge.sh:120-125` actually reaches the diagnose engine. **Today:** the
    classification has no consumer.

---

## 7. What I would not do

### 7.1 On §3.4 of the review design

I cannot report what I am contradicting in a four-line sketch I was unable to read (§0). What I
can do is state the three positions this design takes that a compact sketch most plausibly gets
otherwise, so the review lane can check each against its own text:

- **If §3.4 says the fix is to make `_acceptance_guard`'s heuristic stricter — I disagree.** The
  right move is to delete the heuristic and remove the condition that justified it, by having the
  prepass write a `context.yaml`. A stricter grep chain is a second validator that will drift from
  the first; the codebase already has one of those and it is the bug.
- **If §3.4 says `leadv2-plan.js` becomes the merged engine — I disagree, on the mission's own
  constraint.** A Workflow script is unreachable without a Claude lead. The JS file can survive as
  a shim; it cannot be the path.
- **If §3.4 says Plan needs its own arm-selection logic — I disagree.** The ladder plus
  `DISPATCHABLE_*` already is arm selection. Plan needs one new role-scoped *set*, not a new
  mechanism, and a second mechanism is how an arm ends up hardcoded somewhere.

### 7.2 Independent of §3.4

- **I would not give Diagnose its own engine** — §2.4, with reasons.
- **I would not do a big-bang `dispatch-code.sh` rewrite.** The two function bodies are the whole
  footprint; anything larger collides with the review lane for no gain.
- **I would not delete `leadv2-codex-planner.sh`.** It holds the tier resolver, the `--tier top`
  reason requirement, the spark ban, and the policy short-circuit. Folding those into the engine
  would put provider-specific quota knowledge in the orchestrator — the exact coupling that makes
  "never hardcode an arm" hard to hold.
- **I would not move `acceptance` validation into the engine.** `leadv2-acceptance-shape.sh` is
  already the single validator with a test suite (`tests/test-acceptance-shape.sh`) and a second
  consumer (`leadv2-phase8-assert.sh:535`, assertion A11). Adding a third implementation would
  recreate the problem.
- **I would not let the prepass keep authoring `acceptance.authored_at` implicitly.** The engine
  must stamp it deterministically at `context.yaml` creation, because `assert-precedence` compares
  it against file mtimes — an LLM-authored timestamp is exactly the thing that check exists to
  distrust.

---

## 8. Out of scope

- Any change to review-engine internals — that lane owns them.
- Any change to `leadv2-router-v2.py` / `leadv2-router.sh` arm-resolution semantics beyond adding
  the role-scoped `DISPATCHABLE_PLAN_ARMS` set.
- Any change to `leadv2-phase8-assert.sh` (A11 already calls the real validator and is correct).
- Any Supabase, Qdrant, or Next.js concern — this consolidation is entirely inside the plugin.
- The live Codex-lead proof, deferred to ledger row `SD-ONEPATH-CODEX-LIVE-PROOF-01` (Codex quota
  exhausted until 2026-08-08).
- Consumers of `.claude/scripts/tests/` (a separate open thread with its own blast radius).

---

acceptance:
  surface: file_artifact
  observable: >
    The file docs/handoff/one-review-path-2026-08-06/design-plan-diagnose.md exists and a reader
    opening it finds, for each of the three Plan implementations and each of the three Diagnose
    implementations, a named file with line numbers and a statement of what that implementation
    uniquely does; the verbatim eight-line _acceptance_guard comment from
    leadv2-dispatch-code.sh:1752-1759; a named target script leadv2-plan-run.sh with what it owns
    and what is deleted; a stated Diagnose recommendation with its reasons; a numbered merge order
    marking which steps run in parallel with the review lane and which one waits; and thirteen
    numbered test assertions.
  authored_at: 2026-08-06T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-plan-run.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-acceptance-shape.sh, plugins/leadv2/lib/leadv2-glm-policy-resolve.py, plugins/leadv2/workflows/leadv2-plan.js, plugins/leadv2/workflows/leadv2-diagnose.js, plugins/leadv2/skills/leadv2-iterative-recovery/SKILL.md, plugins/leadv2/scripts/tests/test-plan-run-*.sh, plugins/leadv2/scripts/tests/test-acceptance-guard-*.sh, plugins/leadv2/scripts/tests/test-diagnose-*.sh, plugins/leadv2/scripts/tests/test-prepass-writes-context-yaml.sh, plugins/leadv2/scripts/tests/test-workflows-copies-are-symlinks.sh, plugins/leadv2/scripts/tests/test-plan-arms-role-scoped.sh, plugins/leadv2/scripts/tests/test-task-judge-diagnose-routes.sh

---

Primary artifact: docs/handoff/one-review-path-2026-08-06/design-plan-diagnose.md (identical content).

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# ONE-PATH-EVERYWHERE-01 — design the Plan + Diagnose consolidation (design only, no code)

**Design deliverable only. Do NOT edit a single line of executable code.** A separate lane is
building the review engine right now and both would touch
`plugins/leadv2/scripts/leadv2-dispatch-code.sh`; a code edit here would collide with it. Your
output is documents.

Read first, in this order:
1. `docs/handoff/one-review-path-2026-08-06/design.md` — the approved review design. §3.4 sketches
   Plan in four lines; §1.2 and §1.3 hold the census. Your job is to turn that sketch into a design
   of the same depth as §3.
2. `docs/handoff/one-review-path-2026-08-06/mission-build-r1.md` — what the review lane is building
   right now. Your design must reuse its engine shape, not invent a second one.

Plugin repo: `/Users/kostiantyn.vlasenko/Projects/leadv2` (the single source). Never create a real
copy of a plugin-owned file inside a consuming project.

## Why now

Codex is out of quota until 2026-08-08, so the review lane's live Codex-lead proof is deferred
(ledger row `SD-ONEPATH-CODEX-LIVE-PROOF-01`). The founder wants the consolidation pushed as far as
it can go in the meantime. Design work needs no quota and no live run, and it is the thing that
blocks Plan from starting the moment review merges.

## What to produce

`docs/handoff/one-review-path-2026-08-06/design-plan-diagnose.md`, structured like the review
design, covering BOTH phases:

### Plan (3 implementations today)

Census with file:line for each path. The known one:
`leadv2-dispatch-code.sh:1755-1772`'s `architect_prepass()` substitutes a heuristic text scan for
the real `leadv2-acceptance-shape.sh` validator **and says so in its own comment** — find the exact
lines and quote them. Name the other two paths precisely (`workflows/leadv2-plan.js` and its
`~/.claude/workflows/` copy, `leadv2-codex-planner.sh`) and say what each one uniquely does that
the others do not — that difference is what the merged engine must not lose.

Then: the target `leadv2-plan-run.sh` — what it owns (`context.yaml`, the real acceptance
validation), how the lane and the lead both reach it, what gets deleted, and how
`leadv2-codex-planner.sh` survives as an **arm inside the pool** rather than a parallel entry point.

### Diagnose (3 implementations today)

Same treatment. It is unguarded and lower severity, so say plainly whether it deserves its own
engine or should simply fold into one of the others — a recommendation, not a hedge.

### Cross-cutting

- **Sequencing and file collisions.** Both engines touch `leadv2-dispatch-code.sh`. State the safe
  merge order and which changes can land in parallel without conflicting.
- **Rollout.** Per-phase flags defaulting to 0, staged persona-engine → respiro-ios → m3-market.
  m3-market has Codex disabled: the arm pool must **degrade, not fail closed**. Say how each engine
  proves that.
- **Tests that fail today**, per phase — concrete assertions, not categories.
- **What you would NOT do.** If part of §3.4's sketch is wrong now that you have looked closely,
  say so and say why. A design that only agrees with its predecessor is not worth the pass.

## Hard constraints

- Never hardcode an arm in or out of routing anywhere in the design. Quota, task and complexity
  decide.
- Nothing on the critical path may assume a Claude lead — no Agent tool, no Workflow tool, no
  in-session MCP. A path that works only under a Claude lead is not a single path.
- Shared tree: never `git reset --hard`, `git clean`, or `git stash`.
- Commit only documentation.

## Return

The path to the design + a one-paragraph summary of the Plan target + your Diagnose recommendation
with its reason + the safe merge order relative to the in-flight review lane + anything in the
original §3.4 sketch you are contradicting and why.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b0bb8f7e" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.