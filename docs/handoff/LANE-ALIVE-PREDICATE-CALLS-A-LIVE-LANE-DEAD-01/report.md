# LANE-ALIVE-PREDICATE-CALLS-A-LIVE-LANE-DEAD-01 — report

`alive()` in `plugins/leadv2/scripts/lib/leadv2-lane-state.sh` called a live lane
dead. Both suspects from the brief are real and both were measured before any
line was changed; both branches are fixed, the paired controls run in BOTH
directions, and CI selects the new suite.

**Commits (repo `leadv2`, branch `main`):**
- `d7db3c6a` — fix: three-valued `proc_verdict`/`verdict`/`alive` + `lead_alive` routed through it
- `376ce30d` — test: `test-lane-alive-predicate.sh` (7 green cases + 4-mutant red matrix)
- (this report + artifacts)

`tests/run-all.sh` was **not** edited: suites self-register via
`# run-all-triggers:`, and the selection proof below shows the new suite IS
selected on a change to the lib — an EXTRA_SUITE_MAP row would be dead weight.

## 1. Measurement BEFORE the fix — which branch actually shoots

Probe: `measure-before-fix.sh` (committed alongside, force-added). Live pids,
real `ps`, the shipped test seams; nothing stubbed above the mechanism.

```
=== lib under test: /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/lib/leadv2-lane-state.sh md5=423ecd4d5389cc0a1fb4076812b843fd

[M1] baseline live pid=71352 kill-0:rc0 birth='Sun Sep 6 18:04:…' lane_alive rc=0  (expect 0)

[M2] LIVE pid=71352 kill-0:rc0 pid_start_time='' (empty) lane_alive rc=1  (0 would be correct)
     -> os.kill SUCCEEDED above, so the False verdict comes from the birth-comparison line, not from os.kill

[M3] LIVE pid=71352 correct recorded birth, but birth() observes '' (fixture simulates ps failure/timeout) lane_alive rc=1  (0 would be correct)

[M4] root-owned LIVE pid=630 kill-0 stderr: '…kill: (630) - Operation not permitted' python os.kill: PermissionError (EPERM) real birth recorded lane_alive rc=1  (0 would be correct — EPERM means the process EXISTS)

[M5] DEAD pid=72780 (killed+waited, ESRCH expected) kill-0:rc1 lane_alive rc=1  (1 is CORRECT — a real death must stay dead)

[M6] LIVE pid=71352 with MISMATCHED recorded birth (pid-reuse shape) lane_alive rc=1  (1 is CORRECT — mismatch means the recorded process is gone)

[M7] live registry scan — false-dead victims already on disk:
    total rows dead_at-stamped whose pid still exists: 0
```

**Verdict on the two suspects:**
- **(B) birth comparison is the shooter that fires on our own processes.** M2
  (empty `pid_start_time` — one `ps` failure at REGISTER time stamps the row
  `''` forever) and M3 (empty OBSERVED birth at check time) both returned
  dead-on-live, with `os.kill` proven rc0 in the same breath. The brief's
  caution was right to insist: this, not EPERM, is where today's false
  verdicts come from.
- **(A) EPERM is real, not latent-by-argument**: reproduced against a live
  root-owned pid (M4) — `os.kill` raised `PermissionError`, the old
  `except OSError: return False` collapsed it to dead. For lane rows on this
  single-user laptop it needs the pid to belong to another user, so it is the
  rarer path — but it fired on first try.
- M7: no dead_at-stamped rows whose pid still exists are sitting on disk right
  now — today's damage was caught at the proposal stage (the offered restart),
  and registries get swept; absence of bodies is not absence of the shooter.

## 2. The fix

`lib/leadv2-lane-state.sh` (+24/−13): a three-valued predicate with ONE verdict
pipeline, both call sites routed through it.

- `proc_verdict(pid, recorded_birth)` → `'live' | 'dead' | 'unknown'`:
  - `kill(pid,0)` rc=0 → proceed; **ESRCH → dead** (only proof of death);
    **EPERM → exists** (other owner; falls through to the identity check);
    other `OSError` → `unknown`.
  - birth comparison: both present + equal → `live`; both present + different →
    `dead` (pid reuse — deliberately NOT softened); **either side
    empty/unobservable → `unknown`, never `dead`**.
