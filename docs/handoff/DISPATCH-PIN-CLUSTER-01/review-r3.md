status: fail
reviewer_says: do_not_merge

# DISPATCH-PIN-CLUSTER-01 — adversarial review, round 3

Reviewed: lane `.claude/worktrees/DISPATCH-PIN-CLUSTER-01`, HEAD `ef90ce2`, 6 commits over `main`.
Everything below was executed, not read, unless the row says "read". Mutations were applied to a
scratch copy and reverted; `plugins/` in the lane was never modified.

## Original defects

| # | Defect | Verdict | Evidence |
|---|---|---|---|
| A | writes-outside-lane | **PARTIAL** | ran. `lv2_lane_containment_violation` exists and is reached from `dispatch_ledger_write_terminal:262`; my mutation **M2** (drop the write-set narrowing) turns `test-lane-containment.sh` RED, revert GREEN. But it only accuses paths inside the lane's *declared* write set, never journals the unattributed case (M3), and compares a spawn-time baseline against close-time porcelain hours later (M2). Plus **C1**: this cluster itself committed 15 out-of-lane residue files into the plugin repo. |
| B | commit-not-an-obligation | **PARTIAL** | ran. The terminal funnel is real: mutation **M3** (`elif false`) turns `test-dirty-lane-never-lands.sh` RED, revert GREEN. But it fails OPEN under bash 3.2 (**H4**, reproduced) and the close gate runs a shadowed copy of the filter (**H3**, reproduced). Also: the round-3 worker again died without committing; the lead committed by hand. |
| C | plan-not-in-lane | **PARTIAL** | ran. The round-2 Critical is genuinely fixed: mutation **M1** (move `_deliver_plan_into_lane` above the ensure block) drives `test-lane-placement-pin.sh` to `passed=25 failed=2`; revert restores `passed=27 failed=0`. But `plan-*.md` is never delivered (**H2**, reproduced) and a lane with an empty `founder_task_id` gets no plan and no journal line (**H1**, reproduced). |
| D | class-from-mission-length | **PARTIAL** | ran. `_lv2_class_canonical` closes the live `--task-class standard -> light` hole and the monotonic writer is mutation-killed by the suite's own control. But the floor is bypassed on same-digest resume (**H5**) and `test-class-floor-survives-resume.sh` never executes `_admission_classify` — it tests the library, not the resume flow it is named for. |

---

## Critical

### C1 — `ef90ce2` commits 15 control-plane residue files, 9 of them absolute-path symlinks, into the shared plugin repo

`plugins/leadv2/scripts/docs/leadv2/*` (14 paths) and `plugins/leadv2/scripts/.claude/commands/leadv2.md`:

```
plugins/leadv2/scripts/docs/leadv2/active.yaml    -> /Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/active.yaml
plugins/leadv2/scripts/docs/leadv2/bus.jsonl      -> /Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/bus.jsonl
plugins/leadv2/scripts/.claude/commands/leadv2.md -> /Users/kostiantyn.vlasenko/.claude/plugins/local/leadv2/plugins/leadv2/commands/leadv2.md
plugins/leadv2/scripts/docs/leadv2/status-snapshot.json      (169 lines of live lane state, 2026-08-30 08:58Z)
plugins/leadv2/scripts/docs/leadv2/.broad-status-prev.json
```

Failure scenario: `~/Projects/leadv2` is the single source for persona-engine, m3-market and
respiro-ios. On any checkout that is not this laptop these are dangling symlinks; on this laptop the
repo becomes a writer into the founder's live control plane. It is also defect A — "a worker writes
into the main checkout instead of its lane" — committed by the cluster whose job is to stop that,
and it breaks round-3's own `Done means: git status --porcelain shows only control-plane residue`:
the residue was not cleaned, it was committed, which is why the lane now grades clean.

Required fix: `git rm -r --cached plugins/leadv2/scripts/docs plugins/leadv2/scripts/.claude`, amend
`ef90ce2` so those 15 paths never enter history, and gitignore both parent dirs. The code hunks of
`ef90ce2` are fine and must be kept.

---

## High

