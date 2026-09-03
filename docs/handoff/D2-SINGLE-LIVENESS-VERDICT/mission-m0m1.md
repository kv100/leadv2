# D2-UNBLIND-AND-THIRD-STATE-M0M1-01 — steps M0 and M1 only

LANE_WRITES: .gitignore, plugins/leadv2/scripts/leadv2-lane-liveness.sh, plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, docs/handoff/D2-SINGLE-LIVENESS-VERDICT/

## Read this first

`docs/handoff/D2-SINGLE-LIVENESS-VERDICT/brief.md`, committed at `78116834`. It is the full D2
design. **You implement only M0 and M1** — rows M0 and M1 of its migration table. M2-M6 are later
lanes: do not start them, do not prepare for them, and do not edit any consumer.

The one-line reason this ordering exists, from the brief: M1 replaces a wrong *terminal* verdict
with a safe *non-terminal* one, so the incident stops there with **zero consumer edits**.

## The incident this closes

Five workers were declared dead, four re-dispatches were issued, and each destroyed the evidence of
the one before it. Nobody had died. Every worker had finished and written its report to
`docs/handoff/dispatch-<sig>/developer.full.md` — a path hidden by `.gitignore:49`. The lead saw
`git log` show zero commits and read that as death.

The census in the brief makes it worse than a single oversight: **281 `*.full.md` exist on disk, 97
are tracked, 184 are invisible — and the 97 are tracked only because they predate the ignore rule.**
The reports are ignored *at random*. That is why it went unnoticed for so long.

## M0 — unblind the deliverable

Allowlist `*.full.md` and `*.summary.md` in `.gitignore`. No code path reads `.gitignore`, so this
lands alone and first, and it is a two-line revert.

**Proof — and the trap is specific.** `git check-ignore` exits **0** on a *negation* match too, so
`check-ignore && echo ignored` reports an allowlisted path as ignored. The brief's author hit this
on the brief file itself. Use instead, both of them:

```
git add --dry-run docs/handoff/<any>/developer.full.md      # prints add '...', not "ignored by ..."
git status --porcelain -uall docs/handoff | grep -c 'full\.md'   # > 0
```

## M1 — the third state

Add rung **E4** (the deliverable) to `leadv2-lane-liveness.sh`, and emit
`finished_unlanded:<age>s` **before** `dead:no_log_artifact` can be reached.

Two constraints from the brief that are not negotiable:

- `finished_unlanded:` is a **sibling of `finished:`**, so any future consumer matches `finished*)`.
  Do not invent a shape that breaks that prefix.
- **Rename nothing.** `alive`, `starting:*`, `silent:*`, `dead:*` and `child` are matched as literals
  by the merged reap funnel at `leadv2-dispatch-ledger.sh:981`, `:1380`, `:1409`. A rename is a
  silent break there, and that funnel is the thing that rescues unlanded work.

Consumers have no `finished*` arm yet, so these lanes fall into `*)` — "indeterminate, write
nothing". That is deliberate and is strictly safer than today's `no_work`.

## The suite

Create `plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh` covering, at minimum:

- a lane with a deliverable and no commits reports `finished_unlanded:*`, **never** `dead:*`;
- the mirror — a lane with neither commits nor deliverable still reports `dead:*`, so the third
  state was not achieved by never reporting dead at all;
- an unreadable/absent registry reports `unknown:*`, never coerced to dead.

**Register the suite in `plugins/leadv2/scripts/tests/run-core-offline.sh`, NOT in
`tests/run-all.sh`.** `tests/run-all.sh` is currently held by a concurrent lane and has collapsed
under three-way collisions four times tonight; `run-core-offline.sh` is a legitimate registration
point (`test-claude-account-check.sh` registered there this evening). Append only.

Prove registration by running `run-core-offline.sh`'s own plan dump rather than asserting it:

```
LEADV2_SUITE_SHARDS_DUMP=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh
```

and paste the line naming your suite.

## Negative controls — count changed function bodies, not lanes

That is this repo's standard, learned the expensive way: a merge this week shipped a half whose
original defect could be restored with the suite staying green. Use the real tool, never a
hand-rolled sed:

```
bash plugins/leadv2/scripts/leadv2-mutation-control.sh <suite> <file> '<sed>' docs/handoff/D2-SINGLE-LIVENESS-VERDICT
```

Each mutation goes **inside a function body**, never at file top level, and must yield
`baseline_rc=0`, `mutated_rc=1` (tool exit 0). Exit 1 = the mutant survived, you are not done;
exit 2 = the control never applied, fix the anchor rather than papering over it.

One control is mandatory: **make rung E4 not look at the deliverable**, and show the lane goes back
to reporting `dead:*`. That is the whole defect; without an assertion catching its return, nothing
is proven.

Fixtures must assert the **filesystem post-state**, never a return code, and must verify their own
setup — a load-sensitive `git commit` inside `( … )` with its status discarded produced a false red
in this repo tonight.

## Constraints

- Do NOT touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` or
  `plugins/leadv2/scripts/leadv2-active-registry.sh` — both held by another session.
- Do NOT touch `tests/run-all.sh` — held by another session; that is why registration goes to
  `run-core-offline.sh`.
- Do NOT edit any consumer of the liveness verdict. M1's whole point is zero consumer edits.
- Never `reset --hard`, `clean` or `stash` in this shared tree; never prune worktrees.
- Nothing goes into `tests/known-red-suites.txt`; no assertion is weakened.
- Commit M0 alone and first, then the suite the moment it is green, then M1.

## Report

Per step: the commit sha. For M0: both proof command outputs. For M1: the suite count, the plan-dump
line naming your suite, and the control's exit code with its `baseline_rc`/`mutated_rc` pair and the
literal red line. Nothing else.
