LANE_WRITES: plugins/leadv2/scripts/leadv2-task-judge.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, docs/handoff/F1-ARBITER-SCORING-20260907/judge-revival-diagnosis.md, plugins/leadv2/tests/test-judge-complexity-path.sh

# Mission: revive the complexity-path judge (founder decision, 2026-09-07)

Founder chose "revive the judge" over the two alternatives (formalize heuristic-only / 24h shadow
mode) explicitly because he requires the judge to actually decide complexity correctly before
`enabled: true` ships. This is real production work on a shared plugin (`~/Projects/leadv2`),
symlinked live into 3 repos (persona-engine, m3-market, respiro-ios) -- read
`docs/handoff/F1-ARBITER-SCORING-20260907/design.md` and `judge-revival-estimate.md` (persona-
engine, already committed) for full background before starting.

## Background you must not re-litigate

- `leadv2-task-judge.sh:463-500` has 3 short-circuits before it ever calls the model: explicit
  disable, `CLASS_HINT == "Light"` skip (:468, "R2 mitigation #3"), and a cache hit (:473,
  "R2 mitigation #2"). Only past all three does `_invoke_judge()` run a real
  `claude -p --model haiku` call.
- Real traffic today: 38/83 (46%) of dispatches are `task_class=Light` -- checked, real journal
  count. This alone explains a large share of "0 judge decisions on the complexity path," and it
  is BY DESIGN, not a bug -- do not remove/loosen the Light skip without first checking `get_why`
  or an equivalent decision-record search for why R2 mitigation #3 was added; if you find no
  record, say so explicitly and treat removing it as a real, flagged risk, not a free lunch.
- The remaining 54% (Standard/Heavy) is the ACTUAL population where the judge could fire and
  currently doesn't (0/39 in the design doc's original census, reconfirmed independently at 0/112
  by the seam-diagnosis work in `docs/handoff/F1-ARBITER-SCORING-20260907/seam-diagnosis.md` --
  read it, it also documents a measurement trap you must not repeat, below).

## PART 0 (mandatory, before any fix): name the exact mechanism with runtime evidence, not a code read

Three candidates. They have DIFFERENT fixes. Do not merge them into one story -- today this
project already paid twice for exactly that mistake (a mocked launcher file conflated with a CLI
version mismatch; both were real, both needed separate fixes).

1. **Never called** -- for the Standard/Heavy population specifically (Light is already explained
   above, don't re-derive that), does `_invoke_judge()` even get reached? Check whether the cache
   hit (mitigation #2, :473) is silently absorbing nearly all Standard/Heavy traffic too (e.g. if
   task signatures repeat often enough that a cache entry almost always exists).
2. **Called and fails silently** -- if `_invoke_judge()` IS reached, does the actual `claude -p`
   call fail (timeout at 45s, non-zero exit, empty output, JSON parse failure) and fall through to
   `_fallback_estimate()` at line ~500 without ever surfacing the failure loudly? Check `_validate_
   estimate`'s behavior on a judge response that came back malformed, and check whether any
   failure telemetry currently exists for this branch specifically (as opposed to the generic
   fallback path shared with the Light-skip and cache-hit branches -- if all three funnel through
   the same fallback call with no distinguishing marker, THAT lack of a marker is itself part of
   the fix).
3. **Called, answers, discarded downstream** -- if the judge answers successfully and
   `_validate_estimate` accepts it, does the resulting `estimate_source=judge` /
   `complexity_basis=judge` actually survive to the journal line and to `DC_COMPLEXITY_SOURCE` at
   dispatch-code.sh:7637-7660 (already independently verified reachable in Step 3 -- re-read
   `seam-diagnosis.md` section 2 rather than re-deriving it)?

**How to distinguish 1 vs 2 vs 3 without guessing**: instrument (temporarily, or via existing
telemetry if it exists) which of the three short-circuits or the real invoke fires, on a live
Standard/Heavy dispatch, and read the actual runtime trace -- not the code's theoretical branches.
"No trace of an invoke attempt" proves (1). "A trace of an invoke attempt with no journaled
result" proves (2). "A trace of a successful invoke whose result vanishes before the journal line"
proves (3). Write the finding, with the exact log/trace line as proof, to
`docs/handoff/F1-ARBITER-SCORING-20260907/judge-revival-diagnosis.md` BEFORE writing any fix.

## PART 1: fix, only after Part 0 names a confirmed mechanism

Scope depends entirely on what Part 0 finds -- do not pre-guess the fix here. Whatever it is, it
must not touch the Light-skip's cost-avoidance intent without an explicit, separately-flagged
justification (this mission does not authorize removing R2 mitigation #3 wholesale; if the finding
is "Light-skip alone explains everything and Standard/Heavy genuinely calls+succeeds", there may be
nothing to fix at all -- say so).

## PART 2: negative control -- execution-proven, inside the function body

Per this project's own hard-won discipline (`docs/handoff/F1-HARD-WORK-20260907/`): a negative
control must PROVE the mutated line executed, via a printed token from the mutation itself, not
via "the test suite went red" alone. Mutate the exact branch/line Part 0 identified as the
mechanism, inside the function body, and show the mutation's own token in the output.

## PART 3: live demonstration, with the EXACT exclusion trap fixed this session avoided

`docs/handoff/F1-ARBITER-SCORING-20260907/seam-diagnosis.md` documents a real trap this project
fell into TWICE today: `grep -h` strips filenames before a content-based `ephemeral|deadbeef`
exclusion can match anything, silently letting synthetic fixtures contaminate a "live" count.
**You must exclude by PATH, via `find`, before any `grep -h`** -- the correct pattern is:

```
find ~/.claude/leadv2-state -path '*/tasks/*/journal.md' | grep -vE 'ephemeral|deadbeef' \
  | xargs grep -h '<pattern>'
```

never `grep -h '<pattern>' ~/.claude/leadv2-state/*/tasks/*/journal.md | grep -vE 'ephemeral|deadbeef'`
(the second form is exactly what produced the false "15/79" claim earlier today). Show your actual
command, not a paraphrase.

Live acceptance: after the fix, `complexity_basis=judge` on real (path-excluded)
`route_v2_estimate` lines must be **> 0** on genuinely live Standard/Heavy dispatches you generate
or that occur naturally during your work -- quote the exact `find`/`grep` command and its output.

## Out of scope

Step 4 (`enabled: true`) -- do not touch it, do not flip any default. `router_v2.capability_fit`
config from Steps 1-3 -- unrelated to this mission, do not edit. Any persona-engine file except
the diagnosis doc and new test listed in LANE_WRITES above.

## Acceptance (reviewed by lead against Leadmain's 4 points -- you do not self-certify)

1. Named mechanism (1, 2, or 3 above -- or "no bug, Light-skip explains it all") with a quoted
   runtime-evidence line proving it, not a code-read inference.
2. Live demonstration: `complexity_basis=judge` > 0 on real, path-excluded journal lines, exact
   command and output quoted.
3. Negative control inside the function body, mutation's own token printed as proof of execution.
4. `checked=N` on every count claimed anywhere in the diagnosis or the report.

Report back with commit hash and branch. Under 2500 words.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-f8b18b54" "<question>" \
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