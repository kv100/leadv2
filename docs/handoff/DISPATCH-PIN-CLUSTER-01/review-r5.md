status: fail
reviewer_says: do_not_merge

# DISPATCH-PIN-CLUSTER-01 — adversarial review, round 5

Reviewed lane `.claude/worktrees/DISPATCH-PIN-CLUSTER-01`, HEAD `13cd7c8`, 9 commits over
merge-base `5d1a5d7`. Everything below was **executed**. All mutations were applied to scratch
copies under `/private/tmp/.../scratchpad/{mb,mut,r5,fixB,fixC,inv,chain,chain2}`; the lane's
`plugins/`, `tests/` and `.gitignore` are byte-unchanged by this review:

```
$ git status --porcelain --untracked-files=all -- plugins tests .gitignore
  (empty)
```

Type-checker note: this repo is `/bin/bash` 3.2.57 shell — `mypy`/`tsc` do not apply. The
equivalent gate is `bash -n` on every changed file, run below, all clean.

Interpreter: `GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)`.

---

## Verdict per owed finding

| # | Finding | Verdict |
|---|---------|---------|
| C3 | dirty-lane control inert (`! grep -Fq`) | **FIXED** |
| C2 | four suites back at pre-lane counts | **NOT FIXED** (3 of 4; scope-gate silently lost 4 cases) |
| H8 | close-chain 18/0 | **FIXED** (but the restored semantics are weaker than merge-base — H-new-2) |
| B | commit-not-an-obligation | **FIXED — mechanism proven end-to-end** (with two Highs attached) |
| H9 | `--scope changed` maps both dispatcher files | **FIXED** (and immediately re-broken for `lib/leadv2-lane-guard.sh` — H-new-3) |
| C1 | `.gitignore` + no tracked residue | **FIXED** |

---

### C3 — FIXED

`plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh:89-92` now captures the grep in an
`if` and `exit 1`s. Proven by reinserting the r4 defect (MUT-A: revert
`_PC_BOOTSTRAP_PREFIX_RE` at `lib/leadv2-lane-guard.sh:6` to the pre-fix trailing-slash-only
form) in a scratch copy and running the suite via `LEADV2_TEST_ROOT`:

```
--- line6 after MUT-A ---
_PC_BOOTSTRAP_PREFIX_RE='^\.claude/(commands|scripts|agents)/'
=== RUN with MUT-A ===
bootstrap-symlink-only lane was classified as unscoped work
MUT-A rc=1
=== RUN restored ===
PASS: terminal funnel and CLOSE gate downgrade worker dirt, permit bootstrap-only lanes, bound retries, and name a dead dirty lane
restored rc=0
```

Second, independent mutation INSIDE the function body (MUT-B: delete
`| _pc_drop_bootstrap_dirt "${root}"` from `lv2_lane_dirty`, `lib/leadv2-lane-guard.sh:54`) also
goes RED: `bootstrap-symlink-only lane was classified dirty`, `MUT-B rc=1`.

### C2 — NOT FIXED

Measured baseline by extracting merge-base `5d1a5d7` into a scratch git repo and running each
suite there. Lane HEAD run in the lane.

| suite | merge-base | lane HEAD | verdict |
|---|---|---|---|
| `test-t13-slice1.sh` | `PASS=19 FAIL=0` | `PASS=19 FAIL=0` | restored |
| `test-merged-sweep-orchestration-dirt.sh` | `0 failed, 8 green-pre-fix` | `0 failed, 8 green-pre-fix` | restored |
| `test-worktree-lane-safety.sh` | `11 passed, 0 failed, 13 green-pre-fix` | `11 passed, 0 failed, 13 green-pre-fix` | restored |
| `test-scope-gate-orchestration-dirt.sh` | `0 failed, 13 green-pre-fix, 0 could-not-run` | `0 failed, 9 green-pre-fix, **4 could-not-run**` | **regressed** |

The four missing cases are precisely the ones that exercise lane dirtiness — the load-bearing
behaviour for defects A and B:

```
[TEST] COULD-NOT-RUN: bootstrap-symlink-only-not-dirty (post_rc=2)
[TEST] COULD-NOT-RUN: bootstrap-symlink-plus-real-file-dirty (post_rc=2)
[TEST] COULD-NOT-RUN: real-file-at-bootstrap-prefix-dirty (post_rc=2)
[TEST] COULD-NOT-RUN: tracked-modified-at-bootstrap-prefix-dirty (post_rc=2)
```