### H1 — `leadv2-dispatch-code.sh:965-968` — the D3 silent no-op the round-2 Critical banned, under a new name

```bash
if [[ "${WORK_ROOT}" == "${PROJECT_ROOT}" || -z "${task_id}" ]]; then
  LANE_PLAN_DELIVERY_STATUS="not_required"
  return 0
fi
```

The ensure block at `:6105` keys on `${founder_task_id:-${sig8}}`, so a dispatch with no `--task-id`
and no `--resume-lane` still gets a real lane worktree — and then `_deliver_plan_into_lane` takes the
`-z "${task_id}"` arm and returns 0 with **no `emit`, no `_dl_note`, no stderr**. Reproduced against
the extracted production function:

```
PROBE2 (empty founder id, REAL lane) rc=0 status=not_required line='' journal=''
```

`LANE_PLAN_DELIVERY_STATUS` is written at `:966`, `:972`, `:986` and read at exactly two places, both
inside `test-plan-in-lane.sh`. Round 2 required "the no-op branch must be distinguishable from the
success branch"; at runtime it is not distinguishable at all.
Fix: `emit decision "lane_plan_skipped task=${sig8} reason=no_task_id|shared_tree"` on both arms, and
derive `task_id` from the same `${founder_task_id:-${sig8}}` key the ensure block already used.

### H2 — `leadv2-dispatch-code.sh:976` — `plan-*.md` is globbed in the dispatcher's cwd, so plans never reach the lane

```bash
for f in context.yaml brief.md plan-*.md; do
  [[ -f "${src}/${f}" ]] || continue
```

Bash expands the `for` word list against the **current directory**, not `${src}`. With no match in
cwd the literal token `plan-*.md` survives and `[[ -f "${src}/plan-*.md" ]]` is false. Reproduced
against the extracted production function with `plan-architect.md` present in `src`:

```
PROBE1 delivered: brief.md context.yaml
PROBE1 mission line: LANE PLAN: read <lane>/docs/handoff/TASK/context.yaml and the sibling brief.md and plan-*.md before editing.
```

Failure scenario: this cluster's own `plan-architect.md` (12 KB, the architecture the lane implements)
never reaches the lane, and the worker is explicitly instructed to read a file that is not there.
Worse, the behaviour depends on the dispatcher's cwd, so a lead session that happens to sit in a
directory containing `plan-*.md` gets a different, partially-correct copy set.
`test-plan-in-lane.sh` never puts a `plan-*.md` in the fixture, so it is blind to this.
Fix: `for f in "${src}"/context.yaml "${src}"/brief.md "${src}"/plan-*.md; do [[ -f "$f" ]] || continue; cp -f "$f" "${dst}/$(basename "$f")"; done`.

### H3 — `leadv2-dispatch-product-close.sh:1310/1321/1336` shadow the shared lib sourced at `:66`

The file sources `lib/leadv2-lane-guard.sh` at line 66 and then **re-defines**, after it:
`_PC_PORCELAIN_EXCLUDE_RE` (`:1310`), `_PC_BOOTSTRAP_PREFIX_RE` (`:1321`, the **pre-fix**
`'^\.claude/(commands|scripts|agents)/'` with no `(/|$)`), and `_pc_drop_bootstrap_dirt` (`:1336`).
`lv2_lane_dirty` is called at `:1632` and `:2416`, after those definitions, so the close gate — the
process that decides `landed` vs `refused` on the real path — runs the shadow, not the lib.
Demonstrated on the exact fixture `test-dirty-lane-never-lands.sh` declares must land:

```
porcelain: ?? .claude/commands
LIB   : CLEAN -> lands
CLOSE : DIRTY -> downgraded
```

Round-2 High #2 ("a lane dirty ONLY with bootstrap symlinks must land") is fixed in the library and
inert in production, and no suite can observe it because every suite sources the lib directly.
Fix: delete `leadv2-dispatch-product-close.sh:1310-1406` (regexes, duplicate filter, both
`*_legacy_removed` bodies), keep only the `source` at `:66`, and re-point `:2431`'s direct
`_pc_drop_bootstrap_dirt` call at the lib symbol.

