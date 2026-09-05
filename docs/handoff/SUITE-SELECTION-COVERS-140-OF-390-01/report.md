# SUITE-SELECTION-COVERS-140-OF-390-01 — report

Premise confirmed, and it was worse and narrower than the row said at the same
time. The number s1 measured is exactly right for the directory and the
mechanism she measured; it is not the whole selection story, and the whole story
changes what "unselected" means.

| | |
|---|---|
| `a2b08cd1` | 236 suites self-register — 1888 insertions, comment lines only |
| `e6693ad3` | `tests/unselected-by-design.txt` — the 25 that must NOT be selected, each with a reason |
| *staged* | the coverage guard, its two negative controls, the catalog rows, this report |

The last commit is staged and waiting: a neighbouring session has an unresolved
merge in the shared tree (`AA docs/handoff/REPORT-ONLY-GATE-01/report.md` and
seven more), and `git commit` refuses while it stands. I do not resolve another
lane's conflicts.

---

## Step 0 — the instrument, before any number

Both directions, because a census tool that cannot answer non-zero invalidates
every zero it prints, and one that answers non-zero for everything invalidates
every positive.

```
POSITIVE  dirty leadv2-active-registry.sh -> 10 suites selected,
          test-writeset-carousel.sh among them            (the instrument can say yes)
NEGATIVE  the same run does NOT select test-active-register-miss.sh,
          test-active-registry-failclosed.sh,
          test-active-registry-update-phase.sh
          — three suites that exist, are named after that exact file,
            and were invisible to it                       (the instrument can say no)
```

The negative half is not a synthetic case. Three suites named after the registry
sat unselected while the registry changed under them — I had edited that very
file the hour before.

---

## The census, at pinned sha `27f3bd83`

Population = `test-*.sh` at **maxdepth 1** of the four directories `run-all.sh`
discovers. Depth matters: the scan is `find -maxdepth 1`, so anything in a
subdirectory is invisible to both mechanisms. (Nothing is currently nested, but
`tests/contract/` has been in that hole before — it is how the publish mutation
survived for weeks.)

```
population                                            427
  plugins/leadv2/scripts/tests                        389
  plugins/leadv2/tests                                 25
  tests                                                13
  .claude/scripts/tests                                 0   (at this sha)

A  # run-all-triggers: marker                         144
B  name convention test-<production stem>              27
C  EXTRA_SUITE_MAP rows                                 0
D  run-core-offline SUITE_DEFS                         84 suite files
E  --scope all discovery                              427   (no marker needed)

A ∩ B                                                   4
A ∪ B ∪ C = selectable by --scope changed             167
NOT selectable by --scope changed                     260
   of those, still run by run-core-offline (D)         71
   of those, reachable only by --scope all            189
```

**s1's 140 of 390 reproduces exactly** — 389 files in
`plugins/leadv2/scripts/tests`, 140 of them marked. Three corrections to what
that number means:

1. **`EXTRA_SUITE_MAP` is empty.** The static-map mechanism the row lists no
   longer exists; self-registration replaced it. So the marker is not one of
   three selectors, it is one of *two*.
2. **The second selector is the name convention**, and it is invisible until you
   read the stem loop: a changed `X.sh` selects `tests/test-X.sh` and
   `plugins/leadv2/scripts/tests/test-X.sh` **by name, with no marker at all**.
   27 suites are selected that way, 4 of them redundantly. Counting markers
   alone understates coverage.
3. **"Selected by nothing" is not true — "selected by nothing on a
   change-scoped run" is.** `--scope all` discovers all 427 regardless of
   marker, and `run-core-offline` statically lists 84. The real defect is
   sharper than the row's wording: a CI or dispatch gate that runs
   `--scope changed` — which is what a lane actually runs — saw 167 of 427.

`run-core-offline` lists 84 suite files, not 82; that number had drifted too.

---

## The three classes, and how each suite got into one

Class is decided from **evidence inside the suite**, never from its name
(`classify.py`, committed beside this report): the production files it actually
references, split into those that exist at this sha and those that do not, plus
whether it needs the network or writes over a production file.

| | | |
|---|---|---|
| **(b) connect** | 235 | references at least one existing production file → triggers derived from it |
| **(c) declared** | 24 | needs network, writes over a production file, or references no production file at all |
| **(a) dead** | 1 | every production file it names is gone: `test-glm-first-exception-admitted.sh` → `leadv2-glm-first-agent-gate.sh` |

Nothing is left silent: 235 + 24 + 1 = 260.

### How the triggers were derived

Not from the suite's name and not from every file it sources. A suite sources
shared helpers that say nothing about what it tests — `leadv2-temp.sh` is
referenced by more than a quarter of them. Triggering on that would select ~235
suites on any helper edit, which is technically a dependency and practically
noise, and noise is how a selection gate stops being read. So each suite's
triggers are the production files **its own body references most**, with
infrastructure references excluded, capped at four:

