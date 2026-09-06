# Round 2 — second worker: independent verification + provenance correction (2026-09-06)

**Provenance correction.** The 15:47Z dispatch postscript declared the first
attempt "left nothing — start clean". That premise was wrong: the first
worker's commits (`d7db3c6a` 15:13:48Z, `376ce30d`, `0ab49ea8` 15:25:45Z) were
already on `leadv2` main a minute before its 15:26:47Z crash. The 15:47Z check
inspected the persona-engine lane branch/worktree — but all four LANE_WRITES
paths of this task resolve inside the **leadv2** repo, where the file lives.
Nothing was redone on trust: the second worker re-verified every claim below
before adopting the landed work.

Re-verification, all fresh runs by the second worker:

- **Suite re-run** (live 4-mutant matrix included): `pass=13 fail=0 skip=0`, rc=0 — full paste in §1.
- **Mutation control, round 2**: `mutation-control/20260906T160459Z-17551.txt` —
  `MUTATION-CONTROL ok`, mutant-B (incomparability reverted to dead), red_line
  `c2`, `diff_hash=f7c160ba…` — byte-identical to round 1's (same mutant, deterministic).
- **CI selection re-proof, deterministic**: `--scope changed` reads
  `git diff --name-only HEAD` (tests/run-all.sh:239), and the lane is now
  *committed*, so the live repo can no longer show the selection. Reproduced in
  a throwaway clone: a one-line change to `lib/leadv2-lane-state.sh` selects
  BOTH `test-leadv2-lane-state.sh` and `test-lane-alive-predicate.sh`
  (`run-all: 12 selected`, no `FATAL bad_trigger_decl`) — paste in §2.
  First attempt (clone under `/tmp`) hit `FATAL root_escape` from macOS's
  `/tmp → /private/tmp` symlink; the physical path resolves it.
- **Falsification set**: `bash -n` on lib + suite OK; `py_compile` on the
  extracted embedded python OK; independent EPERM probe (second method, outside
  the suite): `os.kill(1,0) → PermissionError` on this machine.
- **Live-path parity**: repo file and the installed plugin copy
  `~/.claude/plugins/local/leadv2/…/leadv2-lane-state.sh` are the same inode
  (hardlink), md5 `270be083…` — the fix is on the live dispatch path.
- **Radius re-verified on the current tree** (line numbers have drifted — the
  callers are under concurrent edit by other lanes): dispatch-code
  `lane_reconcile … || true` (now :7322) and the false-dead symptom comment
  (now :6258); `leadv2-lane-liveness.sh` keeps its own three-answer
  `_ll_pid_alive` (EPERM=alive, untouched by this task); session-runner /
  codex-session-runner deregister traps (:205/:109) never consult `alive()`;
  internal `register` live-count uses `alive(r)` = unknown-counts-as-live;
  and the out-of-scope observation is confirmed still true:
  `leadv2-active-registry.sh` `_pid_alive` still collapses
  `PermissionError → False` (same disease, different owner — left for the lead,
  outside this lane's LANE_WRITES).

**Round-2 verdict: adopted as-is — no code change needed.** The two
known-reds named in report.md §8 were not re-run (pre-existing,
environment-shaped, documented for the next lane).

## 1. Fresh suite run (second worker, 2026-09-06)

```
[TEST] PASS: c1: live pid + correct birth -> alive, reconcile leaves it live
[TEST] PASS: c2: live pid + EMPTY recorded birth -> alive (unknown never kills), no dead_at
[TEST] PASS: c3: live pid + EMPTY observed birth -> alive (unknown never kills), no dead_at
[TEST] PASS: c4: live pid under EPERM (root-owned) -> alive, no dead_at
[TEST] PASS: c5: genuinely dead pid (ESRCH) -> dead, reconcile stamps dead_at
[TEST] PASS: c6: live pid + mismatched birth (pid reuse) -> dead, reconcile stamps dead_at
[TEST] PASS: c7: lead_alive with empty lead_pid_birth on a live pid -> rc0 (unknown degrades to live)
[TEST] PASS: mutant A RED: EPERM-live case goes red under it (control live)
[TEST] PASS: mutant B RED: empty-recorded-birth case goes red under it (control live)
[TEST] PASS: mutant B RED: empty-observed-birth case goes red under it (control live)
[TEST] PASS: mutant B RED: lead_alive unknown case goes red under it (control live)
[TEST] PASS: mutant C RED: ESRCH-dead case goes red under it (control live)
[TEST] PASS: mutant D RED: mismatch-dead case goes red under it (control live)

[LANE-ALIVE-PREDICATE] pass=13 fail=0 skip=0
SUITE_RC=0
```

## 2. Fresh CI-selection proof (throwaway clone, physical path)

```
$ git clone -q ~/Projects/leadv2 /private/tmp/lv2-select-proof
$ printf '# selection-probe\n' >> …/plugins/leadv2/scripts/lib/leadv2-lane-state.sh
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] …/plugins/leadv2/scripts/tests/test-leadv2-lane-state.sh
[SELECT] …/plugins/leadv2/scripts/tests/test-lane-alive-predicate.sh
run-all: 12 selected, scope=changed, select_only=1
```

## 3. Round-2 mutation-control artifact

`mutation-control/20260906T160459Z-17551.txt`:

```
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-lane-alive-predicate.sh file=plugins/leadv2/scripts/lib/leadv2-lane-state.sh red_line=[TEST] FAIL: c2: live pid + EMPTY recorded birth -> alive (unknown never kills), no dead_at diff_hash=f7c160ba4390a0370c70db4f41ba2ad68cd7499553efcdfb2a2ef87243825eb3 lane_diff_hash=e47ba2c01de10fc746aa46b06d97e2793a35c6fa57828fb4a72eaf12333e17ed
```
