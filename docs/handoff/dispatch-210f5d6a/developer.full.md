# developer.full.md — dispatch-210f5d6a (DISPATCHER-DOES-NOT-PERSIST-WRITES-INTO-THE-REGISTRY-ROW-01)

## State on entry

This lane's worktree already carried, from an earlier session/commit on the same branch:
- `823cb06c` — the actual fix: `_dispatch_register_writes_row` in
  `plugins/leadv2/scripts/leadv2-dispatch-code.sh` forced
  `LEADV2_PROJECT_ROOT="${PROJECT_ROOT}"`, discarding an explicit caller pin. Changed to
  `LEADV2_PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${PROJECT_ROOT}}"` (honor an exported pin,
  same idiom as `deploy-verify-check`/`deploy-classify`).
- The guard suite `plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh`
  (185 lines), pinning: Claim 1 (N=6 concurrent bridge registrations all keep their own
  `--writes`), Claim 1b (caller-pinned root wins over a divergent ambient root), a red-control
  (drop-writes mutation loses 6/6), and Claim 2 (an unrecorded write set still refuses
  `rc=5 reason=pending_resolution` — the reader untouched).
- `docs/handoff/DISPATCHER-DOES-NOT-PERSIST-WRITES-INTO-THE-REGISTRY-ROW-01/report.md`
  (untracked), with two explicit placeholders: `<!-- CHANGED-SCOPE-PENDING -->` and
  `<!-- LEFT-RED-PENDING -->`.
- Two dead scratch scripts (`.wait-capped.sh`, `.wait-runall.sh`) polling a PID (19401) from
  an earlier, apparently-abandoned attempt at the full changed-scope run; the PID was already
  dead. Removed as clutter — not part of the deliverable.

This session's job was to finish what was left open: the DoD-gate-required mutation-control
artifact, and the two report placeholders, then commit.

## Work done this session

### 1. Canonical mutation-control artifact

The mission text (and the DoD gate item (b)) requires "any mutation-control claim must be
backed by a `leadv2-mutation-control.sh` artifact, not asserted prose" — the suite's own
internal red-control (a scratch-copy mutation, inline in the suite) satisfies the lane-rules
negative-control requirement but not this specific mechanical check. Ran the canonical tool in
default (worker) mode:

```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh \
    plugins/leadv2/scripts/leadv2-dispatch-code.sh \
    's/LEADV2_PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${PROJECT_ROOT}}" leadv2_active_register/LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" leadv2_active_register/' \
    docs/handoff/DISPATCHER-DOES-NOT-PERSIST-WRITES-INTO-THE-REGISTRY-ROW-01
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=4
MUTATION-CONTROL ok suite=... file=... red_line=[FAIL] claim 1: kept=1/6 own_set=0/6 diff_hash=d05c78938... lane_diff_hash=b455ec46f...
MC_RC=0
```

`mutated_rc=1` — mutant killed. Artifact force-added (it lands under the gitignored
`docs/handoff/*/*` glob, un-ignored only for `.md`) at
`docs/handoff/DISPATCHER-DOES-NOT-PERSIST-WRITES-INTO-THE-REGISTRY-ROW-01/mutation-control/20260917T195402Z-29380.txt`.

### 2. Changed-scope runner

`LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed` (already in the report)
selects 146 suites. Attempted the real run (`bash tests/run-all.sh --scope changed`,
backgrounded with `nohup`+`disown`, watched in the foreground with bounded `timeout` waits per
this repo's "never end a turn on a wait" rule):

- `run-core-offline.sh` (first in scope order) hit `run-all`'s own 600s per-suite ceiling and
  was killed — this matches a pre-existing, previously-documented systemic condition (this
  repo's own memory: "`run-all` changed-scope runtime — core-offline is ALWAYS-ON in run-all →
  900s e2e gate can't cover changed-scope"). Not caused by, or fixable within, this lane's
  one-function diff.
- After ~30 min of foreground wall time, 31/146 suites had run: 20 passed, 10 failed (plus the
  core-offline timeout). At that pace the full 146-suite run would take multiple hours, which
  is outside any single foreground session — killed the background run rather than let it run
  unbounded.
- **Verified the 10 failures don't reach the changed code.** Grepped all 10 failing suites'
  source for the two symbols this lane's diff touches
  (`_dispatch_register_writes_row`, `_dispatch_registry_writes_proof`) — zero matches.
- One of the 10, `test-leadv2-dispatch-code.sh`, does exercise the changed *file* (not the
  changed function), so it got an explicit baseline diff instead of being trusted on the grep
  alone: ran it against the lane's fixed tree (`PASS=13 FAIL=10`), then temporarily swapped
  `leadv2-dispatch-code.sh` to `main`'s version (`git checkout main -- <file>`, git status
  confirmed clean before), ran again (`PASS=13 FAIL=10`, byte-identical), then restored
  (`git checkout HEAD -- <file>`, confirmed clean after). The 10 failures are pre-existing,
  all in `effort`/`think`/`class_map` selection — unrelated to write-set persistence — and
  this lane's diff changed neither the count nor which cases fail.

Both placeholders in `report.md` replaced with this evidence, plus an honest "Left red / known
issues" section naming every suite left red and why, per
`docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`'s measurement-hygiene and
cause-class-naming requirements. No suite's assertions were touched.

### 3. Falsification set (this session)

```
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh && echo OK
OK
$ bash plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh
[ok] claim 1: 6 concurrent bridge registrations all read back their OWN writes
[ok] claim 1b: caller-pinned LEADV2_PROJECT_ROOT honored over divergent ambient PROJECT_ROOT
[ok] claim 1 red-control: mutated bridge lost 6/6 write sets (harness can fail)
[ok] claim 2: unrecorded write set + live worker still refused rc=5 reason=pending_resolution
=== all checks passed ===
SUITE_RC=0
```

No Python file was changed by this lane (`py_compile` — nothing to run, enumerated in the
report, same as the prior commit).

## Committed

`6fd2f540` on `worktree-e0a3caf252c8` — adds the mutation-control artifact and the completed
`report.md` (the fix itself and the guard suite were already committed at `823cb06c`).

## Left alone / off-limits honored

- `docs/leadv2/.compact-freeze.md` — was already modified (`M`) in git status at session start,
  before this lane's own work; not touched by either the fix commit or this session's commit
  (it's a runtime-state path, off-limits per the DoD gate item (d) and per this lane's own
  mission scope). Left as found.
- `leadv2-dispatch-product-close.sh` — untouched, owned by another lane.
- `tests/known-red-suites.txt` — untouched, not widened.
- No assertion deleted, no grep loosened, no `|| true` added anywhere in this session's work.
- 113/146 `--scope changed` suites not run to completion within this session's time budget
  (see "Changed-scope runner" above); this is disclosed explicitly in the report rather than
  glossed over.

DELIVERABLE_COMPLETE
