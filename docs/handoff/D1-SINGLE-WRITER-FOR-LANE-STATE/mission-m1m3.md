# D1-HARDEN-THE-WRITER-M1M3-01 — steps M1, M2 and M3 only

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-lane-state.sh, plugins/leadv2/scripts/tests/test-lane-state-single-writer.sh, tests/run-all.sh, docs/handoff/D1-SINGLE-WRITER-FOR-LANE-STATE/

## Read this first

`docs/handoff/D1-SINGLE-WRITER-FOR-LANE-STATE/brief.md`, committed at `08c6f187`. It is the full
D1 design. **You implement only §M1, §M2 and §M3** — the three steps that harden the writer itself.
M4-M6 (adoption) are separate lanes and are out of scope; do not start them, do not prepare for
them, do not edit `leadv2-active-registry.sh`, `leadv2-helpers.sh` or `leadv2-lanes-snapshot.sh`.

The reason this ordering exists, in one line: the writer D1 is about to make authoritative for 75
mutating call sites currently carries all three defects D1 exists to kill, so adopting it unchanged
would spread them to 75 sites.

## Scope — the three changes, exactly as the brief specifies them

- **M1** — duplicate rows become an error in themselves. Replace the three
  `next((r for r in rows if ...))` selections at `:82`, `:109`, `:114` with a list comprehension
  plus an explicit arity check. New exit code **5 = duplicate_rows**, distinct from 2/3/4.
- **M2** — `lane_deregister` asserts post-state: `else: sys.exit(4)` for a missing row, and a
  re-read of its own row before releasing the flock, exiting **6 (postcondition_failed)** if
  `dead_at` is not set. Same treatment for `register`.
- **M3** — `_lv2_lane_state_root` (`:14-17`) fails closed instead of guessing.

## The five tests

Create `plugins/leadv2/scripts/tests/test-lane-state-single-writer.sh` with T1-T5 exactly as §M1,
§M2 and §M3 define them. Two of them have a specific trap written into their acceptance and you
must honour it:

- **T1** asserts that on a duplicate `lane_deregister` **both rows are still intact**. A partial
  tombstone is a failure, not a pass.
- **T5** asserts on the **filesystem** — that no `active.yaml` was created in the scratch repo —
  never on the return code. Asserting on rc is precisely the landmine this step exists to fix: a
  registry helper that missed its target has already returned success and removed nothing once.

## Negative controls — three, one per changed function body

Our standard, learned twice tonight: a green suite proves the suite runs, not that it bites. The
D3 merge shipped a half with zero assertions behind it, and its original defect could be restored
with the suite staying 19/0 green. So: **count changed function bodies, not controls.**

Use the real tool, never a hand-rolled sed:
`plugins/leadv2/scripts/leadv2-mutation-control.sh <suite> <file> '<sed>' docs/handoff/D1-SINGLE-WRITER-FOR-LANE-STATE`

Each mutation is applied **inside a function body**, never at file top level, and each must produce
`baseline_rc=0`, `mutated_rc=1` (tool exit 0). Exit 1 means the mutant survived and you are not
done; exit 2 means the control never applied — fix the anchor, never paper over it.

- **NC1** — inside the deregister body, restore `next(...)`-style single selection so a duplicate
  silently picks the first row. T1 must go red.
- **NC2** — inside the deregister body, remove the post-state re-read (or make it always succeed).
  T4 must go red.
- **NC3** — inside `_lv2_lane_state_root`, restore the unguarded `git rev-parse`-in-cwd fallback.
  T5 must go red.

Paste for each: the `baseline_rc`/`mutated_rc` pair and the literal red suite line.

## Registration — prove it, do not assert it

Register the new suite in `tests/run-all.sh` (append only — two other lanes merged registrations
into that file tonight and a lost row disappears silently), then prove selection:

```
LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
```

Make a **real edit** to `lib/leadv2-lane-state.sh` first — `touch` does not work, git does not see
it, and the proof comes back falsely empty. Revert and confirm the tree is clean.

## Pre-flight, before you change anything

`.claude/scripts/lib/leadv2-lane-state.sh` is an **untracked stale copy** of this same writer, still
hardcoding `cap >= 2`. Prove which file the live loader actually resolves before and after your
change. If your suite would pass against the stale copy, the suite is wrong.

## Constraints

- Do NOT touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — held by another session. M1 is
  precisely what makes its `:4555` release path correct **without** editing it. If you conclude it
  must be edited, stop and say so rather than editing it.
- Never `reset --hard`, `clean` or `stash` in this shared tree; never prune worktrees.
- Nothing goes into `tests/known-red-suites.txt`; no assertion is weakened to reach green.
- 12 of 14 P1 callers of these verbs are `|| true`; the other two call `register`, which returns 5
  only when a duplicate already exists — a lane that is already broken. Failing there is correct.
  Do not add compatibility shims to hide rc 5.
- Commit after each of M1, M2, M3 separately, and commit the suite the moment it is green — before
  running the controls.

## Report

Per step: the commit sha. Per control: exit code, `baseline_rc`/`mutated_rc`, the red line. Plus the
suite count before and after, and the `[SELECT]` line. Nothing else.