```
triggers per suite: 1 -> 129,  2 -> 44,  3 -> 32,  4 -> 30
infrastructure excluded (present in >58 suites): leadv2-temp
```

### Applying it in the live checkout, and the one thing I reverted

Re-derived against canonical rather than replaying the pinned plan, because
`main` had moved. That run reported 507 unselected, not 260 — because the live
checkout **also carries `.claude/scripts/tests`, 228 drifted real copies of
canonical suites** that `run-all.sh` scans as a fifth population. The write
touched them too; I reverted all 228 immediately and left them untouched. They
are untracked, they are the symlink-farm drift the guard already reports, and a
marker written into one of them dies at the next symlink restore. **236 tracked
suites carry the marker; 0 of the drifted copies do.** That duplication is a
real finding and belongs in its own row: the same suite exists twice, and
`run-all.sh` can select either copy.

After the change, on canonical:

```
selectable by --scope changed                         403
NOT selectable                                        271
   of those, drifted .claude/scripts/tests copies     246   (out of scope, untouched)
   of those, tracked                                   25   (= the declared 24 + the 1 dead)
```

---

## Proof of selection, from the PRODUCTION file

The dirt is one appended comment in `plugins/leadv2/scripts/leadv2-active-registry.sh`,
reverted in the same command. A dirty *suite* selects itself by name and proves
nothing.

```
pinned tree, before markers   dirty registry -> 10 selected, no test-active-regist* among them
pinned tree, after  markers   dirty registry -> 20 selected, ALL THREE test-active-regist* present
canonical,    after markers   clean -> 4 selected
                              dirty registry -> 20 selected, all three present
```

Newly-connected suites, run in the foreground, rc read from the suite itself:

```
active-register-miss          rc=0    active-registry-failclosed    rc=0
active-registry-update-phase  rc=0    writes-overlap                rc=0
lanes-snapshot                rc=0    fanout-classify-guard         rc=0
phase-refusal-lane-release    rc=0    lane-truth-batch-01           rc=124 (timeout at 55s)
```

7 of 8 green; the eighth exceeded a 55-second sample budget rather than failing.
12 of the 235 were already listed in `tests/known-red-suites.txt`, so CI already
tolerates them. `known-red-suites.txt` was not touched — it may only shrink.

---

## The guard, so this cannot silently come back

`test-suite-selection-coverage.sh` (4/0) asserts the invariant directly: **every
tracked suite is either selectable by a change-scoped run or named in
`unselected-by-design.txt` with one of four allowed reasons.** It re-derives
selectability the way `run-all.sh` does — the same marker prefix, the same stem
convention against the real production directories — and carries no counts.
It also asserts the declaration file cannot rot into a dumping ground: every name
in it must exist, and every line must carry a reason.

**Negative controls, run, by regex inside a function body, on a scratch copy:**

| control | mutation | result |
|---|---|---|
| `SUITE-SELECTION-GUARD-IGNORES-THE-MARKER` | in `_selectable()`: the marker grep is pointed at a prefix that never matches | **case 1 red** — every suite becomes an orphan; the other three cases green |
| `A-SUITE-SILENTLY-LOSES-ITS-TRIGGER` | in `test-active-registry-failclosed.sh`: its `# run-all-triggers:` line is replaced | **case 1 red, naming exactly that one suite** |

The second mutates the **suite corpus, not the guard** — that is the honest
control, because it reproduces the production defect rather than a proxy for it.

One thing worth recording about the control harness: its first run reddened case
4 in *both* mutants for an unrelated reason — macOS `mktemp -d` returns
`/var/folders/...`, a symlink to `/private/var/folders/...`, and `run-all.sh`
FATALs with `root_escape` when its resolved root differs from its invocation
path. That is exactly the "red for the wrong reason" failure mode, and the run
above is after canonicalising the scratch path with `pwd -P`. Both controls now
redden **one** case each, and only their own.

Catalog: `suite-selection-guard-ignores-the-marker`,
`a-suite-silently-loses-its-trigger`. Counted after the append: **19 entries,
all `expected: killed`.**

---

## What I did not do

- **The 246 drifted `.claude/scripts/tests` copies are untouched.** Editing them
  is not the fix; restoring them to symlinks is, and that is
  `SD-SYMLINK-FARM-CONVERT-01`'s job, gated on no live lanes. But note what the
  drift means for *this* row: a suite can be selected in its drifted copy
  instead of canonical, and the two can disagree.
- **The one dead suite is declared, not deleted.** `test-glm-first-exception-admitted.sh`
  names a production file that no longer exists; deleting a suite is a different
  decision from connecting one, and it is not mine to take inside a census lane.
- **`--scope all` was never run in the live checkout.** The mission forbids it
  and the reason is real: it relocates five control-plane symlinks and deletes
  their targets. Every measurement here used `LEADV2_RUN_ALL_SELECT_ONLY=1`,
  which short-circuits before any suite runs, or a pinned scratch tree.