Root cause, proven: `test-scope-gate-orchestration-dirt.sh:113` requires `_pc_lane_dirty`, but
the function was renamed when it moved into the lane guard —

```
$ /bin/bash -c 'set -uo pipefail; source lib/leadv2-lane-guard.sh; declare -F _pc_lane_dirty && echo YES || echo NO; declare -F lv2_lane_dirty && echo "lv2_lane_dirty: YES"'
NO
lv2_lane_dirty: YES
```

`COULD-NOT-RUN` is not counted as a failure, so the suite reports `0 failed` while a third of it
is dead. **Required fix:** `test-scope-gate-orchestration-dirt.sh:113` must probe
`lv2_lane_dirty` (and `:135/:146/:167/:184` call it), or the four cases must be deleted with a
written justification — a silently-skipped case is worse than a deleted one.

### H8 — FIXED (count), see H-new-2 for the semantics

```
$ bash plugins/leadv2/scripts/tests/test-close-chain.sh
[TEST] === T11 close-chain results: 18 passed, 0 failed ===
```

The restoration is controlled. MUT-F (delete the whole `pass_unlanded)` arm from
`leadv2-dispatch-ledger.sh:325-329`):

```
[TEST] === T11 close-chain results: 17 passed, 1 failed ===
[TEST] FAIL: (a/b groundwork) write-once: last state='landed', expected pass_unlanded to survive
```

MUT-G (narrow the arm to a plain `exit 2`, forbidding the refused escalation) →
`test-dirty-lane-never-lands.sh` `MUT-G rc=1`. Both directions are covered.

### Defect B — FIXED, proven by fixture, not by a suite

The suite's own control (`test-dirty-lane-never-lands.sh:105-116`) stubs
`leadv2-lane-worktree.sh` in `$T/bin`, so it does not prove the real `path-of` resolution. I built
the fixture the brief asked for: a real linked worktree whose worker process is gone and whose
write set is dirty, driven through the **real** `cmd_sweep` → real
`dispatch_ledger_sweep_write_dead` → real `leadv2-lane-worktree.sh path-of` → real
`lv2_lane_dirty`, with only the liveness verdict stubbed.

```
=== path-of probe ===
/private/.../fixB/proj/.claude/worktrees/dispatch-abcd1234
=== SWEEP ===
[leadv2-dispatch-ledger] sweep: checked=1 swept=1 skipped_alive=0 skipped_attemptless=0 skipped_indeterminate=0
=== LEDGER ===
{"ts":"...","task_sig":"abcd1234",...,"terminal":"dead_with_unlanded_work","cause":"no_close_owner",
 "evidence":"verdict=dead:no_handoff_dir lane_root=/private/.../dispatch-abcd1234","attempt":"pid-7001"}
=== JOURNAL ===
append dispatch-abcd1234 decision dispatch_terminal task=abcd1234 terminal=dead_with_unlanded_work cause=no_close_owner attempt=pid-7001 source=sweep
```

Negative half — same fixture, lane committed clean, second sig:

```
{"task_sig":"beef0001",...,"terminal":"dead","cause":"no_close_owner","evidence":"verdict=dead:no_handoff_dir"}
```

Distinct terminal, correctly conditioned. MUT-C (`if [[ -n "${lane_root}" ]] && lv2_lane_dirty …`
→ `if false;` at `leadv2-dispatch-ledger.sh:482`) → suite `rc=1`.

Automatic invoker: `leadv2-dispatch-code.sh:5950`, at the top of `cmd_resolve`, which is the
default CLI arm (`leadv2-dispatch-code.sh:7705  *) cmd_resolve "$@"`). Proven live by pointing
`LEADV2_DISPATCH_LEDGER_BIN` at a recorder and running a real dispatch:

```
$ ... LEADV2_DISPATCH_LEDGER_BIN="$R/ledger-rec.sh" bash leadv2-dispatch-code.sh --task-id ZZZ-FIXTURE-01 --mission noop
=== recorder log ===
LEDGER_CALL: sweep
```

