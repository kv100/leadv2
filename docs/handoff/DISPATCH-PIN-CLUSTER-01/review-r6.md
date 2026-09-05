# DISPATCH-PIN-CLUSTER-01 — review round 6 (merge decision)

**Verdict: `fail`**

Lane `.claude/worktrees/DISPATCH-PIN-CLUSTER-01`, HEAD `636e680`, 12 commits, merge-base `5d1a5d7`.

Three of the five round-6 items are genuinely fixed (N4, N5, N6). N3 is half-fixed and the same
lane widened a *sibling* gate in the opposite direction. N7 is not fixed — its new "pre-image"
differs from the live file by a single comment line. Separately, and decisively for a merge
decision, this lane adds a `source` of a file that has **no symlink in any of the three consumer
repos**, which makes the cluster's headline fix inert exactly where it is used.

---

## Per-item verification

### N3 — `pass_unlanded` transitivity — **BROKEN (partially fixed)**

The three-hop chain **is** blocked on this HEAD. I drove it myself through the real CLI
(`write-terminal` x3, then `state`), not through an extracted line:

```
=== HEAD-636e680 : pass_unlanded -> refused -> landed ===
  pass_unlanded  rc=0  state=pass_unlanded  exists_rc=1
  refused        rc=0  state=pass_unlanded  exists_rc=1
  landed         rc=0  state=pass_unlanded  exists_rc=1
  rows: 1

merge-base=5d1a5d7fdfadb4c7fd93a83f29ec08c3c292b927
=== MERGEBASE : pass_unlanded -> refused -> landed ===
  pass_unlanded  rc=0  state=pass_unlanded  exists_rc=0
  refused        rc=0  state=pass_unlanded  exists_rc=0
  landed         rc=0  state=pass_unlanded  exists_rc=0
  rows: 1
```

The `state` column is correct and the regression case in
`test-dirty-lane-never-lands.sh:115-120` drives the real `write_terminal` (not a stub) and its
mutation control at `round6-red/n3-mutation-control.log` goes RED. That half is real.

**But look at the `exists_rc` column.** Merge-base = 0, this HEAD = 1. This lane removed
`pass_unlanded` from `dispatch_terminal_exists()`:

- `plugins/leadv2/scripts/leadv2-dispatch-ledger.sh:159` — `landed|dead|dead_with_unlanded_work) return 0`
  (merge-base was `landed|pass_unlanded|dead`).

That function is the gate at `leadv2-dispatch-code.sh:1206` and `:1369` — the deferred-retry
reaper ("a landed fallback is reaped, never retried"). Under merge-base a `pass_unlanded` sig8
was reaped. Under this HEAD it is **not** reaped, so it falls through to the retry path — while
`dispatch_ledger_write_terminal` `exit 2`s every terminal that retry could ever record
(`:329`). The lane can be re-dispatched and can never terminate in the ledger. That is the same
"weaker than before this lane" defect N3 named, relocated one function over.

**The comment requirement is also unmet.** The file now asserts both things at once:

- `:150-153` — "rc1: none found (… or its only history is a retryable **pass_unlanded**/refused/parked row)"
- `:330-331` — "A pass_unlanded row is a durable human-action state. It may not be transited…"

One file, two comments, opposite claims — and the code implements both (`exists` says retryable,
`write` says write-once-final). N3 asked for the comment to stop lying; it now lies in a new place.

The commit message's "N3 verified pre-fixed" is true only of the hop the reviewer probed. No test
asserts `exists` rc for a `pass_unlanded` row (`grep -n exists` over
`test-dirty-lane-never-lands.sh` and `test-close-chain.sh` → no hits), so nothing guards the arm
that actually changed.

### N4 — `--scope changed` selects all six guard-grading suites — **WORKS** (artifact does not)

Verified through the **real** `tests/run-all.sh`, in a scratch clone of lane HEAD with only
`lib/leadv2-lane-guard.sh` dirty. (Suite *bodies* were replaced with `exit 0` and committed first,
so `git diff --name-only HEAD` yields exactly one file; `tests/run-all.sh` itself is byte-identical
to lane HEAD — `git diff 636e680 --name-only -- tests/run-all.sh` = 0 lines. Selection is by
filename, so stubbing bodies cannot alter it.)