### H4 — `lib/leadv2-lane-guard.sh:45-46` — the dirty-lane guard fails OPEN on bash 3.2

```
$ /bin/bash -c 'set -uo pipefail; source .../lib/leadv2-lane-guard.sh; printf "" | _pc_drop_bootstrap_dirt /tmp'
.../lib/leadv2-lane-guard.sh: line 45: task_lines[@]: unbound variable
```

`kept_lines+=("${task_lines[@]}")` (`:45`) and `for line in "${kept_lines[@]}"` (`:46`) are
unbound-variable errors under bash 3.2 + `set -u`. All three consumers declare `set -uo pipefail`
(`leadv2-dispatch-ledger.sh:81`, `leadv2-dispatch-product-close.sh:13`, `leadv2-dispatch-code.sh:277`)
and all three are `#!/usr/bin/env bash`; `/bin/bash` on macOS is 3.2.57.

Failure scenario: the call sits inside `status="$( git status … | _pc_drop_bootstrap_dirt … )"`, so
the *subshell* dies, `status` is empty, `lv2_lane_dirty` reports **clean**, and every dirty lane
lands. On any host whose PATH bash is `/bin/bash` (launchd / CI / sanitized PATH, or any mac without
homebrew bash) the whole of defect B silently does nothing — the exact "present in the source, never
fires at runtime" disease this cluster exists to end. The file's own siblings already use the safe
idiom (`leadv2-dispatch-code.sh:6283`).
Fix: `kept_lines+=(${task_lines[@]+"${task_lines[@]}"})` and `for line in ${kept_lines[@]+"${kept_lines[@]}"}`,
plus a `/bin/bash`-invoked case in `test-dirty-lane-never-lands.sh`.

### H5 — `leadv2-dispatch-code.sh:3538-3546` — the class floor is bypassed on resume, and the "survives-resume" suite never resumes

`_admission_classify` returns at `:3546` when the on-disk sig8 receipt's digest equals this mission's
digest — **before** `task_floor` is read at `:3553-3556`.

Failure scenario: mission M for founder task T is first dispatched Light, so `task-class.yaml` = Light
and `receipt(sig8_M)` = Light. A different mission for T is then classified Heavy, so
`task-class.yaml` correctly lifts to Heavy (the monotonic write works). M is re-dispatched unchanged
-> digest matches -> early return with `ADMISSION_CLASS=Light`, `ADMISSION_ROUTE=dispatch`. The floor
did not survive the resume; `D4-SHAPE says FLOOR, never demotion` is violated on exactly the path the
suite is named for.

`test-class-floor-survives-resume.sh` calls only `leadv2_admission_write_receipt` and
`leadv2_admission_read_task_receipt`; it never invokes `_admission_classify`, never creates a sig8
receipt, and never re-runs a mission. Its mutation control mutates the *writer*, so it proves the
writer and nothing about resume.
Fix: apply the floor across the digest-match early return, and rewrite the suite to drive
`_admission_classify` twice with the same mission.

### H6 — `leadv2-dispatch-product-close.sh:2413` — the refusal evidence line is now always `<unresolved>`

`_PC_LANE_TOPLEVEL` is set only inside `_pc_lane_root_is_own_worktree_legacy_removed` (`:1401`,
`:1405`), which is no longer called; the live probe is `lv2_lane_root_is_own_worktree`, which sets
`LV2_LANE_TOPLEVEL` instead (shellcheck SC2034 confirms it is never read — raw output below). So
`_PC_LANE_RESOLVED_TOP="${_PC_LANE_TOPLEVEL:-<unresolved>}"` at `:2413` always yields `<unresolved>`.

Failure scenario: a lane refused with `cause=lane_root_not_a_worktree` now always emits
`resolved_toplevel=<unresolved>`, destroying the one field that distinguishes "the lane dir is really
the main checkout" from "the lane dir is a foreign worktree" — the diagnostic this file's own
REVIEW-GATE-LANEROOT-01 comment calls load-bearing. No test covers it.
Fix: read `LV2_LANE_TOPLEVEL` at `:2413`; delete `_PC_LANE_TOPLEVEL`.

---

## Medium

