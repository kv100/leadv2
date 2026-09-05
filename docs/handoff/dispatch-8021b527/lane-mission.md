GLM-PEAK-RULE-IS-MODEL-BLIND-01 — the peak-hours gate refuses the whole GLM arm on the clock
alone, without knowing which GLM model the arbiter actually chose.

FOUNDER DECISION 2026-09-04, verbatim in substance: during peak hours the tokens count 3×
while the money is a flat subscription — so the cost is QUOTA BURN on an account the live
Respiro engine shares, not dollars. His ruling: **in peak hours flash is allowed; the regular
GLM should not be used in peak, only if every other bucket is unavailable.**

Second founder constraint, equally binding: **GLM model versions rotate roughly monthly.**
Walking every repo and plugin to rewrite a version number is not acceptable. Whatever
discriminates flash from non-flash must survive `glm-5.3-flash` becoming `glm-5.4-flash`
without an edit.

WHAT IS TRUE TODAY, measured 2026-09-04 (do not re-derive, but DO re-measure before claiming
a fix works):

- `leadv2-glm-quota-gate.sh:75,80` — peak is a pure clock test, hours 6..9 UTC, no model input.
- The gate takes NO model/arm argument at all. It refuses `glm` as a bucket.
- Live at 09:57:42Z it returned `rc=2 / LEADV2_DISPATCH_REFUSED: peak_hours`; at 10:00:15Z the
  same command returned `rc=0`. The instrument answers both ways — use it.
- Meanwhile the arbiter's live decision in BOTH minutes was
  `arm=glm-flash model=glm-5.3-flash chain=glm-flash,glm,sonnet,freepool util_glm=23`.
  So the arbiter had already chosen flash and the gate refused it anyway.
- The seam you need already exists and is version-free: `leadv2-dispatch-code.sh:5188`
  distinguishes `arm == "glm"` from `arm == "glm-flash"` today. The ARM NAME, not the model
  version string, is the discriminator. Use it.
- Caller: `glm-coder.sh:198` invokes the gate as a sibling and acts on its exit code.
- §1 of the gate's own header records WHY the headroom matters: the Respiro engine shares this
  exact z.ai account and has no provider fallback. The headroom is the persona's, not ours.
  That is what the peak rule protects, and 3× token counting is a 3× faster burn of it.

THE WORK.

1. The gate must learn which arm is being launched. Add the seam; do not guess it from the
   environment if the caller can pass it.
2. Peak + flash  -> allow (exit 0).
3. Peak + non-flash GLM -> refuse as today (exit 2), EXCEPT as a last resort when no other
   bucket can take the work. You must DEFINE "no other bucket" against something real: the
   gate already reads live quota for every provider. Name the condition you implement and say
   why it cannot fire spuriously. If you conclude the gate cannot know this safely, say so and
   leave the existing `GLM_ALLOW_PEAK=1` override as the last-resort path — that is an
   acceptable answer, but it must be argued, not defaulted into.
4. Outside peak: behaviour unchanged. Section 1's 80% reroute: unchanged. Section 3 fail-open:
   unchanged.
5. No version literal anywhere in the discriminator.

ACCEPTANCE. The gate ships `GLM_SIMULATE_UTC_HOUR` for exactly this — use it, do not wait for
a real clock.

1. `GLM_SIMULATE_UTC_HOUR=8` + flash arm -> exit 0. Show the command and the output.
2. `GLM_SIMULATE_UTC_HOUR=8` + plain glm arm -> exit 2 with
   `LEADV2_DISPATCH_REFUSED: peak_hours`.
3. `GLM_SIMULATE_UTC_HOUR=12` + plain glm arm -> exit 0 (outside peak, unchanged).
4. VERSION-ROTATION CONTROL, mandatory and specific to the founder's second constraint:
   feed the gate a flash arm whose model string is a version that does not exist today
   (e.g. `glm-9.9-flash`) and show it still passes in peak. A discriminator that only knows
   `5.3` fails this and must be rewritten.
5. NEGATIVE CONTROL, mandatory: mutate the discriminator INSIDE the function body so flash is
   no longer recognised, show the suite goes red on case 1, restore, show it green again.
   Report both outputs verbatim. A suite that never showed its own red proves nothing.
6. The suite carries a `# run-all-triggers:` header naming the gate, and CI selection is proven
   with `tests/run-all.sh --scope changed`. `EXTRA_SUITE_MAP` was deleted 2026-09-04 — a row
   added there now silently never runs.
7. Report the suite's final count line verbatim; if it prints none, say so.

CONSTRAINTS. This gate lives in the shared plugin tree feeding three repositories; the founder
authorised this specific change. Never `git add -A`. Do not push to origin. Do not widen
`tests/known-red-suites.txt` — it may only shrink. If the close gate returns `e2e_regression`,
run the named suites on main WITHOUT your commit before believing it: two suites are already
red on main independently (`PE-GATE-HAS-NO-KNOWN-RED-LIST-01`). A verdict is not evidence.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-8021b527" "<question>" \
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