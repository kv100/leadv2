# The launch registry says GLM cannot launch. GLM has been launching all day.

**Row A3 of `PRE-WAVES-PLAN.md`** — «every Anthropic and Codex model launchable as itself»,
one of the founder's six gate rows. Its remaining half was believed to be D1 (a 401 priced
as a dead account); D1 merged as `39db77c2` and this is what is left underneath.

REPO: `~/Projects/leadv2`. Its `main` IS the live path — symlink deploy, so a fix not
committed to main is not delivered. **Dispatch and work from `~/Projects/leadv2`.**

---

## The contradiction, measured by the lead 2026-09-08

`plugins/leadv2/scripts/lib/leadv2-launch-registry.py --kind <k> --role <r> --arm <a>
--task-class Standard --json`, run against the live tree:

| kind | role | arm | answer |
|---|---|---|---|
| code | worker | sonnet | `ok: true`, model `sonnet` |
| code | worker | codex | `ok: true`, model `gpt-6-astra` |
| review | reviewer | opus | `ok: true` |
| review | reviewer | fable | `ok: true` |
| plan | planner | fable | `ok: true` |
| code | worker | **glm** | **`ok: false, reason: adapter_argv_not_registered`** |
| review | reviewer | **glm** | **`ok: false, reason: adapter_argv_not_registered`** |
| code | worker | **freepool** | **`ok: false, reason: adapter_argv_not_registered`** |

And yet, on the same machine, the same day:

- `CODEX-ALWAYS-UP` was built by GLM — journal line `product_close … author=glm`, and the
  lane produced 4 files and 323 insertions which are now merged as `15005732`.
- `RECON-5H-WINDOW` was built by GLM — `author=glm`, and it wrote a 21KB report.
- B2's journal shows GLM chosen as the **reviewer**:
  `route_resolved by=arbiter role=reviewer arm=glm task=56eab6cc reason=cheapest_capable`.

So one component answers "this arm cannot be launched" while the dispatcher launches it
several times an hour. **At most one of those two is right, and today nobody knows which.**

`opus` and `haiku` answer `not_a_build_arm` for `kind=code` — that one looks deliberate
(they are not build arms) and is probably NOT part of this defect. Confirm or refute it;
do not assume it either way.

## What to establish, before proposing anything

1. **Does the dispatcher consult this registry for GLM at all?** Find the call sites. If
   GLM reaches its worker through a different adapter path (`glm-coder.sh` and friends)
   that never asks the registry, then the registry is not lying to the dispatcher — it is
   simply not the authority for that arm. Say which it is, with the call site.
2. **Who else asks it?** The review pool is the one that matters: row B3 was literally
   "review pool marks launchable arms unknown and kills the lane" (merged `fe491bff`).
   If the pool consults this registry, a `cheapest_capable` arbiter pick of GLM as reviewer
   meets a registry that says GLM cannot launch — establish what happens at that seam, and
   whether it is what killed any lane we have already seen.
3. **Is `adapter_argv_not_registered` a missing entry or a deliberate exclusion?** Read the
   data the registry loads. A missing row and a policy exclusion look identical from the
   outside and have opposite fixes.

## What the fix has to achieve

**One answer to "can this arm launch", and every caller gets the same one.** Either the
registry becomes authoritative for GLM/freepool too (their adapters registered), or it
declares its own scope explicitly and refuses questions outside it — `not_my_arm` is an
honest answer; `ok: false` for an arm that demonstrably runs is not.

Do not "fix" this by registering a fake argv that nothing executes. A registry entry that
does not correspond to a real launch path is the lying-green disease in registry form.

## Negative controls (E2E-KILLRATE-01, non-negotiable — two, both run, red then green)

1. **The symptom.** Assert on the registry's **answer value** for GLM in both `code/worker`
   and `review/reviewer`, and assert it agrees with what the dispatcher actually does. Then
   mutate your change back to the old answer inside the function body and show the suite
   goes red.
2. **The guard.** An arm that genuinely has no launch path must still answer "no". Invent a
   nonexistent arm and assert the registry refuses it; then mutate your fix so that every
   arm answers `ok: true` and show the suite goes red — otherwise the fix is a registry
   that approves everything, which is worse than the bug.

Insert every mutation **inside the function body**, never at top level: a top-level insert
reddens everything for the wrong reason and reads as a pass. That mistake has already
invalidated one measurement in this repo.

Register your suite with a `# run-all-triggers: <stem>` header and prove selection with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh` printing your `<stem>:<suite>` row.
Do not use `--scope changed` as the selection oracle — it is stateful and lies three ways.

## Constraints

- Do not merge. Report, and the lead verifies and merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`.
  Never `git add -A` — enumerate paths.
- Report `main...HEAD` (three dots), never `main..HEAD`.
- If your conclusion is that there is no defect — that the registry is Claude/Codex-scoped
  by design and every caller already knows that — say so plainly and show the call sites
  that prove it. A well-evidenced "no bug here" closes a gate row just as well as a fix,
  and is worth more than a change that papers over a misunderstanding.

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-launch-registry.py, plugins/leadv2/tests/test-launch-registry-answers-for-every-arm.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-553c1244" "<question>" \
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