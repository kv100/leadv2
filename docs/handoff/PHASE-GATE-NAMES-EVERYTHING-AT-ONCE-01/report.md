# PHASE-GATE-NAMES-EVERYTHING-AT-ONCE-01 — report

Both defects fixed. Four commits, named files only, nothing pushed.

| | |
|---|---|
| `c668e5ab` | both fixes + the existing suite updated to the new contract |
| `3b9c6f5a` | `test-phase-gate-names-everything.sh` (10 cases) + negative-control artifacts + catalog rows |
| `9703e25c` | corrects the catalog header's carried kill-rate number (see **A number I found wrong**) |

The first of these was committed the moment the four existing phase suites were
back at baseline, because the dirty working tree was blocking eight wave-B1
merges. Files touched: `leadv2-phase-record.sh`, `leadv2-dispatch-code.sh`,
`tests/`, `tests/mutations/catalog.yaml`, this handoff dir. Nothing else.

---

## Defect 1 — the gate revealed the mandatory set in installments

### Reproduced first, on a scratch store

```
fresh Standard lane, pre-build:  admitted=bootstrap would_be_missing=classify,plan,gate1
after `record classify`:         missing=plan,gate1
same lane, same state, full:     missing=plan,gate1,build,test,review,live_verify,close
```

`missing=` was only ever the subset unmet **in the scope of that one call**. The
gate had the whole contract in hand — `_resolve_mandatory` is a pure function of
(class, writes, scope) and the full list is one call away — and printed a slice
of it. Five phases arrive later, at roughly a dispatch cycle each.

I could not reproduce your exact sequence (`plan,gate1` → then `classify`)
locally: once `classify` is recorded it stays satisfied in my scratch root. The
most likely explanation for `classify` coming back is that the record and the
assert read *different* `phases.d` — the open row
`PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01` is exactly that shape. I did not
chase it, because the fix does not depend on which state shift moved the subset:
naming the whole contract is right under all of them. Flagging it so nobody
reads this report as having closed that row.

### The fix

`assert` now answers on three lines:

```
missing=plan,gate1
required=classify,plan,gate1,build,test,review,live_verify,close
unmet=plan,gate1,build,test,review,live_verify,close
```

`missing=` is unchanged (scope-local, decides the refusal). `required=` is the
class's whole mandatory contract. `unmet=` is everything still outstanding
across that contract. The bootstrap admission carries them too, so the very
first thing a fresh lane sees is the full set.

`dispatch-code` parses the three tokens by name and prints, in one refusal:

```
dispatch refused: missing mandatory phases: plan,gate1
  full mandatory set for class Standard: classify,plan,gate1,build,test,review,live_verify,close
  still unmet across that whole set: plan,gate1,build,test,review,live_verify,close
  (this refusal is scoped to pre-build; the rest becomes mandatory later in the same lane)
```

**Separate lines, not extra tokens on `missing=`.** Twelve cases in
`test-phase-precondition.sh` match the refusal with an unanchored
`grep -q 'missing=.*review'`, and five assert the **negative** of that. Appending
the full list to the `missing=` line would have made "review is missing" true
whenever review is merely *mandatory*, silently inverting those five. The suite
pins this now (case a2).

### One checker, two questions

The per-phase satisfaction test moved out of `cmd_assert`'s loop into
`_phase_satisfied`, so the scoped answer and the full-contract answer cannot
disagree. **No phase is verified twice per assert** — and that constraint is
load-bearing, not tidiness. `_verify_artifact` is not a pure predicate for
`review`: it adopts a ledger sidecar and journals tamper events as it checks.
The naive "just run the loop twice" version turned six green cases of
`test-phase-precondition.sh` red (G7b/c/e/f/g, G9a). When the requested scope
already *is* full, one loop answers both questions; when it is pre-build, the two
phase sets are disjoint and the scoped answers are reused rather than recomputed.

---

## Defect 2 — a record that announced its own future refusal, then proceeded

