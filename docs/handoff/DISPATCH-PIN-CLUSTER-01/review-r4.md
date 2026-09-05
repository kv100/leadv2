status: fail
reviewer_says: do_not_merge

# DISPATCH-PIN-CLUSTER-01 — adversarial review, round 4

Reviewed: lane `.claude/worktrees/DISPATCH-PIN-CLUSTER-01`, HEAD `2f6649d`, 8 commits over
merge-base `5d1a5d7`. Everything below was **executed**. Mutations were applied to scratch copies
under `/private/tmp/.../scratchpad/{mut,m2,pre,pre2,mb}`; `plugins/` in the lane is byte-unchanged
by this review (`git status --porcelain` in the lane shows only control-plane residue, verified
before and after).

Note on tooling: repowise/graph indexes cover `persona-engine` only — `get_answer(repo="leadv2")`
returns `Unknown repo 'leadv2'`. Discovery in this repo therefore used grep + execution, and every
claim below carries its run output.

**Headline: this round genuinely fixed five of six Highs in the source, and broke five other
suites doing it — none of which CI selects on this diff.** The commit message's "Suites, all
green" covers only the six suites the author ran.

---

## Original defects

| # | Defect | Verdict | Evidence |
|---|---|---|---|
| A | writes-outside-lane | **PARTIAL** (unchanged) | Nothing in `2f6649d` touches containment. M2 (spawn-time `main-dirt.base` vs close-time porcelain; `_lv2_path_in_write_set` prefix matching, `lane-guard.sh:18-27`) and M3 (`lv2_lane_containment_violation` `lane-guard.sh:80-94` — every `return 1` path is silent) are both unchanged. C1's *recurrence* guard was never built: `git check-ignore -v plugins/leadv2/scripts/docs/... plugins/leadv2/scripts/.claude/...` → rc=1 (no rule), and both dirs sit untracked in the lane right now, so the next `git add plugins/` reproduces C1 byte-for-byte. |
| B | commit-not-an-obligation | **NOT FIXED** (down from PARTIAL) | See H7. The dispatcher still has no mechanism that notices a worker that died with uncommitted bytes in its lane. Proven, not read: `dispatch_ledger_sweep_write_dead` (`leadv2-dispatch-ledger.sh:439-441`, its own comment: *"the sweep's OWN write path — deliberately NOT dispatch_ledger_write_terminal()"*) takes `<sig8> <lane> <cause> <evidence> <attempt>` — **no lane root** — so it structurally cannot consult lane dirt; and `cmd_sweep` has exactly one invoker in the whole plugin, the CLI verb at `leadv2-dispatch-code.sh:7698`. `grep sweep hooks/hooks.json` returns only stale-pid / orphan-monitor / merged-worktree rows. Nothing runs it. Meanwhile the write-once change this cluster made to `pass_unlanded` regressed `test-close-chain.sh` from 18/0 to 17/1 (H8). |
| C | plan-not-in-lane | **FIXED** | Production probe of the live `_deliver_plan_into_lane`, run from a cwd with no `plan-*.md`: `PROBE-H2 rc=0 delivered: brief.md context.yaml plan-architect.md`. Both formerly-silent arms now journal (`PROBE-H1 journal='EMIT decision lane_plan_missing task=zz99zz99 reason=source_absent …|NOTE zz99zz99 skipped plan_source_absent'`). My own **MUT-2** (glob reverted to the cwd form) → `test-plan-in-lane.sh` rc=2 RED, restore → rc=0 GREEN. `test-lane-placement-pin.sh` D3 assertions pass on the ensure-created path. One nit → M8. |
| D | class-from-mission-length | **FIXED** | The floor is read before the digest-match early return (`leadv2-dispatch-code.sh:3543-3547`) and applied inside it (`:3560-3566`). `test-class-floor-survives-resume.sh` now extracts and executes the **real** `_admission_classify` body from the dispatcher and asserts `Heavy/phases/task_record` after a same-digest resume. My independent **MUT-4** (flip `>` to `<` on the first, digest-match occurrence only) → suite rc=1 RED, restore → rc=0 GREEN. Nits → L3, L6. |

---

## Prior findings — re-graded

