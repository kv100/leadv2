# INVISIBLE-DELIVERABLES-CENSUS-01 — developer report

One way to ask "what did this lane produce?" that answers correctly from either
name, prints the directories it searched next to its answer, and distinguishes
`none` from `unknown`.

## Files

- `plugins/leadv2/scripts/lib/leadv2-lane-address.sh` (new, 311 lines) — sourceable resolver. Three-valued, exact-attribution field scan, coverage counters, explicit worktree horizon.
- `plugins/leadv2/scripts/leadv2-lane-report.sh` (new, ~100 lines) — CLI. Owns all formatting per the §5 contract. Exit 0 found / 1 none / 2 unknown / 3 usage.
- `plugins/leadv2/scripts/tests/test-lane-report-address.sh` (new) — C1–C12, all fixtures `mkdir`/`printf` under mktemp, no live `docs/handoff/`, no `git archive`.
- `plugins/leadv2/scripts/leadv2-recovery-context.sh` — the one adopting consumer.

Off-limits respected: no touch to `tests/known-red-suites.txt`, `main`, `docs/leadv2/`, `.gitignore`, `leadv2-lane-liveness.sh`, `tests/run-all.sh`.

## Ten consecutive suite runs (post-fix, final)

```
run 1: PASS=20 FAIL=0
run 2: PASS=20 FAIL=0
run 3: PASS=20 FAIL=0
run 4: PASS=20 FAIL=0
run 5: PASS=20 FAIL=0
run 6: PASS=20 FAIL=0
run 7: PASS=20 FAIL=0
run 8: PASS=20 FAIL=0
run 9: PASS=20 FAIL=0
run 10: PASS=20 FAIL=0
```

(20 asserts = brief's C1–C11 minimum set plus C4/C5 multi-asserts plus C12, the
recovery-context adoption case.)

## Mutation negative controls (all against committed HEAD d267a54c, lane_diff_hash d6fd31e4…)

Baseline green before every control (`baseline_rc=0` implied by `MUTATION-CONTROL ok`).
Every red line below is a failed assertion, not a crash.

| control | sed (inside a function body) | red line |
|---|---|---|
| **NC-1 (glob)** — dispatch-dir candidate rung disabled; reproduces the original bug | `s\|"$root"/dispatch-\*/\|"$root"/dispatch-disabled-*/\|` | `FAIL C1 rc=1 out=searched:` |
| **NC-1 (receipt)** — receipt `task_id` equality broken | `s/"$tidval" == "$tid"/"$tidval" == "__NC1_NEVER__"/` | `FAIL C9b rc=1 out=searched:` |
| **NC-2 (mandatory-adjacent)** — `unknown` falls through to `none` | `s/if [[ $LA_COV_UNATTR -gt 0 ]]; then/if false; then # NC2/` | `FAIL C5 rc=1` |
| per-function `lane_address_normalize` — sig8 shape misread as tid | `s/printf 'sig8 %s\n' "${q#dispatch-}"/printf 'tid %s\n' "${q#dispatch-}"/` | `FAIL C2 rc=2 p1=docs/handoff/dispatch-aaaa1111/developer.full.md p2=` |
| per-function `lane_address_is_founder_shaped` — `dispatch-*` accepted as founder pointer | `s/""\|dispatch-*) return 1/""\|dispatch-*) return 0/` | `FAIL C5 rc=1` |
| per-function `lane_address_list_deliverables` — deliverable glob renamed | `s/\*\.full\.md/*.fullZZ.md/g` | `FAIL C1 rc=0 out=lane: TEST-LANE-ONE-01` |
| per-function `leadv2-recovery-context.sh` main body — resolve call stubbed out | `s/lane_address_resolve "$TASK_ID" --worktrees/true # NC3/` | `FAIL C12 rrc=1 log=MISSING` |
| per-function `leadv2-lane-report.sh` main body — "NOT SEARCHED" line silenced | `s/NOT SEARCHED (pass --worktrees)/SEARCH-DISABLED/` | `FAIL C9a rc=1 out=searched:` |

NC-1 note: no single sed disables both rungs that add a dispatch-named dir to the
candidate set (receipt-match append and sig8-direct append), so NC-1 is run as two
controls — glob (red: C1) and receipt-equality (red: C9b, the worktree receipt
route). C2/C3 are reddened by the normalize control. Eponymous path untouched and
still working in all mutants (no eponymous-positive case exists; noted as a gap).

One `anchor_count` refusal occurred mid-session from my own loop splitting a
`|`-delimited sed expression — instrument worked fine once quoted correctly. No
`baseline_not_green` refusal hit; fixtures are `mkdir`/`printf`, no `git archive`.

## C4 / C5 / C9 outputs verbatim

C4 (`none` — complete scan, every dir pointed):