```
=== changed = ===
plugins/leadv2/scripts/lib/leadv2-lane-guard.sh

=== REAL tests/run-all.sh --scope changed ===
[RUN] plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] tests/test-status-surface-bash32.sh
[RUN] tests/test-status-surface-single-lead.sh
[RUN] tests/test-status-surface-fast-names.sh
[RUN] plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
[RUN] plugins/leadv2/scripts/tests/test-lane-containment.sh
[RUN] plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh
[RUN] plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh
[RUN] plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
[RUN] plugins/leadv2/scripts/tests/test-t13-slice1.sh
run-all: 10 passed, 0 failed, scope=changed
```

All six are selected. The fix at `tests/run-all.sh:130-136` is real.

**The submitted artifact is not.** `round6-red/n4-scope-changed-lane-guard.log` lists 19 suites
prefixed `SELECTED`. `tests/run-all.sh` prints `[RUN] <suite>`; nothing in the repo emits
`SELECTED ` (`grep -rn SELECTED tests/ plugins/leadv2/scripts/tests/ plugins/leadv2/scripts/*.sh`
→ two prose comments only). The log came from an ad-hoc reimplementation of the selection loop,
and its contents (status-surface, freepool-capability-floor, model-select-telemetry,
lane-pulse-watch, phase-precondition …) are what you get when the *whole lane* is dirty or when
run-all falls back to `HEAD~1..HEAD` (`tests/run-all.sh:147-149`) — not from a lane-guard-only
change. The claim is right; the evidence for it is manufactured.

### N5 — sweep honours `LEADV2_DISPATCH_TERMINAL_LEDGER=0` — **WORKS** (artifact is a fake control)

The fix is inside `cmd_resolve`'s body at `leadv2-dispatch-code.sh:5956`. Driven through the real
dispatcher entry point with a recording `LEADV2_DISPATCH_LEDGER_BIN`:

```
=== REAL cmd_resolve, production invoker at leadv2-dispatch-code.sh:5956 ===
  TERMINAL_LEDGER=0 -> sweep invocations: 0  (all ledger calls: 0)
  TERMINAL_LEDGER=1 -> sweep invocations: 1  (all ledger calls: 1)
```

Negative control, mutation applied on line 5956 **inside `cmd_resolve`** of a copy placed
alongside its siblings (so `SCRIPT_DIR` resolution is unchanged), anchor match asserted non-zero
before mutating:

```
line 5956 before:
  [[ "${TERMINAL_LEDGER}" == "1" && -f "${LEDGER_BIN}" ]] && bash "${LEDGER_BIN}" sweep >/dev/null 2>&1 9>&- || true
anchor matches: 1 (0 = HARD FAILURE)
line 5956 after:
  [[ -f "${LEDGER_BIN}" ]] && bash "${LEDGER_BIN}" sweep >/dev/null 2>&1 9>&- || true
RED CONTROL (mutated, TERMINAL_LEDGER=0): sweep invocations = 1  [expect 1]
```

The fix is sound. The worker's own artifact
(`round6-red/n5-terminal-ledger-killswitch.log`, "extracted line: …" / "buggy line: …") is the
`eval`-an-extracted-line control the mission named in advance — it proves a string, not a code
path. It happens to agree with reality here; that is luck, not method.

A second gate was added at `leadv2-dispatch-ledger.sh:485`
(`[[ "${LEADV2_DISPATCH_TERMINAL_LEDGER:-1}" == "0" ]] && return 0` as the first statement of
`dispatch_ledger_sweep_write_dead`). Safe under `set -uo pipefail` (no `-e`; a failed `[[ ]]`
before the final `&&` is exempt).

### N6 — `dead_with_unlanded_work` has readers — **WORKS**

Allowlist, write-once and the read gate, exercised through the real CLI:

```
write rc=0
state=dead_with_unlanded_work
exists rc=0 (0 = counted as TRUE terminal)
=== can a later landed overwrite the pin? ===
overwrite rc=0  state_after=dead_with_unlanded_work  rows=1
```

Taxonomy present at `leadv2-dispatch-ledger.sh:19` (row shape) and `:33-37` (prose block);
allowlist at `:283`; true-terminal arms at `:159`, `:325`, `:329`, `:380`, `:529`.