| ID | Grade | Evidence |
|---|---|---|
| **C1** control-plane residue | **PARTIAL** | `git ls-tree -r --name-only HEAD \| grep -cE '^plugins/leadv2/scripts/(docs\|\.claude)/'` → **0**; no tracked symlink anywhere in the tree has a `/Users/...` target. HEAD is clean. But `e9e22d3` *untracked* rather than amended: the same grep at `ef90ce2` → **16**, so the nine absolute symlinks are still in history and land on any checkout of that sha. And no `.gitignore` rule exists (`git check-ignore` rc=1). Recurrence is one `git add plugins/` away. → M9 |
| **H1** empty `founder_task_id` fails open | **FIXED** | Production probe above: both previously-silent arms emit `lane_plan_skipped` / `lane_plan_missing` + `_dl_note`. `PROBE-H1b rc=5 journal='EMIT decision lane_plan_missing task=abcd1234 reason=task_id_unset|NOTE abcd1234 refused plan_task_id_unset'`. Caveat → M8. |
| **H2** `plan-*.md` globbed in cwd | **FIXED** | Probe + MUT-2 above. |
| **H3** close gate runs the shadowed filter | **code FIXED / control NOT FIXED** | Standalone CLOSE-gate probe on the exact r3 fixture (lane dirty only with `?? .claude/commands` + control-plane residue): **LIVE HEAD** → `review_gate … status=blocked reason=no_work`; **MUT-1** (pre-fix `_PC_BOOTSTRAP_PREFIX_RE='^\.claude/(commands\|scripts\|agents)/'` reinserted right after the `source` at `:66`) → `review_gate … status=blocked reason=unscoped_lane_work terminal=refused cause=unscoped_lane_work offending=.claude/commands`. The code fix is real. **But the suite added to prove it does not detect that mutation** — `test-dirty-lane-never-lands.sh` still printed `PASS`. Root cause → **C3**. |
| **H4** bash 3.2 fail-open | **FIXED** | `/bin/bash` 3.2.57, `set -uo pipefail`, live lib, empty stdin → `rc=0` (was `line 45: task_lines[@]: unbound variable`). One bootstrap symlink line → filtered, `rc=0`. **MUT-3** (revert to `"${task_lines[@]}"`) → `test-dirty-lane-never-lands.sh` rc=**127** with the unbound-variable error, restore → rc=0. The suite carries its own `/bin/bash` case at `:35`. |
| **H5** floor bypassed on digest match | **FIXED** | MUT-4 above; the suite drives the real classifier. |
| **H6** `_PC_LANE_TOPLEVEL` orphaned | **code FIXED / UNCOVERED** | `_PC_LANE_TOPLEVEL` no longer exists anywhere; `:2314` reads `LV2_LANE_TOPLEVEL`, which `lv2_lane_root_is_own_worktree` sets at `lane-guard.sh:66` in the immediately-preceding `if` condition. **MUT-5** (revert `:2314` to the dead name) survives `test-dirty-lane-never-lands` (rc=0), `test-lane-containment` (rc=0), `test-plan-in-lane` (rc=0) — still zero coverage, as in r3. → L7 |
| **M1** floor lock has no staleness breaker | **NOT FIXED** | `lib/leadv2-admission-class.sh:193-197` still `until mkdir … (( tries < 100 )) \|\| return 1`, no PID/timestamp, no break. A worker killed between `mkdir` and `rmdir` freezes that task's floor forever. **Six workers died mid-round today.** |
| **M2** containment window + prefix match | **NOT FIXED** | Unchanged. |
| **M3** unattributed main writes silent | **NOT FIXED** | `lane-guard.sh:80-94` — no `emit` on any `return 1`. |
| **M4** `source_absent` silent | **FIXED** | Journaled; see H1 probe. |
| **M5** dead code under a misleading name | **FIXED — and this is what broke four suites** | `_pc_lane_dirty_legacy_removed`, `_pc_lane_root_is_own_worktree_legacy_removed`, `_PC_LANE_TOPLEVEL`, `_pc_phys`, `_PC_PORCELAIN_EXCLUDE_RE`, `_PC_BOOTSTRAP_PREFIX_RE`, `_pc_drop_bootstrap_dirt` all deleted from `leadv2-dispatch-product-close.sh`. → **C2** |
| **M6** resume-lane / no-`LANE_WRITES:` admission control | **NOT FIXED** | `grep -rn "no_lane_writes" plugins/leadv2/scripts/tests/` → nothing. The `remedy:` stderr lines remain untested. |
| **M7** `pass_unlanded` demoted from terminal | **NOT FIXED — now a proven regression** | → **H8** |
| **L1** `LEADV2_WRITE_ROOT` write-only | **NOT FIXED** | One write (`leadv2-dispatch-code.sh:4583`); the only other hits repo-wide are the two plan documents that requested it. |
| **L2** `LEADV2_DIRTY_LANE_MAX_ATTEMPTS` undocumented | **NOT FIXED** | Read at `leadv2-dispatch-ledger.sh:267`, set only by its own test, no registry row. |
| **L3** `_lv2_class_rank` `*)` → 2 | **NOT FIXED** | `lane-guard.sh:9` unchanged: a corrupt `task-class.yaml` silently becomes a Standard floor. This matters more now, because the H5 fix routes the early return through `_lv2_class_rank` on **every** resume. |
| **L4** prose inside the `usage` option list | **NOT FIXED** | `leadv2-dispatch-code.sh:5784-5786` still renders as if `--task-id` takes those words as arguments. |
| **L5** wrong file path in a test comment | **NOT FIXED** | `test-lane-placement-pin.sh:77` still cites `leadv2-route-arbiter.sh:24-28`; the file is `lib/leadv2-route-arbiter.sh`, assignment at `:28`. |