```
searched:
  registry   docs/leadv2/active.yaml                                  -> 0 rows
  receipts   2 dispatch dirs, 2 with a receipt                    -> 0 task_id match
  missions   2 dispatch dirs, 0 with lane-mission.md              -> 0 H1 match
  eponymous  docs/handoff/MISSING-LANE-01/  -> absent
  worktrees  NOT SEARCHED (pass --worktrees)
result: none (searched: docs/leadv2/active.yaml [0 rows], 2 receipts [no task_id match],
        0 missions [no H1 match], docs/handoff/MISSING-LANE-01/ [absent]; 0 unattributable dirs remain;
        NOT searched: .claude/worktrees/*/docs/handoff/)
exit=1
```

C5 (`unknown` — the 74% case, must not read as `none`):

```
searched:
  registry   docs/leadv2/active.yaml                                  -> 0 rows
  receipts   1 dispatch dirs, 0 with a receipt                    -> 0 task_id match
  missions   1 dispatch dirs, 0 with lane-mission.md              -> 0 H1 match
  eponymous  docs/handoff/MISSING-LANE-02/  -> absent
  worktrees  NOT SEARCHED (pass --worktrees)
result: unknown (no pointer matched MISSING-LANE-02, but 1 of 1 deliverable-holding dirs carry no pointer at all (1 unattributable);
        searched: docs/leadv2/active.yaml [0 rows], 0 receipts, 0 missions,
        docs/handoff/MISSING-LANE-02/ [absent]; NOT searched: .claude/worktrees/*/docs/handoff/)
exit=2
```

C9 without `--worktrees` (report only inside a lane worktree):

```
searched:
  registry   docs/leadv2/active.yaml                                  -> 0 rows
  receipts   1 dispatch dirs, 1 with a receipt                    -> 0 task_id match
  missions   1 dispatch dirs, 0 with lane-mission.md              -> 0 H1 match
  eponymous  docs/handoff/TEST-LANE-ONE-01/  -> absent
  worktrees  NOT SEARCHED (pass --worktrees)
result: none (searched: docs/leadv2/active.yaml [0 rows], 1 receipts [no task_id match],
        0 missions [no H1 match], docs/handoff/TEST-LANE-ONE-01/ [absent]; 0 unattributable dirs remain;
        NOT searched: .claude/worktrees/*/docs/handoff/)
exit=1
```

C9 with `--worktrees`:

```
lane: TEST-LANE-ONE-01
resolved: tid=TEST-LANE-ONE-01 sig8=- via=direct
searched:
  registry   docs/leadv2/active.yaml                                  -> 0 rows
  receipts   2 dispatch dirs, 2 with a receipt                    -> 1 task_id match
  missions   2 dispatch dirs, 0 with lane-mission.md              -> 0 H1 match
  eponymous  docs/handoff/TEST-LANE-ONE-01/  -> absent
  worktrees  searched 1 worktree handoff root(s)
coverage: 1 dirs hold a deliverable; 1 carry a pointer; 0 unattributable
found:
[wt/WTX]  .claude/worktrees/WTX/docs/handoff/dispatch-eeee6666/developer.full.md  10b  2026-09-04T03:41:43Z
result: found 1
exit=0
```

## recovery-context.sh before/after (was line 40)

Before:

```bash
HANDOFF_DIR="${PROJECT_ROOT}/docs/handoff/${TASK_ID}"
```

After (`plugins/leadv2/scripts/leadv2-recovery-context.sh:39-62`): sources
`lib/leadv2-lane-address.sh`, runs `lane_address_resolve "$TASK_ID" --worktrees`,
keeps `HANDOFF_DIR` on the eponymous path for the aux reads (context.yaml /
architect.md / rollback.md), and adds to **both** `recovery-full.md` and the stdout
compact block: `result:` + `searched:` + `coverage:` + the prior-deliverable file
list under "DO NOT re-dispatch over these", or the explicit sentence "No prior
deliverable found. If result is unknown, absence is NOT evidence the worker died."

Real invocation, fixture (founder id → dispatch-named report via the converted consumer):

```
$ PROJECT_ROOT=$R plugins/leadv2/scripts/leadv2-recovery-context.sh --task-id DEMO-RECOVERY-01 --attempt 2
[leadv2-recovery-context] archived full incident log: /tmp/rc.ev6yCO/docs/handoff/DEMO-RECOVERY-01/recovery-full.md
RECOVERY-CONTEXT (compact)
Original task: DEMO-RECOVERY-01
Prior deliverables: found (see below)
  searched: registry docs/leadv2/active.yaml [0 rows]; receipts 1 [1 task_id match]; missions 0 [0 H1 match]; eponymous docs/handoff/DEMO-RECOVERY-01/ [absent]; worktrees searched=0 root(s)
  coverage: 1 dirs hold a deliverable; 1 carry a pointer; 0 unattributable
...
## Prior deliverables (address resolution)
result: found (rc=0)
Prior deliverable files (DO NOT re-dispatch over these):
[main]  docs/handoff/dispatch-beef0001/developer.full.md  13b  2026-09-04T03:32:48Z
```

