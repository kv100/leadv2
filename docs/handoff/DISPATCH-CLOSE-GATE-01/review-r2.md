# DISPATCH-CLOSE-GATE-01 — adversarial review, round 2

**VERDICT: fail**

Lane: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01` @ `f06d325`
Reviewed: `git diff origin/main...HEAD -- plugins/ tests/` (7 files, +860/-8)

All mutations below were applied INSIDE the function body of the **production** file, in a byte-copy
of the lane at `/private/tmp/claude-503/.../scratchpad/lane`, which reproduces the lane's baseline
exactly (`mission-writeset 18/0`, `red-proof 14/0`). Every mutation asserts its anchor count and
hard-fails on a zero match. No source in the lane was modified.

| Item asked | Verdict |
|---|---|
| 1 — wiring control discriminates | **WORKS** |
| 2 — Mechanism 2 on the live close path | **BROKEN** |
| 3 — the two real specimens | **WORKS** |
| 4 — fixtures not written to fit the code | fixtures genuine, but **BROKEN**: the extractor refuses this lane's own mission |
| 5 — red-proof semantics | lib **WORKS**; the close-side "downgrade" **UNPROVEN** |
| (carried) C4 — `--scope changed` selects both suites | **BROKEN** |

---

## Item 1 — the wiring control: WORKS

Round 1's exact mutation (delete all three `_mission_writeset_guard` call sites, keep the
definition) now turns the suite RED.

```
M1 applied: 3 call sites deleted, definition kept
remaining call sites: 4  (definition+comment only)
=== M1 SUITE ===
PASS: control C2: mutated lib always reports covered -> caught (would be red)
FAIL: wiring: architect_prepass rc=0 out=[leadv2-dispatch-code] architect_prepass task=wiretest8 status=disabled reason=kill_switch
FAIL: control C1-wiring: mutation source pattern not found (dispatcher drifted, update mutation, rc=2)
SUMMARY: pass=16 fail=2
=== RESTORED ===
SUMMARY: pass=18 fail=0
```

The `wiring:` assertion drives the real `architect_prepass` via `LEADV2_DISPATCH_SOURCE_ONLY=1` and
dies without the call site. The zero-match anchor is a hard `fail`, not a skip. Genuine fix of
round-1 C1.

## Item 3 — the two real specimens: WORKS

Run against the **real on-disk files**, not the copies:

```
=== fix-round-4.md (docs/handoff/ANTI-SILENCE-STATUSLINE-01/) — must be ACCEPTED ===
rc=0
mission_writeset_ok

=== fix-round-5.md (docs/handoff/DISPATCH-PIN-CLUSTER-01/), PRE-CORRECTION csv — must be REFUSED ===
rc=1
mission_writeset_refused missing=lib/leadv2-lane-guard.sh
lib/leadv2-lane-guard.sh