---

## New findings

### Critical

#### C2 — `2f6649d` breaks four previously-green suites; none is CI-selected on this diff

`leadv2-dispatch-product-close.sh` lost `_PC_PORCELAIN_EXCLUDE_RE` (was `:1310`),
`_PC_BOOTSTRAP_PREFIX_RE`, `_pc_drop_bootstrap_dirt` and `_pc_phys`. Four existing suites read those
symbols **out of that file by name/line-anchor** — deliberately, so a drifted copy cannot pass.
Bisected by restoring only `leadv2-dispatch-product-close.sh` from `e9e22d3` into an otherwise
identical scratch copy:

```
suite                                     e9e22d3                              2f6649d
test-t13-slice1.sh                        PASS=19 FAIL=0                       PASS=16 FAIL=3
test-scope-gate-orchestration-dirt.sh     9 passed, 0 failed, 4 could-not-run  0 passed, 2 FAILED, 11 could-not-run
test-merged-sweep-orchestration-dirt.sh   8 passed, 0 failed                   1 FAILED (exclusion-regex-matches-its-twin)
test-worktree-lane-safety.sh              24 passed, 0 failed                  10 passed, 1 FAILED (P10-twin-regex-unchanged)
```

Named failures: `test-t13-slice1.sh` — `tasks-only-refusable`, `tasks-noise-with-real-work`,
`tasks-bak-anchored` (its `extract_close()` at `:92-95` greps `^_PC_PORCELAIN_EXCLUDE_RE=` and
`^_pc_phys()` and returns 2 when either is absent). `test-scope-gate-orchestration-dirt.sh` —
`both-sites-use-constant`, `both-sites-use-bootstrap-filter`, plus **11 cases downgraded to
COULD-NOT-RUN**, i.e. the entire porcelain-exclusion contract is now untested on the close path.

Failure scenario: the porcelain exclusion set is what decides `unscoped_lane_work` vs `landed` for
every lane in the fleet. This commit removed its only coverage and left two suites reporting FAIL
while the commit message says "Suites, all green". Anyone who later runs `tests/run-all.sh --scope
all` sees five red suites and cannot tell which belong to this cluster.

Required fix: point all four suites at `lib/leadv2-lane-guard.sh` (the new single definition) —
`_extract_filter` / `extract_close` / the twin-regex checks each take a script path, so it is a
one-line source change per suite — and re-run to 19/0, 9-passed/0-failed, 8/0 and 24/0. Do **not**
re-add the shadow to satisfy the greps.

#### C3 — `tests/test-dirty-lane-never-lands.sh:89` — the H3 negative control is inert (`! cmd` is exempt from `set -e`)

```bash
[[ $close_rc -eq 5 ]] # no product diff is expected; the gate still wrote its verdict
! grep -Fq 'reason: unscoped_lane_work' "$T/main/docs/handoff/dispatch-closeboot/review-gate.md"
```

bash's own rule: *"The shell does not exit if the command that fails is … a command whose return
value is being inverted with `!`"*. Demonstrated:

```
$ bash -c 'set -euo pipefail; echo x > /tmp/zz1; ! grep -Fq x /tmp/zz1; echo "REACHED… rc_of_prev=$?"'
REACHED-AFTER-INVERTED-FAILURE rc_of_prev=1
```