- `verdict(row)` wraps it; `alive(row) == verdict(row) != 'dead'` — i.e.
  **unknown behaves as live for every kill/restart decision**.
- The `lead_alive` op's inline copy of the same pattern (its subject is the
  lead session's pid, not the worker's) now calls `proc_verdict` too — same
  contract, one implementation. Contract twin: `leadv2-orphan-reaper.sh`
  `_owner_death_state` (`16efd6fa`): unknown never kills.

## 3. Measurement AFTER the fix — same probe, same machine

```
=== lib under test: … md5=270be083414f89a5c27d34959eee3d1d

[M1] baseline live pid=64170 kill-0:rc0 birth='Sun Sep 6 18:06:…' lane_alive rc=0  (expect 0)
[M2] LIVE pid=64170 … pid_start_time='' (empty) lane_alive rc=0
[M3] LIVE pid=64170 … birth() observes '' … lane_alive rc=0
[M4] root-owned LIVE pid=630 … PermissionError (EPERM) … lane_alive rc=0
[M5] DEAD pid=65175 … lane_alive rc=1  (1 is CORRECT — a real death must stay dead)
[M6] LIVE pid=64170 with MISMATCHED recorded birth … lane_alive rc=1  (1 is CORRECT)
[M7] total rows dead_at-stamped whose pid still exists: 0
```

All three false-dead paths now return live; the two correct-dead paths
(ESRCH, pid-reuse mismatch) are unchanged. Full log: `measure-after-fix.log`.

## 4. Radius — every verdict consumer, named

