P1b — LAUNCH-WHAT-THE-ARBITER-ACTUALLY-CHOSE-01. The arbiter's verdict is already correct; the
launcher throws it away. This is the wiring P1a (`b761089d`) was built for, and it closes founder gate
row 3 outright and is the precondition for rows 2 and 5.

REPO: ~/Projects/leadv2. Gate table with all six rows and their measured status:
`~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/GATE-EVIDENCE.md`.

## HARD PRECONDITION — do not start until this is true

Lane `13581c3eb064` (P2, commit `4e15098b`) must be merged into `main` first. It rewrites
`lib/leadv2-route-arbiter.sh` and `config/leadv2-routing.yaml` under your feet otherwise. Check with
`git branch --merged main | grep worktree-13581c3eb064`. If it is not merged, STOP and say so — do not
rebase around it and do not re-implement its parts.

P2 already did two things this mission used to claim, so **do not redo them**: it replaced
`dispatch: false` with a per-cell `pool_default` (haiku `true`, opus `false`) and it rebuilt the
exclusion logic as an ordered, typed stage list. Its own note is worth reading before you touch the
arbiter: *"opus/fable at ZERO of 73 live decisions was reachability, not economics."*

## Three changes, in this order

### 1. `leadv2-dispatch-code.sh:6251` — stop launching sonnet no matter what was chosen

    local -a _sonnet_profile_args=()
    ...
    out="$(cd "${WORK_ROOT}" && ... bash "${SUBSESSION_BIN}" \
           --role developer --model sonnet \
           --task-id "dispatch-${sig8}" ... )"

`--model sonnet` is a literal. It is one of only two `--model` sites in the file (the other, `:5344`,
reads `LEADV2_DISPATCH_ARCHITECT_MODEL` — also never the arm). So an arbiter verdict of `arm=fable`,
`arm=haiku` or `arm=opus` on a worker role **launches sonnet while the journal says otherwise**: the
telemetry line is truthful about the decision and silent about the launch. Note the surrounding
variables are literally named `_sonnet_profile_args` / `_sonnet_effort_args` — rename them too, or the
next reader will assume the arm is still hardcoded.

Replace with a lookup through `lib/leadv2-launch-registry.py` (landed `b761089d`; read it first — it
already defines `(kind, role, arm, task_class) -> argv`, a `check(arm, model)` refusal helper, and
per-arm argv builders). Lane `cd486551a5cb` (`fe55a781`) added the codex tuples; if it is merged, its
entries are there too.

**The registry narrows; it must never widen.** Every kind/trust restriction the matrix imposes stays.
A registry miss must be a loud refusal on the existing `spawn_failed`/`refused` path — never a silent
fallback to sonnet, which would reproduce today's bug with extra steps.

### 2. `leadv2-dispatch-code.sh:8386-8417` — the pre-arbiter opus park

    if [[ "${arm}" == "opus" ]]; then
      atomic_dispatch_reserve_confirm_opus ...   # reserved, never spawned