I also disproved my own worry that the pin is cwd-dependent: an identical sweep run from *inside*
a lane worktree with `PROJECT_ROOT`/`LEADV2_PROJECT_ROOT` unset still produced
`"terminal":"dead_with_unlanded_work"` (`leadv2-lane-worktree.sh`'s `resolve_root` walks to the
common dir). Not a finding.

### H9 — FIXED

Reproduced HEAD into a scratch git repo, touched the files, and instrumented the runner to print
its selection instead of executing it:

```
=== both dispatcher files changed ===
plugins/leadv2/scripts/leadv2-dispatch-ledger.sh
plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
SELECTED plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
SELECTED plugins/leadv2/scripts/tests/test-close-chain.sh
SELECTED plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh
SELECTED plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh
SELECTED plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
(+ run-core-offline.sh, 3 status-surface suites)

=== ONLY leadv2-dispatch-product-close.sh changed ===
SELECTED test-dirty-lane-never-lands.sh, test-scope-gate-orchestration-dirt.sh,
         test-merged-sweep-orchestration-dirt.sh, test-worktree-lane-safety.sh

=== ONLY leadv2-dispatch-ledger.sh changed ===
SELECTED test-dirty-lane-never-lands.sh, test-close-chain.sh
```

### C1 — FIXED

```
$ git check-ignore -v plugins/leadv2/scripts/docs/x plugins/leadv2/scripts/.claude/y
.gitignore:64:plugins/leadv2/scripts/docs/	plugins/leadv2/scripts/docs/x
.gitignore:65:plugins/leadv2/scripts/.claude/	plugins/leadv2/scripts/.claude/y
rc=0

$ git ls-tree -r --name-only HEAD | grep -cE '^plugins/leadv2/scripts/(docs|\.claude)/'
0

$ git status --porcelain --untracked-files=all | grep 'plugins/'
(no plugins/ residue)
```

Working-tree dirt in the lane is control-plane only (`docs/leadv2/*`, `docs/handoff/*`,
`docs/LEAD_V2_STATE.md`) — the paths `_PC_PORCELAIN_EXCLUDE_RE` exists to exclude. Five new files
land in the lane, all intentional (`lib/leadv2-lane-guard.sh` + four suites). No new absolute
symlinks; the `/Users/...` symlinks in `git ls-files` (`.claude/agents/*`,
`plugins/leadv2/docs/leadv2/*`) are all pre-existing at merge-base.

---

## New findings

### [Critical] N1 — the C2 "restoration" restored the counts, not the controls

`plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh:91-96`

```bash
_both_sites_use_bootstrap_filter() { # <script>
  ...
  grep -Fq '_pc_drop_bootstrap_dirt' "$s" && return 0
```

The old form counted porcelain call sites and required every one of them to be filtered. The
rewrite is a bare substring grep — and `_pc_drop_bootstrap_dirt` appears in the file as its own
**definition** at `lib/leadv2-lane-guard.sh:29`. The assertion therefore cannot fail while the
function exists, no matter how many call sites lose the filter. This is the exact C3 disease the
round-5 brief said to sweep for, reintroduced in the C2 fix.

Proven. MUT-D deletes the call site from inside `lv2_lane_dirty`'s body
(`lib/leadv2-lane-guard.sh:54`) and leaves the definition:

```
$ grep -n '_pc_drop_bootstrap_dirt' lib/leadv2-lane-guard.sh
29:_pc_drop_bootstrap_dirt() { # <lane-root>; filters stdin porcelain -> stdout
--- scope-gate under MUT-D ---            Results: 0 passed, 0 failed, 9 green-pre-fix, 4 could-not-run
--- worktree-lane-safety under MUT-D ---  Results: 11 passed, 0 failed, 13 green-pre-fix
--- merged-sweep under MUT-D ---          Results: 0 passed, 0 failed, 8 green-pre-fix
--- t13-slice1 under MUT-D ---            [TEST] RESULTS PASS=19 FAIL=0
```

**All four "restored" suites stay fully green** with the bootstrap filter deleted from the live
path. Only `test-dirty-lane-never-lands.sh` catches it. The four suites are back at their
pre-lane numbers and are no longer evidence of anything about this file.

