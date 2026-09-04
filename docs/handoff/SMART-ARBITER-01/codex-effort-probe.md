# SMART-ARBITER-01 — codex effort wiring probe (2026-09-04)

Question: is the arbiter's effort decision actually wired to the codex spawn, end to end?

## Verdict: WIRED, 4 hops, all verified on this tree

| # | hop | evidence (file:line) |
|---|-----|----------------------|
| 1 | arbiter resolves effort task-first | `lib/leadv2-route-arbiter.sh:404-446` — `TASK_EFFORT_KEYS` rows evaluated first, arm-`tags` rows fallback only; prints `effort=%s` on its own decision line (`:504`) |
| 2 | dispatch parses it | `leadv2-dispatch-code.sh:7883-7884` (`_arb_effort` sed from arbiter stdout) → `:7926` `export RESOLVED_EFFORT="${_arb_effort:-medium}"`, journaled on `route_resolved` (`:7927`) |
| 3 | codex arm passes it on the wire | `leadv2-dispatch-code.sh:5818` `[[ -n "${RESOLVED_EFFORT:-}" ]] && tier_args+=(--effort "${RESOLVED_EFFORT}")`; absent arbiter → tier default, unchanged pre-wiring behaviour |
| 4 | codex-task.sh honours it | `codex-task.sh:1396-1400` — explicit `--effort` suppresses the tier-derived default (`_tier_model_effort :1953-1971`: top→high/xhigh, standard→medium, volume→low); tier→model resolution still applied |

Vocabulary compatibility: arbiter/yaml matrix emits only low|medium|high (`config/leadv2-routing.yaml:138-145`); codex wire accepts the low..xhigh set — no translation needed, no out-of-vocabulary value reachable from the matrix.

Direct-exec path (adversarial-review rescue) pins it separately: `leadv2-codex-session-runner.sh:474,492` pass `model_reasoning_effort="$EFFORT"` to `codex exec` — same value journaled at `:439`.

## Live evidence (main checkout journals)

164 `route_resolved by=arbiter arm=codex` lines carry `effort=`, e.g.
`2026-09-03T03:42:03Z route_resolved ... arm=codex model=gpt-5.6 tier=standard effort=high task=e8db84ba ... complexity=complex duration_class=long`
— effort=high tracks the task-keyed `{kinds:[code], complexity:[complex], effort:high}` phase-1 row, not the arm.

## Residual gaps (observability, not wiring)

1. **No `effort_applied` line for the codex arm.** GLM emits `effort_applied by=router ... mechanism=flag source=...` (`dispatch-code:5535`); codex/sonnet arms journal only `route_resolved ... effort=` — the applied-vs-resolved distinction is unverifiable from the journal alone.
2. **Codex review path has no effort wire** by design: `adversarial-review|review` accept `--model` only ("review has no --effort wire", `codex-task.sh:1383-1389`); effort pinning there lives in the session-runner direct path.
3. Timeout retry re-derives effort from the downgraded tier (`codex-task.sh:1982-1991`), overriding the explicit `--effort` the router passed — intentional (fallback ladder), but the journal never shows the demotion.

## Probe commands (re-runnable)

```
grep -n "effort" plugins/leadv2/scripts/leadv2-dispatch-code.sh | grep -i codex
grep -h "effort=" docs/leadv2/tasks/*/journal.md | grep "arm=codex" | tail
sed -n 1953,1971p plugins/leadv2/scripts/codex-task.sh
```
