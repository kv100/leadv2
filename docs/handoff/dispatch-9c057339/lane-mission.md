P6b — WIRE-THE-COMPLEXITY-ESTIMATOR-INTO-THE-DEPTH-GATE-01. The branch that scales review depth by
complexity has existed for weeks and has only ever evaluated one way. Make the other way happen, once,
for real. This closes founder gate row 6 and supplies the input gate row 4 needs.

REPO: ~/Projects/leadv2. Gate table:
`~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/GATE-EVIDENCE.md` (row 6).

## HARD PRECONDITIONS — check both, stop if either is false

1. SATISFIED as of 2026-09-08T09:1xZ — P6a is merged to `main` as `a7db808f` (branch
   `worktree-f33ff575078f`, whose own commit was `aa18b583`). The estimator you are wiring is
   `plugins/leadv2/scripts/lib/leadv2-complexity-estimate.py`, and the merge changed nothing on the
   live path — nothing calls it yet. Lane `e9eee486`, launched AFTER that merge, still logged
   `complexity=unknown complexity_source=unknown conf=0.0`. That is the gap you are closing.
2. SATISFIED as of 2026-09-08T10:4xZ — P1b is merged to `main` as `45efe543`. It rewrote the
   same region of `leadv2-dispatch-code.sh` (the subsession spawn now carries the arbiter's
   chosen arm and model instead of a hardcoded `--role developer --model sonnet`), so branch
   from main AS IT IS NOW and read that spawn before touching it — the hardcoded pair the older
   drafts of this mission described is gone.

## What is measured, and why it is the disease and not a bug

The branch is real and already written:

    leadv2-dispatch-code.sh:4352        plan_first | brief_direct
    leadv2-dispatch-code.sh:4355-4357   review rounds 1 / 2 / 3
    leadv2-dispatch-code.sh:4536        logged as complexity_gate_applied

Re-measured 2026-09-07T20:55Z across every lane journal: **13 `complexity_gate_applied` rows, 13
`plan_first`.** `review_rounds` is 3 (×7) or 2 (×6). `brief_direct` has never occurred. `review_rounds=1`
has never occurred. Provenance is mostly `complexity_source=flag` — the caller DECLARES the class and
the heuristic resolves the whole fleet to `standard`.

**A condition that only ever evaluates one way is a constant with a branch drawn around it**, and every
test asserting `plan_first` passes forever without proving anything. That is the same failure this
repo has now hit three times in one day (`transport_gone_app_server_absent` attached unconditionally;
`codex-task.sh:14-20` documenting a tier table the code had abandoned).

## What to build

Feed `lib/leadv2-complexity-estimate.py` into the existing gate block so `complexity_source=estimate`
becomes the normal case and `flag` goes back to being what its name says: an explicit operator
override. Read the estimator first — it already emits exactly the consumer's vocabulary
(`complexity=trivial|simple|standard|complex`, `pipeline_route`, `review_rounds`) and its own
`reason=` string, and it already enforces the two rules that matter:

- **Unknown provenance resolves DEEPER, never shallower.** No mission text and no write-set ⇒
  `standard / plan_first / 2`, never `brief_direct`. Preserve that when wiring; a missing estimate must
  never be able to buy a shallower review.
- **An explicit declared class still wins**, and is still labelled `complexity_source=flag`.

Do not re-derive the vocabulary, do not add a second estimator, and do not change the ceilings.

## Acceptance
acceptance:
  surface: log_line
  observable: A REAL dispatch of a genuinely trivial task produces
    `complexity_gate_applied … complexity_source=estimate pipeline_route=brief_direct review_rounds=1`
    in its lane journal, and the lane actually runs ONE review round — not two with one skipped. Show
    the journal line and the round count from the same task id. In the same evidence, show a heavy task
    from the same day still landing on `plan_first` with 3 rounds: one sample proves reachability, two
    opposite samples prove the branch is a branch.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the gate block's function body, ignore the estimate and hardcode `standard`. The suite must
   go red **on `pipeline_route` for the trivial fixture** — the exact value that has never varied.
   A control that only checks the heavy fixture cannot tell a wired gate from today's constant.
