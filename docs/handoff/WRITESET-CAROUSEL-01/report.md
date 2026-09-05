# WRITESET-CAROUSEL-01 — report

Both rows addressed in one change to one production file, because they are one
question asked twice. Five commits, named files only, nothing pushed.

| | |
|---|---|
| `cd1a4d2e` | the fix: `_lv2_ws_live_worker()` + the gated pending branch, and the new suite |
| `dce6f3fc` | the two existing pending suites, which had pinned the bystander shape by accident |
| `a997ed75` | both negative controls, run, with their log |
| `40de2da3` | two `tests/mutations/catalog.yaml` rows |
| `cbb24fcb` | the live before/after runner and its output |

Write set: `plugins/leadv2/scripts/leadv2-active-registry.sh`,
`plugins/leadv2/scripts/tests/test-writeset-{carousel,pending-overlap,admission-block}.sh`,
`tests/mutations/catalog.yaml`, `docs/handoff/WRITESET-CAROUSEL-01/`. Nothing
outside it.

---

## The two states that were fused

The guard asked **"is this incumbent's write set undeclared?"** and, on yes,
refused with the same code and the same finality as a proven path intersection.
But an undeclared write set is *unknown* overlap, and unknown is only dangerous
when something might be writing right now. So the guard now asks the question
that actually decides the danger: **does this row have a LIVE WORKER under it?**

```python
def _lv2_ws_live_worker(other):
    pid = other.get("pid")
    if pid in (None, "", "null", "None"):
        return False
    if not _pid_alive(pid):
        return False
    return _proc_kind(pid) != "interactive"
```

- `_lv2_ws_pending(other) and _lv2_ws_live_worker(other)` → `exit 5`, unchanged.
- `_lv2_ws_pending(other)` alone → **journal the downgrade by name** and fall
  through to the pre-existing unknown policy, where `LEADV2_WRITESET_ENFORCE`
  still decides: `block` refuses with its own code 6, `warn` proceeds.

The third state routes to the unknown policy, **not past it**. That is case (4)
of the suite and it is the one I would check first if you doubt the change.

It fails **closed** on genuine ambiguity: a live pid whose kind reads `other` or
`unknown` still counts as a worker and still blocks. Only three answers release
the block, and each is a positive proof: no pid at all, a dead pid, or a live
pid that is an interactive lead.

`proc_kind` is read from the **live process**, never from the row's stored
field, so a recycled pid cannot inherit a stale classification.

### Your second row is the same predicate's second clause

`RECOVERY-ATTACHES-A-BYSTANDER-PID-TO-A-LANE-01` — you removed a row at night
that carried your **own** pid and the liveness check honestly answered "alive",
because it was. It just was not a worker. `_proc_kind()` already existed for
exactly this — `PHASE-REFUSAL-LEAVES-A-LANE-REGISTERED-01` built it because "a
recorded PID can belong to the interactive lead session rather than a worker" —
and this guard consulted neither it nor the pid at all. Same shape as the
arbiter: **the fact was already computed and simply never reached the decision.**

---

## Measured, not assumed

Live registry at the moment of the fix (`~/.claude/leadv2-state/leadv2/active.yaml`):

```
02:52Z   19 rows — 18 pid-less AND undeclared, 1 dead+declared, ZERO interactive
06:1xZ   24 rows — 22 pid-less AND undeclared
```

Every row that was refusing every dispatch in the repo had **`pid: None`** — no
process at all. And `pid: null` is not an accident: `leadv2-backlog-pump.sh:653`
and `leadv2-fanout.sh:1365` write it deliberately as a *lane reservation before
the worker exists*, and fanout's own comment says the point is to "let the row
be indistinguishable from a dead session". The writers already meant these rows
to read as not-a-live-process. The guard was the only reader that disagreed.

### Two live runs, same real registry, before and after