| Consumer | How it reaches the verdict | What changed for it |
|---|---|---|
| `hooks/leadv2-stale-pid-sweep.sh` | `lane_reconcile` (:13) — the reaper: `if not alive(row): dead_at=now()` | Live-but-unprovable rows (empty birth, EPERM, ps hiccup) are **no longer dead_at'd** → no more "restart this lane" offers for live workers. Genuinely-dead rows still reaped (M5/c5). No refusal path: reconcile rc is tolerated in the hook. |
| `leadv2-dispatch-code.sh` | `lane_reconcile` (:7311, `\|\| true`); `register` cap check; :6247 comment documents this exact false-dead symptom | Post-dispatch reconcile no longer stamps async arms dead on unprovable liveness. `register`'s lane-cap refusal (exit 3) can now count unknown rows as live — only reachable at ≥64 live lanes (founder's unlimited order; the safe direction: never free a slot on a guess). No silent skip. |
| `leadv2-lane-liveness.sh` | Reads `dead_at` (owned by lane_reconcile/lane_deregister per its :358); has its own three-answer `_ll_pid_alive` | Fewer false `dead_at` stamps upstream → fewer false "corroborated dead: pid dead" verdicts. Its own kill handling was already correct; untouched. |
| `leadv2-active-registry.sh` | Own `_pid_alive` (:322, independent of this predicate); incumbent writeset blocks key off `dead_at` | A live incumbent is no longer falsely dead_at'd → its writeset keeps blocking admission (closes the doubled-worker door from this side). Its admission refusals use its own `_pid_alive`, unchanged. |
| `leadv2-session-runner.sh` / `leadv2-codex-session-runner.sh` | `lane_deregister` in exit traps (:205/:109) | **No change**: deregister stamps `dead_at` unconditionally and never consults `alive()` (verified in source). |
| internal ops of the lib | `register` live-count (:132), recovery `live_tasks` (:251), lead lane count (:336), `alive`/`lead_alive` ops | Unknown counts as live everywhere → recovery no longer re-adopts a worktree whose lane is alive-but-unprovable; `lane_alive` rc0 on unknown (degrade to live — matches lane-liveness.sh's "never reclaim a slot on a guess"). |

## 5. The suite and its mutation matrix

`plugins/leadv2/scripts/tests/test-lane-alive-predicate.sh` — green side:
live is never dead (incl. EPERM and empty birth on either side); red side:
dead stays dead (ESRCH) and pid-reuse stays dead. The predicate has FOUR
independent verdict sources, so the negative control is FOUR single-line
mutants, each inserted INSIDE `proc_verdict`'s body (never top-level), each
expected to redden exactly its own case — a one-point mutation cannot pass
this matrix (the brief's two-readers rule).

```
$ bash plugins/leadv2/scripts/tests/test-lane-alive-predicate.sh
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
```

Mutant → case map: **A** kill-classification reverted (EPERM→dead) ⇒ c4;
**B** incomparability reverted (missing birth→dead) ⇒ c2, c3, c7; **C** ESRCH
silenced ⇒ c5; **D** mismatch silenced ⇒ c6. If a machine cannot exercise
EPERM (e.g. suite run as root), c4 and mutant-A report a loud SKIP, never a
silent pass.

## 6. leadv2-mutation-control.sh artifact

`mutation-control/20260906T151849Z-44302.txt` (committed, force-added per
precedent), produced with
`LEADV2_LANE_START_SHA=$(git rev-parse d7db3c6a^)`:

```
suite=plugins/leadv2/scripts/tests/test-lane-alive-predicate.sh
file=plugins/leadv2/scripts/lib/leadv2-lane-state.sh
anchor=s/if not recorded or not observed: return 'unknown'/if not recorded or not observed: return 'dead'/
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: c2: live pid + EMPTY recorded birth -> alive (unknown never kills), no dead_at
diff_hash=f7c160ba4390a0370c70db4f41ba2ad68cd7499553efcdfb2a2ef87243825eb3
lane_diff_hash=1bf3a08cb8c870b74686fce880e49c86208118a08d4245d40e7de1662e3646fc
```

## 7. CI selection proof (leadv2 repo — the repo the file lives in)

```
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
…
[SELECT] …/plugins/leadv2/scripts/tests/test-leadv2-lane-state.sh
[SELECT] …/plugins/leadv2/scripts/tests/test-lane-alive-predicate.sh
[SELECT] …/plugins/leadv2/tests/test-lane-state.sh
…
run-all: 172 selected, scope=changed, select_only=1
```

No `FATAL bad_trigger_decl` — triggers are base names
(`# run-all-triggers: leadv2-lane-state.sh`). The lane touches only the
leadv2 repo (no persona-engine files), so no second-repo run applies.

## 8. Falsification set

```
$ bash -n plugins/leadv2/scripts/lib/leadv2-lane-state.sh && echo "bash -n OK"
bash -n OK
$ bash -n plugins/leadv2/scripts/tests/test-lane-alive-predicate.sh && echo "bash -n OK"
bash -n OK
$ awk "/<<'PY'/{f=1;next} /^PY\$/{f=0} f" plugins/leadv2/scripts/lib/leadv2-lane-state.sh | python3 -m py_compile && echo "py_compile OK"
py_compile OK
```

Regression sweep over the existing suites of the same lib (verdict + baseline
against unmodified HEAD lib in a full scripts-dir mirror — the first
partial-mirror attempt produced garbage failures from missing sibling files
and was discarded):

```
test-single-writer-lane-state.sh           PASS (10 pass, 0 fail)
test-lane-registry-outlives-dispatcher.sh  PASS (10 pass, 0 fail)
test-leadv2-lane-state.sh                  FAIL: case5-RED only — IDENTICAL on HEAD-lib baseline
test-lane-registry-self-deadlock.sh        FAIL: (c)+(d) only  — IDENTICAL on HEAD-lib baseline
```

Both reds are pre-existing and environment-shaped, not caused by this lane:
`case5-RED` is a negative control whose fixture hardcodes bystander pids
(30132/30133) that can collide with real processes on a loaded laptop, and
the self-deadlock (c)/(d) checks depend on journal artifacts of sibling
scripts mid-edit by concurrent workers. Named here so the next lane inherits
them as known-reds, not as surprises. No suite that was green on HEAD turned
red under this fix.

## 9. Observations out of this lane's scope (for the lead)

1. **`leadv2-active-registry.sh:322` `_pid_alive` has the same disease**:
   `except (…, PermissionError): return False` — an EPERM incumbent is
   "dead", and `_lv2_ws_dead` then frees its writeset block, which can admit
   a second lane into a live incumbent's write set. Not touched here (outside
   this lane's LANE_WRITES).
2. `test-leadv2-lane-state.sh` case5-RED's hardcoded fixture pids make that
   negative control un-REDdable in this environment regardless of the lib —
   it needs its own lane.