2. Inside the same body, let a missing estimate fall through to `brief_direct` instead of the deeper
   floor. The suite must go red on the no-signal fixture. This is the dangerous direction: a wiring bug
   that makes unknown mean "cheap" silently removes review from everything the estimator cannot read.
Insert each mutation INSIDE the function body, never at top level — a top-level insert makes every
suite red for the wrong reason and reads as a pass. Self-register with
`# run-all-triggers: leadv2-dispatch-code` and verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`; do NOT edit `tests/run-all.sh`.

## Constraints
- Do NOT modify `lib/leadv2-complexity-estimate.py` (landed and lead-verified: suite selected by the
  trigger map, 5/5 green, control inside `_route_and_rounds` red at pass=2 fail=3). If it needs a
  change, STOP and report what and why.
- Do NOT touch `lib/leadv2-route-arbiter.sh`, `config/leadv2-routing.yaml`, `codex-task.sh`,
  `tests/run-all.sh`. Read them freely.
- Never `git add -A`. **`git commit -- <path>` commits the WORKING TREE for that path, not the index**
  — in a dirty repo it silently sweeps in other people's uncommitted edits. Stage explicitly, check
  `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact: a journal line, a round count, a suite output. Say "unverified"
  out loud; never say "should work".

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-depth-gate-uses-the-estimate.sh


---

## ADDENDUM 2026-09-08 — a complexity signal already exists, and it is being LOST

Measured by the lead today from a live dispatch log (`B4-EMPTY-DIFF`, lane `1401655b`). This
changes the shape of the task and it is not in the body above, which assumes the signal is simply
absent.

**The first resolution carries a real signal:**

    route_resolved by=arbiter role=worker arm=glm model=glm-5.3 ... complexity=complex
    duration_class=long complexity_policy=capability_fit complexity_source=judge conf=0.9
    req_eff=4.0 fit_mode=on fit_pick=glm

**The second resolution, after the primary arm was benched, does not:**

    route_headroom_chosen task=1401655b arm=codex after=primary_arm_benched ordered=codex,sonnet
    ... complexity=unknown duration_class=unknown complexity_policy=capability_fit
    complexity_source=unknown conf=0.0 req_eff=3.0 fit_pick=codex

Same lane, same mission text, seconds apart. `complexity=complex conf=0.9` from a judge became
`complexity=unknown conf=0.0`, and `req_eff` fell 4.0 → 3.0 with it — so the *arm actually chosen*
was selected against a lower effort requirement than the one the judge had already established.

Three consequences for this mission:

1. **`complexity_source=judge` is a third source you must not clobber.** The body above talks about
   estimator-vs-unknown; there is a judge in the picture too. Establish what it is, when it runs,
   and how its answer relates to the estimator's before you wire anything. If the estimator and the
   judge can disagree, say which wins and why.
2. **The re-resolution path losing the signal may be the more urgent defect than the missing
   wiring.** A signal that exists and is dropped is worse than one that was never computed, because
   the first resolution's log makes it look like the system knows. Find where the second resolution
   builds its inputs and why it does not inherit them.
3. **Do not assume the estimator is called anywhere.** Verified today:
   `lib/leadv2-complexity-estimate.py` is referenced by exactly two files — itself and
   `scripts/tests/test-complexity-estimate-easy-half.sh`. **Zero production callers.** So the
   `complexity_source=judge` above is emphatically *not* the estimator, and wiring the estimator
   does not by itself fix the loss described in (2).

Add a negative control for (2) specifically: a lane whose primary arm is benched must carry the
same complexity and `req_eff` into the second resolution as the first. Assert the **values**, not
the presence of a log line — and assert them on BOTH lines, because the current failure is a
disagreement between two lines that each look fine alone.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-9c057339" "<question>" \
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