=== same file, POST-correction (its own LANE_WRITES) — must be ACCEPTED ===
rc=0
mission_writeset_ok
```

The bare-fragment false positive (`round4-red/`) is fixed by the `repo_rooted()` >=2-segment rule
(`lib/leadv2-mission-writeset.sh:38-39`); `instr_re` (`:89`) now matches "Leave the RED logs in".
The specimen copies under `docs/handoff/DISPATCH-CLOSE-GATE-01/specimens/` are **byte-identical** to
the originals (`diff -u` -> IDENTICAL, both files), so the "fixture fitted to the code" charge does
not apply to them.

## Item 5 — red-proof semantics: lib WORKS, close-side downgrade UNPROVEN

Independent fixture, not their suite:

```
### two named fixes, one RED artifact:
unproven: beta claim
count=1
### after adding a 0-failed artifact for beta (must still be unproven):
unproven: beta claim
### rc of unproven (must be 0 = never blocks): 0
### close-gate CLI rc with unproven present: rc=0
```

Bash 3.2.57 clean; both suites 18/0 and 14/0 under `/bin/bash` 3.2.57. Round-1 H1 (unbound array ->
fail-open) is genuinely fixed — with an empty `writes_csv` the lib now fails **closed**:

```
$ /bin/bash -c 'set -uo pipefail; source lib/leadv2-mission-writeset.sh; ... | leadv2_writeset_missing ""'
docs/handoff/Q/red/
rc=0
```

What is **not** proven is the only part of Mechanism 2 that reaches a human: the `unproven=` suffix
landing in the close's decision line. See CR-4.

---

# Findings

## Critical

### CR-1 — `plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh:43,62` — false positive on this lane's own mission

I swept all 149 real mission-shaped docs in `docs/handoff/*/` carrying a `LANE_WRITES:` line, each
checked against its **own** declared write set. 6 refusals. Two are false positives, and the first
one is this lane:

```
REFUSED docs/handoff/DISPATCH-CLOSE-GATE-01/fix-round-2.md
    mission_writeset_refused missing=lib/leadv2-lane-guard.sh
REFUSED docs/handoff/dispatch-1c354714/lane-mission.md      <-- THIS lane's dispatched mission
    mission_writeset_refused missing=lib/leadv2-lane-guard.sh
### total missions with a LANE_WRITES line: 149 ; refused: 6
```

Cause — `fix-round-2.md`'s own `## Done means`, line 99:

> the pre-correction form of `fix-round-5.md` refused with `lib/leadv2-lane-guard.sh` named

That backtick is the **expected output string of the checker**, quoted from another lane's write-set
defect. It is not a file this lane writes, and this lane's `LANE_WRITES` correctly omits it. The
Done-means backtick scan (`:62` section detect, `:43` `path_re`) cannot tell "a path I must produce"
from "a path named inside a sentence about a different lane".

`REQUIRE_MISSION_WRITESET` defaults to `1` (`leadv2-dispatch-code.sh:646`), so had this shipped,
**the dispatch of this task's own round-2 mission would have been parked before spawn.** Round 1's
C2 verdict was "a false positive here gets the mechanism switched off permanently"; the fix moved
the false positive rather than removing it.

*Fix:* exclude a Done-means backtick whose line describes checker/test output, or — better —
restrict extraction to imperative constructions with the mission as subject (the `instr_re` shape)
and drop the blanket Done-means backtick sweep, which is the source of both remaining false
positives. Add `fix-round-2.md` and `dispatch-1c354714/lane-mission.md` as must-pass specimens.

### CR-2 — `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:3237` + `:180` — Mechanism 2 is wired to the wrong directory

The call is real; the argument is not. `HANDOFF` is defined at `:180` as
`"${ROOT}/docs/handoff/dispatch-${TASK}"`, and `TASK` is the **sig8**
(`leadv2-dispatch-code.sh:4553` passes `"${sig8}"`). `leadv2_red_proof_has_red`
(`lib/leadv2-red-proof.sh:46`) then requires `${dir}/red` to be a directory.

Measured against all 652 real dispatch handoff dirs on disk:

```
### total real dispatch handoff dirs: 652
### dirs that have a red/ subdir at all: 0
### dirs where the LIVE wiring would print at least one 'unproven:' line: 4
--- docs/handoff/dispatch-1c354714  (red/ dir: NO)
unproven: Mechanism 2 is a library and a CLI verb, not a mechanism
unproven: C1 — the wiring is invisible to the suite
unproven: C2 — it false-positives on a real, already-correct mission
unproven: C3 — it misses the specimens it was built for, and the fixture was written to fit
      from: lane-mission.md
--- docs/handoff/dispatch-37a9e8fa  (red/ dir: NO)   from: lane-mission.md
--- docs/handoff/dispatch-6280f73a  (red/ dir: NO)   from: lane-mission.md
--- docs/handoff/dispatch-8c4b0f7c  (red/ dir: NO)   from: developer.full.md, lane-mission.md
```

Three consequences, each disqualifying:

1. **It can never be satisfied.** Nothing in the repo ever creates
   `docs/handoff/dispatch-<sig8>/red/` — the only reference to that path anywhere is
   `lib/leadv2-red-proof.sh:46` itself. The real convention, from the missions themselves:
   ```
   $ grep -ohE 'docs/handoff/[^ ]+/[a-z0-9-]*red[a-z0-9-]*/' docs/handoff/*/{fix-round-*,lane-mission}.md | ...
      5 red/   4 round5-red/   4 round2-red/   3 round4-red/   1 round6-red/   1 round3-red/
   ```
   i.e. `docs/handoff/<TASK-ID>/roundN-red/`, under the human task-id dir, which is *not* `HANDOFF`.
   So `has_red` returns 1 for every fix on every real close, forever.
2. **When it fires it is 100% false positive.** 4 of 652 (0.6%), and in 3 of those 4 the names are
   read from `lane-mission.md` — the *brief*, which quotes the previous round's review findings. The
   mechanism reports the mission's own problem statement as the worker's unproven fixes.
3. **The showcase case is this lane.** `dispatch-1c354714` is DISPATCH-CLOSE-GATE-01's own dispatch
   dir; the four names printed are round-1's findings verbatim. The only "real close that prints an
   `unproven` name" this diff can produce is one where every printed name is wrong.

The round-2 Done-means required "proven by a real close that prints an `unproven` name". No such
artifact exists: `docs/handoff/DISPATCH-CLOSE-GATE-01/` contains only `fix-round-2.md`,
`lane-mission.md`, `review-r1.md` and the untracked `specimens/` — no `round2-red/`, no close log.
Round 1's central finding ("a verb nothing calls is not a mechanism") is now "a call nothing can
answer" — the same defect one layer in.

*Fix:* resolve the fix-claim source and the RED dir from the founder task id (`FOUNDER_TASK_ID` /
`LANE_NAME`, already available at `:24-31`), i.e. `${ROOT}/docs/handoff/${FOUNDER_TASK_ID}`, and
match `red/` **or** `round*-red/`. Add a control that runs the block against a fixture shaped like a
real task dir, and one proving the dispatch-dir form finds nothing.

### CR-3 — `tests/run-all.sh:133-135` — `--scope changed` still selects neither suite

Round-1 C4 is unfixed. The diff widened the `case` glob to include `lib/*.sh`, but that glob is
never reached: `changed` on a dirty lane contains no `plugins/` path at all, and the `HEAD~1..HEAD`
fallback at `:134` is gated on `changed` being *empty*.

Real lane tree, real command, runner stubbed so only selection is observed:

```
$ git diff --name-only HEAD
docs/LEAD_V2_STATE.md
docs/handoff/dispatch-nw5sig005/phases.d/e2e.yaml
... (12 paths, all docs/)

$ PATH=<stub-bash>:$PATH /bin/bash tests/run-all.sh --scope changed
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] .../tests/test-status-surface-bash32.sh
[RUN] .../tests/test-status-surface-single-lead.sh
[RUN] .../tests/test-status-surface-fast-names.sh
run-all: 4 passed, 0 failed, scope=changed
```

Neither new suite is selected. The unconditional fallback does not save it either:

```
$ grep -c 'mission-writeset\|red-proof-gate' plugins/leadv2/scripts/tests/run-core-offline.sh
0
```

Both new `EXTRA_SUITE_MAP` rows are dead. *Fix (unchanged from round 1):* union
`git diff --name-only HEAD` with `git diff --name-only $(git merge-base origin/main HEAD)..HEAD` —
do not treat a non-empty dirty set as "the changed set" — then paste the `--scope changed` output
showing both suites.

### CR-4 — `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:3242` + `tests/test-red-proof-gate.sh:147-154` — the close-side downgrade is untested

The C5 control tests that the block exists and computes a string. It does not test that the string
reaches the close. I removed every one of the five `${_pc_unproven_suffix}` interpolations from the
`_dl_note` calls in the production file — deleting the entire user-visible effect of Mechanism 2 —
and both suites stayed fully green:

```
M2 applied: removed all 5 uses of _pc_unproven_suffix from the _dl_note decision lines
=== M2 SUITE (red-proof) ===        SUMMARY: pass=14 fail=0
=== M2 SUITE (mission-writeset) === SUMMARY: pass=18 fail=0
```

Cause: `_extract_c5_block` (`test-red-proof-gate.sh:147-152`) awk-slices from the anchor comment to
the **first line that is exactly `fi`** and `eval`s that fragment. Every `_dl_note` call is below
that line, so nothing past the suffix assignment is under test. Round-1 C1 reproduced one level up:
the control locks the part that does not matter.

For balance, deleting the whole block IS caught:

```
M3 applied: whole C5 block deleted (897 chars), suffix stubbed empty
FAIL: C5 wiring: block anchors not found in leadv2-dispatch-product-close.sh (drifted, update extractor)
SUMMARY: pass=12 fail=1
```

*Fix:* extend the extracted region through the `_dl_note landed review_verdict_pass` line (or stub
`_dl_note` and assert the evidence string it receives contains `unproven=`), then re-run the M2
mutation and show it RED.

### CR-5 — `plugins/leadv2/scripts/tests/test-mission-writeset.sh:230-232` — the specimen fixtures are gitignored, so the suite is red for everyone else

```
$ git check-ignore -v docs/handoff/DISPATCH-CLOSE-GATE-01/specimens/fix-round-4.md
.gitignore:40:docs/handoff/*/*	docs/handoff/DISPATCH-CLOSE-GATE-01/specimens/fix-round-4.md
$ git ls-files docs/handoff/DISPATCH-CLOSE-GATE-01/specimens/
(empty)
$ git status --porcelain | grep -c specimens
0
```

The files exist only in this worktree. `.gitignore:40` (`docs/handoff/*/*`) means a plain `git add`
cannot commit them, and the diff under review does not commit them. On any other checkout the
`[[ -f "${R4}" ]]` guards fall to their `else` branches, which are `fail "specimen: ... not found"` —
a hard FAIL, not a skip. So the two assertions carrying the whole round-2 correctness claim are
green **only on this machine, in this worktree**.

*Fix:* move the specimens under `plugins/leadv2/scripts/tests/fixtures/` (tracked), or add a
`!docs/handoff/DISPATCH-CLOSE-GATE-01/specimens/**` negation — and commit them.

## High

### H-1 — `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:36` — unguarded `source` kills the mechanism in the three consumer repos

```bash
source "${SCRIPT_DIR}/lib/leadv2-red-proof.sh"
```

Every neighbouring source in that block is guarded (`_ROUTE_ARBITER_SH` at `:35` uses
`[[ -f ]] && ... || true`; `_PARKED_DETECT_SH` at `:40-41` has an explicit
`${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/...` fallback — for
exactly this reason). The new line has neither. Consumer repos hold a per-file symlink to the script
but do not carry the lib:

```
$ ls -la persona-engine/.claude/scripts/leadv2-dispatch-product-close.sh
... -> /Users/.../leadv2/plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
$ SCRIPT_DIR=$(cd "$(dirname persona-engine/.claude/scripts/leadv2-dispatch-product-close.sh)" && pwd)
SCRIPT_DIR=/Users/.../persona-engine/.claude/scripts
lib MISSING -> source fails
$ ls persona-engine/.claude/scripts/lib/leadv2-red-proof.sh
No such file or directory
```

`SCRIPT_DIR` is derived from `dirname "${BASH_SOURCE[0]}"`, which for a per-file symlink is the
*consumer's* dir. The script runs `set -uo pipefail` (no `-e`), so this is not fatal: it prints
`No such file or directory` into every close log, then `leadv2_red_proof_unproven` is a
command-not-found and `_pc_unproven` stays empty. Mechanism 2 is silently inert in persona-engine,
m3-market and respiro-ios — the repos that actually dispatch — plus a permanent spurious error line
in the close output.

*Fix:* mirror the `_PARKED_DETECT_SH` pattern — try `${SCRIPT_DIR}/lib/...`, fall back to
`${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/...`, guard with `[[ -f ]]`.

### H-2 — `plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh:43` — second false positive: a "must NOT exist" assertion read as a required write

```
REFUSED docs/handoff/DISPATCH-PIN-CLUSTER-01/fix-round-4.md
    mission_writeset_refused missing=plugins/leadv2/scripts/docs/,plugins/leadv2/scripts/.claude/
```

Source, line 81 of that mission:

> **nothing under `plugins/leadv2/scripts/docs/` or `plugins/leadv2/scripts/.claude/` is tracked**

A negative assertion about what must *not* exist, extracted as two paths the worker must write.
`citation_re` (`:33-36`) covers see/read/refer/per/cited/described/shown/documented; it has no
concept of a negation or of an assertion about repo state. Same root cause as CR-1.

(The other three refusals in the sweep — `ANTI-SILENCE-STATUSLINE-01/fix-round-3.md` missing its
`round3-red/`, and two lane-missions naming a deliverable outside the write set — are genuine true
positives. Precision on the 149-mission corpus is 3/6.)

### H-3 — `plugins/leadv2/scripts/tests/test-mission-writeset.sh:198` — the suite writes a mutant into the production scripts directory

```bash
MUT_DISPATCH="${SCRIPT_DIR}/../.mut-dispatch-code.$$.sh"
```

That resolves to `plugins/leadv2/scripts/.mut-dispatch-code.<pid>.sh` — a full copy of the
dispatcher, dropped next to the real one, in a tree symlinked into three live repos. The `rm -f` is
reached only on the success branch; a `^C`, a timeout, or a failure in `_run_prepass_refusal` leaves
it behind, and it is not gitignored by name. A stale `.mut-dispatch-code.*.sh` in the scripts dir is
exactly what a later glob or a `--scope all` `find` picks up.

*Fix:* write the mutant to `${TMP}` with a symlinked `lib/` beside it, or `trap`-remove on EXIT.

## Medium

### M-1 — `lib/leadv2-mission-writeset.sh:194-205` — the pasted correction is not a real repo path

The refusal on the round-5 specimen suggests:

```
LANE_WRITES: ...,.gitignore,lib/leadv2-lane-guard.sh
```

`lib/leadv2-lane-guard.sh` is the shortened form used in prose; the real file is
`plugins/leadv2/scripts/lib/leadv2-lane-guard.sh`. `leadv2_writeset_missing` tolerates the tail form
via its own `*"/${path}"` rule (`:167-169`), but the lane scope gate that actually enforces writes
does not. A human who pastes the suggested line gets a write-set entry this checker accepts and the
real gate does not. *Fix:* when the tail rule is what would have matched, emit the repo-rooted decl.

### M-2 — `leadv2-dispatch-product-close.sh:3240-3244` — arbitrary heading text into a `key=value` evidence field

`_pc_unproven_csv` is built with `tr '\n' '|'` and interpolated as `unproven=<csv>` into the
`_dl_note` evidence string and into `emit decision "... names=${_pc_unproven_csv}"`. The names are
raw markdown headings: they contain spaces (`unproven=negated grep never fails`, from the suite's
own C5 assertion) and may contain `=`, `|`, quotes or em-dashes (the live census produced
``N3 — the `pass_unlanded` exception is transitive, and its comment is false``). Any consumer that
splits the evidence string on whitespace or `=` mis-parses it. *Fix:* emit `unproven=<count>` and
keep the names on their own lines.

### M-3 — `leadv2-dispatch-product-close.sh:3266,3283,3287,3299,3325` — "downgraded" is a string append, not a downgrade

The terminal stays `landed` and the exit code is unchanged; only free-text evidence grows. D3 says
the gate must report and not trap the lane — correct — but the brief asked for a *downgrade*, and
nothing keyed on terminal state can distinguish a close with four unproven claims from a clean one.
Either give it its own terminal value / `landed_unproven` cause, or drop the word from the comment.

### M-4 — `tests/test-red-proof-gate.sh:155,187` — the C5 control is a source-grep plus an `eval` of a slice

`grep -qF 'leadv2_red_proof_unproven "${HANDOFF}"'` against the extracted text is a source assertion,
and the "negative control" mutates a **scratch copy** (`MUT_PC`) rather than the production file. It
does still discriminate for the specific case of the production call site being deleted (the outer
anchor grep fails -> hard `fail`; verified as M3 above), so it is not a fake control — but it is one
refactor away from being one, and it is why CR-4 slipped through. Prefer stubbing `_dl_note`/`emit`
and sourcing the real script region.

### M-5 — process: the round-2 rules' own RED-log requirement is unmet

`fix-round-2.md` required "Logs in `docs/handoff/DISPATCH-CLOSE-GATE-01/round2-red/`".
`ls docs/handoff/DISPATCH-CLOSE-GATE-01/` -> `fix-round-2.md  lane-mission.md  review-r1.md` (plus
the untracked `specimens/`). No `round2-red/`, no mutation logs, no close output. The round-2
deliverable's mutation claims are unbacked on disk — precisely the condition Mechanism 2 exists to
detect.

---

## Type checks

Not applicable — the diff is Bash plus one embedded Python heredoc; no Python module, no TypeScript,
so `mypy --strict` / `tsc --noEmit` have no target. The equivalent checks that were run:

```
$ /bin/bash --version | head -1
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)

$ grep -nE 'mapfile|readarray|read -N|read -d|\$\{[A-Za-z_]+\^\^|declare -A|local -A' \
    lib/leadv2-mission-writeset.sh lib/leadv2-red-proof.sh \
    tests/test-mission-writeset.sh tests/test-red-proof-gate.sh
plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh:11:# Bash 3.2 safe: no associative arrays, no ${x^^}, no mapfile.
plugins/leadv2/scripts/lib/leadv2-red-proof.sh:19:# Bash 3.2 safe: no associative arrays, no ${x^^}, no mapfile.
  (comments only — no bash-4 idiom in code)

$ /bin/bash plugins/leadv2/scripts/tests/test-mission-writeset.sh  -> SUMMARY: pass=18 fail=0
$ /bin/bash plugins/leadv2/scripts/tests/test-red-proof-gate.sh    -> SUMMARY: pass=14 fail=0
```

No unbound-array-under-`set -u` regression in the new code: `${decls[@]+"${decls[@]}"}`
(`lib/leadv2-mission-writeset.sh:145`) is the correct bash-3.2 form and the empty-writeset path
fails closed (evidence in Item 5). Pre-existing, not from this diff: `tests/run-all.sh:166` iterates
`"${SUITES[@]}"` unguarded, which would be an unbound-variable error under bash 3.2 `set -u` if
selection ever produced zero suites — today four always-on suites mask it.

## Pre-finalize contradiction scan

- **Env-var names vs readers:** `LEADV2_REQUIRE_MISSION_WRITESET` -> `REQUIRE_MISSION_WRITESET`
  (`leadv2-dispatch-code.sh:646`, read at `:3467`) — consistent, default `1` (live).
  `LEADV2_CLOSE_GATE_DIR_OVERRIDE` (`:5919`) and `LEADV2_DISPATCH_SOURCE_ONLY` (`:7688`) are each
  read exactly where declared and set only by the suites. No drift.
- **Flag semantics:** `REQUIRE_MISSION_WRITESET=0` genuinely restores prior behaviour (the guard
  returns 0 before any work) — matches its comment.
- **Path existence:** three contradictions, all filed —
  `docs/handoff/DISPATCH-CLOSE-GATE-01/specimens/` exists on disk but is gitignored and untracked
  (CR-5); `${SCRIPT_DIR}/lib/leadv2-red-proof.sh` does not exist for the symlinked consumers that
  run product-close (H-1); `${HANDOFF}/red` exists in 0 of 652 real dispatch dirs (CR-2).
- **Comment vs behaviour:** `leadv2-dispatch-product-close.sh:3230-3234` claims the block makes
  "`landed` here visibly distinguishable from a fully proven landed close" — true only of the
  evidence string, not of the terminal (M-3); and "cross-check fixes the worker claimed" is false on
  the live path, where the names come from `lane-mission.md` (CR-2).

## What must land in round 3

1. CR-2: point Mechanism 2 at `docs/handoff/${FOUNDER_TASK_ID}` and accept `round*-red/`; prove it
   with a real close whose printed names are the worker's, plus a control showing the old
   dispatch-dir form finds nothing.
2. CR-1 + H-2: stop extracting a path from a sentence that merely quotes one. Both
   `docs/handoff/DISPATCH-CLOSE-GATE-01/fix-round-2.md` and
   `docs/handoff/DISPATCH-PIN-CLUSTER-01/fix-round-4.md` become must-pass specimens; re-run the
   149-mission sweep and report the refusal list.
3. CR-4: extend the C5 control past the `_dl_note` calls; show the 5-suffix-deletion mutation RED.
4. CR-3: union the dirty set with `merge-base..HEAD`; paste `--scope changed` naming both suites.
5. CR-5 + H-1 + H-3: commit the specimens somewhere tracked; guard the `source`; move the mutant out
   of the production scripts dir.
6. Write the mutation logs to `docs/handoff/DISPATCH-CLOSE-GATE-01/round3-red/` and commit.

**VERDICT: fail**
