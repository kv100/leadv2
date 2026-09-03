# ROUTER-BRAIN-01 — one brain decides class, phases, model and arm for every task

Author: lead (Fable 5.1), 2026-09-01. Founder order, verbatim intent: "селектор должен быть
максимально умным: все задачи идут через систему оценки сложности, через N фаз в зависимости от
сложности, запускаются на нужной модели; селектор умеет работать с квотами".

## What is true today (measured 2026-09-01, gap map by an Explore pass over main)

| Capability | Exists | Live on the dispatch path | Gap |
|---|---|---|---|
| complexity estimator | `scripts/leadv2-task-judge.sh` | **no** — only behind `LEADV2_ROUTER_V2` (default 0); the default `resolve_arm` never calls it | class is whatever the lead typed in `--task-class` |
| effort matrix | `config/leadv2-routing.yaml: effort_matrix`, arbiter :226-241 | yes, but the rule that chose the effort is not logged | unexplainable decision |
| class escalation | `leadv2-admission-class.sh` admits ≥ computed class | half — nothing computes the class it escalates from | declared class is a fact, not a floor |
| complexity → arm cost | arbiter `complexity_penalty` (:184-205) | **no** — yaml has the key, zero rules | complexity is printed, never used |
| quota-aware arm pick | `leadv2-quota-live.sh` + arbiter `cheapest_capable` | yes for the arm; **no** per-bucket snapshot in the decision line; codex cooldown flat 900 s, no escalation | an arm that died 3× is re-elected every 15 min |
| two Anthropic profiles | `leadv2-claude-profile-select.sh` | yes (verified live today: `selected=work`, child `CLAUDE_CONFIG_DIR=~/.claude-work`) | selection ignores the phase's effort weight |
| outcome → capability | `leadv2-dispatch-ledger.sh` writes telemetry; capability matrix hand-maintained | **no** reader | the brain never learns |
| phase gate | `_phase_precondition_guard` (dispatch-code :3835) | yes, enforcing since 2026-09-01 | it checks a hardcoded `plan,gate1`, not a per-class plan |

So the founder's sentence is false on three of its four clauses. The parts exist; they are switched
off, unconfigured, or unread.

## The design

**One decision record per task, written once, read by everything downstream.**
`docs/handoff/<task>/brain.yaml` + a single journal line
`brain_decision task=<sig8> class=<c> class_source=computed|escalated_from_declared phases=<list>
think=<model> build=<arm/model/effort> review=<arms> quota={glm:%,codex:%,claude_personal:%,claude_work:%}
reason=<rule ids>`. The phase gate, the review pool, the deploy verifier and the pulse read this
record. Nothing downstream re-derives a class or a model from flags.

### A. Class is computed; a declared class is a floor
`leadv2-task-judge.sh` moves from the v2 branch into the default path. Signals, all evidence-derived
from the brief + repo: write-set size and subsystem count (LANE_WRITES), risk classes touched
(safety / publish / schema / auth / hooks — each a listed path pattern), novelty (no hit in
`solutions-archive.yaml`), test presence for the touched files, brief ambiguity (open questions,
missing LANE_WRITES). `--task-class` stays as a **floor**: the brain may escalate above it, never
below; every escalation journals `class_escalated from=<declared> to=<computed> because=<signal>`.
At close, the real diff is re-judged; a diff that crossed a risk class the brief did not name
escalates the close gate (review tier, mutation control) — never silently.

### B. Phases follow the class
| Class | Phases | Gate 1 |
|---|---|---|
| Trivial | build → verify(smoke) | none |
| Light | build → review(1 arm, falsifiability probe) → verify | none |
| Standard | plan(think) → gate1 → build → review(2 distinct arms + falsifiability) → verify | auto-accept after timeout unless a risk class is touched |
| Heavy | diverge → plan(think xhigh + Codex top) → gate1 → build(split by write-set) → review(3 arms + mutation negative control run by the reviewer) → verify → soak row in scheduled-decisions | blocking |
| Strategic | Heavy + founder gate at plan and at deploy | blocking, twice |

