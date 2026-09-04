# INVISIBLE-DELIVERABLES-CENSUS-01 — round 2: C6 defends the branch it names

## Verdict on the round-1 premise

The reviewer's mechanism hypothesis — "`chmod 000` on a directory does not deny the
**owner** a listdir on macOS, so `LA_UNREADABLE` is never set" — was measured and is
**false**. `chmod 000` does deny the owner (the kernel checks owner rwx bits); the
probe below shows the scan dropping the dir (`receipts 1 dispatch dirs` — the unreadable
dir is never counted as seen).

The real gap: the C6 fixture queried the **founder tid**. For a tid query the unreadable
dir is caught early — `lane_address_scan_handoff_root` puts it in `LA_UNREADABLE_DIRS`
before any receipt can be read, so it never enters `LA_MATCH_DIRS`, and the gather loop's
`LA_UNREADABLE` arm (the `unknown` at the six-space anchor) never fires. That arm is
reachable when a **matched** dir is unreadable: the sig8 path appends `dispatch-<sig8>`
to `LA_MATCH_DIRS` with no readability check. Measured live — the branch is **kept and
now defended**, not deleted. The resolver lib needed **zero** changes; only the suite's
C6 case changed (one query added, assertions strengthened, section moved before C5 so
the global control's red line names C6).

## Evidence — the two-arm discriminator probe

Same fixture, `chmod 000` on `dispatch-eeee5555`, two queries against
`plugins/leadv2/scripts/leadv2-lane-report.sh`:

```
--- tid query (round-1 C6):
  receipts   1 dispatch dirs, 1 with a receipt                    -> 1 task_id match
result: unknown (/tmp/c6probe.LXy33Y/docs/handoff/dispatch-eeee5555/exists but listdir failed;
rc=2
--- sig8 query:
  receipts   1 dispatch dirs, 1 with a receipt                    -> 0 task_id match
result: unknown (/tmp/c6probe.LXy33Y/docs/handoff/dispatch-eeee5555 exists but listdir failed;
rc=2
```

The reason text discriminates the arms: trailing slash (`dispatch-eeee5555/exists…`) =
the scan-level `LA_UNREADABLE_DIRS` catch; no slash (`dispatch-eeee5555 exists…`) = the
gather-loop arm. Both arms are now asserted in C6 (renamed C6a/C6b), each asserting the
full triple: `result: unknown`, a reason naming the directory, exit status 2.

## Evidence — control 1, single-site anchor (the round deliverable)

Command (run via `leadv2-mutation-control.sh` against committed HEAD):

```
bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
  plugins/leadv2/scripts/tests/test-lane-report-address.sh \
  plugins/leadv2/scripts/lib/leadv2-lane-address.sh \
  's|      LA_RESULT="unknown"|      LA_RESULT="none"|' \
  docs/handoff/INVISIBLE-DELIVERABLES-CENSUS-01
```

Before the fix (measured this round against round-1 HEAD `d0f4aff0`):

```
MUTATION-CONTROL mutant_survived suite=plugins/leadv2/scripts/tests/test-lane-report-address.sh file=plugins/leadv2/scripts/lib/leadv2-lane-address.sh
```

After the fix:

```
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-lane-report-address.sh file=plugins/leadv2/scripts/lib/leadv2-lane-address.sh red_line=  FAIL C6b rc=1 out=searched: diff_hash=1bc21dc79b320b52e296af5e1a1c79730a050108259157d088424766b3dd5f5d lane_diff_hash=2d3f3491e1974168bfbc8da217419e14845ca55cfd8c050dc1093d4bfbb6a556
```

Pair: `baseline_rc=0` / `mutated_rc=1`. Red line: `FAIL C6b rc=1 out=searched:` — a clean
assertion failure (the mutant flips the sig8-query arm to `result: none`, the CLI's
`none` branch exits 1), not a crash. Artifact:
`mutation-control/20260904T042436Z-72311.txt`.

## Evidence — control 2, global anchor

```
bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
  plugins/leadv2/scripts/tests/test-lane-report-address.sh \
  plugins/leadv2/scripts/lib/leadv2-lane-address.sh \
  's|LA_RESULT="unknown"|LA_RESULT="none"|g' \
  docs/handoff/INVISIBLE-DELIVERABLES-CENSUS-01
```

```
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-lane-report-address.sh file=plugins/leadv2/scripts/lib/leadv2-lane-address.sh red_line=  FAIL C6a rc=1 out=searched: diff_hash=f4379e39ccdff2de165d6903db11561d4f34a36a8b1fd10519dd3bde9a2e609b lane_diff_hash=2d3f3491e1974168bfbc8da217419e14845ca55cfd8c050dc1093d4bfbb6a556
```

Pair: `baseline_rc=0` / `mutated_rc=1`. Red line: `FAIL C6a rc=1 out=searched:` — names
**C6**, not C5 alone (C6 now runs before C5; C5's assertions are unchanged, only
relocated).

## Evidence — ten consecutive suite runs

```
run  1 rc=0  PASS=25 FAIL=0
run  2 rc=0  PASS=25 FAIL=0
run  3 rc=0  PASS=25 FAIL=0
run  4 rc=0  PASS=25 FAIL=0
run  5 rc=0  PASS=25 FAIL=0
run  6 rc=0  PASS=25 FAIL=0
run  7 rc=0  PASS=25 FAIL=0
run  8 rc=0  PASS=25 FAIL=0
run  9 rc=0  PASS=25 FAIL=0
run 10 rc=0  PASS=25 FAIL=0
```

25 assertions (was 20; C6 grew from 1 to 6). C1–C5 and C7–C12 untouched.
Re-run at final HEAD after the round-2 edits below — same ten green lines (see the
falsification set).

## Control binding refresh

The control outputs above were measured against HEAD `e79a066e` (identical code bytes
to final HEAD; only this report changed afterwards). After this report's commit, both
controls were re-run so `lane_diff_hash` binds to the final HEAD; the **two newest
files** in `mutation-control/` are that refresh — same red lines (`FAIL C6b` /
`FAIL C6a`), same `diff_hash` per anchor, `baseline_rc=0` / `mutated_rc=1`.

## Falsification set

`bash -n` on every shell file in the lane diff (round 1 + round 2), no Python files
changed:

```
bash -n OK: plugins/leadv2/scripts/tests/test-lane-report-address.sh
bash -n OK: plugins/leadv2/scripts/lib/leadv2-lane-address.sh
bash -n OK: plugins/leadv2/scripts/leadv2-lane-report.sh
bash -n OK: plugins/leadv2/scripts/leadv2-recovery-context.sh
no python files changed
```

Changed-scope runner selection (state file reset first — the per-git-dir
`leadv2-run-all-last-checked-sha` had collapsed the range to the docs-only HEAD):

```
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-lane-report-address.sh
```

(the three `test-status-surface*` rows come from uncommitted foreign runtime-state
dirt in `docs/leadv2/`, not from this lane's committed diff).

Full `tests/run-all.sh --scope changed` (state file reset so the lane range re-selects;
three foreign lanes were running core-offline concurrently, per-worktree `flock` shown
in the process table):

```
[FAIL] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[PASS] .../tests/test-status-surface-bash32.sh
[PASS] .../tests/test-status-surface-single-lead.sh
[PASS] .../tests/test-status-surface-fast-names.sh
[PASS] .../plugins/leadv2/scripts/tests/test-lane-report-address.sh
run-all: 4 passed, 1 failed, scope=changed
```

The lane's own suite: `PASS=25 FAIL=0` inside the runner. The one failure is
core-offline, with two NOT-KNOWN-RED nested labels that run:
`core:broad-status relay scoping` and `core:prepass resume invalidation
(LANE-OBSERVABILITY-02)`. Both measured independent of this lane:

- the NOT-KNOWN-RED label set **differs between two consecutive full runs** under the
  same tree (first run also flagged `core:plugin reliability` and `core:burn governor`;
  both pass standalone: `test-plugin-reliability-01` 21/0, `test-burn-governor` 35/0) —
  the known concurrent-runner contention signature, not a lane regression;
- `test-prepass-resume-invalidate.sh` is red **standalone** too, is owned by
  LANE-OBSERVABILITY-02, and references none of this lane's files (`grep -l` over
  `lane-address|lane-report|recovery-context`: no match) — pre-existing, unrelated.

Ten consecutive suite runs at final HEAD (raw):

```
run  1 rc=0 PASS=25 FAIL=0
run  2 rc=0 PASS=25 FAIL=0
run  3 rc=0 PASS=25 FAIL=0
run  4 rc=0 PASS=25 FAIL=0
run  5 rc=0 PASS=25 FAIL=0
run  6 rc=0 PASS=25 FAIL=0
run  7 rc=0 PASS=25 FAIL=0
run  8 rc=0 PASS=25 FAIL=0
run  9 rc=0 PASS=25 FAIL=0
run 10 rc=0 PASS=25 FAIL=0
```

## Evidence — session incident (parallel-writer check)

Mid-session the suite file flipped between two C5 variants (a never-committed WIP line
was briefly on disk, then reverted to HEAD bytes). Measured: `git log -S` proves the
strong variant was never committed; the second live registry lane claiming the same
LANE_WRITES (`CENSUS-UNREADABLE-DIR-BRANCH-UNDEFENDED-01`, main checkout) has **no
branch, no files, no worker process** — a phantom row. Proceeded as the single writer;
commits are pathspec-scoped.

## Commits

- `14ea7a9f` — test: C6 exercises both unknown arms (tid scan-level + sig8 gather-loop, full triple); C6 before C5
- `be2688f7` — round-2 report (first landing)
- `e79a066e` — mutation-control ok x2 bound to `e79a066e` (single-site C6b, global C6a, lane hash `2d3f3491`)
- the commit carrying this file — report placeholders resolved, falsification set, ten-run re-verify; followed by a control-binding refresh (two newest `mutation-control/` artifacts)
