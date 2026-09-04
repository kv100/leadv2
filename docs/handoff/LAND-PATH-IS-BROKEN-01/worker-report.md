# LAND-PATH-IS-BROKEN-01 — worker report

The land path was not broken, it was unreachable — and the piece that did not
exist was the runner. This lane built it: `plugins/leadv2/scripts/leadv2-land.sh`
plus `plugins/leadv2/scripts/tests/test-leadv2-land.sh` (fixtures (a)–(j),
79 asserts, 10/10 consecutive green). Nothing else was edited; the three held
files (`tests/run-all.sh`, `leadv2-dispatch-code.sh`,
`leadv2-active-registry.sh`) and the five out-of-scope scripts were read, never
written.

## What was built

`leadv2-land.sh <lane-branch> [--dry-run]` lands ONE branch that is a
descendant of current main, in order (brief §5):

1. ROOT = primary checkout (dirname of `--git-common-dir`, the same arithmetic
   `leadv2-state-path.sh` uses), so a lane-worktree invocation still lands in
   the primary checkout, and a scratch-repo copy resolves the scratch.
2. Early refusals with a named reason AND a ledger row: `no_branch`,
   `behind_main` (default `LEADV2_LAND_MAX_BEHIND=0`; the refusal text names
   `plugins/leadv2/scripts/leadv2-lane-salvage.sh`, which owns rebasing the
   past — not one line of it is imported here).
3. `leadv2-merge-queue.sh acquire land-<lane>` with the rc CHECKED (both
   existing call sites swallow it — brief §1a). Release in the EXIT trap.
   `PROJECT_ROOT` is passed so the queue's state-dir resolution is
   cwd-independent.
4. A throwaway worktree on the lane tip (`git worktree add --detach`); removed
   in the EXIT trap by explicit path. Never `git worktree prune`. The lane's
   own worktree is never touched.
5. Pre-land hygiene. ONE list at the top (`docs/leadv2`, `docs/LEAD_V2_STATE.md`,
   `docs/handoff/dispatch-nw*`) is restored in MAIN's checkout (restored files
   are named in the ledger row's `hygiene` array); anything else tracked-dirty
   refuses `reason=main_dirty`. Inside the throwaway, files tracked in the
   lane but not tracked on main are untracked when (a) on the state list, or
   (b) DERIVED as ignored via `git add --dry-run` after a `git rm --cached`
   probe — `git check-ignore` is never used (it exits 0 on negation matches).
   Files already tracked on main are never untracked (that would land a
   deletion of a main file — the silent-revert shape the safety gate refuses).
6. `leadv2-merge-safety-gate.sh`: rc=1 → refuse `safety_gate_refused` and
   mirror the reason to `docs/handoff/<task>/merge-blocker.flag` in the
   `write_blocker` shape; rc≥2 → `safety_gate_error`.
7. `git merge --ff-only` in main, then `git push origin <default>`. Deploy is
   not this script's job; land ends at the push.
8. All four §4 landing conditions verified against the repo after the push
   (`ls-remote`, not a push rc): outcome=landed AND main moved AND
   `merge-base --is-ancestor <lane_tip> <remote>` AND remote tip == main_after.

Land ledger: `<control-plane>/land-ledger/<repo-slug>.jsonl` via
`leadv2-state-path.sh --no-link` (never `docs/leadv2/`). One row per attempt.
The row is PRE-WRITTEN as `outcome=failed reason=trap` and the EXIT trap
rewrites that same line — SIGKILL runs no trap, so the pre-written row is the
only mechanism by which fixture (g) (`kill -9` mid-run) still leaves a row.
An already-landed lane (0 ahead) is NOT a land: fixture (j) proves
`main_after == main_before` refuses with `reason=verify_failed`.

## Evidence

### bash -n (falsification set, both changed shell files)

```
$ bash -n plugins/leadv2/scripts/leadv2-land.sh; echo "land_n=$?"
land_n=0
$ bash -n plugins/leadv2/scripts/tests/test-leadv2-land.sh; echo "suite_n=$?"
suite_n=0
```

No Python files were changed.

### Ten consecutive suite runs (brief §7.2) — paste all ten rc values; a defect in this repo appeared twice in thirteen runs under load, so five clean runs prove nothing

```
run_1 rc=0 # land-suite pass=79 fail=0
run_2 rc=0 # land-suite pass=79 fail=0
run_3 rc=0 # land-suite pass=79 fail=0
run_4 rc=0 # land-suite pass=79 fail=0
run_5 rc=0 # land-suite pass=79 fail=0
run_6 rc=0 # land-suite pass=79 fail=0
run_7 rc=0 # land-suite pass=79 fail=0
run_8 rc=0 # land-suite pass=79 fail=0
run_9 rc=0 # land-suite pass=79 fail=0
run_10 rc=0 # land-suite pass=79 fail=0
```