End-to-end, with MUT-1 applied to the scratch copy and the suite instrumented to dump the artifact
it asserts on:

```
status: blocked
reason: unscoped_lane_work            <-- the defect IS present
…
[leadv2-dispatch-product-close] review_gate task=closeboot status=blocked reason=unscoped_lane_work terminal=refused cause=unscoped_lane_work offending=.claude/commands
PASS: terminal funnel and CLOSE gate downgrade worker dirt, permit bootstrap-only lanes, and bound retries   <-- suite still green
```

`close_rc` is 5 for an unrelated reason (`empty_diff`) on both the fixed and the broken script, so
that assertion is vacuous too. The one control added this round for the one High whose whole point
was "the fix is inert on the live path" is **itself inert on the live path**.

Required fix: `if grep -Fq 'reason: unscoped_lane_work' "$T/main/…/review-gate.md"; then echo 'CLOSE
gate ran a shadowed bootstrap filter' >&2; exit 1; fi`, and assert the positive direction
(`reason: no_work`) too. Re-run MUT-1 and paste the RED. Grep the changed suites for the same
`! cmd` idiom before merging.

### High

#### H7 — defect B: nothing detects a worker that dies with uncommitted work; the sweep cannot, and nothing runs it

Two independent breaks on the same path:

1. **The sweep's write path bypasses the dirty-lane funnel by design.**
   `leadv2-dispatch-ledger.sh:439-441` — *"the sweep's OWN write path — deliberately NOT
   `dispatch_ledger_write_terminal()`"*. `dispatch_ledger_sweep_write_dead()` (`:442`) has the
   signature `<sig8> <lane> <cause> <evidence> <attempt>`: **no lane root, no porcelain, no
   `lv2_lane_dirty` call**. It appends `{"terminal":"dead","cause":"swept|no_close_owner"}` and that
   row is write-once-final (`case … landed|pass_unlanded|dead) exit 2`). Round 3's entire B fix — the
   `landed → pass_unlanded dirty_lane:` downgrade — lives in `dispatch_ledger_write_terminal`, which
   the crash path never reaches.
2. **`cmd_sweep` has no automatic invoker.** Its only caller in the plugin is the CLI verb
   `leadv2-dispatch-code.sh:7698`. `hooks/hooks.json` carries `leadv2-stale-pid-sweep.sh`,
   `leadv2-orphan-monitor-sweep.sh`, `leadv2-merged-worktree-sweep.sh` — and no ledger sweep. A dead
   lane is noticed only because a human types the verb. `LEADV2_LEDGER_SWEEP_ENABLE` defaults to `1`,
   which is a flag that is on and reaches nothing.

Failure scenario — the one that happened six times today, including for **this very commit**
(message: *"Rescues work left uncommitted by a codex worker that died at 09:57 (the fifth worker
death without a commit today)"*): the worker dies, no close gate runs, no terminal is written, the
lane sits with uncommitted bytes, and the only actor that notices is the lead reading `git status`
by hand. If a sweep is ever run, the lane is stamped `dead` with no record that bytes were left
behind and no route to `pass_unlanded`.

The mechanism B actually needs, plainly: **on the crash path, before stamping `dead`, resolve the
lane root and call `lv2_lane_dirty` / `_pc_lane_produced_files`; when dirty, stamp `pass_unlanded
cause=dirty_lane_orphan` with the offending path list as evidence instead of `dead`; and give the
sweep an automatic trigger** (a `SessionStart`/`Stop` hook row, or a beat in the single-lead loop)
so it runs without a human verb. Until both exist B is not fixed, no matter what
`test-dirty-lane-never-lands.sh` prints — that suite only exercises the close-gate funnel, which the
crash path does not use.

#### H8 — `pass_unlanded` write-once removal regresses `test-close-chain.sh` (r3's M7, now demonstrated)

```
HEAD (2f6649d):                     === T11 close-chain results: 17 passed, 1 failed ===
                                    FAIL: (a/b groundwork) write-once: last state='landed', expected pass_unlanded to survive
merge-base ledger restored, rest HEAD: === T11 close-chain results: 18 passed, 0 failed ===
```

