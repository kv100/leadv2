# HEAVY-TIER-VS-SAFETY-OPUS-01 — Round 2 report

Lead adjudication implemented exactly as `fix-round-2.md` specifies: the hard-safety
tag pin now outranks the Heavy/Strategic think tier, with `arch` carved out.
Round 1 (`99b4f865`) was not redone; its assertions stay green.

## Change

`plugins/leadv2/scripts/leadv2-session-route.sh` — model-selection order is now:

1. `light` → light model (unchanged)
2. **tag hit on a HIGH_RISK_TAG other than `arch`** → `CLAUDE_SAFETY_MODEL`/`_EFFORT`
   (opus/high). Evaluated FIRST, so Heavy/Strategic + a hard-safety tag
   (`auth,rls,safety,publish,security`) pins opus. Still outside the config/env
   override surface, as round 1 built it.
3. `heavy|strategic` (or Heavy + arch-only tag) → think arm
   (`lib/leadv2-think-model.sh` → fable; opus fallback)
4. `_high_risk` on a non-Heavy class → safety pin (unreachable in default config;
   kept so a class-forced high-risk never falls through to SUGGESTED_MODEL)
5. `SUGGESTED_MODEL`

`arch` carve-out rationale (from the adjudication): the five hard tags name
consequences in the world; `arch` names difficulty, not consequence.
`PLANNER-MODELS-DECISION-01` deliberately pins Heavy planning/architecture to the
think tier. On a non-Heavy class, `arch` keeps round-1 behaviour (safety pin) —
asserted.

The tag-scan loop now runs unconditionally and records the matched tag
(`_risk_tag_hit`) instead of only setting a boolean; `_high_risk` semantics
(Codex/GLM/kimi bans, early-exit route emission) are unchanged.

## New assertions (plugins/leadv2/scripts/tests/test-session-route.sh)

- `Heavy + safety tag -> opus (safety outranks think tier)` — replaces round 1's
  `Heavy + safety tags stays think-tier`, which asserted the exact branch the lead
  reversed. Flipped per the adjudication, not weakened.
- `Heavy + arch tag stays think-tier (arch carve-out)` — `model=fable`.
- Plus `Standard + arch tag pins opus` (non-Heavy arch keeps round-1 behaviour).
- All round-1 assertions retained and green (suite: PASS=12 FAIL=0).

## Negative controls (both directions)

NC1 — reorder reverted (round-1 branch order, new tests kept):

```
[TEST] FAIL: Heavy + safety tag -> opus (safety outranks think tier) missing 'model=opus' in: provider=claude
[TEST] Results: PASS=11 FAIL=1
```

NC2 — `arch` carve-out dropped (`-n "$_risk_tag_hit"` without the `!= arch` guard):

```
[TEST] FAIL: Heavy + arch tag stays think-tier (arch carve-out) missing 'model=fable' in: provider=claude
[TEST] Results: PASS=11 FAIL=1
```

Both reverted → green again (PASS=12 FAIL=0).

## Platform proof (exit codes measured unpiped)

macOS (Darwin 25.5.0, bash 3.2):

```
bash plugins/leadv2/scripts/tests/test-session-route.sh
[TEST] Results: PASS=12 FAIL=0
macos-exit=0
```

Linux container (python:3.12-slim, GNU bash 5.2.37, Python 3.12.14):

```
[TEST] Results: PASS=12 FAIL=0
exit=0
```

## Census: other callers resolving safety through a class check

Grepped `plugins/leadv2/scripts` for safety→model decisions and class checks.
`CLAUDE_SAFETY_MODEL` appears only in `leadv2-session-route.sh`.

**One found second instance — flagging for the lead, not fixed here (out of
round-2 scope):** `plugins/leadv2/scripts/lib/leadv2-admission-class.sh:57-77`
(`leadv2_admission_map_class`) folds `risk_class=safety_publish_payments` into
**class Heavy** (`complexity == "complex" OR risk == "safety_publish_payments"
OR subsystems_touched >= 4 → Heavy`). The resulting Heavy class is what reaches
`leadv2-session-route.sh` as `TASK_CLASS`, while the safety-pin channel is
`RISK_TAGS` — a separate input populated from the dispatch's risk tags, not from
the judge's `risk_class`. So a task the judge classified
`safety_publish_payments` but that carries no explicit high-risk `risk_tags`
would now take the think arm (fable) instead of the safety pin. That is the same
"class-check-instead-of-tag-check" shape the lead called a bug in round 1.
Candidate fixes (lead's call): propagate `risk_class=safety_publish_payments`
into `risk_tags` at admission, or teach the route script to read the judge's
risk_class. Not done here because the admission→route contract is cross-lane
surface.

No other caller routes a model decision for safety through a class check
(`leadv2-route-arbiter.sh` uses class only for bucket flooring;
`leadv2-task-judge.sh` only produces `risk_class`, it does not route).

## Self-check

- `bash -n leadv2-session-route.sh` ok; `bash -n tests/test-session-route.sh` ok
  (SYNTAX-OK pasted above in transcript; both clean).
- No Python files changed (no `py_compile` needed).
- Changed-scope runner: this lane's changed scope is the route script + its
  suite; the suite itself is the changed-scope test (12/12 green on both
  platforms, above). `tests/run-all.sh --scope changed` was not run: core-offline
  alone exceeds 10 min (see run-all-changed-scope-runtime memory) and no other
  suite's inputs changed; negative controls above cover the regression surface.