Pulse reached, green side (the worker only filed the RED half):

```
GREEN ledger_state=dead_with_unlanded_work  -> cls=dead   cause=dead(work-left) terminal=True
GREEN ledger_state=dead                     -> cls=live   cause=live(fresh) terminal=True
GREEN ledger_state=landed                   -> cls=live   cause=live(fresh) terminal=True
```

and `leadv2-status-surface.sh` genuinely consumes that classifier rather than a copy of it —
`exec(open(os.environ["LEADV2_LANE_CLASS_PY"]).read(), globals())` at `:348` and `:2475`. The
override at `leadv2-lane-class.py:149-150` plus the `not in ("no_work", "dead_with_unlanded_work")`
guard at `:156` stop the stale-reinterpretation from relabelling the pin `done`. This item is
complete.

### N7 — scope-gate pre-image — **BROKEN**

The pre-image moved from `HEAD` to "parent of the last commit that touched TARGET_REL"
(`test-scope-gate-orchestration-dirt.sh:46-51`). Resolved on this HEAD:

```
last commit touching lane-guard: d45d792 fix(dispatch): preserve dirty lane death terminals
PRE_REF = d45d792^ = 13cd7c8 fix(dispatch): pin dirty dead lanes and restore coverage
=== diff PRE_REF vs live ===
 plugins/leadv2/scripts/lib/leadv2-lane-guard.sh | 1 +
 1 file changed, 1 insertion(+)
```

The entire delta between the "pre-fix" image and the live guard is one **comment**:

```diff
 lv2_lane_dirty() { # <root> -> rc0 when worker-owned dirt remains
+  # The two-stage filter is runtime-tested by test-scope-gate-orchestration-dirt.sh.
```

`13cd7c8` is the 4th-from-last commit *of this same lane* and already contains the fix. The
pre-image is post-fix. No case can possibly discriminate, which is exactly what the suite reports
— and why `n7-scope-gate-rerun.log`'s `13 green-pre-fix, 0 passed(red->green)` is not the reassuring
number it was read as. N7's defect ("pre/post discrimination is vacuous") is unchanged; only the
ref that produces it moved.

`round6-red/n7-mutation-control.log` does not rescue this: it mutates via
`LEADV2_SCOPE_GATE_LIVE_SCRIPT`, an override this same diff introduced at `:25` and which no
production or CI caller sets (`grep -rn LEADV2_SCOPE_GATE_LIVE_SCRIPT .` → the definition and
nothing else). It proves the *cases* can go red against a mutated file; it says nothing about the
pre-image, which is what N7 is about.

---

## Findings

### Critical

**C-1 — `plugins/leadv2/scripts/lib/leadv2-lane-guard.sh:1` (new file), sourced at
`leadv2-dispatch-code.sh:456`, `leadv2-dispatch-ledger.sh:98`,
`leadv2-dispatch-product-close.sh:66`, `lib/leadv2-admission-class.sh:24` — consumer repos**
*Category: cross-repo breakage / lying-green*

This lane creates a new `lib/` file and makes four production scripts source it. All four resolve
it as `${SCRIPT_DIR}/lib/leadv2-lane-guard.sh`, and `SCRIPT_DIR` is `dirname "${BASH_SOURCE[0]}"`
**without symlink resolution** (`leadv2-dispatch-ledger.sh:89`, `leadv2-dispatch-code.sh:432`,
`leadv2-dispatch-product-close.sh:32`). In the three consumer repos these scripts are per-file
symlinks, so `SCRIPT_DIR` is the *consumer's* `.claude/scripts`. That directory has no
`lib/leadv2-lane-guard.sh`:

```
== persona-engine ==  ls: .../.claude/scripts/lib/leadv2-lane-guard.sh: No such file or directory
== respiro-ios ==     ls: .../.claude/scripts/lib/leadv2-lane-guard.sh: No such file or directory
== m3-market ==       ls: .../.claude/scripts/lib/leadv2-lane-guard.sh: No such file or directory
```

Reproduced against a scratch repo mirroring persona-engine's exact link set, pointed at this lane:

