# A 401 from the usage endpoint is not a dead account

**Priority 0, and the sharpest item on the pre-WAVES list.** One bug, three symptoms. Section D1 of
`PRE-WAVES-PLAN.md`; the founder has started that plan, and this is first because fixing it moves
gate rows A3 and A5 at once.

REPO: `~/Projects/leadv2`. Its `main` IS the live path — symlink deploy, so a fix not committed to
main is not delivered. **Dispatch and work from `~/Projects/leadv2`.**

---

## The three symptoms, and why they are one bug

1. **`max_20x` is priced out of every selection.** `subscription_type=max`, usage endpoint answers
   http 401, so it classifies `unknown` and carries `UNKNOWN_PROBE_PENALTY=50.0`
   (`lib/leadv2-route-arbiter.sh:913`). Fifty clears the entire cost range — the most expensive arm
   in the matrix is opus at 9 — so that account can never be selected for anything, while possibly
   being completely alive.
2. **Three review arms were marked unknown and a lane died for it.** fable/opus/sonnet came back
   `unknown` in the review pool, glm refused on quota, and the lane was killed
   `all_arms_unavailable` ten minutes after its worker had already spawned. The consumer half of
   that is **already fixed and merged** (`fe491bff`) — do not redo it. What was measured there is
   the input to this mission: the probe exists, it calls the live Anthropic quota CLI, and it
   returned **http 401**.
3. **`max_5x` answers 401 by design.** It is a team account; the standing rule is that we do not
   measure spend on it and that **a 401 from usage never by itself proves a token is dead.**

So in at least three places the system reads its own documented normal condition as a fault.

---

## The contradiction to start from — I derived this today, verify it before building on it

`plugins/leadv2/scripts/leadv2-quota-read.py:412-434`, `classify_account_state`. Its own docstring
states the precondition:

> http_code is the /api/oauth/usage response code for an account whose credential **DID resolve an
> access token** (read_anthropic only reaches this classification once `accessToken` was present —
> a token-less entry never gets here at all, which is the "credential dead" case: it is excluded
> upstream, not classified `unknown` by this function).

And then, four lines later, it calls a 401 on a non-team account:

> the ordinary "this credential is actually dead" shape

**Those two statements cannot both be true.** By the function's own precondition, every account it
classifies has already resolved an access token. A dead credential does not reach this function. So
a 401 here cannot be evidence that the credential is dead — for `max` any more than for `team`.

