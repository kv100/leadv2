# Adversarial review — SUPERVISOR-RESIDUE-SWEEP-01

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/eacd0eb5`
HEAD: `ca479b6` (merge of main `53d4465` into the lane; the sweep itself is `c312ac8`)
Diff reviewed: `git diff 53d4465...HEAD`
Diff hash: `efc1dd5d878485531987e7a9c0efba5822c5c2ecfa0d656f29417bf912ab336f`
Reviewed 2026-08-20. repowise not used (per mission). Every probe below was run in
the lane worktree; a base worktree at `53d4465` was created solely to separate
pre-existing failures from regressions, and removed afterwards.

**Verdict: PASS_WITH_NITS.**

The substantive goal of the sweep is achieved: the retired supervisor mode is no
longer enterable (writer gone, all hook arms unregistered), the S3 heartbeat
block is reduced to static globals with no dangling references, and the three
dead test files are resolved. One genuine regression was introduced — a fourth
test file of exactly the class H2 was chartered to eliminate went green → red —
plus three smaller residue nits. None is on the core gate.

---

## Acceptance criteria, verified by me

### (a) zero `.supervise-active` references in `hooks/` + `scripts/` — **NOT MET AS WRITTEN**

```
$ grep -rn '\.supervise-active' plugins/leadv2/hooks/ plugins/leadv2/scripts/
plugins/leadv2/hooks/leadv2-task-anchor.sh:160:    path = control_plane_path(root, resolver, ".supervise-active")
plugins/leadv2/hooks/leadv2-supervisor-mode-reinject.sh:16,82,85,123
plugins/leadv2/hooks/leadv2-supervisor-guard.sh:6,144
plugins/leadv2/hooks/leadv2-supervise-bash-guard.sh:34
plugins/leadv2/scripts/leadv2-beat-owner.sh:26,31          (comments)
plugins/leadv2/scripts/leadv2-status-collector.sh:143
plugins/leadv2/scripts/leadv2-status-surface.sh:257,319,2624
plugins/leadv2/scripts/leadv2-lane-status-line.sh:142
plugins/leadv2/scripts/tests/… (11 further files, fixtures + assertions)
```

The literal criterion fails. **The property it was standing in for holds**, which
is what matters, and I verified it two ways:

1. **No writer survives.** The `PYSENTINEL` block, the `--enter` flag and the
   `LEADV2_SUPERVISE_ENTER` override are all gone from the one script that had
   them:
   ```
   $ grep -n -iE 'supervise-active|LEADV2_SUPERVISE_ENTER|--enter|PYSENTINEL' \
       plugins/leadv2/scripts/leadv2-lanes-snapshot.sh
   (rc=1 — no matches)
   ```
   Every remaining non-test reference is a **read**: either a
   `leadv2-state-path.sh --no-link` path resolution or an `open()`/`[ -f ]`
   probe. The only writes left in-tree are sandboxed test fixtures
   (`printf 'pid %s\n' "$$" > "${STATE_DIR}/.supervise-active"`), which write
   into a per-test `STATE_DIR`, and `test-status-surface.sh:649-657` still
   asserts none of them escapes into the real state dir.

2. **No hook arm survives.** `hooks.json` now contains zero supervisor
   registrations:
   ```
   $ grep -n 'supervis' plugins/leadv2/hooks/hooks.json
   (rc=1 — no matches)
   ```
   The diff removes all six arms the prior critic listed: pump-caller
   (UserPromptSubmit), fanout-guard (PreToolUse:Agent), sentinel-cleanup (Stop),
   and supervisor-guard on Write, Edit and NotebookEdit — the last of which took
   the whole `"matcher": "NotebookEdit"` block with it.

So H1's mechanism is dead: nothing writes the sentinel, and nothing would act on
it if something did. **See N1 below** for the residue this leaves behind.

### (b) zero `supervise-loop.heartbeat` references — **NOT MET AS WRITTEN, property holds**

```
$ grep -rn 'supervise-loop\.heartbeat' plugins/leadv2/hooks/ plugins/leadv2/scripts/
plugins/leadv2/scripts/leadv2-status-surface.sh:258:# …anymore, so this is permanently "off" — kept as
plugins/leadv2/scripts/tests/test-status-surface.sh:266,274,275,421,622,769,793,975,1017,1613,1635,1658,1736,1759
plugins/leadv2/scripts/tests/test-supervisor-reason-honest.sh:77,78,90,91,114,115,127,128
```

The only production hit is a comment. The S3 block itself is correctly reduced
(`leadv2-status-surface.sh:256-262`) from ~200 lines of liveness arithmetic to
three static globals:

```bash
SUP_STATE="off"
SUP_WHY="supervisor retired (SUPERVISOR-DELETE-01)"
SUP_SHORT="retired"
```

**No orphaned references.** I swept the renderer for every symbol the removed
block used to define: `SUP_STATE` is still read at `:1651`, `:1654`, `:1676-1679`
and `SUP_SHORT`/`SUP_WHY` at the same sites — all three remain defined, so the
`case` statements resolve to their `*)`/`off` branch rather than expanding
unset variables. `_status_single_lead_mode()` (`:319`) still tests for the
sentinel file, which nothing writes, so it now unconditionally returns 0 —
fail-open into single-lead, the correct post-retirement behavior.

`test-supervisor-reason-honest.sh` is the residue here, and it is a regression —
see N1.

### (c) three dead test files — **MET**

```
$ ls plugins/leadv2/scripts/tests/test-question-delivery-01.sh \
     plugins/leadv2/tests/test-supervise-sentinel-readonly.sh \
     plugins/leadv2/tests/test-supervise-stale-truth.sh