`leadv2-phase-record.sh` wrote the record and printed:

```
WARN: phase 'plan' for <sig8> recorded done but proof NOT verified — assert will refuse
```

That record is worse than no record, and worse in a way the warning does not
say. A lane's bootstrap grace is "this lane has **no** phase record at all"
(`cmd_assert`'s `_lane_bootstrap`; `_phase_precondition_guard`'s variant is "no
record other than `classify`"). So writing an unprovable `plan` **ends the
grace without satisfying anything** — it converts a lane that would have been
admitted into one that is refused. The suite pins that consequence directly
(case b5), and the negative control demonstrates it: with the record written,
the next assert answers `missing=classify,plan,gate1` instead of admitting.

### The fix, and where I narrowed your ask — deliberately

I first implemented it exactly as written: if `_verify_artifact` says no, refuse.
**Six green cases went red.** `record-review` (in `dispatch-code`) writes the
phase record and its provenance ledger row in one flow, so a review record
legitimately fails verification at the instant it is written and passes seconds
later. Verification at *write* time is not the same question as verification at
*assert* time.

So the refusal is scoped to the part that **is** decided at write time and that
nothing downstream repairs: **artifact integrity** — the named file is absent,
unreadable, or does not hash to the sha recorded beside it.

- unhashable/missing artifact → `exit 5`, **nothing written**
- artifact real, other evidence not landed yet → recorded, `proof: unverified`,
  and the warning now says the true thing: *"proof NOT yet verified — assert will
  refuse until the rest of its evidence lands"*
- `classify` / `diverge` → never refused; assert does not verify them either, and
  `cmd_resolve` records `classify` on every dispatch, so refusing it would refuse
  every lane

This is narrower than "refuse anything that will fail". I think the narrow rule
is the correct one and the evidence is above; if you want the wide rule anyway,
the blocker is the write ordering inside `record-review`, which is
`leadv2-dispatch-code.sh` work.

---

## The five requirements

**1. Real function under assertion.** All 10 cases of
`test-phase-gate-names-everything.sh` drive the real `leadv2-phase-record.sh`
CLI (`record` / `assert` / `show`) against real `phases.d` stores on disk. Only
the project root is faked. Nothing stubs `cmd_assert`, `cmd_record`,
`_phase_satisfied` or `_verify_artifact`.

```
a scoped refusal names the class's FULL mandatory contract
required= rides on its own line: a merely-mandatory phase never lands in missing=
unmet= spans the whole contract, not just this scope
nothing the later full-scope refusal names is new
the bootstrap admission names the full contract before any work is done
an unhashable artifact refuses (rc=5) and writes nothing
a missing artifact refuses (rc=5) and writes nothing
a real artifact whose other evidence has not landed is still recorded, stamped unverified
classify/diverge are never refused (assert does not verify them either)
a refused record leaves the lane's bootstrap grace intact
[PHASE-GATE-NAMES-EVERYTHING] pass=10 fail=0
```

Case (a4) is the one that carries the point: *whatever the later full-scope
refusal names must already appear in the first refusal's `required=`*. That is
the property whose absence cost a dispatch cycle per discovery.

**2. Negative controls — run, by regex, inside a function body**, on a scratch
copy (never the shared canonical file; live lanes read it):

| control | mutation | result |
|---|---|---|
| `PHASE-GATE-NAMES-ONLY-ITS-OWN-SCOPE` | in `cmd_assert()`: `required_csv` is emptied | **4 red** — a1, a2, a4, a5. Every defect-2 case green. |
| `PHASE-RECORD-WRITES-THE-DEAD-RECORD-ANYWAY` | in `cmd_record()`: the refusal's `exit 5` → `_proof="unverified"` | **3 red** — b1, b2, b5. Every defect-1 case green. |

Each reddens only its own defect's cases. Artifacts:
`mutation-control/negative-controls.log` (mutated line shown in context, plus
per-case verdicts) and two `leadv2-mutation-control.sh` runs, both
`MUTATION-CONTROL ok`.

**3. Catalog rows.** `phase-gate-names-only-its-own-scope` and
`phase-record-writes-the-dead-record-anyway` in `tests/mutations/catalog.yaml`.
The first anchor deliberately avoids a `${...}`-bearing pattern — macOS BSD sed
degenerates those into an empty match, which the catalog header already warned
about.

**4. CI selection, proven from the PRODUCTION file.** The suite self-registers
`# run-all-triggers: leadv2-phase-record leadv2-dispatch-code.sh`. With the
runner's state file advanced to HEAD so only working-tree dirt counts:

```
CONTROL — tree clean:                        8 selected, not one phase suite
PROOF   — dirty ONLY leadv2-phase-record.sh: 15 selected, including
          test-phase-gate-names-everything.sh
          (+ test-phase-precondition{,-bootstrap}, -gate-inversion,
             -gate-default-class, test-phase-record)
```

The dirt was a comment appended to the production file, reverted immediately;
tree clean afterwards. A dirty suite selecting itself would prove nothing.

> On the earlier note that `LEADV2_RUN_ALL_SELECT_ONLY` does not exist: it does.
> `tests/run-all.sh:412`, `grep -c` = 1 on the canonical tree, and it is not
> inert — with the flag the run closes in **3.4 s** printing `[SELECT]` lines and
> `select_only=1`; without it the same invocation did not finish inside 120 s and
> had to be killed. There are a dozen `run-all.sh` copies under
> `.claude/worktrees/`; a grep against one of those would explain a zero.

**5. Suite state, before and after.** Baseline taken from a clean `git archive
HEAD` tree, not from memory:

| suite | baseline at HEAD | after |
|---|---|---|
| `test-phase-precondition.sh` | 79 / 1 | **81 / 1** (same pre-existing G3 red, +2 assertions) |
| `test-phase-precondition-bootstrap.sh` | 34 / 0 | 34 / 0 |
| `test-phase-gate-inversion.sh` | 9 / 4 | 9 / 4 (red before me, untouched) |
| `test-phase-gate-default-class.sh` | 15 / 4 | 15 / 4 (red before me, untouched) |
| `test-phase-gate-names-everything.sh` | did not exist | 10 / 0 |

`test-phase-precondition.sh`'s F1 block **pinned the defect itself** — it asserted
that a directory artifact is written with `proof: unverified`. Rewritten to
assert the refusal *and* that nothing is written, then to reach the still-real
unverified state through a file artifact whose git-side evidence has not landed.
G10's UNVERIFIED-column row moved to the same mechanism, so the column stays
covered.

---

## A number I found wrong on the way past

The catalog header read "now 8/8" while the file already held **eleven** entries
— the three `smart-arbiter-*` rows were added without updating it. Both of
today's lanes, mine included, then *incremented* the stale number (10/10, 12/12)
instead of counting it. Counted: **15 entries, all `expected: killed`.** The
header now carries the one-line command that recomputes the total instead of a
number anyone can inherit (`9703e25c`). A carried number is the same disease as a
lying green, one layer up. The arbiter report's "8/8 → 10/10" line is wrong for
the same reason and is corrected there.

---

## Where I stopped

- **`PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01` is not closed by this.** It
  remains the most likely reason `classify` reappeared as missing in your
  sequence, and it lives in the same file — but it is a different defect and I
  did not touch it.
- **The wide version of defect 2** (refuse on the verifier's whole answer, not
  just artifact integrity) needs `record-review` in `leadv2-dispatch-code.sh` to
  write its ledger row before the phase record. Named, not done.
- `G3: dispatch should exit 0 (got 4)` in `test-phase-precondition.sh`, and the
  4+4 reds in `test-phase-gate-inversion.sh` / `test-phase-gate-default-class.sh`,
  were red at HEAD before this lane and are untouched.
