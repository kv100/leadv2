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

## FP-07 — review engine codex arm chokes (P1, found 2026-08-28)
leadv2-review-run.sh's codex reviewer dies on its first rg exit-1 (no matches treated
as fatal) -> review_body_lost, twice deterministically on PHASE-DISCIPLINE-01. Judge
escalation covered it, but the primary review arm is broken. Fix the arm's command
error handling (rg exit 1 is not an error) + add a body-lost retry on a DIFFERENT arm.

## MERGE-UP-PHASE8-GATES-01 (found 2026-08-28, P1)
leadv2 repo .claude/scripts/leadv2-phase8-assert.sh + leadv2-phase8-e2e-gate.sh are REAL
copies diverged BOTH ways vs canonical: copies carry CLOSE-GATE-BYPASSABLE-BY-ENV-01
(2026-08-17 hardening, 21+37 unique lines) canonical never got; canonical has 07-31/08-04
work the copies lack. Needs a real merge-up into canonical, tests, then symlink. Until
then these two stay real copies deliberately (do NOT blind-symlink — loses the hardening).

## FP-08 — freepool arm produces instant empty diffs on real code missions (P1, 2026-08-28)
Two Standard/Light code missions (27434c7a, e9e1ad51): arbiter picks freepool as cheapest_capable,
worker exits in ~23s with zero diff, dispatcher records no_work. Either the freepool claude-p glue
dies silently or capability floor is wrong (freepool should be bulk-only until FP-04 quality gate).
Investigate worker glue logs + add capability floor: freepool ineligible for class>=Standard.

## FP-07b — body-lost retry found no candidate live (P2, 2026-08-28)
First live body_lost after FP-07 merge: retry preconditions met (rc=0, 158B, err set) but
_review_next_distinct_ok_arm returned empty — pool variable empty/shape mismatch for author=freepool
(resolver printed arm=/rule= shape, engine expects reviewer=/pool=). Add live-pool regression + fix pool parse.

## MON-PULSE-01 — pulse beat default-on in single-lead + dispatcher-owned lane watch (P1, 2026-08-28)
Founder complaint (3rd time, = PULSE-IN-SINGLE-LEAD-01): lead does not truly track lanes and founder gets no updates. Two fixes:
1. leadv2-dispatch-code.sh arms the lane watch ITSELF at spawn (tail -n +1 replay-safe, terminal-state matched) and writes beats to the pulse file — no session-improvised Monitors racing the journal.
2. BROAD_STATUS/pulse beat fires in single-lead mode by default (every 5 min while any lane live), not only in the retired supervise loop.
Evidence 2026-08-28: two lead Monitors armed with tail -n 0 missed dispatch_terminal written 25s post-spawn; founder saw nothing until he asked.
