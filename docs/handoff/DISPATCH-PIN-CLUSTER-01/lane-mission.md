# DISPATCH-PIN-CLUSTER-01 — implement four dispatcher fixes (Heavy)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`
All edits go there. Never `cd` to `/Users/kostiantyn.vlasenko/Projects/leadv2` and never edit
files under it. Never touch `/Users/kostiantyn.vlasenko/Projects/persona-engine`.

## Binding plan — read these three first, inside the lane

- `docs/handoff/DISPATCH-PIN-CLUSTER-01/context.yaml`  ← BINDING. decisions[] and off_limits[] are law.
- `docs/handoff/DISPATCH-PIN-CLUSTER-01/plan-architect.md`  ← exact file:line sites, diff sketches.
- `docs/handoff/DISPATCH-PIN-CLUSTER-01/concerns-critic.md` ← why the obvious fix is wrong.

They already exist in the lane (the dispatcher's own plan-delivery bug, D3, is one of the
things you are fixing — the plan was copied in by hand this once).

## What you are building

Five steps, in this order. Do not reorder: step 1 is a prerequisite for 2 and 3, and 3's
verdict is delivered through 2's choke point.

1. **Extract `plugins/leadv2/scripts/lib/leadv2-lane-guard.sh`.** Move `lv2_lane_dirty`
   (currently `_pc_lane_dirty`, `leadv2-dispatch-product-close.sh:1377-1385`),
   `_PC_PORCELAIN_EXCLUDE_RE`, `_pc_drop_bootstrap_dirt`, `lv2_lane_root_is_own_worktree`,
   and `_lv2_class_rank` (extracted from `leadv2_admission_class`). Pure move + `source`
   back from product-close. ZERO behaviour change — prove it: the existing suites that
   cover product-close must stay green with no edits.
2. **D2 — a dirty lane can never produce `landed`.** In `dispatch_ledger_write_terminal`
   (`leadv2-dispatch-ledger.sh:250`) — the single funnel all six success surfaces pass
   through — downgrade `landed` to the existing `pass_unlanded` terminal when the lane
   worktree is dirty, with `dirty_lane:` prefixed on the reason.
   **REQUIRED (do not skip):** bound the retry. `pass_unlanded` is retryable and routes
   into `advance-arm` (`product-close:1695`), which re-runs the same mission on the next
   arm while the reservation stays confirmed for `CONFIRMED_TTL=7200`. Carry a per-sig8
   attempt counter; after N dirty-lane downgrades the terminal becomes final (`refused`),
   not retryable. Without this the fix converts one silent failure into an arm-burning loop.
   Do NOT auto-commit. Both existing autocommitters are broken by construction and stay
   as-is: `leadv2-turncap-checkpoint-commit.sh:54` no-ops in every lane, and
   `pc_stop_gate_autocommit` stages only `_PC_SCOPE_WRITES_CSV` — that IS the 3-of-5 bug.
3. **D1 — containment verdict, NOT a write fence.** In `spawn_worker`
   (`leadv2-dispatch-code.sh:4590`), before the arm `case`, when `WORK_ROOT != PROJECT_ROOT`,
   record the main checkout's `git status --porcelain --untracked-files=all` into
   `docs/handoff/dispatch-<sig8>/main-dirt.base`. Add
   `lv2_lane_containment_violation <sig8> <work_root> <project_root>` to the lane-guard lib;
   call it from ONE site — the D2 choke point. On violation the terminal is
   `refused cause=wrote_outside_lane`, never `landed`.
   **REQUIRED:** the exclude-set is explicit and load-bearing: `docs/handoff/**`, the
   control-plane state dir, journals, the active registry, the event ledger, the question
   store, `.git` internals. Miss one and the guard refuses 100% of rounds — and specifically
   starves `_dispatch_evidence_exists` (`dispatch-code.sh:2720`), which reads
   `${PROJECT_ROOT}/docs/handoff/dispatch-<sig8>/`.
   Also export `LEADV2_WRITE_ROOT="${WORK_ROOT}"` next to `LEADV2_LANE_WORK_ROOT` (`:4516`)
   on every arm launch. The child-side guard that would consume it is OUT OF SCOPE.