P2's `pool_default: false` keeps opus out of the **default auction**, which is the right economics
(opus shares the lead's own account window; lead starvation is worse than any routing gain). This park
is a *different* gate: it fires even when a caller explicitly asks for opus via `--pin-arm` /
`--arm-pool`, so the escape hatch P2 documented does not actually work. Remove the park and let the
pool decide. Keep the reserve/dedup semantics for whatever path still needs them — read
`atomic_dispatch_reserve_confirm_opus` before deleting anything.

### 3. `lib/leadv2-route-arbiter.sh` — stop punishing an account we simply cannot meter

Both Claude accounts answer `http 401` on the usage endpoint, so `util('claude')` is `unknown`, so
`UNKNOWN_PROBE_PENALTY=50` lands on **every** claude cell (`:311, :340-347, :829, :887`). But the 401
on the `work` slot is the **team-account** usage endpoint, not a dead credential —
`leadv2-claude-account-check.sh` reports `VERDICT: TWO_BUCKETS accounts=2`. A 401 from a usage endpoint
is never by itself proof that a token is dead.

P1a already shipped the producer side: `classify_account_state` distinguishes *unmetered* (usable,
unmeterable) from *unknown* (genuinely unclassifiable). Consume it here. An `unmetered` account must be
priced conservatively from its configured allowance, **not** hit with the unknown penalty. `unknown`
keeps the penalty — the distinction is the whole point, and collapsing the two states back together is
the failure mode to guard against.

## Acceptance
acceptance:
  surface: log_line
  observable: A live dispatch whose arbiter verdict is a non-sonnet claude arm launches THAT arm.
    Prove it with two lines from the same task id: the `model_select_telemetry … arm=<X>` decision and
    the launcher's own resolved-model line showing `<X>`, for at least one arm that is not sonnet.
    Additionally: with the `work` slot's usage endpoint answering 401, a claude arm must be able to WIN
    an auction — show the winning `route_resolved` line. Today that is impossible for every claude arm,
    so a single such line is the proof.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the launch function body, restore the literal `--model sonnet`. The suite must go red **on
   the argv actually passed to the subsession binary** — not on a journal line, and not on the
   arbiter's verdict, which was already correct before this mission and stays correct after it. This is
   the control that matters: today's bug is invisible to anything that reads the decision instead of
   the launch.
2. Inside `classify_account_state`'s consumer, map `unmetered` back onto `unknown`. The suite must go
   red on the resulting **penalty value**, showing 50 applied to a usable account.
3. Inside the pool logic, restore the unconditional opus park. The suite must go red on an explicit
   `--pin-arm opus` failing to reach a spawn.
Insert each mutation INSIDE the function body, never at top level — a top-level insert makes every
suite red for the wrong reason and reads as a pass. Self-register each suite with
`# run-all-triggers: leadv2-dispatch-code leadv2-route-arbiter` and verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`; do NOT edit `tests/run-all.sh`.

## Constraints
- Do NOT touch `codex-task.sh` or `lib/leadv2-launch-registry.py` — read them freely. If the registry
  needs a new tuple, STOP and report which one and why; that is 1b part B's file, not yours.
- Do NOT print, commit, or quote `~/.claude/state/leadv2/claude-profiles.tsv`. Refer to account slots
  by LABEL only (personal, work). Do not read or modify `~/.claude/settings.json`.
- Never `git add -A`. **Trap verified by experiment: `git commit -- <path>` commits the WORKING TREE
  for that path, not the index** — in a dirty repo it silently sweeps in other people's uncommitted
  edits to the same file. Stage explicitly, check `git diff --cached --stat`, then commit WITHOUT a
  pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact: an argv, a penalty value, a `route_resolved` line. Say
  "unverified" out loud; never say "should work".

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh, plugins/leadv2/tests/test-launch-uses-the-chosen-arm.sh, plugins/leadv2/tests/test-unmetered-account-not-penalised.sh, plugins/leadv2/tests/test-arm-pool-reachability.sh, plugins/leadv2/scripts/lib/leadv2-launch-registry.py

## RE-DISPATCH 2026-09-08T05:0xZ — the precondition is satisfied

An earlier attempt at this mission refused itself and wrote, correctly:
`dispatch-735574f4: BLOCKED — precondition lane 13581c3eb064 (4e15098b) not merged into main`.
That lane (P2, `POOL-IS-COMPUTED-AFTER-THE-ARM-IS-CHOSEN-01`) is now merged as `4adf985f`, and the
four suites around it are green on main from one run: 21/0, 9/0, 12/0, 2/0. Its arbiter change is
the thing you build on — eligibility is now an ordered typed stage list
(`not_in_pool | not_launchable | untrusted | capped | failure_memory | price_ratio`) and the pin is
parsed before the pool is built. Two facts about it you must not re-litigate here: opus carries
`pool_default: false` (out of the default auction, reachable by pin or explicit pool), and
`launchable_arms` is a STUB over the `DISPATCHABLE_*_ARMS` sets until `ARMS-CANNOT-LAUNCH-THEMSELVES-01`
lands the real registry — do not fork a second registry.

Proceed with the mission above. If you find a DIFFERENT unmet precondition, stop and name it
rather than working around it.

---

## Scope question ANSWERED by the lead 2026-09-08T09:2xZ — read this before you start

The previous attempt (lane `e9eee486`, codex) did exactly the right thing: it found that this
mission's write-set was too narrow to do the work, asked, and stopped without touching anything.
It could not reach the ask-helper because that helper's state dir is outside its sandbox write
access — that is a separate defect, not your problem. Here are the answers, so you do not have to
ask again:

1. **Yes — wire the existing Python registry into P2's launchability seam.** That IS the work.
   P1a landed `lib/leadv2-launch-registry.py`; P2's seam loads a `.sh` registry that does not
   exist, so the seam currently answers "nothing is launchable" for every non-sonnet arm and the
   dispatcher falls back to its hardcoded `--role developer --model sonnet`. Wiring those two
   together is the whole point of P1b.
2. **Yes — update `test-arm-pool-reachability.sh`, and it is now IN your write-set.** Its current
   assertion (non-sonnet arms must be REFUSED) is the bug written down as an expectation. Invert it
   with care: after your change a CAPABLE non-sonnet arm must be LAUNCHED AS ITSELF, and the suite
   must still keep at least one case proving a genuinely INCAPABLE arm is still refused. Deleting
   the refusal case to make the file green is the failure mode here — an arbiter that launches
   everything is not better than one that launches nothing.
3. **Yes — commit your report and mutation artifacts** under `docs/handoff/dispatch-<your lane>/`.

## What the previous attempt also exposed (not your work, but do not be surprised by it)

That lane produced ZERO commits, and the pipeline still reported `selfcheck status=green` and
reviewed a 202 KB diff — the review was measuring an old base (`a3ac0067`), i.e. main's own recent
merges, not the lane's work. Then the close gate timed out because a lane with no relevant changes
selects ALL 95 suites (`changed=0 unmapped=0 reason=no_relevant_changed_files -> selected=95`).
Three separate defects, all filed. None of them means your work is expected to be empty.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-c0840827" "<question>" \
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