Introduced by `c0403ab` (`leadv2-dispatch-ledger.sh:154`, `:320`, `:324`). `test-close-chain.sh:74`
states the contract in its own header: *"D1 schema: `pass_unlanded` is a valid, write-once TRUE
terminal"*. This cluster silently reversed it. Failure scenario: a lane downgraded to
`pass_unlanded` for dirt can now be overwritten by a later `landed` — precisely the
commit-not-an-obligation hole defect B exists to close; the downgrade is not durable.
Required fix: restore `pass_unlanded` to the write-once set and show `test-close-chain.sh` 18/0, or
change that suite's D1 case **and** put the justification in the commit message. Do not merge with
the suite red and unmentioned.

#### H9 — CI selects zero suites for two of the three production files this cluster changes

Replaying `tests/run-all.sh`'s own selection logic (`:136-158` + `EXTRA_SUITE_MAP` `:105-128`)
against `HEAD~1..HEAD`:

```
changed:  leadv2-dispatch-code.sh, leadv2-dispatch-product-close.sh, lib/leadv2-lane-guard.sh, 3 tests
selected: test-class-floor-survives-resume, test-dirty-lane-never-lands, test-freepool-capability-floor,
          test-lane-containment, test-lane-placement-pin, test-lane-pulse-watch,
          test-model-select-telemetry, test-phase-precondition, test-plan-in-lane,
          test-single-lead-beat-loop
```

There is no `test-leadv2-dispatch-product-close.sh` and no map row keyed
`leadv2-dispatch-product-close`, so a change to the close gate selects **nothing**; same for
`leadv2-dispatch-ledger`. That is the mechanism by which C2's four breakages and H8's fifth ship
green — every one is a suite CI cannot reach on this diff. r3's own gap
(`test-class-floor-survives-resume.sh` sources the lane guard transitively and has no
`leadv2-lane-guard:` row) is also still open.
Required fix: add `leadv2-dispatch-product-close:` rows for `test-t13-slice1.sh`,
`test-scope-gate-orchestration-dirt.sh`, `test-merged-sweep-orchestration-dirt.sh` and
`test-worktree-lane-safety.sh`; a `leadv2-dispatch-ledger:` row for `test-close-chain.sh`; and a
`leadv2-lane-guard:` row for `test-class-floor-survives-resume.sh`. Prove each with `--scope changed`.

### Medium

#### M8 — `leadv2-dispatch-code.sh:970-975` + `:6138` — the new loud-refusal branch is unreachable in production, and its control asserts that unreachable branch

The same commit that added

```bash
if [[ -z "${task_id}" ]]; then
  LANE_PLAN_DELIVERY_STATUS="refused"; emit decision "lane_plan_missing … reason=task_id_unset"
  _dl_note "${sig8}" refused plan_task_id_unset; exit 5
fi
```

changed the only caller to `_deliver_plan_into_lane "${sig8}" "${founder_task_id:-${sig8}}"`
(`:6138`), so `task_id` is never empty at runtime — `sig8` is always set. The branch is dead on the
live path, and `test-plan-in-lane.sh:62-67` (`_deliver_plan_into_lane abc12345 ''`, expect rc 5)
asserts a state production cannot enter. What actually happens on a no-`--task-id` dispatch is
`src=$PROJECT_ROOT/docs/handoff/<sig8>` → absent → `source_absent` → `return 0`, which I probed:
`PROBE-H1 rc=0 … reason=source_absent`. Two consequences: (a) every legitimately task-idless
dispatch now writes a `lane_plan_missing` line that reads like an error but is normal; (b) the
`reason=no_task_id` signal r3 asked for is never emitted. Fix: emit `reason=no_task_id` from the
`source_absent` arm when `task_id == sig8`, and make the control drive `cmd_resolve`'s real call
shape rather than the masked one.

#### M9 — C1's recurrence guard was never built

`git check-ignore -v plugins/leadv2/scripts/docs/leadv2/active.yaml
plugins/leadv2/scripts/.claude/commands/leadv2.md` → rc=1, no rule. Both directories exist untracked
in the lane right now (`?? plugins/leadv2/scripts/.claude/`, `?? plugins/leadv2/scripts/docs/`).
`ef90ce2` still carries all 16 paths, nine of them `/Users/...` symlinks, so anyone checking out
that sha in another clone gets them. Fix: add both prefixes to `.gitignore` in this cluster, and
state explicitly in the commit message whether history is being left as-is.

### Low