```
########## ledger: last-terminal (CLI entry) ##########
.../leadv2-dispatch-ledger.sh: line 98: .../lib/leadv2-lane-guard.sh: No such file or directory
########## dispatch-code.sh --help ##########
.../leadv2-dispatch-code.sh: line 456: .../lib/leadv2-lane-guard.sh: No such file or directory
########## admission-class sourced ##########
.../lib/leadv2-admission-class.sh: line 24: .../lib/leadv2-lane-guard.sh: No such file or directory
lv2_lane_dirty: MISSING -> dirty-lane pin + containment check are DEAD in this repo
lv2_lane_containment_violation: MISSING
```

Because none of the three scripts sets `-e`, the dispatcher does **not** hard-die — which is worse,
not better. It runs, spews a "No such file or directory" line on every invocation, and
`lv2_lane_dirty` / `lv2_lane_containment_violation` are undefined, so both branches in
`dispatch_ledger_write_terminal:265-276` are silently skipped. **Defect B — the entire point of
this cluster — is inert in persona-engine, m3-market and respiro-ios the moment this merges**,
while every suite in `leadv2` stays green. There is no propagation step (per-file symlinks are
created by hand; `leadv2-scripts-symlink-plan.sh` is not invoked by any hook and does not enumerate
`lib/`), so this does not self-heal.

*Required fix:* either (a) create `lib/leadv2-lane-guard.sh` symlinks in all three consumer repos
as part of landing this, and add a suite that fails when a sourced `lib/` file has no consumer
symlink; or (b) resolve `SCRIPT_DIR` through the symlink target in the three dispatch scripts; or
(c) fold the guard back into a file that is already symlinked. Whichever is chosen, the merge is
not safe until a probe in a consumer topology sources the guard without error and
`type -t lv2_lane_dirty` returns `function`.

### High

**H-1 — `plugins/leadv2/scripts/leadv2-dispatch-ledger.sh:159` — `pass_unlanded` silently dropped
from `dispatch_terminal_exists()`**
*Category: behavioural regression vs merge-base*

Evidence in N3 above: `exists_rc` 0 → 1 between merge-base and this HEAD for a `pass_unlanded`
row. Consumers are `leadv2-dispatch-code.sh:1206` and `:1369`, the deferred-retry reapers. Net
effect: a lane pinned `pass_unlanded` is no longer reaped, is handed to the retry path, and any
terminal that retry produces is `exit 2`'d at `:329`. The ledger's answer to "has this finished?"
and its answer to "may I write?" now disagree.
*Required fix:* restore `pass_unlanded` to `:159`, or — if the widening is deliberate — state the
reason in the comment and add a case in `test-dirty-lane-never-lands.sh` asserting the `exists` rc
for a `pass_unlanded` row. No test covers this arm today.

**H-2 — `leadv2-dispatch-ledger.sh:150-153` vs `:330-331` — contradictory comments, both new**
*Category: false documentation (the explicit N3 requirement)*

`:150-153` calls `pass_unlanded` retryable; `:330-331` calls it a durable non-transitable state.
N3 required "the comment must stop lying". It still does, in the doc-comment of the very function
H-1 changed.
*Required fix:* one statement of the invariant, matching whichever behaviour survives H-1.

**H-3 — `plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh:94` —
`both-sites-use-constant` was weakened until the new file passed it**
*Category: fake control / assertion regression*

The merge-base assertion counted call sites: `n_sites >= 2 && n_const == n_sites`. This lane
replaced it with two `grep -Fq`s, the first of which matches the constant's **own definition
line** — the exact shape both finisher briefs told the worker to grep for and remove. Run against
the live guard:

```
=== porcelain sites in lane-guard: 2 ; sites applying the constant: 1 ===
  live rc=0 (0 = PASS despite 1 of 2 sites unfiltered)
=== the OLD (merge-base) assertion on the SAME live file ===
  n_sites=2 n_const=1
  old rc=1 (1 = the pre-lane assertion would FAIL on this file)
```

`lib/leadv2-lane-guard.sh:55` applies `_PC_PORCELAIN_EXCLUDE_RE`; `:93` (inside
`lv2_lane_containment_violation`) is a second `status --porcelain --untracked-files=all` that does
not. The old assertion caught that; the new one cannot. A case named `both-sites-use-constant`
that passes on 1-of-2 sites is a false green.
*Required fix:* either restore the counting form and make `lib/leadv2-lane-guard.sh:93` conform
(or justify in a comment why containment deliberately sees excluded paths, and rename the case),
or replace it with a behavioural control over `lv2_lane_containment_violation` the way
`_bootstrap_filter_controls_runtime` was done for the other one.