The narrowness was deliberate and its stated reason is honest ("a broader rule would risk quietly
reclassifying a genuinely dead personal/pro credential as merely unmetered"). Your job is not to
call that wrong. It is to find the test that actually distinguishes the two cases, because the
current one does not — it distinguishes `subscription_type`, which is not the same question.

---

## What the fix has to achieve

**The test for whether an arm is usable must be whether it can LAUNCH, not what a usage endpoint
says about its tier.** That sentence is the acceptance criterion; everything else is how.

Concretely, at minimum:

- An account whose token resolved and whose usage endpoint answers 401 must not carry a penalty
  that removes it from every possible selection. Whether the right answer is the existing
  `unmetered` state widened past `team`, a fourth state, a launch probe, or a much smaller penalty
  is yours to determine and defend.
- A genuinely dead credential must still be excluded. Name the signal that distinguishes it. If the
  honest answer is "no signal short of attempting a launch", say so — that is a finding, and it
  points at the shape of the fix rather than away from it.
- Do not double-price one fact. `lib/leadv2-route-arbiter.sh:937` already warns about exactly that:
  *"pricing it twice for one fact is the error this…"* — read that comment before you touch the
  penalty.

**Out of scope, deliberately:** the review-pool consumer (merged), the dispatcher's launchable-arm
fallback (merged as `7351b176`), and anything about switching accounts — that is a separate filed
task with its own design.

---

## Negative controls (E2E-KILLRATE-01, non-negotiable — run them, red then green)

Two at minimum:

1. **The symptom.** An account with `subscription_type=max` and http 401 must become selectable.
   Before your fix this must FAIL; after it, pass. Assert the *selection outcome* — the arm the
   arbiter returns — not a log line.
2. **The guard.** A genuinely unusable credential must still be excluded. Widen your own rule
   deliberately (make everything usable) and show the suite goes red on a value. This is the
   mirror of the control I ran on P1b, which caught a widening with
   `PENALTY_MISMATCH usable account charged 0` — that suite,
   `plugins/leadv2/tests/test-claude-account-states.sh`, already exists and is the right neighbour
   to extend.

Insert every mutation **inside the function body**, never at top level.

Register your suite with a `# run-all-triggers: <stem>` header. **Then prove selection correctly**,
because this knob lies in three different ways and has already produced two wrong conclusions today:

- it counts from `$GIT_DIR/leadv2-run-all-last-checked-sha` if that file exists (`:294-310`);
- with no checkpoint and no resolvable base ref it degrades to `HEAD~1..HEAD` — the last commit
  only (`:308-317`);
- so a correctly registered suite can look unregistered, and a broken one can look fine.

Pin the range to the merge base for the proof (write the merge-base sha into the checkpoint file,
run, then remove it) and state in your report which range you measured from. Filed as
`SCOPE-CHANGED-IS-STATEFUL-AND-A-SECOND-RUN-LIES-01` and
`SCOPE-CHANGED-DEGRADES-TO-THE-LAST-COMMIT-01`.

---

## Constraints

- Do not merge. Report, and the lead verifies and merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`. Never
  `git add -A` — enumerate paths.
- **Never print or commit `~/.claude/state/leadv2/claude-profiles.tsv`.** Refer to account slots by
  LABEL only (personal, work). Do not read or modify `~/.claude/settings.json`.
- Report `main...HEAD` (three dots), never `main..HEAD` — two dots renders every commit that landed
  on main after your branch point as a deletion, and that has produced two false alarms today.
- If the honest fix needs a live launch attempt against an account, do NOT perform repeated live
  attempts. One is a probe; several is credential abuse and trips fraud heuristics. Describe the
  probe, run it once at most, and say so.

LANE_WRITES: plugins/leadv2/scripts/leadv2-quota-read.py, plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh, plugins/leadv2/tests/test-claude-account-states.sh, plugins/leadv2/tests/test-401-is-not-a-dead-account.sh


---

## ADDENDUM 2026-09-08 — the fixture question, answered; and your predecessor's finding, kept

The first attempt at this mission ended its turn on a question instead of committing, and produced
zero work. **Do not do that.** If you hit a fork you cannot resolve, take the narrower of the two
paths, do it completely, and put the fork and your reasoning in the report. A lane that ends on a
question delivers nothing; a lane that chooses and argues delivers work plus the question.

### Keep this finding — it is the honest answer the mission asked for

Verbatim from the first attempt, and I agree with it:

> "The contradictory comments are present, but a stored access token does not itself prove
> launchability. The classifier currently has no signal that distinguishes an expired token from
> denied access to usage data."

That is the answer to «name the signal that distinguishes a genuinely dead credential», and the
answer is **there isn't one at classification time**. Build on that; do not re-derive it.

### The blocking fixture — I read it myself, and the framing was slightly off

`plugins/leadv2/tests/test-unmetered-account-not-penalised.sh` (47 lines). Line 26 is the whole
thing:

    'account_state': m.classify_account_state('team' if state=='unmetered' else 'pro', 401)

and line 39:

    assert penalty==(50 if state=='unknown' else 0), 'PENALTY_MISMATCH usable account charged %g'

So it drives exactly two cases: **(team, 401) → unmetered → 0** and **(pro, 401) → unknown → 50**.

The `pro` arm is not an obstacle to this mission. **It is the negative control this mission's own
control #2 demands** — the guard against widening the rule until everything is usable. It is the
same control that caught a widening during P1b. Do not weaken it to make your change pass.

Three consequences, and this is the ruling:

1. **`max` is not asserted anywhere in that file.** `subscription_type=max` + 401 currently falls
   through to the `else` and lands on `unknown`/50 — the `max_20x` symptom in the mission body —
   and no test pins it. So the founder's actual accounts can be fixed **without touching the pro
   assertion at all.**
2. **LANE_WRITES is expanded to include that fixture — to ADD a `max` case, not to weaken the `pro`
   case.** The file is in scope; the `pro` arm of it is not yours to relax.
3. **If your chosen fix necessarily changes pro+401 too** (for example a global shrink of
   `UNKNOWN_PROBE_PENALTY` rather than a classification change), then you have widened past the
   guard and you owe an explicit argument for retiring it — in the report, as a recommendation to
   me, not as a silent edit. Take the narrower fix in the same lane so work still lands.

### A thing worth weighing, which may be the real defect

`UNKNOWN_PROBE_PENALTY=50.0` against a cost matrix whose most expensive arm is opus at 9. A penalty
that exceeds the entire range is not a penalty, it is an exclusion wearing a penalty's clothes —
"unknown utilization" is currently indistinguishable from "forbidden". Whether the right answer is
a smaller number (unknown = expensive but reachable, so a dead credential gets tried once and the
existing lockout/standdown machinery parks it — which IS "the test is whether it can launch") or a
classification change is still yours to decide and defend. But note that `lib/leadv2-route-arbiter.sh:937`
already warns about pricing one fact twice; read it before you move the number.

### Also

- **Report file allowed:** you may write **one** report at `docs/audits/d1-401-launchability.md`.
  No new evidence directory — a write set that is all-`docs/` is refused as `undiffable_write_set`,
  and a lane-local dir is not needed when the close path already carries your report.
- **The `codebase-memory-mcp` graph tool is DOWN for everyone this session**, not denied to you by
  policy — it failed to connect at startup. Do not spend time on it; raw reads and
  `mcp__repowise__*` are the tools you have.

**Revised LANE_WRITES (supersedes the line at the bottom of this file):**

    plugins/leadv2/scripts/leadv2-quota-read.py,
    plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh,
    plugins/leadv2/tests/test-claude-account-states.sh,
    plugins/leadv2/tests/test-401-is-not-a-dead-account.sh,
    plugins/leadv2/tests/test-unmetered-account-not-penalised.sh,
    docs/audits/d1-401-launchability.md

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-c4717023" "<question>" \
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