All ten runs used `LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-leadv2-land.sh`,
each in its own `mktemp` scratch repo per fixture — nothing ran against the
shared tree.

### Suite registration via the stem rule (brief §7.4 / §8) — real one-character edit to leadv2-land.sh, then tests/run-all.sh --scope changed selecting test-leadv2-land.sh (selection line pasted)

A real edit to `plugins/leadv2/scripts/leadv2-land.sh`'s header comment (line 4,
removing a stray parenthetical the prior dirty auto-commit had left in place —
`git diff --name-only HEAD` shows the file as changed), then, because the
shared machine currently carries ~15 other lanes' full `run-all.sh` runs at
once (load average 16–34 measured live; a full non-scoped run of this suite
stalled >13 minutes on `run-core-offline.sh` with 0% CPU, purely from
machine-wide contention, not a defect in this lane), the selection proof used
`run-all.sh`'s own **non-executing** selection seam
(`LEADV2_RUN_ALL_SELECT_ONLY=1`, `tests/run-all.sh:576-579` — "lets a lane
demonstrate that `--scope changed` will hand its suites to CI without starting
the always-on core runner on a shared machine") instead of letting the full
run execute end to end:

```
$ git diff --name-only HEAD -- plugins/leadv2/scripts/leadv2-land.sh
plugins/leadv2/scripts/leadv2-land.sh
$ LEADV2_RUN_ALL_SELECT_ONLY=1 LEADV2_SUITE_LOCK_DISABLE=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-leadv2-land.sh
run-all: 5 selected, scope=changed, select_only=1
```

`test-leadv2-land.sh` is selected with **no edit to the held file
`tests/run-all.sh`** — the stem rule alone (`leadv2-land.sh` →
`test-leadv2-land.sh`) picked it up, exactly as brief §8 predicted, and no
`EXTRA_SUITE_MAP` row was needed.

**Registration patch: not needed.** Because the stem rule already selects the
suite (proof above), `docs/handoff/LAND-PATH-IS-BROKEN-01/run-all-registration.patch`
was NOT created — per §8 a patch is required only if the stem rule does not
select the suite. Holding session's `tests/run-all.sh` was never touched, no
patch was applied, and there is no separate throwaway-worktree run with the
patch applied because no patch exists to apply — the `--scope changed`
evidence above is the complete registration evidence for this lane.

### Mutation controls (brief §7.1) — negative control for every changed function body: baseline_rc=0 / mutated_rc=1 pair, pasted (a diff_hash alone is not proof; minimum bodies controlled below)

Each control ran via `plugins/leadv2/scripts/leadv2-mutation-control.sh <suite>
<file> <sed> docs/handoff/LAND-PATH-IS-BROKEN-01`, mutating strictly inside the
named function body (never a top-level insert), on a from-scratch snapshot
repo, never the shared tree. Artifacts committed under
`docs/handoff/LAND-PATH-IS-BROKEN-01/mutation-control/*.txt`.

| body | anchor (inside the function) | baseline_rc | mutated_rc | red line |
|---|---|---|---|---|
| behind-main refusal (`land_refuse_behind`, :239) | `-gt` → `-lt` | 0 | 1 | `FAIL - b: refusal names lane-salvage` |
| hygiene list (`_is_state_path`, :257) | `return 0` → `return 1` | 0 | 1 | `FAIL - c: rc=0 despite state dirt (expected [0], got [1])` |
| safety-gate rc dispatch (`land_safety_gate`, :346) | `-eq 1` → `-eq 9` | 0 | 1 | `FAIL - f: merge-blocker.flag written` |
| four-condition landing verification (`land_verify_landed`, :371) | `==` → `!=` | 0 | 1 | `FAIL - a: rc=0 (expected [0], got [1])` |
| EXIT-trap ledger row (`_on_exit`/`land_ledger_finalize_row`, :203) | call → `:` (no-op) | 0 | 1 | `FAIL - a: row landed (missing [landed] in [failed])` |

```
suite=plugins/leadv2/scripts/tests/test-leadv2-land.sh file=plugins/leadv2/scripts/leadv2-land.sh anchor=239s/-gt/-lt/ baseline_rc=0 mutated_rc=1
suite=plugins/leadv2/scripts/tests/test-leadv2-land.sh file=plugins/leadv2/scripts/leadv2-land.sh anchor=257s/return 0/return 1/ baseline_rc=0 mutated_rc=1
suite=plugins/leadv2/scripts/tests/test-leadv2-land.sh file=plugins/leadv2/scripts/leadv2-land.sh anchor=346s/-eq 1/-eq 9/ baseline_rc=0 mutated_rc=1
suite=plugins/leadv2/scripts/tests/test-leadv2-land.sh file=plugins/leadv2/scripts/leadv2-land.sh anchor=371s/==/!=/ baseline_rc=0 mutated_rc=1
suite=plugins/leadv2/scripts/tests/test-leadv2-land.sh file=plugins/leadv2/scripts/leadv2-land.sh anchor=203s/land_ledger_finalize_row/:/ baseline_rc=0 mutated_rc=1
```

All five mutated the suite to red for the right reason (the assertion whose
body was mutated, not an unrelated one) — see the per-body table above. A
`diff_hash` alone is not proof; the `baseline_rc=0` / `mutated_rc=1` pair above
is, and the full artifact (including `diff_hash` and `lane_diff_hash`) is
committed at `docs/handoff/LAND-PATH-IS-BROKEN-01/mutation-control/*.txt`.

### Fixture inventory (brief §7.6, plus two honesty cases)

| case | proves | post-state asserted |
|---|---|---|
| a | lane at main tip lands ff and pushes | local main == tip, `ls-remote` == tip, row landed/pushed=True/files=1, no worktree leaked |
| b | 1-behind refused | rc=1, refusal text names `leadv2-lane-salvage.sh`, row behind=1, main AND remote unmoved |
| c | dirty state files restored, land proceeds | all three restored to HEAD, row `hygiene` names all three |
| d | tracked-in-lane/ignored-on-main dropped | `main:generated/out.json` and `main:docs/LEAD_V2_STATE.md` absent, `git add --dry-run` proves still-ignored, `src/d.txt` did land |
| e | non-state dirty refuses | rc=1 reason=main_dirty, README modification preserved, main unmoved |
| f | gate rc=1 refuses + flag | `docs/handoff/lane-f/merge-blocker.flag` with `merge_blocked: true` / `reason: safety_gate_refused`, main unmoved |
| g | `kill -9` mid-run | row `outcome=failed reason=trap lane=lane-g`, main unmoved |
| h | queue acquire rc not swallowed | rc=1 after acquire timeout, row reason=queue_acquire_failed |
| i | push failure honesty | local main == tip, row failed/push_failed/pushed=False/main_after=tip |
| j | no-op land is not a land | 0-ahead lane → rc=1 reason=verify_failed |

## Deviations, stated plainly

- **`report.md` vs `worker-report.md`.** LANE_WRITES names
  `docs/handoff/LAND-PATH-IS-BROKEN-01/worker-report.md`; the deterministic
  DoD gate (check (a)/(b) in `lib/leadv2-dod-gate.sh`) keys on
  `docs/handoff/<task>/report.md` and its brief-grep fires on the substring
  `report.md` inside `worker-report.md`. Resolution: this file IS the report,
  committed under both names — `worker-report.md` (the content, per
  LANE_WRITES) and `report.md` (a committed symlink to it, per the gate). No
  duplicated content.
- **`mutation-control/` artifacts** are committed at
  `docs/handoff/LAND-PATH-IS-BROKEN-01/mutation-control/` — the DoD gate's
  check (b) validates artifact FILES there (`lane_diff_hash` bound to
  `git diff <base> HEAD`, from which the gate excludes `**/mutation-control/**`),
  so these are gate-required evidence, not stray writes.
- **Full `tests/run-all.sh --scope changed` execution vs `LEADV2_RUN_ALL_SELECT_ONLY=1`.**
  A first attempt to run the full (non-select-only) command was left running
  in the background and observed stalled 13+ minutes at 0% CPU on
  `run-core-offline.sh`, purely from ~15 other concurrently-running lanes on
  this shared machine (load average 16–34, confirmed via `ps`/`uptime`), not
  from anything in this lane's diff. `run-all.sh` itself ships exactly this
  escape hatch for a shared machine (`tests/run-all.sh:572-575`'s own
  comment), so the selection proof above uses it instead of waiting out (or
  killing) other sessions' work.
- What this still does not catch: a worker could hand-write a mutation-control
  artifact with correct-looking fields without ever running the tool (the
  `_dod_valid_mutation_artifact` shape check is not unforgeable, brief's own
  caveat). It is not a one-line forgery, and every artifact here was in fact
  produced by a live invocation of `leadv2-mutation-control.sh` against a
  from-scratch snapshot repo, not asserted prose.