### M1 — `lib/leadv2-admission-class.sh:193-206` — the floor lock has no staleness breaker
`until mkdir "${lockdir}" … (( tries < 100 )) || return 1`. A process killed between `mkdir` and
`rmdir` leaves `docs/handoff/<task>/.task-class.lock` forever: every later write spins 5 s and returns
1, and that task's class floor is frozen. This cluster's own workers died mid-flight in round 2 **and**
round 3, so this is not hypothetical. Fix: record PID/timestamp in the lockdir and break it after N
seconds, or use an atomic `ln`/`mv -n` compare-and-swap.

### M2 — containment attribution window and prefix matching
`main-dirt.base` is snapshotted at worker spawn (`leadv2-dispatch-code.sh:4641-4646`); the comparison
runs at close (`leadv2-dispatch-ledger.sh:262`), potentially hours later. Any main-checkout write in
that window that lands inside this lane's declared write set is graded
`refused cause=wrote_outside_lane`; the lead session edits plugin scripts in main routinely.
Additionally `_lv2_path_in_write_set` (`lane-guard.sh:18-27`) does prefix matching, so a lane
declaring a directory (`plugins/leadv2/scripts`) claims every write beneath it, and two concurrent
lanes with overlapping declarations still cross-blame. `test-lane-containment.sh` only proves the
**disjoint** case (`own-lane.txt` declared, `other-lane.txt` written); the overlapping case is neither
tested nor handled. Fix: also require the offending path to be absent from the lane worktree's own
diff, or re-snapshot immediately before the verdict and diff the delta.

### M3 — `lib/leadv2-lane-guard.sh:88-91` — unattributed main writes are completely silent
Round 2 said "narrow the verdict … **or** drop the accusation and report it as unattributed". Only the
narrowing shipped: every `return 1` path emits nothing, so a worker that escapes its lane into a path
outside its declared write set is now invisible. Add
`emit decision "lane_containment_unattributed task=<sig8> paths=<n>"`.

### M4 — `leadv2-dispatch-code.sh:970-973` — `source_absent` is silent too
`PROBE3 (context.yaml absent) rc=0 status=source_absent line='' journal=''`. A lane whose plan
directory does not exist gets no plan and no journal line; D3 fails quietly. Journal it.

### M5 — dead code retained under a misleading name
`_pc_lane_dirty_legacy_removed` (`:1378`) and `_pc_lane_root_is_own_worktree_legacy_removed` (`:1400`)
are described as "inert markers". They are not inert: their globals and their sibling
`_pc_drop_bootstrap_dirt` are live and shadow the shared lib (H3), and `_PC_LANE_TOPLEVEL`'s orphaning
is H6. Delete them.

### M6 — no control for the round-3 resume-lane admission fix
`_resolve_pinned_placement:910` now binds `founder_task_id="${key}"`, and I verified by call order
that `_lane_writes_guard` (inside `architect_prepass`, `:4348`, invoked after `:6081`) does see it.
But round 3 required: "a resume-lane dispatch with no `LANE_WRITES:` and no `--task-id` must be
admitted on the strength of the existing worktree". No suite asserts it — grepping
`plugins/leadv2/scripts/tests/` for `no_lane_writes`, `LANE_WRITES` or `remedy` returns nothing. The
new `remedy:` stderr lines (`:3484-3485`) are equally untested.

### M7 — `pass_unlanded` silently demoted from terminal, untested
`leadv2-dispatch-ledger.sh:154`, `:320`, `:324` remove `pass_unlanded` from `dispatch_terminal_exists`
and from the write-once guard. That is a semantics change to a dedup guard shared far outside this
cluster; nothing in the diff exercises the re-dispatch path it opens, and no commit message justifies
it. Add the coverage or put the justification in the message.

---

## Low

- **L1** `leadv2-dispatch-code.sh:4565` — `LEADV2_WRITE_ROOT="${WORK_ROOT}"` has **zero readers**
  repo-wide (grep over `plugins/`, `tests/`, `docs/`, `.claude/ref` finds only this write and the two
  plan documents that requested it). `plan-architect.md:15` justified it as "so a child-side guard can
  deny on the same value later"; no such guard exists. Delete it or build the reader.