`docs/handoff/WRITESET-CAROUSEL-01/live-runs.sh` copies the live `active.yaml`
into a scratch state root and drives the real `leadv2_active_register` twice —
once with the registry file at `cd1a4d2e^`, once at HEAD. Nothing is written to
the live registry. Full output in `live-runs.log`.

**Candidate declaring `leadv2-active-registry.sh` (a real overlap exists):**

```
BEFORE  rc=5  [registry] writeset conflict: other=3e1922c7 reason=pending_resolution writes_reason=undeclared
AFTER   rc=5  [registry] writeset pending downgraded: other=3e1922c7 reason=no_live_worker pid=None proc_kind=no_pid
              ... same for ARM-CAPABILITY-FROM-OUTCOMES-01, daeee945, de4fcc31
              [registry] writeset conflict: other=RECOVER-WAVE1-TEN-01 paths=plugins/leadv2/scripts/leadv2-active-registry.sh
```

Both refuse — and that is the point. Before, the refusal named a row with no
process and no known write set. After, it names **the actual conflicting path
and the actual lane holding it**. (That lane is `RECOVER-WAVE1-TEN-01`, the one
your measurement caught being refused three times. It now legitimately holds
this file, and the message says so.)

**Candidate declaring only its own report file (overlaps nothing):**

```
BEFORE  rc=5  refused — on 3e1922c7, reason=pending_resolution
AFTER   rc=0  ADMITTED
```

That is the carousel in one pair of lines: a lane whose write set intersected
**nothing at all** was refused, by a row with no process, for a reason that was
never about overlap.

---

## The five requirements

**1. A real function under the claim.** All six cases of
`test-writeset-carousel.sh` seed real YAML rows in the real wire format into a
scratch `LEADV2_STATE_ROOT` and drive the real `leadv2_active_register`. The
fake is one level lower — the *processes*: case 2 uses a genuinely live pid,
case 3 spawns a real process whose argv reads as an interactive lead. Nothing
stubs `_lv2_ws_live_worker`, `_lv2_ws_pending`, `_pid_alive`, `_proc_kind` or
the register op.

```
a write-less incumbent with NO process no longer refuses (and the downgrade is journaled)
a write-less incumbent WITH a live process still refuses (rc=5, pending_resolution)
a live LEAD pid attached to a lane no longer holds the lock (proc_kind=interactive)
the downgrade lands in the unknown policy, not past it (enforce=block still refuses, rc=6)
a PROVEN path overlap still refuses, pid or no pid (paths= named)
the live 02:52Z registry shape (5 young pid-less rows) stops blocking, and all 5 are named
[WRITESET-CAROUSEL] pass=6 fail=0
```

**2. Negative controls — run, by regex, inside the function body**, on a scratch
copy of `plugins/leadv2/scripts` (never the shared canonical tree):

| control | mutation | result |
|---|---|---|
| `WRITESET-PIDLESS-ROW-COUNTS-AS-A-WORKER` | `/if pid in (None, "", "null", "None"):/{n;s/return False/return True/;}` | **3 red** — 1, 4, 6. Case 3 and the two guard cases stay green. |
| `WRITESET-BYSTANDER-LEAD-COUNTS-AS-A-WORKER` | `s/return _proc_kind(pid) != "interactive"/return True/` | **1 red** — 3, only. Every no-process case stays green. |

The two are disjoint: neither can pass for the other's reason. Artifacts:
`mutation-control/run.sh`, `mutation-control/negative-controls.log` (each mutated
line printed in the context of its function), plus two
`leadv2-mutation-control.sh` runs, both `MUTATION-CONTROL ok`
(`diff_hash=4df6337d…`, `128d007a…`).

**3. Catalog rows.** `writeset-pidless-row-counts-as-a-worker` and
`writeset-bystander-lead-counts-as-a-worker`. Counted after the append: **17
entries, all `expected: killed`** — counted, not carried.

**4. CI selection, proven from the PRODUCTION file.** Runner state advanced to
HEAD so only working-tree dirt counts; the dirt was one comment appended to
`leadv2-active-registry.sh`, reverted in the same command.

