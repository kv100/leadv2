# FABLE-THINK-TIER-01 — Fable 5.1 is the thinking model; Opus becomes its fallback

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FABLE-THINK-TIER-01`
LANE_WRITES: plugins/leadv2/config/model-capability.yaml,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/scripts/leadv2-router.sh,plugins/leadv2/workflows/leadv2-diverge.js,plugins/leadv2/workflows/leadv2-learn.js,plugins/leadv2/workflows/leadv2-diagnose.js,plugins/leadv2/workflows/leadv2-po-feedback-loop.js,plugins/leadv2/docs/model-effort-matrix.md,plugins/leadv2/docs/phases.md,plugins/leadv2/ref/leadv2-main-model.yaml,plugins/leadv2/scripts/tests/test-fable-think-tier.sh,tests/run-all.sh,docs/handoff/FABLE-THINK-TIER-01/
Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Founder order (2026-09-01)
"fable 5.1 надо встроить в диспатч. Явно не везде где у нас опус нужен опус — иногда, а может даже
очень часто, лучше fable на подумать." Claude Fable 5.1 (`claude-fable-5-1`) is GA, 1M context,
same Claude Max bucket as Opus — no new quota arm, no new credential. Model IDs: Fable 5.1
`claude-fable-5-1`, Opus 5 `claude-opus-5`, Sonnet 5 `claude-sonnet-5`, Haiku `claude-haiku-4-5-20251001`.

## The rule this lane ships
**Every role whose value is THINKING (not typing) runs on Fable first; Opus is the fallback when
Fable is refused/unavailable.** Roles whose value is typing (developer, devops, frontend, GLM/Kimi/Codex
build arms, haiku reads) do not change. Sonnet stays the Standard critic.

| Role | Today | After |
|---|---|---|
| dispatch architect prepass (`LEADV2_DISPATCH_ARCHITECT_MODEL`, dispatch-code.sh ~4483) | opus | fable |
| plan synthesis / architect (`model-effort-matrix.md`, phases.md §2) | opus Standard / fable Heavy | fable both, effort high/xhigh |
| judge (`leadv2-judge`, diverge judge `leadv2-diverge.js:114`) | opus hardcoded | fable, opts.model override, opus fallback |
| diagnose root-cause synth (`leadv2-diagnose.js:150`) | opus hardcoded | fable |
| learn proposal (`leadv2-learn.js:301`) | opus hardcoded | fable |
| PO audit (`leadv2-po-feedback-loop.js:147`) | opus hardcoded | fable |
| review verify-on-distinct-arm / Heavy critic (`leadv2-review-run.sh:489` pool) | opus arm | fable arm listed before opus; author-exclusion unchanged |
| lead main model (`ref/leadv2-main-model.yaml`) | opus | fable |

## Steps
1. `config/model-capability.yaml`: fable row — `context_k: 1000`, `role: think`, `fallback: opus`,
   `model_id` fields for every Claude row using the IDs above. Opus row: `role: think_fallback`.
2. Router (`leadv2-router.sh` ~900-1020): one `think_model()` resolver — `LEADV2_THINK_MODEL` env
   override wins; else `fable` unless the capability yaml marks it `unavailable`; else `opus`.
   Every think-role caller uses it. No hardcoded `opus` literal may remain at a think-role spawn site.
3. The four hardcoded `model: 'opus'` in the workflows → `opts.model || THINK_MODEL` where
   THINK_MODEL reads env `LEADV2_THINK_MODEL` (default `fable`).
4. dispatch-code.sh architect prepass default → the resolver. review-run.sh: fable arm enters the pool
   ahead of opus with the same ceiling (claude 95). SAME bucket: headroom math counts
   fable+opus+sonnet together — do not add a bucket.
5. `docs/model-effort-matrix.md` + `docs/phases.md` §2/§5: rewrite Opus rows as "Fable (Opus fallback)".
   Keep: GLM/Kimi never take think roles. Add a ban: never set `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`
   (CC 2.1.257) — it overrides every explicit `model=` pin, and our routing IS the pins.
6. `ref/leadv2-main-model.yaml` (plugin): `main_model: fable`. Do NOT touch persona-engine's copy.
7. Suite `plugins/leadv2/scripts/tests/test-fable-think-tier.sh`: (a) resolver default fable / opus when
   fable unavailable / env override wins; (b) grep-gate: zero `'opus'` literals at the four workflow
   spawn sites; (c) review pool orders fable before opus and never picks the diff author's arm.
   Mutation negative control (RUN it, paste the red): hardwire `echo opus` in `think_model()` → (a) red.
   Register the suite in `tests/run-all.sh`.

## Do NOT
- Change developer/sonnet lanes, GLM/Codex/Kimi arms, or haiku read roles.
- Add a quota bucket for fable.

## Evidence for docs/handoff/FABLE-THINK-TIER-01/report.md
Suite green; negative-control red; `git diff --stat`; one dry-run spawn line from leadv2-diagnose.js
showing `model=fable`.