The phase gate reads `brain.yaml: phases` and refuses a dispatch whose recorded phases are behind
the plan — the current hardcoded `plan,gate1` list becomes the Standard row of this table.

### C. Model per phase, chosen by the value of the phase
- **think** (plan synthesis, architect, judge, diagnose, learn, PO audit, Heavy critic): Fable 5.1,
  Opus 5 fallback (FABLE-THINK-TIER-01, already in a lane). Effort: high Standard, xhigh Heavy.
- **build**: arbiter `cheapest_capable` with `complexity_penalty` rules populated — Trivial/Light →
  glm-flash/freepool; Standard → glm or codex standard; Heavy or any risk class → sonnet or codex top.
  GLM/Kimi never take a think phase (standing rule).
- **review**: arms distinct from the author; tier = class; the verify-on-distinct-arm step is a think
  model for Heavy.
- **effort**: from `effort_matrix`, and the decision line names the rule (`effort=high by=rule:heavy_plan`).

### D. Quota is an input to every pick, not a refusal at the end
`leadv2-quota-live.sh` is the single source; the brain snapshots all five buckets (glm weekly,
codex, claude personal, claude work, plus the 5-hour windows) into the decision line. Ceilings stay
80/90/95 (standing). Profile selection weighs the phase: a think phase on xhigh goes to the profile
with the most 5-hour headroom, a haiku read goes anywhere. Codex cooldown escalates
900 → 1800 → 3600 s and an arm in cooldown is re-elected only after one successful cheap probe —
never by the clock alone, and never by excluding the arm from routing (standing rule).

### E. The brain learns from outcomes
A reader for `leadv2-dispatch-ledger.sh` telemetry feeds the arbiter a third score beside cost
and quota: per (arm, work_kind, class) cell, recent died / review-fail / landed counts. A cell that
failed twice in a row on a shape is penalised for that shape only; a landed outcome heals it.
Hand-edits to the capability matrix become the exception with a journaled reason.

### F. Proof, not green
`test-router-brain-e2e.sh`: five synthetic briefs (one per class, one with a declared class below
its evidence) → assert the decision line's class, phases, think model, build arm and quota snapshot.
Each lane ships its own mutation negative control and runs it. Live proof at close: three real
dispatches from the backlog, each with its `brain_decision` line pasted into the report and the
phase list matching the table above.

## Lanes (in order; each ≤ 1 h, each with its own control)
1. `BRAIN-CLASS-LIVE-01` — A: judge in the default path, `--task-class` as floor, `brain.yaml`
   + decision line. Absorbs COMPLEXITY-ESTIMATOR-IS-OFF-01 and CLASS-IS-COMPUTED-NOT-DECLARED-01.
2. `BRAIN-PHASES-BY-CLASS-01` — B: phase gate reads `brain.yaml: phases`; table above is the config.
3. `BRAIN-MODEL-PER-PHASE-01` — C: complexity_penalty rules, effort rule logged, review tier by class.
   Depends on FABLE-THINK-TIER-01 (think resolver). Absorbs EFFORT-IS-NOT-WIRED-01.
4. `BRAIN-QUOTA-01` — D: quota snapshot in the line, effort-weighted profile pick, cooldown escalation
   with probe. Absorbs CODEX-COOLDOWN-DOES-NOT-ESCALATE-01.
5. `BRAIN-LEARNS-01` — E. Absorbs ARM-CAPABILITY-FROM-OUTCOMES-01.
6. `BRAIN-E2E-PROOF-01` — F, closes the umbrella; the founder sees three real decision lines.

Lanes 1 and 4 have disjoint write sets and run in parallel; 2 waits for 1; 3 waits for
FABLE-THINK-TIER-01; 5 waits for 1; 6 last.

## Not in scope
Replacing the arbiter or the router-v2 script wholesale. Changing quota ceilings. Any change to
what GLM/Kimi are allowed to do.
