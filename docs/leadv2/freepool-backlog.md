# Freepool backlog — founder order 2026-08-28

Source: 48h cross-project audit (persona-engine session, scratchpad reports
freepool-getmany.md / freepool-platform.md). Founder assessment: "работа сделана
процентов на 30" — confirmed. Canonical home: this repo (plugins/leadv2/).

Priority order (dependency-driven):

## FP-01 — Wire FREEPOOL_ROLE end to end (P0, small)
`freepool-coder.sh` never exports/passes FREEPOOL_ROLE into
`lib/leadv2-freepool-model-select.sh`, so the role-aware ranking that already
exists is dead code. Wire it: dispatcher sets role (implement|review|bulk) from
mission class, selector consumes it, journal line records chosen role+model.
Evidence of done: journal line `freepool_select role=X model=Y` from a real dispatch.

## FP-02 — Populate role_rank roster in freepool-arm.yaml (P0, small)
`config/freepool-arm.yaml` role_rank block is commented out → flat fallback
(gemini-3.7-flash for everything). Fill per-role rankings from
free-model-research.md findings: NIM / Gemini / Groq / Mistral only —
13/14 OpenRouter `:free` routes rate-limit immediately (document this exclusion
as a comment IN the yaml, not only in the research doc). kimi-k3 noted as best
SOTA candidate. Evidence: selector picks different models for implement vs bulk.

## FP-03 — Installer: seed ~/.fcc/.env + document owner of every setting (P1)
`freepool-install.sh` is a stub. It must: create ~/.fcc/.env skeleton with all
12 keys, mark WHO fills each (operator: provider API keys, auth, port; system:
schema/defaults), verify proxy health on :8317 after setup. Kills the founder's
"в вебе фрипула много настроек и хз кто их должен заполнить" confusion — the
answer becomes: keys = operator once, everything else = yaml defaults.

## FP-04 — Freepool as review arm (arbiter/review roles) (P1, gated)
Today routing policy is build-only (spillover codex→sonnet→freepool). Design
task: can free models take review/arbiter roles safely? Requires FP-01+FP-02
landed and a quality gate (review verdicts from a free model must be spot-checked
against codex/sonnet on N=20 diffs before the arm is trusted). Do NOT enable by
default — proposal + measurement first.

## FP-05 — Dispatcher hardening (P2)
Autostart-on-arm_down exists; add: probe-timeout override path documented,
FREEPOOL_ARM_CONFIG path documented, stale-fetch margin (5s) and warmup (30s)
into arm.yaml comments with rationale.

## FP-06 — Model-selection telemetry (P2)
Per-dispatch journal row: role, model chosen, fallback depth, latency, outcome
(review pass/fail). Without this FP-04's quality gate has no data.

## Appendix — FCC admin UI (127.0.0.1:8317/admin) field ownership (2026-08-28)
Established from freepool-coder.sh:402-412: workers send per-request `--model <provider/slug>`
from OUR selector; tier envs are exported as `freepool-default`. Therefore:
- Providers/API keys: operator, once (already done via ~/.fcc/.env).
- Default Model: safety net ONLY (used when selector fails → `freepool-default`). Any cheap model fine.
- Fable/Opus/Sonnet/Haiku Overrides: keep None — our workers never send tier names.
- Fallback Models: the one field worth filling (mid-flight provider failover FCC does itself;
  our selector cannot catch a provider dying before first token). Recommend 2-3 entries.
- Reasoning: From client. Web Tools: on.
FP-03 installer must print this table so no future operator re-derives it.