For contrast, `_both_sites_use_constant` (`:78-83`) survived my probe — MUT-E (remove
`| grep -vE "${_PC_PORCELAIN_EXCLUDE_RE}"` from `lv2_lane_dirty`) does go RED:
`Results: 0 passed, 1 failed, 8 green-pre-fix, 4 could-not-run / FAIL: both-sites-use-constant: post-fix rc=1`.
So the fix is to give `_both_sites_use_bootstrap_filter` the same shape — assert on a *call site*
(`| _pc_drop_bootstrap_dirt "$`), not on the identifier.

**Required fix:** `test-scope-gate-orchestration-dirt.sh:91-96` must assert that every
`status --porcelain --untracked-files=all` site in the guard pipes through
`_pc_drop_bootstrap_dirt`, and MUT-D must go RED before this lane lands.

### [High] N2 — the new `dead_with_unlanded_work` pin is not write-once and is erased by the next `landed`

`plugins/leadv2/scripts/leadv2-dispatch-ledger.sh:322-330` — `dispatch_ledger_write_terminal`'s
guard is still `case "${_last_terminal}" in landed|dead) exit 2 ;; pass_unlanded) …`. The new
terminal is absent, so a later ordinary terminal write appends on top of the pin and the ledger's
answer flips. Proven against the fixture lane that had just been pinned:

```
=== state/cause BEFORE overwrite ===
dead_with_unlanded_work
no_close_owner
=== attempt to overwrite the pin with landed ===
write rc=0
=== rows for abcd1234 ===  2
{"task_sig":"abcd1234",...,"terminal":"landed","cause":"completed",...}
=== state AFTER ===
landed
```

