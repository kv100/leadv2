LANE_WRITES: plugins/leadv2/config/leadv2-routing.yaml, docs/handoff/F1-ARBITER-SCORING-20260907/step4-flip.md

# Mission: ARBITER-SCORING-DESIGN-01, Step 4 -- enabled: true (founder-approved, gate passed)

Founder decision + Leadmain's gate review are both closed: the judge is confirmed live (see
`docs/handoff/F1-ARBITER-SCORING-20260907/judge-revival-diagnosis.md`, commits `35ee99a4`,
`d40dab17`, `d3b66dd2` on this lane), and the Step 4 acceptance gate (design.md §8 row 4: >=20
fresh decision lines, zero `complexity_source=unknown` among real-source lines, >=1 positive
control) has been run and passed by the lead. This mission is pure execution of an already-made
decision -- do not re-litigate whether to flip the flag.

## Scope: ONLY this

1. `~/Projects/leadv2/plugins/leadv2/config/leadv2-routing.yaml`: flip `router_v2.capability_fit.
   enabled` from `false` to `true`. That is the entire code change. Do not touch any other key in
   this block, do not touch `source_confidence.heuristic` (stays 0.4 per Leadmain's OQ1 decision),
   do not touch any capability tier.

2. Write `docs/handoff/F1-ARBITER-SCORING-20260907/step4-flip.md` documenting:
   - The exact one-line diff.
   - A fresh live demonstration, AFTER the flip, that `fit_mode=on` now actually appears on real
     arbiter decisions and that at least one real decision's `arm=` pick differs from what it would
     have been under `fit_mode=off` (i.e. `capability_fit` actually changes at least one real
     routing decision now that it's live -- not just that the tokens print). If you cannot produce
     a real example where the pick changes, say so explicitly rather than padding the report.
   - Confirmation the rollback is a single flag flip: `LEADV2_ARBITER_CAPABILITY_FIT=off` (env
     override) or reverting this yaml line. Quote it, don't just assert it.
   - `checked=N` on every count.

3. Run the existing suites one more time post-flip to confirm nothing regresses now that `on` is
   live by default: `test-router-v2-capability-fit.sh`, `test-router-v2-headroom-order.sh`,
   `test-complexity-source-provenance.sh`, `test-router-v2-shadow-mode.sh`,
   `test-judge-complexity-path.sh`. All five must stay green with the flag flipped -- if any one
   goes red because it assumed `enabled: false`, fix the ASSUMPTION in the test (it should assert
   behavior under whatever mode is actually configured, not hardcode `off`), not the production
   code, unless the red reveals a genuine defect -- in which case name it, do not silently patch
   around it.

## Out of scope

Everything else in `router_v2` config, the arbiter/dispatcher/task-judge scripts themselves (no
code changes needed for this flip -- Step 1 already built the full `on` path), any persona-engine
file.

## Acceptance (lead reviews, does not self-certify)

- One-line yaml diff, nothing else touched in that file.
- All 5 suites green post-flip, quoted output.
- A real live decision line with `fit_mode=on` and, if found, one where the pick actually changed
  vs. what cost-only ordering would have chosen -- or an honest statement that none was found in
  the sample taken.
- `checked=N` throughout.

Report commit hash and branch. Under 1500 words.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-e8429c73" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.