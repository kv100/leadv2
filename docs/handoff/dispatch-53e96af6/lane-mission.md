# One plugin source, no project copies — design arm A (fable)

**Report only. Change no behaviour.** A second arm (astra, via codex) is designing the same
question independently and must not see your answer. Two independent reads is the point; if you
find yourself reasoning about what the other arm would say, stop and answer the question instead.

REPO: `~/Projects/leadv2`. Its `main` IS the live path — a locally-linked marketplace, so
committing to main is deploying. **Work from `~/Projects/leadv2`.**

---

## The founder's order, verbatim

> «Короче, вероятно что все оверрайды и тут, и в getmany-followup, и в m3 (эти активные только)
> устарели и не нужны или чё-то такое. По сути постоянно мы видим что в проектах разные копии
> плагина и это мешает. Давай сделаем так чтобы везде всё тянулось из репо плагина и работал
> чистый плагин и не было никогда вопроса — а где править, в репо проекта или плагина. Это тоже в
> список до WAVES. Пускай это тоже fable и astra спланируют! Я готов в это вложить много ресурса.»

The deliverable is a **design**: what the end state is, what has to move, in what order, and how
each step is proven and reversed. Not an implementation.

---

## Measured surface — 2026-09-08, by the lead. Verify it, do not assume it

The founder's framing says "different copies of the plugin in the projects". **The measurement
says otherwise, and this is the single most important input to your design.** The projects are
nearly clean; the mess is inside the plugin repo's own `.claude/`.

| tree | symlinks | real files | real files that SHADOW a plugin-owned script | of those, drifted |
|---|---|---|---|---|
| `persona-engine/.claude/scripts` | 616 | 48 | **0** | 0 |
| `getmany-followup-bot/.claude/scripts` | 318 | 13 | **0** | 0 |
| `respiro-ios/.claude/scripts` | 403 | 20 | **1** | 1 |
| **`leadv2/.claude/scripts`** | **14** | **386** | — (it *is* the shadow) | **265** |

`~/Projects/leadv2/.claude/scripts` is additionally **untracked in its entirety**:
`git ls-files | grep '^\.claude/scripts/'` returns 0. And `tests/run-all.sh:152` loads its
`run-core-offline.sh` as the gate's core runner — 496 lines against the tracked file's 1114, with
zero `SCOPE_SELECTION_REASON` and zero fail-open logic. That is filed P0 separately
(`GATE-RUNS-AN-UNTRACKED-HALF-SIZED-CORE-RUNNER-01`); do not fix it here, but your design must say
what happens to that directory, because the P0 fix and your end state have to agree.

Remaining surface, unmeasured beyond counts:

- `.claude/leadv2-overrides/` — 38 (persona-engine), 7 (respiro-ios), 8 (getmany) = 53 files. The
  founder's hypothesis is that they are stale and unneeded. **Test that hypothesis file by file**;
  do not accept or reject it wholesale.
- `.claude/agents/` — 10 real + 3 symlinks (pe), 15 + 3 (respiro), 9 + 0 (getmany).
- `.claude/hooks/` — 35 real + 6 symlinks (pe), 5 + 1 (respiro), 4 + 1 (getmany).
- `~/.claude/leadv2-shared/scripts` — 149 real files sitting where a canonical symlink belongs
  (the SessionStart hook reports this every session and has never been acted on).
- The active repos are **persona-engine, getmany-followup-bot, respiro-ios**. `m3-market` does not
  exist on this machine; the line naming it in `.claude/CLAUDE.md` is stale and your design should
  say so.

---

## What the design has to answer

1. **What is the end state, precisely?** "Everything pulls from the plugin repo" has at least three
   readings: every project file is a symlink into `plugins/leadv2/`; or projects hold nothing at
   all and the runtime resolves through `~/.claude/plugins/`; or a per-project layer survives but
   is declared, small, and machine-checkable. Pick one and defend it against the other two.

2. **What legitimately stays per-project?** Each repo has 13–48 genuinely repo-native scripts —
   deploy scripts, App-Store pollers, engine probes. Those are not plugin files and must not be
   swept up. Where is the boundary, and can a machine decide which side a new file is on? A rule a
   human has to adjudicate will rot the same way this did.

3. **Are the 53 override files stale?** For each one: is it read at runtime, by what, and does its
   content still differ from what the plugin now does by default? An override that merely restates
   the default is dead weight; an override that contradicts the plugin is a decision someone made
   and its rationale has to be recovered before it is deleted.

4. **How does the invariant hold after the cleanup?** The 2026-07-29 doctrine already says "never
   create a real copy of a plugin-owned file inside a project", and 265 copies exist inside the
   plugin repo anyway. A rule that is only prose has already failed once. What check enforces it,
   where does it run, and what does it cost on a normal edit?

5. **Order and reversibility.** Live lanes hold worktrees under `.claude/worktrees/` right now. A
   conversion that breaks a running lane is worse than the drift. Give the order, name what must
   be quiet before each step, and give each step a one-command rollback.

---

## Constraints

- **Report only.** No conversion, no deletion, no symlinking. Your diff is the report.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`. Never
  `git add -A` — enumerate paths.
- Do not touch `~/.claude/settings.json` or any permission file.
- Every count you state carries the command that produced it. Where you could not measure, write
  UNVERIFIED and say what would settle it. A confident number derived from one of two trees is
  exactly the failure mode that produced this task.
- Do not chase the P0 gate defect. Reference it; do not fix it.

Write to `docs/handoff/one-plugin-source-fable.md`.

LANE_WRITES: docs/handoff/one-plugin-source-fable.md

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-53e96af6" "<question>" \
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