- **L6** `tests/test-class-floor-survives-resume.sh:26-31` — the classifier body is sliced out with
  `s.index('\n}\n', start)`. Any future top-level `}` inside `_admission_classify` (a heredoc, a
  `case` closed at column 0) silently truncates the extraction and the suite keeps passing on a
  fragment. `assert old in s` guards the mutation, not the extraction. Assert the extracted text
  ends with the real closer, or brace-count.
- **L7** H6 has zero coverage: MUT-5 (revert `:2314` to `_PC_LANE_TOPLEVEL`) survives
  `test-dirty-lane-never-lands`, `test-lane-containment` and `test-plan-in-lane`. One assertion on
  `resolved_toplevel=` in the `lane_root_not_a_worktree` evidence line closes it.
- **L1–L5** carried forward unfixed, as graded above.

---

## My own mutation controls (RED/GREEN, scratch copies, restored)

| # | Mutation (inserted inside the body under claim) | Result |
|---|---|---|
| **MUT-1** | H3: reinsert the pre-fix `_PC_BOOTSTRAP_PREFIX_RE` immediately after `source lib/leadv2-lane-guard.sh` in `leadv2-dispatch-product-close.sh` | **standalone CLOSE probe RED** (`reason: no_work` → `reason: unscoped_lane_work`, `offending=.claude/commands`); **suite SURVIVED** (`PASS`, rc=0) → C3 |
| **MUT-2** | H2: `for f in "${src}"/…` → `for f in context.yaml brief.md plan-*.md` | `test-plan-in-lane.sh` rc=**2 RED** → restore rc=**0 GREEN** |
| **MUT-3** | H4: `kept_lines+=(${task_lines[@]+…})` → `kept_lines+=("${task_lines[@]}")` | `test-dirty-lane-never-lands.sh` rc=**127 RED** (`line 45: task_lines[@]: unbound variable`) → restore rc=**0 GREEN** |
| **MUT-4** | H5: flip `>` to `<` on the **first** (digest-match) `_lv2_class_rank` comparison only | `test-class-floor-survives-resume.sh` rc=**1 RED** → restore rc=**0 GREEN** |
| **MUT-5** | H6: `${LV2_LANE_TOPLEVEL:-…}` → `${_PC_LANE_TOPLEVEL:-…}` at `:2314` | **SURVIVED** all three suites (rc=0,0,0) → L7 |
| **BISECT** | C2/H8: restore only `leadv2-dispatch-product-close.sh` (from `e9e22d3`) / only `leadv2-dispatch-ledger.sh` (from merge-base) | the four suites go 19/0, 9-passed, 8/0, 24/0 and close-chain 18/0 — proving the regressions belong to this cluster |

---

## Static checks (raw output)

No Python or TypeScript in this diff; `mypy --strict` / `tsc --noEmit` are not applicable.

```
### bash -n (bash 5.x) AND /bin/bash -n (3.2.57 arm64-apple-darwin25)
plugins/leadv2/scripts/leadv2-dispatch-code.sh                         OK
plugins/leadv2/scripts/leadv2-dispatch-product-close.sh                OK
plugins/leadv2/scripts/lib/leadv2-lane-guard.sh                        OK
plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh       OK
plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh            OK
plugins/leadv2/scripts/tests/test-plan-in-lane.sh                      OK
(no BASH32-SYNTAX-FAIL lines)

### bash 3.2 + set -u runtime probe of the live lane guard (H4)
/bin/bash -c 'set -uo pipefail; source lib/leadv2-lane-guard.sh; printf "" | _pc_drop_bootstrap_dirt /tmp'  -> rc=0
/bin/bash … printf "?? .claude/commands\n" | _pc_drop_bootstrap_dirt <root>                                  -> rc=0, line filtered

### set -e + `!` semantics (C3)
bash -c 'set -euo pipefail; echo x > /tmp/zz1; ! grep -Fq x /tmp/zz1; echo REACHED…'
REACHED-AFTER-INVERTED-FAILURE rc_of_prev=1

### tracked-residue / symlink audit (C1)
git ls-tree -r --name-only HEAD | grep -cE '^plugins/leadv2/scripts/(docs|\.claude)/'   -> 0
same at ef90ce2                                                                         -> 16
tracked symlinks with a /Users/... target at HEAD                                       -> none
git check-ignore -v plugins/leadv2/scripts/{docs,.claude}/...                            -> rc=1 (no rule)
```

