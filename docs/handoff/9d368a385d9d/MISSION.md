# JUDGE-ARM-GLM-VS-HAIKU-LIVE-COMPARISON-01

## Why this exists

The complexity judge now takes an arm: `LEADV2_JUDGE_ARM=glm|haiku`, GLM by default
(`plugins/leadv2/scripts/leadv2-task-judge.sh:65`, landed 2026-09-13 in merge `1e688f5c`,
31/31 hermetic assertions). The founder's reason for it, in his words: «я просил не раз
архитекторов сделать эти сервисы Умными даже если надо делать ллм запрос (апи ключ глм может
использоваться для этого)» — the decision layer was spending Anthropic quota to decide how to
spend Anthropic quota.

The switch is BUILT and its transport is covered hermetically. **What was not reached is the only
thing that proves the default is safe: a live comparison.** Round 2's own report says so —
"The required ten-mission live comparison was not reached".

Right now GLM is the DEFAULT on every dispatch with no evidence it agrees with haiku. That is the
gap this lane closes. It is a measurement lane, not a feature lane.

## What to measure

Run BOTH arms over a fixed corpus of **at least 10 real missions** and report agreement.

- Corpus: real mission texts already on disk — `docs/handoff/*/MISSION*.md` in the plugin repo.
  Pick a spread, not ten of the same shape: at least one trivial, one docs-only, one multi-subsystem
  build, one safety/protected path. Name the ten you chose and why, so the sample is auditable.
- For each mission run the judge twice — `LEADV2_JUDGE_ARM=glm` and `LEADV2_JUDGE_ARM=haiku` — and
  record the full verdict each returns (complexity, confidence, required effort, whatever the
  envelope carries), not just a single field.
- Report: the disagreement COUNT, and for each disagreement the mission, both verdicts, and which
  one a reader would call right. A disagreement on confidence alone is not the same as a
  disagreement on complexity class — separate them.
- Run each arm TWICE on at least three missions to measure the judge's own self-consistency. An
  arm that disagrees with ITSELF makes cross-arm agreement meaningless, and that number must be in
  the report before the cross-arm number is interpreted.

## The decision this measurement drives

- GLM agrees on complexity class in essentially every case → keep it as default, record the number.
- GLM disagrees materially → **flip the default back to haiku** and say why, with the cases.
  A cheaper judge that is worse is not a win; the founder has already ruled that the decision layer
  may spend to decide well (`feedback_decision_layer_may_spend_to_decide_well`).
- GLM is unreliable in a way that is not about verdicts — timeouts, malformed envelopes, empty
  results — report the failure RATE separately from the disagreement rate. Those are different
  defects with different fixes, and the fallback path's behaviour under each must be stated.

Whatever the outcome, the default in the file at the end of this lane must match what you measured,
and the report must name the number that justifies it.

## Method — binding

- No verdict may be reported without the invocation that produced it.
- Do not stub the model. This lane exists precisely because the hermetic tests already pass; a
  mocked comparison would repeat work that is done and prove nothing new.
- If an arm cannot be exercised at all (no key, quota exhausted, endpoint down), that is a
  reportable result with its error text — say `NOT REACHED: <reason>`, never infer agreement.
- Re-check what looks obviously true: if the two arms agree perfectly on all ten, suspect the
  harness before believing it, and prove the two paths really differ by showing the arm actually
  used in each run (`judge_arm` is audited on the envelope).

## Acceptance

1. A committed report naming the ten missions, both verdicts each, the self-consistency number,
   the disagreement count, and the failure rate per arm.
2. A re-runnable harness committed alongside it, so the comparison can be repeated after any judge
   change rather than re-derived by hand.
3. `test-leadv2-task-judge.sh` still 31/31.
4. The default arm in `leadv2-task-judge.sh` matches the measurement, and the report says which.

## Off limits

- The judge's separation of concerns: it carries ZERO arm/model/provider/quota vocabulary
  (`leadv2-task-judge.sh:11`). Configure and measure its arm; never teach it about quota.
- `leadv2-route-arbiter.sh` — a sibling lane is writing it.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
