verdict: APPROVE
next_action: review_round_2

# SPAWN-GATE-AND-MODEL-GUARD-DEADLOCK-01 — developer full report

Full analysis, all reproductions, the intersection finding, the chosen
mechanism, the composition test, and both negative controls are in the
mission-specified report:
`docs/handoff/SPAWN-GATE-AND-MODEL-GUARD-DEADLOCK-01/report.md` (committed).

## One-paragraph summary

The two-hook deadlock the brief describes was already closed five days
earlier by `BUILTIN-AGENT-SPAWN-DEADLOCK-01` (commit `55d40e29`,
2026-09-10): `leadv2-spawn-arbiter-gate.sh` now auto-consults the arbiter
inside a declared `speakable_models` pool (`sonnet opus haiku fable`) on
absence of a decision, so a bare built-in spawn with an explicit non-opus
model the arbiter is willing to honour passes both hooks on the first
attempt. Reproducing the brief's three claims against current code showed
2 of 3 no longer occur; the third (arbiter naming an unspeakable model like
`freepool-default`) still occurred, but only through the gate's own DENY
message, which suggests a manual `bash leadv2-route-arbiter.sh worker
'{...}'` fallback for a spawn whose true `work_kind` isn't recon — and that
suggested command omitted `speakable_models`, so a human following it
verbatim could still walk into the exact deadlock. Fixed with a one-line
text edit threading the same pool into that suggestion. Added
`plugins/leadv2/scripts/tests/test-spawn-gate-composition.sh` (20/20, two
`leadv2-mutation-control.sh`-backed negative controls) because neither
existing suite (`test-spawn-arbiter-gate.sh`, `test-spawn-speakable-pool.sh`)
ran both hooks in sequence — the gap that let this composition go untested
in the first place.

## Files changed (committed on this branch)

- `plugins/leadv2/hooks/leadv2-spawn-arbiter-gate.sh` — `SPEAKABLE_JSON` var
  + one DENY-text edit (way-forward manual CLI now carries
  `speakable_models`).
- `plugins/leadv2/scripts/tests/test-spawn-gate-composition.sh` — new,
  self-registered (`# run-all-triggers: leadv2-spawn-arbiter-gate
  leadv2-model-inherit-guard leadv2-route-arbiter`).
- `docs/handoff/SPAWN-GATE-AND-MODEL-GUARD-DEADLOCK-01/report.md` +
  `mutation-control/*.txt` — mission report and control artifacts.

`leadv2-model-inherit-guard.sh`, `leadv2-route-arbiter.sh`: untouched (per
off-limits; reproduction shows their semantics are already correct).

## What I deliberately left alone

- `test-spawn-arbiter-gate.sh`'s pre-existing "refusal not recorded"
  failure — confirmed identical on unmodified HEAD (swapped the hook back
  to `git show HEAD:...`, ran the suite, restored my diff via `git apply`).
  Environment-sensitive (arbiter/kimi capability drift), unrelated to this
  lane's change; not touched per "never weaken a fixture to get green."
- `run-core-offline.sh` failing under `tests/run-all.sh --scope changed` —
  does not reference either hook file (`grep` confirms zero hits); several
  other `/leadv2` sessions were active in this environment during the run.
  Flagged as environment-sensitive, not investigated further (out of this
  row's hook-boundary scope).

## Self-check evidence

```
$ bash -n plugins/leadv2/hooks/leadv2-spawn-arbiter-gate.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-spawn-gate-composition.sh && echo OK
OK
```

No Python files changed.

```
plugins/leadv2/scripts/tests/test-spawn-gate-composition.sh   pass=20 fail=0
plugins/leadv2/scripts/tests/test-spawn-speakable-pool.sh     pass=26 fail=0
plugins/leadv2/scripts/tests/test-spawn-arbiter-gate.sh       pass=27 fail=1 (pre-existing, see above)
tests/run-all.sh --scope changed                              5 passed, 2 failed (both pre-existing/environment, see above)
```

Mutation controls (both via `plugins/leadv2/scripts/leadv2-mutation-control.sh`,
artifacts under `docs/handoff/SPAWN-GATE-AND-MODEL-GUARD-DEADLOCK-01/mutation-control/`):

```
MUTATION-CONTROL ok suite=test-spawn-gate-composition.sh file=leadv2-spawn-arbiter-gate.sh
  red_line=FAIL: F1 way-forward missing speakable_models: ...
MUTATION-CONTROL ok suite=test-spawn-gate-composition.sh file=leadv2-model-inherit-guard.sh
  red_line=FAIL: B4 guard=allow
```

Work is committed on this lane branch (`worktree-bd9c35163b33`), 3 commits
ahead of base `40327a32`.

DELIVERABLE_COMPLETE