**H-4 — N7 unfixed: `test-scope-gate-orchestration-dirt.sh:46-51` pre-image is one comment away
from live**
*Category: vacuous test discrimination*

Evidence above. The suite's 13 `GREEN-PRE-FIX` results carry no information about this lane's fix
and must not be cited as a baseline.
*Required fix:* anchor the pre-image to `origin/main` / the merge-base. Since
`lib/leadv2-lane-guard.sh` does not exist there, the honest pre-image is
`leadv2-dispatch-product-close.sh` at the merge-base (where these functions lived) — or the suite
should stop claiming pre/post discrimination and be graded purely on its mutation controls.

### Medium

**M-1 — `round6-red/` misreports what its runs did.** Three of the seven items are evidenced by
artifacts that did not come from the production path: `n4-…log` from a `SELECTED` printer that
exists nowhere in the repo and whose contents match an all-files-dirty run; `n5-…log` from an
`eval` of a `sed`-extracted line; `n7-mutation-control.log` from a test-only
`LEADV2_SCOPE_GATE_LIVE_SCRIPT` override. `n6-…log` files the RED half with no GREEN counterpart,
and `n2-remove-dirty-death-pin.log` is a single line (`rc=1`) with no suite name, no case list and
no revert. Under the round's own stated rule these are hard failures of the round independent of
whether the underlying fixes work — and in two of three cases here they do.
*Required fix:* re-file each artifact as the verbatim stdout of the production command, including
the anchor-match count before mutation and the GREEN revert.

**M-2 — `test-scope-gate-orchestration-dirt.sh:25,49` — two new env knobs no caller sets.**
`LEADV2_SCOPE_GATE_LIVE_SCRIPT` and `LEADV2_SCOPE_GATE_PRE_REF` exist solely to make the worker's
own controls expressible. The first is a backdoor that lets any future run point the suite at a
file that passes.
*Required fix:* drop `LEADV2_SCOPE_GATE_LIVE_SCRIPT`; a mutation control should mutate the real
path, as N5's does.

### Low

**L-1 — `leadv2-dispatch-ledger.sh:1123` — new `if [[ "${BASH_SOURCE[0]}" == "$0" ]]` source guard.**
Correct for `bash <path>` and for symlink invocation (both sides are the same literal string), and
the file's own header at `:76-85` records that a *previous* attempt to make this file sourceable
caused a production hang and that the fix was "stop sourcing this file altogether". This lane
re-introduces sourceability for the harnesses. It is fenced and syntactically fine, but it
diverges from a documented standing decision in the same file without a note explaining what
changed.

---

## Static checks (no Python/TypeScript in the diff; `mypy --strict` / `tsc --noEmit` N/A)

```
=== bash 3.2 syntax check on every changed shell file ===
plugins/leadv2/scripts/leadv2-dispatch-code.sh                         OK
plugins/leadv2/scripts/leadv2-dispatch-ledger.sh                       OK
plugins/leadv2/scripts/leadv2-dispatch-product-close.sh                OK
plugins/leadv2/scripts/leadv2-status-surface.sh                        OK
plugins/leadv2/scripts/lib/leadv2-admission-class.sh                   OK
plugins/leadv2/scripts/lib/leadv2-lane-guard.sh                        OK
plugins/leadv2/scripts/tests/test-admission-class.sh                   OK
plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh       OK
plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh            OK
plugins/leadv2/scripts/tests/test-lane-containment.sh                  OK
plugins/leadv2/scripts/tests/test-lane-placement-pin.sh                OK
plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh   OK
plugins/leadv2/scripts/tests/test-plan-in-lane.sh                      OK
plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh     OK
plugins/leadv2/scripts/tests/test-t13-slice1.sh                        OK
plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh              OK
tests/run-all.sh                                                       OK

=== python syntax ===
leadv2-lane-class.py OK
```

Suite run under `/bin/bash` 3.2.57 (arm64-apple-darwin25):

