LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, docs/handoff/F1-ARBITER-SCORING-20260907/seam-diagnosis.md, plugins/leadv2/tests/test-router-v2-shadow-mode.sh

# Mission: ARBITER-SCORING-DESIGN-01, Step 3 -- shadow mode wiring, gated on a seam diagnosis first

Spec: `docs/handoff/F1-ARBITER-SCORING-20260907/design.md` in persona-engine (§8 row 3, §9.2, §9.3).
Builds on Step 1 (`b64ce433`) and Step 2 (`8d6dbe6d`), both already landed and reviewed on this
same lane/worktree (`F1-ARBITER-SCORING-20260907-step1`). Read the full design doc, especially §6,
§8, §9.2 before touching anything.

## PART 0 (do this FIRST, before any Step 3 code): diagnose a real seam defect

Two real, both-honest measurements disagree and the disagreement matters:
- The design doc's original census (§4.2/M3, taken before Step 2 shipped) found `estimate_source=
  judge` on 0 of 39 sampled `route_v2_estimate` journal lines -- 100% fallback, judge path looked
  dead on the complexity-estimate path specifically.
- A fresh live count taken minutes ago, AFTER Step 2 landed, found 15 of 79 real
  `route_v2_estimate ... complexity_basis=judge` lines in the SAME kind of journal line, today.

Both numbers are real (checked directly against live lane journals both times). They cannot both
describe the live-judge-usage rate on the same population unless something maps `estimate_source`
and `complexity_basis` inconsistently, or the two counts sample genuinely different populations
(different call sites, different time windows, different admission-vs-route_v2_estimate line
types) without that being obvious from the token names alone.

**Find the actual explanation and write it to `docs/handoff/F1-ARBITER-SCORING-20260907/seam-
diagnosis.md`** before writing any Step 3 code. Concretely:

1. Read `leadv2-task-judge.sh`'s emission of BOTH `estimate_source` and `complexity_basis` on the
   SAME journal line (`route_v2_estimate ... estimate_source=... complexity_basis=...`, appended
   around :386 per Step 2's commit) -- can these two fields disagree on a single real line (e.g.
   `estimate_source=fallback complexity_basis=judge`, or the reverse)? If so, that alone would
   explain divergent counts depending on which field a census greps.
2. Read the derivation in `leadv2-dispatch-code.sh` around :7636-7660 (the python block computing
   `DC_COMPLEXITY_SOURCE` from `DC_ESTIMATE_SOURCE` and `DC_COMPLEXITY_BASIS`) -- confirm whether
   `est_src == 'judge'` (giving `complexity_source=judge`) is reachable at all given how
   `DC_ESTIMATE_SOURCE` is actually populated by `_dispatch_complexity_estimate()` (:3084-region) --
   is there a code path where the judge genuinely ran and decided, but `DC_ESTIMATE_SOURCE` still
   reads `fallback` by the time it reaches this block?
3. Pull the ACTUAL 15 real `complexity_basis=judge` lines from live journals (`grep -h
   "route_v2_estimate.*complexity_basis=judge" ~/.claude/leadv2-state/*/tasks/*/journal.md`) and
   check what `estimate_source=` value each one carries on the SAME line. If they say
   `estimate_source=judge` too, the two numbers are simply sampling different time windows/corpora
   (the original 0/39 predates today's traffic) and there is no seam bug -- SAY SO explicitly,
   with the checked=N count of how many of the 15 also carry `estimate_source=judge`. If some or
   all of them say `estimate_source=fallback`, THAT is the seam: name the exact line/branch where
   the judge's real decision gets relabeled as fallback before it reaches `complexity_source`.
4. State plainly in the diagnosis doc whether this seam (if real) affects `source_confidence`
   grading at all: if `complexity_source` is being silently downgraded to `heuristic`/`unknown`
   when the judge actually ran, that directly undermines the confidence tiers this design leans
   on (judge=0.9, heuristic=0.4) -- say whether that risk is real or ruled out, with evidence.

**checked=N discipline applies to this diagnosis exactly as it does to code**: quote the actual
grep output for every claim, don't summarize a count without showing where it came from.

## PART 1: Step 3 implementation (only after Part 0's diagnosis is written)

Per design.md §8 row 3: wire `LEADV2_ARBITER_CAPABILITY_FIT=shadow` as a real mode. Step 1 already
computes `_fit_order`/`_cost_order`/`fit_pick`/`fit_differs` in every `FIT_MODE` (off/shadow/on) --
confirm this is already true by reading `leadv2-route-arbiter.sh` §6 (Step 1's own code, not the
design doc pseudocode) before assuming anything is missing. If shadow mode already works end to
end from Step 1's implementation (i.e. setting the env var to `shadow` already produces correct
`fit_pick=`/`fit_differs=` tokens with the actual pick staying on `_cost_order`), your job in this
part is to PROVE that with the design's own acceptance test (§8 row 3): produce ≥29 live
`route_resolved` lines with `LEADV2_ARBITER_CAPABILITY_FIT=shadow` set, and match them against
§9.2's expected differ/match table -- do NOT re-implement something that already exists. If you
find shadow mode is NOT fully wired (e.g. the dispatcher never actually sets/forwards the env var,
or `leadv2-dispatch-code.sh` needs a `--shadow-fit` style flag to opt a real dispatch into it),
implement the minimal missing piece only.

Write `plugins/leadv2/tests/test-router-v2-shadow-mode.sh` asserting the §9.2 differ/match table
holds under shadow mode on constructed inputs (same style as Step 1's
`test-router-v2-capability-fit.sh`), plus the live acceptance check (≥29 lines, differ/match
consistent with §9.2, quote the actual grep output).

## Out of scope (§11 + Steps 1/2's own out-of-scope lists, unchanged): task_class's sizes-filter
role, freepool floor mode, UNKNOWN_PROBE_PENALTY, failure-memory demotion, effort_matrix, legacy
resolver/kimi arm, complexity_penalty itself, any persona-engine file, Step 4's `enabled: true`
flip. Do NOT flip `enabled: true` or make `on` the default under any condition in this mission.

## Hygiene note (do not repeat this session's mistake)

If you need to kill a stray process during testing, kill by the EXACT PID you yourself spawned and
recorded -- never a `pkill` by name/pattern. This machine has live, legitimate long-running
processes that share command-line patterns with test artifacts; a broad pkill can kill real work
mid-flight and get misread as evidence that a lane died.

## Acceptance (reviewed by lead against §9.2/§9.3 and this mission -- you do not self-certify)

- `docs/handoff/F1-ARBITER-SCORING-20260907/seam-diagnosis.md` exists, names a definite conclusion
  (seam bug and its exact location, OR "no bug, different time windows" with the checked=N proof),
  never an inconclusive shrug.
- Step 1 + Step 2 suites still green, no regression.
- New shadow-mode suite green.
- Live ≥29-line demonstration matching §9.2, quoted verbatim.
- Report the commit hash and branch, same format as Steps 1/2.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-94b88e76" "<question>" \
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