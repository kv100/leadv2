# Model × Effort Routing Matrix — canonical source (EFFORT-ROUTING-01, 2026-07-03)

The lead picks TWO knobs per spawn, not one: **model = task hardness, effort = marginal
value of extra thinking**. They are independent axes. Getting either wrong wastes quota
or quality; getting both wrong (weak model × max effort) is the worst trade — burns
thinking tokens AND fails the task.

## The three-question decision procedure (lead runs this per spawn)

1. **Code-shaped AND repo has `codex_enabled: true`?** → **Codex** (zero Claude quota).
   Effort: `high` default; `xhigh` for Heavy plan / final adversarial review.
2. **Background / bulk / mechanical — nobody waits at screen?** → **GLM** via
   `glm-coder.sh bg` (zero Claude quota; GLM-5.2 ≈ Sonnet 5 on SWE-bench Pro 62.1 vs
   63.2, within ~1% of Opus 4.8 on FrontierSWE long-horizon). Banned for
   architecture / design / safety. Haiku is the fallback when GLM lane is absent.
3. **Else Claude ladder by hardness** (interactive work):

| Hardness | Model | Effort | Examples |
|---|---|---|---|
| Reads, classify, greps, commits, aggregation | haiku | `low` | Explore, capability-classifier, quality-scorer, archive-write |
| Standard build / synthesis | sonnet | `medium` | developer, plan-synthesize, context.yaml writes |
| Adversarial gate / verdict | sonnet | `high` | critic, security-auditor, verify-blocking (Codex is primary; this is the 2nd voice) |
| Heavy design synthesis / judge | **fable (opus fallback) → sonnet** | `xhigh` | Heavy/Strategic architect, diverge judge, safety-touched review verdict |
| One-shot irreversible / Strategic gate | **fable (opus fallback) → sonnet** | `max` | Strategic plan synthesis, final deploy verdict on Heavy+safety |

## Effort ladder semantics

- `low` — no deliberation needed: the task is lookup, transform, or checklist-shaped.
- `medium` — DEFAULT for every spawn unless a rule below raises it. Standard code fits here.
- `high` — the output is a gate or verdict (review finding, judge score, security call):
  correctness has leverage, a miss costs a bad merge.
- `xhigh` — genuine novel synthesis: Heavy design, root-cause synthesis AFTER evidence
  is gathered, diverge judging across candidate frames.
- `max` — reserved: Strategic synthesis and irreversible one-shot verdicts only.
  NEVER a frontmatter default.

**Escalation direction rule:** when a task outgrows its tier, escalate the MODEL, not
the effort. Sonnet's effort cap is `high` — if a sonnet spawn seems to need `xhigh`,
it needs a think model (fable, opus as fallback — or Codex), not a longer sonnet run. Thinking tokens are output
tokens — the most quota-expensive thing a spawn emits.

## Fable (Opus fallback) — only the hardest thinking (FABLE-THINK-TIER-01, founder order 2026-09-01, supersedes the 2026-07-03 opus-first directive; FABLE-RETIRE-01 2026-07-06 covered Fable 4.x — Claude Fable 5.1 is GA since 2026-08)

> evidence: model_id — Claude Code environment banner, verbatim: "Model IDs —
> Fable 5.1: 'claude-fable-5-1', Opus 5: 'claude-opus-5', Sonnet 5:
> 'claude-sonnet-5', Haiku 4.5: 'claude-haiku-4-5-20251001'"; confirmed live by
> `claude -p --model claude-fable-5-1 'say ok'` → rc=0 (2026-09-01).
> evidence: quota-read delta 2026-09-01 (`leadv2-quota-read.py anthropic
> --no-cache` before 21:02:03Z / after 21:03:17Z) — the round-1 claim "same
> Claude Max bucket as Opus" is WITHDRAWN: five_hour_pct on the active max_20x
> account did not move across the probe (31→31), and the reader exposes a
> model-scoped window `weekly_scoped scope.model.display_name="Fable"` (pct 7,
> unchanged) SEPARATE from `weekly_all`. Fable has its own bucket entry
> (`cost_class: fable-scoped-weekly` in model-capability.yaml); the 1M-context
> figure is UNVERIFIED (`context_k: unverified`). glm-policy-resolve.py keeps
> fable on the anthropic ACCOUNT reading as the conservative ceiling.

