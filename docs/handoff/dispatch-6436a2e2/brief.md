# DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01 — move the session registry out of lane worktrees

Repo: `~/Projects/leadv2` (shared plugin tree). Founder standing permission for this session is
recorded at `persona-engine/.claude/leadv2-overrides/extensions.md:748`
(`SHARED-TREE-STANDING-PERMISSION-01`); the scope approved is **this task, named below**. If you find
the work needs anything outside that scope — stop and ask, do not widen it yourself.

## The defect, measured (do not re-derive; DO re-measure before claiming a fix works)

Six of six lanes carrying `dod_fail check=runtime_state_in_diff` fail on the **same single path**:

    6  dod_fail check=runtime_state_in_diff paths=docs/LEAD_V2_STATE.md
    6  lanes carrying that verdict at all

`docs/LEAD_V2_STATE.md` is leadv2's own active-sessions registry. The DoD gate kills a lane for a
file the harness wrote **during that lane's own run** — `MONITORS-ARE-THE-SECOND-CONSUMER-…-01` died
30 s into a restart this way and will die identically on every restart.

Already ruled out, do not re-investigate: this is **not** an addressing bug. The lane worktree and
the main checkout hold two independent real files (inodes 483409307 vs 474018428, mode `100644`, not
symlinks) and **both** are dirty; `diff_root` resolves to the lane worktree when one exists
(`leadv2-dispatch-product-close.sh:2052-2057`) and did so here. The gate read the right tree; the
tree was genuinely dirty because the harness dirtied it.

## The chosen direction (founder's, not open for re-litigation)

**The harness writes the registry to the shared state root, not into lane worktrees.** The rejected
alternative — exempting harness-owned paths inside the gate — is symptom suppression: the harness
would keep dirtying lane worktrees and we would merely stop seeing it.

This is coherent with what the file already is: `leadv2-active-registry.sh:1152` **regenerates
`LEAD_V2_STATE.md` as a markdown index from `active.yaml`** — and `active.yaml` already lives in
`~/.claude/leadv2-state/leadv2/` with the rest of the control plane. The derived view should sit
beside its source.

## Task 1 — enumerate writers and readers BEFORE changing anything

Writer and readers move together or not at all. If the writer relocates and one reader keeps looking
at `docs/`, we get "fixed the write, broke the read", and we will discover it as silence, not as a
red gate. (Same shape already found today by `e9`: a journal writer follows the worker via
`git rev-parse --show-toplevel` while its reader stays at the session root.)

Starting census — **verify and extend it, do not trust it**; ~28 code files name the path:

- **Writers:** `leadv2-active-registry.sh` (path built at :117 from `LEADV2_PROJECT_ROOT`;
  auto-refresh on every register :962 and unregister :1012; regenerator at :1152) and
  `claude-subsession.sh:1008-1013` (marks `state=paused`).
- **Readers:** `leadv2-status-snapshot.sh:46-47`, `leadv2-priors-compile.sh:47,194-199`,
  `leadv2-agent-stats.sh:24,99`, `leadv2-rag-intake.sh:21,74`, `leadv2-backfill-history.sh:26`,
  `leadv2-negative-memory-compile.sh`, `leadv2-helpers.sh:45,148,202,946,1257,2383-2388`,
  `leadv2-lane-watch-v2.sh:160` (an explicit `-not -name 'LEAD_V2_STATE.md'` exclusion — it already
  knows this file is noise).
- **Existing seams to prefer over new ones:** `LEADV2_STATE_FILE` (`leadv2-backfill-history.sh:20`)
  and `LEADV2_LEAD_STATE_PATH` (`leadv2-helpers.sh:148,202`). Route the path through one derivation
  rather than editing ~28 call sites.

Deliverable: the list, writers and readers separated, each with file:line — in the report.

## Task 2 — decide the tracked copy explicitly

`docs/LEAD_V2_STATE.md` is tracked as mode `100644` in **both** `main` and `origin/main`, and is
**not** gitignored. Unlike `active.yaml` this morning, the two mains agree — so check both and say
so, rather than assuming from one. (That exact assumption produced a false blocker today: a "guard"
rested on "main does not carry the file", true of the local main and false of origin.)

State the decision in the commit body: untracked via `git rm --cached` + gitignore, replaced by a
pointer, or left as-is. Any of the three is defensible; **silently leaving it is not**, because the
next lane inherits whatever you choose.

## Acceptance — behavioural, with a negative control. A green run alone is NOT acceptance.

1. **The write moved.** Run a lane, let the harness do its bookkeeping, and show
   `docs/LEAD_V2_STATE.md` **does not appear** in the lane worktree.