`leadv2-dispatch-ledger.sh:512` (the *sweep's own* guard) does list
`dead_with_unlanded_work`; `:320`, `:324` and `:364` do not. A pin that the next dispatch can
overwrite does not solve "seven workers died leaving uncommitted work" — it just records it until
someone writes again.

**Required fix:** add `dead_with_unlanded_work` to the true-terminal arms at
`leadv2-dispatch-ledger.sh:320`, `:324` and `:364`, and add a control that mutates it back out.

### [High] N3 — the restored `pass_unlanded` write-once is one hop deep: `pass_unlanded → refused → landed`

`plugins/leadv2/scripts/leadv2-dispatch-ledger.sh:325-329` permits one escalation to `refused`.
Its own comment claims "a later landed (or another pass) may never overwrite the first pass row."
That is false, because `refused` is retryable and the guard only inspects the **last** terminal:

```
=== CHAIN PROBE (lane HEAD) ===
pass_unlanded rc=0 state=pass_unlanded
refused       rc=0 state=refused
landed        rc=0 state=landed
```

Merge-base `5d1a5d7` (`leadv2-dispatch-ledger.sh:301  landed|pass_unlanded|dead) exit 2`) does
not have this hole:

```
=== CHAIN PROBE (merge-base) ===
MB pass_unlanded rc=0 state=pass_unlanded
MB refused       rc=0 state=pass_unlanded
MB landed        rc=0 state=pass_unlanded
```

So H8's fix restored the suite count while making the invariant *weaker than before the lane*, in
exactly the direction this cluster exists to prevent: a lane with uncommitted worker bytes reading
as `landed`. `test-close-chain.sh` does not catch it (it tests one hop).

**Required fix:** scope the escalation to the *whole sig8 history*, not the last row — once any
`pass_unlanded` row exists for a sig8, only `refused` may ever be appended. Add the two-hop chain
as a case in `test-dirty-lane-never-lands.sh`.

### [High] N4 — H9 recreated: `lib/leadv2-lane-guard.sh` has no CI mapping to the suites that now assert on it

This round made `lib/leadv2-lane-guard.sh` the single home of `_PC_PORCELAIN_EXCLUDE_RE`,
`_PC_BOOTSTRAP_PREFIX_RE`, `_pc_drop_bootstrap_dirt` and `lv2_lane_dirty`, and retargeted four
suites at it — but added no `leadv2-lane-guard:` rows for them in `tests/run-all.sh:120-134`:

```
=== changed ===
plugins/leadv2/scripts/lib/leadv2-lane-guard.sh
SELECTED plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
SELECTED plugins/leadv2/scripts/tests/test-lane-containment.sh
(nothing else)

$ grep -nE 'lane-guard|t13-slice1' tests/run-all.sh
132:leadv2-lane-guard:plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
133:leadv2-lane-guard:plugins/leadv2/scripts/tests/test-lane-containment.sh
```

A change to the guard selects 2 of the 6 suites that grade it. `test-t13-slice1.sh`,
`test-scope-gate-orchestration-dirt.sh`, `test-merged-sweep-orchestration-dirt.sh` and
`test-worktree-lane-safety.sh` now read the guard and would never run. This is the identical
shape H9 named, moved one file to the left by H9's own fix.

**Required fix:** four more `leadv2-lane-guard:` rows in `tests/run-all.sh`'s `EXTRA_SUITE_MAP`,
proven with `--scope changed`.

### [Medium] N5 — the automatic sweep ignores the ledger kill switch it is documented to obey

`leadv2-dispatch-code.sh:499` documents `LEADV2_DISPATCH_TERMINAL_LEDGER=0` as disabling *all*
ledger writes, and every other `LEDGER_BIN` call site gates on `TERMINAL_LEDGER` (`:1802`,
`:2908`, `:2920`). The new invoker at `:5950` does not:

```
$ LEADV2_DISPATCH_TERMINAL_LEDGER=0 ... bash leadv2-dispatch-code.sh --task-id ZZZ-FIXTURE-01 --mission noop
with LEADV2_DISPATCH_TERMINAL_LEDGER=0 -> recorder log:
LEDGER_CALL: sweep
```

With the switch off, a dispatch still writes TRUE terminals and — per the sweep's own T16 §10
block — deregisters lane rows from `active.yaml`. All of it with `>/dev/null 2>&1 || true`, so a
wrongly-swept live lane leaves no trace in the dispatch log while permanently poisoning that
sig8 (the exact failure mode `HIGH-1` in the sweep's comments already had a live repro for).

**Required fix:** `[[ "${TERMINAL_LEDGER}" == "1" && -f "${LEDGER_BIN}" ]]` at `:5950`, matching
the other three sites.

Latency is not the problem here — the real probe measures 1.2s
(`leadv2-lane-liveness.sh --all --json` against the live repo, `1.209 total`), which is acceptable
on the dispatch path.

### [Medium] N6 — `dead_with_unlanded_work` is a write-only value: nothing reads it

Repo-wide census, excluding handoff docs:

```
plugins/leadv2/scripts/leadv2-dispatch-ledger.sh:483    terminal="dead_with_unlanded_work"
plugins/leadv2/scripts/leadv2-dispatch-ledger.sh:512    landed|pass_unlanded|dead|dead_with_unlanded_work) exit 2
plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh:115  assert_last dead_with_unlanded_work swept
```

Three consequences: it is missing from the `write-terminal` allowlist
(`leadv2-dispatch-ledger.sh:278`) and from the taxonomy header (`:19`, `:382`), so no other writer
can produce it and the documented row shape is now wrong; and the brief's "the pulse can show"
half is unbuilt — `leadv2-lane-pulse-watch.sh:153-154` matches only the generic
`dispatch_terminal` kind and truncates the detail at 60 chars
(`cut -c1-60`), which lands mid-token on
`dispatch_terminal task=abcd1234 terminal=dead_with_unlanded_work` (64 chars). The founder gets
`…terminal=dead_with_unlande`.

### [Medium] N7 — scope-gate's pre/post discrimination is vacuous in this lane

`test-scope-gate-orchestration-dirt.sh:37` builds the "pre-fix" script with
`git show HEAD:plugins/leadv2/scripts/lib/leadv2-lane-guard.sh`. HEAD *is* the lane head, so:

```
$ git show HEAD:plugins/leadv2/scripts/lib/leadv2-lane-guard.sh | diff - plugins/leadv2/scripts/lib/leadv2-lane-guard.sh
IDENTICAL -> scope-gate PRE==LIVE, pre/post discrimination is vacuous
```

Every case is therefore reported `GREEN-PRE-FIX` and `0 passed(red->green)`. The suite's whole
labelling apparatus conveys nothing here. Either pin the pre-image to a named merge-base sha or
drop the pre/post framing.

### [Low] N8 — stale doc block on the function this round changed

`leadv2-dispatch-ledger.sh:443-467` still describes the sig8-wide write-once check as
"(landed|dead) … UNCHANGED" and does not mention that the function now resolves a lane root and
can emit a second terminal value. The header at `:19` still lists the row's terminal enum without
`dead_with_unlanded_work`.

### [Low] N9 — `grep -Fqx` exact-line coupling

`test-scope-gate-orchestration-dirt.sh:243` asserts the source line with `grep -Fqx`. It is a real
control — MUT-H (append a trailing comment to the `source` line in
`leadv2-dispatch-product-close.sh`) produces
`[TEST] FAIL: product-close does not source the lane guard` — but it also fails on any harmless
reformat. Prefer `grep -Fq 'lib/leadv2-lane-guard.sh"'`.

---

## bash 3.2 / `set -u` scan

Requested explicitly. Clean.

```
$ git diff 5d1a5d7..HEAD -U0 -- plugins tests | grep '^+' | grep -E 'read -N|mapfile|readarray|declare -A|\$\{[A-Za-z_]+,,\}|\$\{[A-Za-z_]+\^\^\}|&>>|wait -n'
(no matches)
```

Both unbound-array sites in the new guard use the bash-3.2-safe alternate form
(`lib/leadv2-lane-guard.sh:45-46`, `${kept_lines[@]+"${kept_lines[@]}"}`). I probed it directly
rather than reading it, because the unquoted outer form looks like a word-splitting bug:

```
$ /bin/bash -c 'set -uo pipefail; source lane-guard.sh; printf " M src/a b.sh\n?? docs/x y.md\n" | _pc_drop_bootstrap_dirt "$root" | sed -n l'
 M src/a b.sh$
?? docs/x y.md$
$ printf " M zz*.txt\n" | _pc_drop_bootstrap_dirt "$root"   # cwd contains zz1.txt zz2.txt
 M zz*.txt
```

Whitespace preserved, no glob expansion. Not a finding.

The negated-command assertions at `test-worktree-lane-safety.sh:127,164,190,200,225` are the last
statement of their `case_*` helper, so the rc propagates to `run_case`. They are not C3's hole.

## `bash -n` — raw output

```
ok plugins/leadv2/scripts/leadv2-dispatch-code.sh
ok plugins/leadv2/scripts/leadv2-dispatch-ledger.sh
ok plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
ok plugins/leadv2/scripts/lib/leadv2-lane-guard.sh
ok plugins/leadv2/scripts/lib/leadv2-admission-class.sh
ok plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
ok plugins/leadv2/scripts/tests/test-close-chain.sh
ok plugins/leadv2/scripts/tests/test-t13-slice1.sh
ok plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh
ok plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh
ok plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
ok tests/run-all.sh
```

(no diagnostics emitted by any file)

## Contradiction scan

- **`LEADV2_DISPATCH_TERMINAL_LEDGER` semantics vs the new invoker** — contradiction, see N5.
- **Code comment vs behaviour at `leadv2-dispatch-ledger.sh:326-328`** ("a later landed … may
  never overwrite the first pass row") — contradicted by the chain probe, see N3.
- **Row-shape doc at `leadv2-dispatch-ledger.sh:19` vs the value the sweep now writes** —
  contradiction, see N6.
- **`.gitignore:64-65` vs the residue paths** — consistent; `git check-ignore` rc=0 for both.
- **`EXTRA_SUITE_MAP` keys vs the files that own the assertions** — contradiction for
  `lib/leadv2-lane-guard.sh`, see N4. The duplicate `leadv2-dispatch-ledger` / 
  `leadv2-dispatch-ledger.sh` rows (`tests/run-all.sh:123-124`) are harmless — `add_suite`
  dedupes, verified in the selection output.
- **Path existence** — every file cited above exists at HEAD; `leadv2-lane-worktree.sh path-of`
  is a real verb (`leadv2-lane-worktree.sh:333`) and resolves correctly under the fixture.

## Blocking set for round 6

N1 (Critical), N2/N3/N4 (High) and the scope-gate `COULD-NOT-RUN` regression under C2. Each one
needs its mutation run and left RED in `docs/handoff/DISPATCH-PIN-CLUSTER-01/round6-red/`.

verdict: fail