- **L2** `leadv2-dispatch-ledger.sh:267` — `LEADV2_DIRTY_LANE_MAX_ATTEMPTS` is set by nothing but its
  own test and has no registry/doc row.
- **L3** `lib/leadv2-lane-guard.sh:9` — `_lv2_class_rank`'s `*)` arm returns 2 (Standard), so a corrupt
  `task-class.yaml` becomes a silent Standard floor instead of a loud error.
- **L4** `leadv2-dispatch-code.sh:5766-5769` — a three-line prose paragraph is emitted inside the
  bracketed option list of `usage`; it renders as if `--task-id` takes those words as arguments.
- **L5** `tests/test-lane-placement-pin.sh:74` — the comment cites `leadv2-route-arbiter.sh:24-28`; the
  file is `lib/leadv2-route-arbiter.sh` and the assignment is at `:28`. (Both seam names
  `LEADV2_ROUTE_ARBITER_QUOTA_LIVE` / `LEADV2_QUOTA_LIVE` are genuinely read there — the quota-pin fix
  itself is sound and is the one unambiguous win of round 3.)

---

## My own mutation controls (RED/GREEN, scratch copy, reverted)

**M1 — the round-2 Critical: move `_deliver_plan_into_lane` back above the ensure block**
```
6081:  _deliver_plan_into_lane "${sig8}" "${founder_task_id}"
--- mutation applied ---
[TEST] FAIL: D3: ensure-created plan missing (rc=0, cwd='/tmp/leadv2-lpp-DyZ117/target/.claude/worktrees/ENSURE-PLAN-01')
[TEST] FAIL: D3: worker mission omitted lane-local plan instruction
[LANE-PLACEMENT-01] passed=25 failed=2
--- reverted; rerunning GREEN ---
[LANE-PLACEMENT-01] passed=27 failed=0
```

**M2 — containment attribution: drop the write-set narrowing in `lv2_lane_containment_violation`**
```
=== GREEN baseline (scratch, unmutated) ===
PASS: declared writes violate containment; concurrent/unattributed and control-plane residue do not
rc=0
=== RED expected (M2: containment blames any main path) ===
unattributed main-checkout write was blamed on this lane
rc=1
=== GREEN after revert ===
PASS: declared writes violate containment; concurrent/unattributed and control-plane residue do not
rc=0
```

**M3 — terminal funnel: `elif [[ -n "${_lane_root}" ]] && lv2_lane_dirty …` -> `elif false`**
```
=== GREEN baseline ===
PASS: terminal funnel downgrades worker dirt, permits control-plane/bootstrap-only lanes, and bounds retries
rc=0
=== RED expected (M3: dirty lane still lands) ===
rc=1
=== GREEN after revert ===
PASS: terminal funnel downgrades worker dirt, permits control-plane/bootstrap-only lanes, and bounds retries
rc=0
```

All three mutations were inserted inside the function body / statement under claim, and every mutated
file was restored from a `.bak` before the GREEN rerun.

---

## Static checks (raw output)

No Python or TypeScript in this diff; `mypy --strict` / `tsc --noEmit` are not applicable. Shell
equivalents:

```
### bash -n (bash 5.3.9)
plugins/leadv2/scripts/leadv2-dispatch-code.sh                 OK
plugins/leadv2/scripts/leadv2-dispatch-ledger.sh               OK
plugins/leadv2/scripts/leadv2-dispatch-product-close.sh        OK
plugins/leadv2/scripts/lib/leadv2-lane-guard.sh                OK
plugins/leadv2/scripts/lib/leadv2-admission-class.sh           OK
tests/run-all.sh                                               OK

### bash 3.2 -u runtime probe of lane-guard  (see H4)
plugins/leadv2/scripts/lib/leadv2-lane-guard.sh: line 45: task_lines[@]: unbound variable

### shellcheck -S warning plugins/leadv2/scripts/lib/leadv2-lane-guard.sh   (see H6)
In plugins/leadv2/scripts/lib/leadv2-lane-guard.sh line 66:
  LV2_LANE_TOPLEVEL="${top}"
  ^---------------^ SC2034 (warning): LV2_LANE_TOPLEVEL appears unused. Verify use (or export if used externally).
```

