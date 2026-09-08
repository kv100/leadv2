JUDGE-CANNOT-PARSE-ITS-OWN-ANSWER-01. The complexity judge fails to read its own reply most of
the time and silently falls back to a constant. This closes founder gate row 5(a) and is a
precondition for rows 4 and 6 ever being measurable — both consume the judge's estimate.

REPO: ~/Projects/leadv2. Gate table:
`~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/GATE-EVIDENCE.md` (row 5).

## The measurement

Across real lane journals: **14 of 38 judge invocations usable (37%), 23 failed (61%)**, the
dominant failure being `judge_fail_reason=envelope_parse`. A live example from tonight's dispatch
of lane `31b4e0e4`:

    route_v2_estimate estimate_id=54516bb7 estimate_source=fallback complexity=standard
      work_kind=build duration_class=medium … judge_path=judge_fail judge_fail_reason=envelope_parse

The mechanism, in `leadv2-task-judge.sh`:
- `:60`  `JUDGE_MODEL="${LEADV2_JUDGE_MODEL:-haiku}"`
- `:409-410` the envelope parse: `|| { _fail "envelope_parse"; return 1; }`
- on failure the caller drops to `_fallback_estimate`, which resolves to `standard`.

So two thirds of the time the "smart" estimate is the word `standard` with a judge-shaped ritual
around it. Every downstream branch that reads `complexity` is therefore evaluating a constant —
which is exactly why gate row 6 shows 13 of 13 dispatches on `plan_first` and row 4 shows 79% of
decisions at `tier=standard effort=high`.

**Measurement hygiene, learned the hard way:** an earlier count of "44% usable over 90
invocations" was wrong in the flattering direction because test fixtures (`dispatch-deadbeef*`,
which exist only to exercise `LEADV2_JUDGE_DISABLE`) were in the denominator. Exclude fixture task
ids from any rate you report, and say in the report how many you excluded.

## What to build

1. **Find out what the model actually returns when the parse fails.** Capture the raw reply for a
   failing invocation before changing anything, and put a redacted sample in your report. Do not
   guess at the cause: prose around the JSON, a code fence, a truncated reply and a refusal are
   four different bugs with four different fixes, and picking wrong here buys nothing.
2. **Fix the parse for whatever the evidence shows** — tolerate the wrapper the model actually
   emits (fenced block, leading prose, trailing text), and keep rejecting a genuinely unparseable
   reply. Being permissive about the WRAPPER must not become being permissive about the CONTENT:
   a reply with no usable fields still fails.
3. **A failure must not be silent.** `envelope_parse` already reaches the journal; make sure the
   raw reply (truncated, redacted) reaches the lane's handoff dir so the next investigation does
   not start from zero.
4. **Do not remove the fallback.** `standard` on failure is the safe direction. The defect is the
   RATE, not the existence of a fallback.

Out of scope: changing `JUDGE_MODEL`, changing the estimate vocabulary, touching any consumer of
the estimate. If the evidence says the model itself is the problem (e.g. haiku cannot hold the
format), STOP and report that finding rather than swapping the model on your own.

## Acceptance
acceptance:
  surface: log_line
  observable: over at least 10 REAL judge invocations after the fix, `judge_fail_reason=envelope_parse`
    is gone from the journals and `estimate_source=judge` appears where `estimate_source=fallback`
    used to. Report the before/after rates with the fixture ids excluded and the count of
    exclusions. One passing invocation is not evidence of a rate.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the parse function's body, revert to the strict form that rejects the wrapper the model
   actually emits. The suite must go red on `estimate_source` for a fixture carrying a REAL captured
   reply — the value that has never varied in production — not on a log string.
2. Inside the same body, accept a reply that has the wrapper but NO usable fields. The suite must
   go red: a permissive parse that manufactures an estimate out of nothing is worse than the
   current failure, because the fallback at least announces itself.
Insert each mutation INSIDE the function body, never at top level — a top-level insert makes every
suite red for the wrong reason and reads as a pass. Self-register with
`# run-all-triggers: leadv2-task-judge` and verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`; do NOT edit `tests/run-all.sh`.

## Constraints
- Touch ONLY `plugins/leadv2/scripts/leadv2-task-judge.sh` and your new suite.
- Do NOT touch `leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`,
  `leadv2-phase8-e2e-gate.sh`, `leadv2-helpers.sh`, `codex-task.sh`,
  `leadv2-lane-worktree.sh`, `config/leadv2-routing.yaml` — live lanes own several of these.
- Never `git add -A`. **`git commit -- <path>` commits the WORKING TREE for that path, not the
  index.** Stage explicitly, check `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact: a journal line, a captured reply, a rate with its denominator.
  Say "unverified" out loud; never say "should work".

LANE_WRITES: plugins/leadv2/scripts/leadv2-task-judge.sh, plugins/leadv2/scripts/tests/test-judge-parses-its-own-answer.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-75d7ef49" "<question>" \
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