```
CONTROL — tree clean:               50 selected, no writeset suite among them
PROOF   — registry dirty ONLY:      53 selected, including
          test-writeset-carousel.sh, test-writeset-pending-overlap.sh,
          test-writeset-admission-block.sh
```

**A gap found on the way, and closed.** `test-writeset-admission-block.sh` had
**no trigger line and appeared in no `EXTRA_SUITE_MAP` row** — nothing selected
it, ever. It was green for weeks while CI never ran it against the file it
tests. It now self-registers on `leadv2-active-registry.sh`, and the second
proof run above shows it appearing. (That one-line change was staged when
another session's merge landed; its content is in HEAD, swept into merge commit
`4ee5bc8d` rather than a commit of mine.)

**5. Suite state, before and after.**

| suite | before | after |
|---|---|---|
| `test-writeset-pending-overlap.sh` | 7 / 0 | **7 / 0** |
| `test-writeset-admission-block.sh` | 7 / 0 | **7 / 0** |
| `test-writeset-carousel.sh` | did not exist | **6 / 0** |

Three cases in the two existing suites went red on the fix, and they were right
to: **they had pinned the bystander shape by accident.** Each registers its
incumbent from inside the suite's own process, so `_lv2_durable_pid` — which
walks the PPID chain to the nearest `claude` — stamps the pid of the
*interactive session running the suite*. That is precisely the row the guard now
downgrades, so the cases would have gone green for the wrong reason had I
changed the assertions. Instead each now stamps a genuinely worker-shaped
process onto its incumbent, and keeps testing the race it was written for.
Nothing about the guard is faked in that repair.

---

## Where I stopped, and one residual risk you should hold me to

- **The residual.** If a production path ever calls `leadv2_active_register`
  with an undeclared write set from *inside a lead's own process tree*, that row
  will now be downgraded rather than blocking. I measured the live registry
  before deciding — 24 rows, **zero** carrying an interactive pid, 22 carrying
  none at all — so no real guard is being relaxed today. The exposure is bounded
  by design: downgrade is not admission, and `LEADV2_WRITESET_ENFORCE=block`
  still refuses these rows with code 6.
- **The row's immortality in the stale sweep is NOT fixed.** I changed only what
  the write-set guard concludes from a bystander pid. A row carrying a lead's
  pid still looks alive to `_pid_alive` everywhere else. Teaching the sweep to
  call such a row dead would delete rows for lanes genuinely registered under a
  lead pid, which is a different and larger decision — named, not taken.
- **`_pid_alive` returns False on `PermissionError`.** EPERM means the process
  exists and is not ours; treating it as dead errs permissive. Untouched here
  because it is not this defect, but it is the same family and worth a row.

---

## An accidental negative control I did not plan

Mid-lane, a neighbouring session ran a suite census, saw `leadv2-active-registry.sh`
modified, took my uncommitted fix for the residue of a vandal suite, and ran
`git checkout --` on it. Before anyone knew, I ran my own suite against the
reverted file: **exactly cases 1, 3, 4 and 6 went red, and only those** — the
four the fix changes — while 2 and 5 stayed green. That is a cleaner control
than either of the ones I authored, and it is the strongest single piece of
evidence in this report that the suite measures the fix and nothing else.

The root cause of that incident belongs in this report because it is the same
disease one layer up: `test-fp07-codex-rg-no-match.sh:35` writes its mock over
the real `codex-task.sh` (2146 lines → 16) and its `cleanup()` only removes its
own temp dir. A watcher then cannot tell a live edit from suite residue — and,
exactly like the write-set guard, **a mechanism that cannot distinguish unknown
from bad chooses the destroying interpretation.** The guard refused; the watcher
reverted. Both were reading unknowledge as a verdict.

The operational lesson I have adopted for the rest of the session: in a shared
tree, commit after every edit that would be painful to lose, not after every
finished piece. This lane is five commits for that reason.