Every role whose value is THINKING (not typing) runs on **Fable first; Opus is the fallback**
when Fable is refused/unavailable — never the default. This resolves through
`leadv2-router.sh think_model()` (env `LEADV2_THINK_MODEL` overrides; else fable unless
`config/model-capability.yaml`'s fable row is `unavailable: true`, else opus). No think-role
spawn site may hardcode an `'opus'` literal — call the resolver. This invariant is enforced
tree-wide (scripts, workflows, skills, hooks — tests excluded) by the census grep-gate in
`scripts/tests/test-fable-think-tier.sh`; literal `opus` survives only on explicit fallback
sites, route-telemetry lines that describe an opus decision already made, and prose.

Fable (opus fallback) is allowed ONLY where genuinely novel reasoning or judgment happens:

- Heavy/Strategic plan **synthesis** (not discovery — discovery is haiku/Explore)
- Diverge judge (scoring/clustering candidate frames)
- Safety-touched review **verdict** (not the scan — scans are Codex/sonnet/haiku)
- Root-cause **synthesis** after cheap models gathered the evidence
- Lead main model (`ref/leadv2-main-model.yaml: main_model: fable`)

Fable/Opus is BANNED for: evidence gathering, file reads, bulk transforms, classification,
mechanical edits, commit messages, status aggregation, anything a checklist could do.
**GLM/Kimi never take think roles** — the fable-first change does not touch that boundary.

**Chain on refusal/absence, never hard-pin.** Always `fable → opus → sonnet` (fable is
first-class for design/synthesis/verdicts, opus is its fallback). In workflows:
`model: opts.model || THINK_MODEL` (THINK_MODEL defaults to `fable`, env
`LEADV2_THINK_MODEL` overrides) with an explicit opus retry, then sonnet fallback on
refusal/absence.

**Never set `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`** in a Workflow-tool script's environment.
Scope, confirmed by disassembly of the installed CC 2.1.257 binary (`strings` on
`~/.local/share/claude/versions/2.1.257`, evidence below): when this env var is set, the
Workflow tool's internal `agent()` dispatcher nulls `opts.model` before spawning and logs
`Workflow agent model "<model>" ignored: CLAUDE_CODE_SUBAGENT_MODEL_FORCE is set` — so it
overrides `model: opts.model || THINK_MODEL` above, i.e. our fable/opus think-role routing,
for any `agent()` call made from inside a Workflow script. It has NOT been probed against
non-Workflow spawns (the `Agent` tool, `claude-subsession.sh --model`) — do not extend this
claim to those paths without a separate probe.

```
evidence: strings -a ~/.local/share/claude/versions/2.1.257 | grep -B2 -A2 \
  'ignored: CLAUDE_CODE_SUBAGENT_MODEL_FORCE'
->  Workflow agent model "
->  " ignored: CLAUDE_CODE_SUBAGENT_MODEL_FORCE is set
->  minified source: if(I?.model!==void 0 && a.CLAUDE_CODE_SUBAGENT_MODEL_FORCE)
->    t(`Workflow agent model "${I.model}" ignored: ...`), I.model=void 0;
```

## Zero-Claude-quota lanes come FIRST (founder: "GLM и Codex по максимуму")

Priority order for any spawn: **Codex → GLM → Claude ladder.** Both external lanes run
on separate subscription pools; every task routed there protects the Opus weekly
cap for the few spawns that truly need it.

| Lane | Carries | Effort control | Gate |
|---|---|---|---|
| Codex (gpt-5.5) | plan review, adversarial review, bug-hunt/root-cause, fitting dev tasks | `--effort medium\|high\|xhigh` on codex-task.sh | `codex-policy.yaml codex_enabled: true` |
| GLM-5.3 | background latency-class, bulk/mechanical transforms, standard code nobody waits on | `GLM_EFFORT` env on glm-coder.sh → `claude -p --effort` (GLM-EFFICIENCY-01, 2026-09-02; was prompt-level only) | route arbiter capability matrix |
| GLM-5.3-flash (`glm-flash` arm) | mechanical edits, small fixes, doc rounds, test authoring — trivial/light/standard only | same `GLM_EFFORT` seam; model via `GLM_MODEL` env on glm-coder.sh | route arbiter capability matrix (cost 0.33 = measured credit-weight ratio) |

## GLM effort wiring (GLM-EFFICIENCY-01, 2026-09-02)

Z.AI evidence (all fetched live 2026-09-02):
- GLM-5.3 / 5.3-flash force thinking ON — no disable. `reasoning_effort`: `low` |
  `high` | `max`, **default `max`** — [glm-5.3](https://docs.z.ai/guides/llm/glm-5.3.md),
  [glm-5.3-flash](https://docs.z.ai/guides/vlm/glm-5.3-flash.md).
- Claude Code reaches Z.AI's Anthropic-compat endpoint (`https://api.z.ai/api/anthropic`)
  with `output_config.effort`; CC's `--effort <level>` (2.1.258) maps onto the same
  low/high/max ladder — [latest-model](https://docs.z.ai/devpack/latest-model.md).
- The field measurably changes the response. Raw endpoint probe, same prompt, glm-5.3:
  `output_tokens` **130 at `low` vs 369 at `max`** (input_tokens 40 both). CC-level A/B:
  output 3 vs 29, wall 34s vs 41s on a 1-line prompt. Artifacts:
  `docs/handoff/GLM-EFFICIENCY-01/report.md`.
- Credit weights (coding plan, per 10k credits) — [teamplan](https://docs.z.ai/devpack/teamplan.md):
  glm-5.3 in 6.9 / cached 1.7 / out 24; glm-5.3-flash in 2.3 / cached 0.56 / out 8.
  **Flash weighs ⅓ of glm-5.3** — its "3× the quota" means 3× the allowance, not 3× the
  cost (GLM-EFFICIENCY-AUDIT-01 read the direction backwards; the matrix's `cost: 0.4`
  is directionally right, mildly conservative vs the true 0.33).

Dispatcher contract (`_glm_effort_for_class` in leadv2-dispatch-code.sh; journaled as
`effort_applied … mechanism=flag source=class_map`):

| Raw task class | GLM effort |
|---|---|
| trivial, light, bulk | `low` |
| standard | `high` |
| heavy, strategic | `max` |
| review / verify roles | `high` (contract-complete; glm is review-excluded today) |

glm-coder.sh appends `--effort <v>` to both `claude -p` spawn sites when `GLM_EFFORT`
is set and in the accepted vocabulary; unset or out-of-vocabulary ⇒ flag omitted
(fail-open to the provider default `max`, byte-identical pre-lane spawn).
Suite: `scripts/tests/test-glm-effort-wiring.sh`.

**GLM-53-FLASH-ARM-01 (2026-08-27): when flash is chosen.** The dispatch route
arbiter picks `glm-flash` whenever the task cell is code/docs (incl.
fanout-class-funnel / backlog-pump), size ≤ standard, unprotected, and the glm
bucket is under its ceiling — flash's `cost: 0.33` (corrected 2026-09-02,
GLM-EFFICIENCY-01 ask q-bba84179) encodes its measured credit-weight ratio —
⅓ of glm-5.3's (2.3/0.56/8 vs 6.9/1.7/24, [teamplan](https://docs.z.ai/devpack/teamplan.md);
the pre-lane 0.4 was a legacy-plan figure), so among capable uncapped arms it
sorts first. It shares the one glm quota bucket and lockout record with
glm-5.3. Flash is NEVER chosen for: protected/safety/publish/payments paths
(matrix `protected: false` + ladder `untrusted: true` strip it from those
chains), review/audit/plan (not in its `kinds`, and glm-family is in
DEFAULT_REVIEW_EXCLUSIONS), or heavy/bulk sizes (stays on glm-5.3/codex/
sonnet). Static preference only — the arbiter models provider-level
utilization, not per-model quota consumption.

Fallback ladders on lane failure: see `docs/model-routing.md §Codex quota EXHAUSTION`.
Surface every fallback to the founder — never degrade silently.

## Per-phase defaults (class × phase)

| Class | Plan | Build | Review |
|---|---|---|---|
| Trivial | skip | haiku `low` inline | skip |
| Light | sonnet `medium` single-pass | sonnet `medium` (GLM if background) | skip (low-risk) or Codex `medium` |
| Standard | architect sonnet `medium` + Codex `high` + critic sonnet `high` | sonnet `medium` / GLM bulk | Codex `high` + critic sonnet `high` |
| Heavy | architect fable(opus fallback) `xhigh` + Codex `xhigh` + critic sonnet `high` | sonnet `medium` parallel fan-out / GLM bulk | Codex `xhigh` + verdict fable(opus fallback) `xhigh` (safety) |
| Strategic | fable(opus fallback) `max` + Codex `xhigh` | as Heavy | as Heavy, verdict `max` |

## Anti-patterns (each one observed in production before this doc)

1. **`effort: max` in agent frontmatter** — makes EVERY direct Agent spawn burn max
   thinking regardless of class. Frontmatter default is `high` for adversarial roles,
   `medium` otherwise; workflows override per-class via `opts.effort`.
2. **Cranking effort instead of escalating model** — sonnet `xhigh` on a Heavy design
   task. Wrong axis: use a think model — fable `xhigh` (opus fallback).
3. **Fable/Opus for discovery** — evidence gathering is haiku; synthesis is fable (opus fallback).
4. **Haiku for verdicts** — a `low`-effort judge on a gate decision (acceptable only as
   an explicit degraded-mode fallback, logged as such).
5. **Ignoring the external lanes** — running sonnet review when Codex is available, or
   sonnet bulk transforms when GLM is available: burns Claude quota for nothing.

## Where this is enforced

- `agents/*.md` frontmatter — per-role defaults (this doc is the authority).
- `workflows/*.js` — per-class `effort:` pins on every `agent()` call.
- `commands/leadv2.md §Routing summary` — the table the lead sees at invocation.
- Per-repo `routing.yaml` — may add advisory `effort:` keys per step; router scripts
  pass them through untouched.

Benchmark sources (2026-07): benchlm.ai claude-sonnet-5-vs-glm-5-2, codingfleet.com
glm-5.2 comparison, semgrep.dev GLM-5.2 cyber benchmarks.

Sonnet spawns with thinking OFF under-trigger tools — missions must name expected tools explicitly.