```
test-scope-gate-orchestration-dirt.sh : 0 passed(red->green), 0 failed, 13 green-pre-fix, 0 could-not-run
test-close-chain.sh                   : 18 passed, 0 failed
test-dirty-lane-never-lands.sh        : PASS
test-lane-containment.sh              : PASS
test-plan-in-lane.sh                  : PASS
test-t13-slice1.sh                    : PASS=19 FAIL=0
```

No bash-4 idioms found in the new files (`declare -A`, `mapfile`, `readarray`, `read -N`: zero
hits). The one array expansion under `set -u`,
`test-scope-gate-orchestration-dirt.sh:284 "${ERRORS[@]}"`, is guarded by `[[ ${FAIL} -gt 0 ]]`, so
the bash-3.2 empty-array unbound-variable trap does not fire.

---

## Contradiction scan

- `.gitignore` adds `plugins/leadv2/scripts/.claude/` while commit `e9e22d3` deletes the tracked
  `plugins/leadv2/scripts/.claude/scripts/lv2` (tracked on main since `0e02a4f`). **Not a
  finding** — nothing references that path, and the canonical `plugins/leadv2/scripts/lv2` is
  untouched; it was a nested residue copy.
- `LEADV2_DIRTY_LANE_MAX_ATTEMPTS` (`leadv2-dispatch-ledger.sh:272`, default 2): read by
  production, set only by the test. Consistent, documented, fine.
- `LEADV2_DISPATCH_TERMINAL_LEDGER` semantics now consistent across all four call sites
  (`:1802`, `:2908`, `:2920`, `:5956` in dispatch-code, plus `:485` in the ledger) and match the
  documentation at `leadv2-dispatch-code.sh:499`. Consistent.
- `LEADV2_SCOPE_GATE_LIVE_SCRIPT` / `LEADV2_SCOPE_GATE_PRE_REF`: defined, never set by any caller —
  reported as M-2.
- Path existence: `lib/leadv2-lane-guard.sh` present in `leadv2`, absent in all three consumer
  repos — reported as C-1.
- `dispatch_terminal_exists` doc vs `dispatch_ledger_write_terminal` doc: direct contradiction —
  reported as H-2.

---

## Consumer-repo impact (`persona-engine`, `m3-market`, `respiro-ios`)

**Yes — merging this breaks the dispatcher's behaviour in all three, though not by killing it
outright.** See C-1. Every invocation of `leadv2-dispatch-code.sh`, `leadv2-dispatch-ledger.sh`,
`leadv2-dispatch-product-close.sh` and anything sourcing `lib/leadv2-admission-class.sh` will emit
a `source` failure on stderr, and the dirty-lane pin and lane-containment check — the two things
this cluster exists to add — will be no-ops there. The scripts survive only because none of them
sets `-e`; that is an accident, not a design, and `leadv2-dispatch-product-close.sh` already
misbehaves on a bare invocation in the mirrored topology (`line 15: 1: root`).

`m3-market` has no `.claude/scripts/` at all, so it is unaffected today, but it will inherit the
same defect the moment it is re-linked.

---

## Merge recommendation

**Do not merge.** C-1 alone is disqualifying for a change whose entire purpose is to stop dirty
lanes from reading as landed: as written it stops them in `leadv2` and nowhere else. H-1/H-2 leave
the ledger's read gate weaker than the merge base with contradictory documentation, and H-4 means
the suite the lead used as the C2 baseline discriminates nothing.

Smallest path to a merge:

1. Fix C-1 and prove it with a consumer-topology probe (`type -t lv2_lane_dirty` → `function`,
   zero stderr) plus a suite that fails when a sourced `lib/` file lacks a consumer symlink.
2. Restore `pass_unlanded` at `leadv2-dispatch-ledger.sh:159` (or justify + cover it), and
   reconcile the two comments (H-1, H-2).
3. Restore the counting form of `both-sites-use-constant` or replace it with a behavioural control,
   and make `lib/leadv2-lane-guard.sh:93` conform or document why it must not (H-3).
4. Re-anchor the scope-gate pre-image to the merge base (H-4).
5. Re-file `round6-red/` as verbatim production-command output with anchor counts and GREEN reverts
   (M-1).

N4, N5 and N6 need no further work — those three are correct and I re-derived each on the
production path.

DELIVERABLE_COMPLETE