## Live-tree coverage (resolver output vs brief §3b)

Run read-only against the main checkout `~/Projects/leadv2` (worktree holds only
the tracked slice of `docs/handoff/`; this worktree: 76 lane-mission.md, 0
receipts — the rest are untracked main-tree files):

```
coverage: 291 dirs hold a deliverable; 70 carry a pointer; 221 unattributable
receipts 847 dispatch dirs, 189 with a receipt
missions 847 dispatch dirs, 355 with lane-mission.md
registry 0 rows
```

vs brief §3b: 291/75/216, 846 dirs, 188 receipts. Same shape; the ±5 drift is
tree motion since `a02c9189`. The headline holds: **~76% unattributable, honest
`unknown` is the common answer.**

Live exemplars:

- `COMPLEXITY-ESTIMATOR-IS-OFF-01` → **found**, `docs/handoff/dispatch-0672c002/developer.{full,summary}.md`, via receipt, exit 0.
- `D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01` → **unknown** (its real dir `dispatch-57a94876` carries the report but no admissible pointer — the §3b 74%, live). One *other* dir's mission H1 matches the tid but holds no deliverable; it is correctly not credited with one.

## CI-ROW-PENDING

Three-line append to `EXTRA_SUITE_MAP` in `tests/run-all.sh` (no other change
needed); lands when the run-all.sh concurrency lock clears. Do not apply in this
lane.

```
leadv2-lane-address.sh:plugins/leadv2/scripts/tests/test-lane-report-address.sh
leadv2-lane-report.sh:plugins/leadv2/scripts/tests/test-lane-report-address.sh
leadv2-recovery-context.sh:plugins/leadv2/scripts/tests/test-lane-report-address.sh
```

## Consumer-migration backlog (`.full.md`/`.summary.md` referencers)

Re-derived live (`grep -rc '\.full\.md\|\.summary\.md'` over `plugins/leadv2/scripts/*.sh`
+ `plugins/leadv2/hooks/*`): **28 files** still reference the deliverable names;
`leadv2-recovery-context.sh` now references zero (converted). Top of the list:

```
20 claude-subsession.sh        5 leadv2-mission-lint.sh      3 leadv2-lane-shape.sh
12 leadv2-phase-advance.sh     5 leadv2-dispatch-product-close.sh   2 leadv2-status-snapshot.sh
 5 leadv2-score-helpers.sh     4 leadv2-build-feedback.sh    2 leadv2-review-run.sh
 4 hooks/leadv2-verdict-format-guard.sh   4 hooks/leadv2-lead-edit-guard.sh
 3 leadv2-score-compute.sh     3 hooks/leadv2-lead-read-guard.sh   (+9 more at 1–2 refs)
```

Note: brief §6 said 31 consumers with `leadv2-broad-status.sh` at 6 — that file
shows 0 refs on the live tree today; the count above is what re-derives now.

## Debt rows (named, not built)

1. Make `leadv2-lane-liveness.sh` consume the shared library (its `deliverable_dirs`
   was renamed/reshaped upstream — the brief's `:637` citation has drifted; the
   log_path consult is now near `:711`. The invariant is inherited as prose in the
   lib header).
2. The 28-consumer migration above (exactly one converted in this lane, per scope stop).
3. **The real fix behind the 74%:** write `admission-receipt.yaml` with a
   founder-shaped `task_id` for every dispatch (dispatcher change, separate lane);
   coverage then climbs from ~24% toward 100% and the scan becomes a lookup.

## Falsification set (final)

```
bash -n OK: plugins/leadv2/scripts/lib/leadv2-lane-address.sh
bash -n OK: plugins/leadv2/scripts/leadv2-lane-report.sh
bash -n OK: plugins/leadv2/scripts/leadv2-recovery-context.sh
bash -n OK: plugins/leadv2/scripts/tests/test-lane-report-address.sh
PASS=20 FAIL=0 × 10 consecutive runs (above)
```

No Python files changed (no `py_compile` applicable). `tests/run-all.sh
--scope changed` was not run: the suite's EXTRA_SUITE_MAP rows are the pending
CI block above, and run-all.sh itself is under the §8a lock.

## Commit shas

- `cf1f5be6` — resolver lib + CLI + suite (C1–C11) + recovery-context adoption
- `a7d88f30` — C12 recovery-context coverage
- `d267a54c` — worktree-path double-slash squeeze
- (this report commit follows)