2. **The read still works.** Show the registry updated in the shared root **and** that the surface
   which consumes it shows current data — a file in the right place that nobody reads is the same
   zero. Name the surface you checked.
3. **Negative control, mandatory.** Restore the write into a lane worktree and show
   `dod_fail check=runtime_state_in_diff` **comes back**. Without it, "the lane did not die" is
   indistinguishable from "the gate stopped checking" — a confusion this system has produced twice
   today already.
4. The six `dod-gate.md` counter must stop growing. Report it, but **do not treat it as proof**:
   absence of new deaths is silence, not measurement. Item 3 is the measurement.

## Constraints

- Commit separately, with the reasoning in the body — not "fix". One `git revert` must undo it.
- Do not touch `tests/known-red-suites.txt`; it may only shrink.
- Do not `git add -A` anywhere in this tree: the shared checkout carries other sessions'
  uncommitted files (`docs/leadv2/*`, foreign `docs/handoff/*/phases.d/*.yaml`). Stage by path.
- Do not run the core-offline suite while a lane is live inside its e2e gate.

## Addendum (lead, after dispatch) — the active-registry suite is part of YOUR acceptance

You are editing `leadv2-active-registry.sh`. Its own suite, `core:active registry phase updates`, is
currently the single unexpected red in CI (`ci-gate: known_red=13 unexpected=1`, run 33859056529).
This is not a scope extension: you touch the file, you run its suite, and you may not leave it red.

If it is still red after the registry relocation: **name the cause explicitly, and say whether it
predates your change.** Do not fix it blind, and do not silence it.

Two facts and one hypothesis — keep them apart:

- **Fact, from the run trace:** `bash: line 4: leadv2_active_register: command not found` — the
  function is absent from the suite subshell.
- **Fact:** `leadv2_active_register()` is defined **twice** — `leadv2-active-registry.sh:899` and
  `leadv2-helpers.sh:1441`. Which definition the suite gets, and whether it gets either, depends on
  what sourced what.
- **Hypothesis, NOT established:** `run-core-offline.sh` runs pooled suites through a branch that
  overrides `HOME` and serial ones through a plain call, so a suite moving between pools changes
  environment. Treat this as a lead to check, never as the answer.

Timing, for attribution: the suite did not fail in run 33853873478 (before the SERIAL markers were
restored) and failed in 33855398846 and 33859056529 (after). Two of two with the markers, zero of
one without — suggestive, not proof.

## Addendum 2 — do not trust an `e2e_regression` verdict without a main-baseline run

Measured by `persona-engine-3a` on 2026-09-04: a lane died with `e2e_regression`, and re-running the
two failing suites on a clean `main` **without that lane's commit** produced the same failures. The
gate can therefore report a regression for a red that predates you.

You are safe from the sharpest version of this — your worktree is a `leadv2` worktree
(`git-common-dir = ~/Projects/leadv2/.git`) and it carries `tests/known-red-suites.txt` with 15
entries. (`persona-engine` has no such file at all, so a lane closing there cannot distinguish an
inherited red from its own regression. Not your case; recorded so nobody re-derives it.)

**Still: if your close reports `e2e_regression`, re-run the named suites on `main` without your
commit before accepting the verdict, and say in the report which reds predate you.** A verdict is
not evidence.

## Addendum 3 — you are restarting a lane whose work already exists. Do NOT redo it.

A first attempt produced commit `1de50b2c fix(state): move LEAD_V2_STATE.md writes out of lane
worktrees` on branch `worktree-DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01` — 15 files, 155
insertions, 18 deletions. It moved the writer (`_leadv2_state_md()` in `leadv2-active-registry.sh`)
and ~12 readers onto one resolver, `leadv2-state-path.sh --no-link LEAD_V2_STATE.md`. That lane then
parked on `e2e_gate verdict=timeout rc=124 timeout_s=900` — a wall, not a verdict on the work — and
could not be resumed.

**Start from that commit. Review it, do not rewrite it.** Your job is the part it never reached:
the acceptance in the section above — the behavioural proof, the named reading surface, and the
mandatory negative control. If you find the commit wrong, say what and why; do not silently redo it.

**On the timeout, one measurement we still owe:** record how many suites `--scope changed` selected
for this 15-file change and how long the gate took. The standing hypothesis — unproven — is that 900
s is budgeted for a narrow change and a wide harness edit overruns it by construction, the same
widening that took the merge-queue selection to 86 suites this morning. Report the three numbers
(files changed, suites selected, seconds) or say plainly that you could not measure them.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-6436a2e2" "<question>" \
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