---

## Contradiction scan

- `_PC_BOOTSTRAP_PREFIX_RE` / `_PC_PORCELAIN_EXCLUDE_RE` / `_pc_drop_bootstrap_dirt` / `_pc_phys` —
  now single-defined in the lib (r3's contradiction resolved) but **four suites still expect them in
  `leadv2-dispatch-product-close.sh`**. New contradiction confirmed → **C2**.
- `pass_unlanded` write-once: `leadv2-dispatch-ledger.sh:154/320/324` says "not a terminal";
  `test-close-chain.sh:74` says "write-once TRUE terminal". **Contradiction confirmed** → **H8**.
- `_deliver_plan_into_lane`'s `task_id_unset` refusal vs its caller's `${founder_task_id:-${sig8}}`
  masking — **contradiction confirmed** → **M8**.
- `LEADV2_LEDGER_SWEEP_ENABLE` defaults to `1` while `cmd_sweep` has no automatic invoker — a flag
  that is on and reaches nothing. **Contradiction confirmed** → **H7**.
- `_PC_LANE_TOPLEVEL` vs `LV2_LANE_TOPLEVEL` — resolved; the dead name is gone repo-wide.
- `LEADV2_WRITE_ROOT` — still written once, read nowhere. **Contradiction confirmed** → L1.
- `LEADV2_DIRTY_LANE_MAX_ATTEMPTS` — read only by the code that defines it, no registry row → L2.
- `LEADV2_TEST_ROOT` — honoured consistently by all six suites (`ROOT="${LEADV2_TEST_ROOT:-…}"`);
  no contradiction. That is what made scratch-copy mutation possible without touching `plugins/`.
- Path existence: every file named in the diff exists. `docs/handoff/DISPATCH-PIN-CLUSTER-01/`
  contains `fix-round-4.md`, `review-r3.md`, `plan-architect.md`, `lane-mission.md` and
  `live-evidence-20260830-0820.md` — all present. No dangling reference in the changed files.

---

## Required before merge

1. **C2** — repoint `test-t13-slice1.sh`, `test-scope-gate-orchestration-dirt.sh`,
   `test-merged-sweep-orchestration-dirt.sh`, `test-worktree-lane-safety.sh` at
   `lib/leadv2-lane-guard.sh`; show 19/0, 9-passed/0-failed, 8/0, 24/0.
2. **C3** — replace the `! grep` no-op at `test-dirty-lane-never-lands.sh:89` with a real assertion
   and paste MUT-1 going RED.
3. **H7** — make the crash path (`dispatch_ledger_sweep_write_dead`) consult lane dirt and stamp
   `pass_unlanded cause=dirty_lane_orphan`, and give `cmd_sweep` an automatic trigger. Until then,
   defect B stays NOT FIXED.
4. **H8** — restore `pass_unlanded` write-once (or change the contract in the message) and show
   `test-close-chain.sh` 18/0.
5. **H9** — add the six `EXTRA_SUITE_MAP` rows and prove selection with `--scope changed`.
6. **M8, M9** — emit `reason=no_task_id` on the reachable arm; gitignore both residue prefixes.
7. Carried forward, still open: M1, M2, M3, M6, L1–L7.

Suites run by this review, from the lane worktree against the lane's own code:
`test-lane-placement-pin.sh` **passed=27 failed=0** · `test-plan-in-lane.sh` **PASS 1/1** ·
`test-lane-containment.sh` **PASS 1/1** · `test-dirty-lane-never-lands.sh` **PASS 1/1** ·
`test-admission-class.sh` **pass=24 fail=0** · `test-class-floor-survives-resume.sh` **PASS 1/1**
(the six named in the brief: 6 suites, 0 failures) — plus five suites the brief did not name and CI
does not select: `test-t13-slice1.sh` **PASS=16 FAIL=3**, `test-scope-gate-orchestration-dirt.sh`
**0 passed / 2 failed / 11 could-not-run**, `test-merged-sweep-orchestration-dirt.sh` **1 failed**,
`test-worktree-lane-safety.sh` **10 passed / 1 failed**, `test-close-chain.sh` **17 passed /
1 failed** — all five green at the parent commit; plus 5 independent mutation pairs (MUT-1..MUT-5)
and two commit-scoped bisects, every mutated file restored from the lane's own copy before the
GREEN re-run.

DELIVERABLE_COMPLETE