4. **D3 — deliver the plan into the lane.** New `_deliver_plan_into_lane <sig8>
   <founder_task_id>` in `dispatch-code.sh`, called from `cmd_resolve` after
   `_resolve_pinned_placement` (`:6023`) and before any spawn. No-op when
   `WORK_ROOT == PROJECT_ROOT`. **COPY** `context.yaml`, `brief.md`, `plan-*.md` — never
   commit them: `docs/handoff` is already excluded from the writes grammar (`:3425`), and a
   force-commit lands them outside `LANE_WRITES` and PARKs the round as `unscopable_diff`
   (`:596-601`), i.e. it would turn BLOCKED into PARKED. On a resume where the lane copy
   differs, the main checkout wins. If the source `context.yaml` exists and the copy does
   not resolve under `WORK_ROOT`: emit `lane_plan_missing`, `_dl_note <sig8> refused
   plan_not_in_lane`, `exit 5`. Prepend ONE mission line naming the lane-local absolute
   plan path.
5. **D4 — class is a floor from the task record, never re-derived.** Root cause: `sig8 =
   sha256(normalised mission text)` (`compute_sig:1770`), so a short resume mission is a
   different key and misses the admission receipt entirely.
   (a) Write a second, task-keyed receipt `docs/handoff/<founder_task_id>/task-class.yaml`
   from `leadv2_admission_write_receipt` whenever `founder_task_id` is non-empty.
   (b) In `_admission_classify` (`dispatch-code.sh:3488-3543`), after the sig8-receipt miss
   and BEFORE invoking the judge, read the task receipt and treat its class as a FLOOR:
   `ADMISSION_CLASS=max(task_floor, mapped)`, `ADMISSION_SOURCE=task_record`. Reuse
   `_lv2_class_rank` from step 1 — do not write a second ordering.
   **REQUIRED, second demotion site:** `advance-arm` (`dispatch-code.sh:7345-7351`)
   `sed`-scrapes the class from the ledger row and DEFAULTS TO `Standard`. Fixing only
   `_admission_classify` leaves the chain-advance path still demoting. Both sites read the
   task record. Note the carrier already exists and is discarded at `:5977-5983` (reads
   `intake_cls` from the receipt, assigns only `sig`/`sig8`).
   A resume mission may ESCALATE a class, never demote it.

## Tests — a negative control per fix, and you RUN it

Four new suites. For each: name the mutation in the suite header, apply it INSIDE the
function body in a scratch worktree, show the suite goes red, revert, show it green.
A top-level insert that reddens everything is not a valid control.

| Fix | Mutation | Suite |
|---|---|---|
| D2 | delete the `landed`→`pass_unlanded` downgrade branch (keep the function) | `tests/test-dirty-lane-never-lands.sh` |
| D1 | `return 1` as the first statement of `lv2_lane_containment_violation` | `tests/test-lane-containment.sh` |
| D3 | replace `_deliver_plan_into_lane`'s `exit 5` refusal with `return 0` | `tests/test-plan-in-lane.sh` |
| D4 | make the task-receipt read return empty in `_admission_classify` | `tests/test-class-floor-survives-resume.sh` — a 40-line resume mission on a Heavy task record must resolve Heavy, not Light, on BOTH the classify path and the advance-arm path |

Also register each suite wherever the repo's suite map selects tests on a changed path — a
green suite CI never runs is worth nothing.

## Off-limits (from context.yaml, these are law)

- No write fence / path-prefix denial on the worker process. A lane's `.git` is a FILE
  pointing at the main checkout's object store, so a prefix fence blocks the lane's own
  commit; and the control plane is deliberately rooted at `PROJECT_ROOT`
  (`dispatch-code.sh:406-414`). `WORK_ROOT` also fails OPEN to `PROJECT_ROOT` at `:412-413`.
- No auto-commit of a dirty lane as the enforcement mechanism.
- No force-commit of `docs/handoff` into the lane branch.
- No second class-ordering ladder.
- No real copies of plugin files into a consuming repo. Fix once, here.

## Done means

`git -C <lane root> status --porcelain` is EMPTY — every change committed on the lane
branch. All four mutation runs shown red-then-green. Report the commit shas.