ls: …/test-question-delivery-01.sh: No such file or directory
ls: …/test-supervise-sentinel-readonly.sh: No such file or directory
-rw-r--r--  … plugins/leadv2/tests/test-supervise-stale-truth.sh
```

Two deleted, one retargeted (`SUPERVISE="${SCRIPT_DIR}/leadv2-lanes-snapshot.sh"`,
was `leadv2-supervise.sh`). **SUITE_DEFS is consistent**: `run-core-offline.sh`
is byte-identical across this range (`git diff 53d4465...HEAD -- …/run-core-offline.sh`
is empty), which is correct because none of the three was ever registered. No
non-docs reference to either deleted file survives; the only hits are historical
handoff records under `docs/`.

The retarget is not cosmetic — it repaired a broken suite:

| Suite | BASE `53d4465` | HEAD |
|---|---|---|
| `tests/test-supervise-stale-truth.sh` | rc=1, **0 passed, 5 failed** | rc=0, **5 passed, 0 failed** |

---

## N1 (High) — the sweep created a fourth dead test of the class it was killing

`plugins/leadv2/scripts/tests/test-supervisor-reason-honest.sh` was green before
this change and is red after it. It is not in the diff, so nobody looked at it.

| Suite | BASE `53d4465` | HEAD |
|---|---|---|
| `scripts/tests/test-supervisor-reason-honest.sh` | rc=0, **0 failures** | rc=1, **4 passed, 5 failed** |

```
[TEST] FAIL: fresh beat, no sentinel -> ON (got: supervisor: OFF  (supervisor retired (SUPERVISOR-DELETE-01)))
[TEST] FAIL: old beat, no sentinel -> STALE (got: supervisor: OFF  (supervisor retired (SUPERVISOR-DELETE-01)))
[TEST] FAIL: no beat, no sentinel -> OFF (got: supervisor: OFF  (supervisor retired (SUPERVISOR-DELETE-01)))
[TEST] FAIL: sentinel present, pid dead -> pid-gone clause (got: supervisor: OFF  (…))
[TEST] FAIL: supervised/unsupervised did not differ as expected (…)
[TEST] === 4 passed, 5 failed ===
```

This is the direct and expected consequence of replacing the S3 computation with
`SUP_STATE="off"`: the test is the regression guard for N7E-SURFACE-DISAGREES
defect 2 ("the supervisor reason string must be honest about *why* it says OFF"),
and its subject died with the supervisor. The failing assertions are exactly the
ON/STALE/pid-gone branches that can no longer be reached.

**Not a gate regression.** It is registered in no runner:
```
$ grep -rn 'reason-honest' plugins/leadv2/scripts/tests/run-*.sh plugins/leadv2/tests/
(rc=1 — no matches outside the file's own header)
```

But H2's whole point was that unrunnable, permanently-red test files are dead
readers to be swept, and this one is now precisely that — created rather than
inherited. Fix is the same disposition the sweep already applied three times:
delete it (its subject is gone), or reduce it to the single surviving assertion
that the OFF reason string is non-empty and names the retirement.

Same shape, lower stakes: `test-status-surface.sh` retains ~14 fabricated
`.supervise-loop.heartbeat` fixtures (`:266-1759`) that now set up state no code
reads. Harmless, since that suite's failures are unchanged (below), but it is
the ~10 fixtures M1 asked to sweep and they were only partly swept.

## N2 (Low) — three unregistered supervisor hook files left on disk

```
$ ls plugins/leadv2/hooks/ | grep -i supervis
leadv2-supervise-bash-guard.sh
leadv2-supervisor-guard.sh
leadv2-supervisor-mode-reinject.sh
```

All three are unregistered (see the `hooks.json` grep above) and therefore inert
— they cannot fire. But all three still read `.supervise-active` and
`mode-reinject.sh:155` still names `leadv2-supervise.sh`, a script that no longer
exists. The prior critic's H1 explicitly said "delete it with the rest". The hook
*arms* were removed, the hook *files* were not. Two live scripts also still carry
comments pointing at now-deleted hooks
(`leadv2-backlog-pump.sh:73`, `leadv2-pulse-beat.sh:59` → `leadv2-supervisor-pump-caller.sh`).

## N3 (Low) — L3 date normalization is incomplete

The founder-facing stubs are correctly normalized to **2026-08-17**
(`supervisor-role.md:3`, `SKILL.md:3,10`, `leadv2.md:72,73`). Two code comments
still stamp the decision id with 2026-08-20:

```
plugins/leadv2/scripts/leadv2-plugin-sync.sh:519:  # … SUPERVISOR-DELETE-01 (2026-08-20): the
plugins/leadv2/scripts/leadv2-status-collector.sh:104:#    …in SUPERVISOR-DELETE-01 (2026-08-20) — this call is
```

Defensible if read as the implementation date (which is honest — the commit is
from 08-19/20), but they attach that date to the *decision id*, which is what L3
asked to normalize. One-line fix or an explicit "impl 08-20, order 08-17".

## N4 (Low) — L4 fanout is a doc notice, not a refuse-stub

`commands/leadv2.md:73` now reads "**Retired 2026-08-17 …** — fanout was the
supervisor's multi-child dispatch arm; it is retired with the supervisor it
served." The mission asked for "the same refuse-stub pattern as `supervise`".
`supervise` got a real refusal — its `SKILL.md` narrows `allowed-tools` to `Read`
so the mode cannot act even if loaded. `fanout` got only prose:
`scripts/leadv2-fanout.sh` is 104,926 bytes, executable, with no stub and no
refusal at its head. The doc row is also internally inconsistent — it says
"retired" and then "remains on disk but is founder-order-only", which are two
different states. Either add the stub or say "restricted, not retired".

## N5 (informational) — `hooks.json` was re-serialized

The description line changed from a literal em-dash to `—`, i.e. the file
went through a Python `json.dump` round-trip rather than a targeted text edit.
Semantically identical, `python3 -m json.tool` parses it clean, and I confirmed
key ordering and all untouched blocks are byte-preserved in the diff. Noting it
only so a future reviewer doesn't read it as an encoding bug.

---

## Regression control — what was already broken

`test-status-surface.sh` fails, and it is **not** this change's fault. Same 22
failures, identical set, at base and at HEAD:

```
BASE fails: 22
HEAD fails: 22
=== fails only at HEAD (new) ===   (empty)
=== fails only at BASE (fixed) === (empty)
```

Root cause is environmental, not the sweep: the suite asserts against
`leadv2-status-surface.10s.sh` (`test-status-surface.sh:19`), the SwiftBar
wrapper, which does not exist anywhere in the tree
(`find . -name '*status-surface*10s*'` → nothing), so `bash -n` on it and every
badge/title assertion downstream fail. **The mission's "affected suites green"
criterion is unreachable for this suite in this environment** — it was never
green here. Worth a separate row; it means status-surface has ~22 assertions
providing no signal to anyone running the suite locally.

`test-lanes-snapshot.sh` needs a large timeout — it took over 150 s and under
420 s. My first two runs hit 100 s/110 s timeouts and looked like a hang. Given
an equal 420 s budget both trees are green and identical:

```
HEAD: [TEST] === Results: PASS=13 FAIL=0 ===   rc=0
BASE: [TEST] === Results: PASS=13 FAIL=0 ===   rc=0
```

Full suite matrix (90 s budget unless noted):

| Suite | BASE | HEAD | Read |
|---|---|---|---|
| `scripts/tests/test-lanes-snapshot.sh` (420 s) | PASS=13 FAIL=0 | PASS=13 FAIL=0 | unchanged |
| `scripts/tests/test-status-surface.sh` | 22 FAIL | 22 FAIL | pre-existing, identical set |
| `tests/test-supervise-stale-truth.sh` | 0/5 | **5/5** | **fixed by the retarget** |
| `scripts/tests/test-supervisor-reason-honest.sh` | green | **5 FAIL** | **N1 regression** |
| `scripts/tests/test-statusline-supervisor-gate.sh` | green | green | unchanged |
| `scripts/tests/test-supervisor-mode-reinject.sh` | green | green | unchanged |
| `scripts/tests/test-question-delivery-ownership-01.sh` | PASS=10 FAIL=0 | PASS=10 FAIL=0 | H2's surviving coverage intact |

## Merge-conflict resolution — correct

`leadv2-supervisor-pump-caller.sh` deleted (sweep wins over main's edit). The
deletion is right: the hook was gated on a live `.supervise-active` pid, so with
no writer it was permanently a no-op, and its `hooks.json` arm is removed in the
same diff. Nothing live calls it — the only surviving mentions are two comments
(N2) and `docs/` history.

**Nothing from main was clobbered.** The strongest evidence is the shape of the
range diff itself: `git diff 53d4465...HEAD --name-only` lists exactly the 15
sweep files and nothing else. A merge that reverted main content would show
reverting hunks in other files; there are none. Spot-checked the file named in
the merge message:

```
$ git diff 53d4465 HEAD -- plugins/leadv2/scripts/leadv2-backlog-pump.sh | wc -l
0
```

ENV-GUARDS' change to `backlog-pump.sh` is byte-identical to main. (The merge
message's phrasing "HOME-liveness change survives in backlog-pump.sh itself" is
accurate in effect, though `grep -n HOME` on that file returns nothing — the
surviving change is not literally spelled `HOME` there.)

## Mechanical gates

```
$ bash -n  (every changed .sh that still exists)
OK plugins/leadv2/hooks/leadv2-supervisor-mode-reinject.sh
OK plugins/leadv2/scripts/leadv2-lanes-resume.sh
OK plugins/leadv2/scripts/leadv2-lanes-snapshot.sh
OK plugins/leadv2/scripts/leadv2-status-surface.sh
OK plugins/leadv2/scripts/tests/test-status-surface.sh
OK plugins/leadv2/tests/test-supervise-stale-truth.sh

$ python3 -m json.tool plugins/leadv2/hooks/hooks.json  → VALID JSON OK
```

`shellcheck -S warning` over the changed scripts reports only SC2120 in
`test-status-surface.sh` — **pre-existing**, 2 occurrences at base, 2 at HEAD.

## L1 / L2 — both fixed, verified

- **L1**: `leadv2-lanes-resume.sh` now prints `[lanes-resume] unknown arg: %s`;
  `grep -n 'supervise-resume'` returns rc=1.
- **L2**: `leadv2-lanes-snapshot.sh:2` self-identifies correctly and the
  user-facing help line reads
  `Usage: leadv2-lanes-snapshot.sh [--json] [--since <ISO>] [--print]`. The one
  remaining `leadv2-supervise.sh` string (`:1058`) is inside a prose comment
  describing a historical non-inference — correct to leave.

---

## Summary table

| # | Sev | Finding |
|---|---|---|
| N1 | High | `test-supervisor-reason-honest.sh` went green → 5 FAIL. Its subject (live S3 supervisor-state derivation) was removed by this sweep. Not on the gate, but it is a newly-created dead red test — the exact class H2 existed to eliminate. Delete or reduce to the OFF-reason assertion. |
| N2 | Low | Three unregistered supervisor hook *files* left on disk (`supervisor-guard.sh`, `supervise-bash-guard.sh`, `supervisor-mode-reinject.sh`); arms removed but files kept, against the prior critic's "delete it with the rest". Inert. Plus 2 stale comments pointing at deleted hooks. |
| N3 | Low | L3 incomplete: `leadv2-plugin-sync.sh:519` and `leadv2-status-collector.sh:104` still stamp SUPERVISOR-DELETE-01 with 2026-08-20. |
| N4 | Low | L4 is a doc notice, not a refuse-stub: `leadv2-fanout.sh` (104 KB) is unmodified and executable; the doc row also says both "retired" and "founder-order-only". |
| N5 | Info | `hooks.json` re-serialized via a JSON round-trip (em-dash → `—`); parses clean, ordering preserved. |
| — | Info | `test-status-surface.sh`'s 22 failures are pre-existing and environmental (missing SwiftBar wrapper `leadv2-status-surface.10s.sh`); the mission's "status-surface green" criterion is unreachable locally. |
| — | Info | `test-lanes-snapshot.sh` needs >150 s; short timeouts look like a hang. Green on both trees at 420 s. |

**VERDICT: PASS_WITH_NITS**
**DIFF_HASH: efc1dd5d878485531987e7a9c0efba5822c5c2ecfa0d656f29417bf912ab336f**