---

## CI selection check (E2E-KILLRATE-01 rule 3)

Read + verified. `tests/run-all.sh:143` filters changed files with
`[[ "${cf}" == plugins/leadv2/scripts/*.sh ]]`, and `[[ ]]`'s `*` crosses `/`, so
`plugins/leadv2/scripts/lib/leadv2-lane-guard.sh` matches and yields stem `leadv2-lane-guard`, which
the two new `leadv2-lane-guard:` rows pick up; the `leadv2-dispatch-ledger` / `leadv2-dispatch-code`
rows match the `key == stem` comparison at `:156`. Selection is sound.
Gap: `test-class-floor-survives-resume.sh` sources the lane guard transitively via
`lib/leadv2-admission-class.sh:24`, so it needs a `leadv2-lane-guard:` row too — today a
lane-guard-only change does not select it.

---

## Contradiction scan

- `LEADV2_WRITE_ROOT` — written once, read nowhere. **Contradiction confirmed** -> L1.
- `LEADV2_DIRTY_LANE_MAX_ATTEMPTS` — read only by the code that defines it, no registry row -> L2.
- `LEADV2_QUOTA_LIVE` / `LEADV2_ROUTE_ARBITER_QUOTA_LIVE` — both genuinely read at
  `lib/leadv2-route-arbiter.sh:28`. **No contradiction**; my first grep truncated and I re-derived.
- `_PC_LANE_TOPLEVEL` vs `LV2_LANE_TOPLEVEL` — **contradiction confirmed** -> H6.
- `_PC_BOOTSTRAP_PREFIX_RE` — two live definitions with different semantics -> H3.
- `main-dirt.base` — writer (`dispatch-code.sh:4644`) and reader (`lane-guard.sh:85`) agree. No contradiction.
- `_lane_writes_guard` vs `_resolve_pinned_placement` call order — guard runs inside `architect_prepass`
  (`:4348`), invoked after `:6081`. Order correct, the fix does fire. No contradiction.
- `task_class` reaching `_phase_precondition_guard` — reassigned from `ADMISSION_CLASS` at `:6145`.
  No contradiction.
- Path existence: every file named in the diff exists.
  `docs/handoff/dispatch-DISPATCH-PIN-CLUSTER-01/` — cited by `fix-round-2.md` as the round-1 report
  location — **does not exist**; the report is at `docs/handoff/DISPATCH-PIN-CLUSTER-01/review-opus.md`.
  Brief-only, no code impact.

---

## Required before merge

1. C1 — strip the 15 residue paths from `ef90ce2` and gitignore both parent dirs.
2. H1, H2 — journal every `_deliver_plan_into_lane` exit and fix the `plan-*.md` glob; extend
   `test-plan-in-lane.sh` with a `plan-architect.md` fixture and an empty-`task_id` real-lane case.
3. H3, H6 — delete the shadowing block in `leadv2-dispatch-product-close.sh:1310-1406`; read
   `LV2_LANE_TOPLEVEL` at `:2413`.
4. H4 — `${arr[@]+"${arr[@]}"}` in `_pc_drop_bootstrap_dirt`, plus a `/bin/bash` case in the suite.
5. H5 — apply the floor across the digest-match early return; make
   `test-class-floor-survives-resume.sh` actually drive `_admission_classify` twice.
6. M6 — add the resume-lane / no-`LANE_WRITES:` admission control round 3 asked for.

Suites run by this review, from the lane worktree, against the lane's own code:
`test-lane-placement-pin.sh` passed=27 failed=0 (3m50s) · `test-plan-in-lane.sh` PASS 1/1 ·
`test-lane-containment.sh` PASS 1/1 · `test-dirty-lane-never-lands.sh` PASS 1/1 ·
`test-admission-class.sh` pass=24 fail=0 · `test-class-floor-survives-resume.sh` PASS 1/1 —
6 suites, 0 failures; plus 3 independent mutation pairs (M1/M2/M3), each RED then GREEN in a scratch copy.

DELIVERABLE_COMPLETE
