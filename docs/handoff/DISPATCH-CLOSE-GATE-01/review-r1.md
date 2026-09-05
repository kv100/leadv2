# DISPATCH-CLOSE-GATE-01 — adversarial review, round 1

**VERDICT: fail**

Lane: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01` @ `0bb8743`
Reviewed: `git diff origin/main...HEAD -- plugins/ tests/` (6 files, +594/-3)

| Mechanism | Verdict |
|---|---|
| 1 — `lib/leadv2-mission-writeset.sh` | **BROKEN** — the lib logic is genuinely mutation-proven, but it false-positives on a real corrected specimen, misses the specimen the brief named, fails open on bash 3.2, and its dispatcher wiring is untested |
| 2 — `lib/leadv2-red-proof.sh` | **UNPROVEN** — the lib logic is mutation-proven, but the mechanism is **not wired into any close gate**; nothing on the live path calls it |

---

## Mechanism 2 — UNPROVEN: zero callers on the live close path

The mission's own round-2 note (`lane-mission.md:107-111`) says: *"the only live close gate is
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, and that file was missing from
`LANE_WRITES`. It is now in scope."* The file is in `LANE_WRITES`. The diff never touches it.

```
$ git diff origin/main...HEAD --name-only
plugins/leadv2/scripts/leadv2-dispatch-code.sh
plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh
plugins/leadv2/scripts/lib/leadv2-red-proof.sh
plugins/leadv2/scripts/tests/test-mission-writeset.sh
plugins/leadv2/scripts/tests/test-red-proof-gate.sh
tests/run-all.sh
```

```
$ grep -rn "close-gate\|leadv2_red_proof" --include="*.sh" plugins/ | grep -v "/tests/"
plugins/leadv2/scripts/leadv2-dispatch-code.sh:461:source "${SCRIPT_DIR}/lib/leadv2-red-proof.sh"
plugins/leadv2/scripts/leadv2-dispatch-code.sh:5921:  unproven="$(leadv2_red_proof_unproven "${dir}")"   # inside cmd_close_gate
plugins/leadv2/scripts/leadv2-dispatch-code.sh:7680:  close-gate)    shift; cmd_close_gate "$@" ;;
```

The only path into `leadv2_red_proof_unproven` is a human typing
`leadv2-dispatch-code.sh close-gate <task-id>`. The brief's requirement is *"enforced at the close
gate … the close is downgraded, not passed silently."* Nothing downgrades anything. This is a
library plus a CLI, not a mechanism. It cannot fire on a real close.

The library itself IS real — mutations applied inside the function body, on the production file,
in a scratch copy of the lane:

```
M3: leadv2_red_proof_has_red — replaced the nonzero-failure-count grep with `return 0`
FAIL: has_red: a '0 failed' artifact wrongly satisfied its fix
SUMMARY: pass=8 fail=2                       <-- RED

M4: leadv2_red_proof_unproven — replaced the `has_red || printf 'unproven: …'` cross-check with `:`
FAIL: CLI: close-gate rc=0 out=… red_proof_ok task=DISPATCH-CLOSE-GATE-01/redproof-fixture-85871
SUMMARY: pass=7 fail=3                       <-- RED

restore -> SUMMARY: pass=10 fail=0            <-- GREEN
```

So the three fixture behaviours the brief asked for (two named fixes + one RED artifact -> exactly
one `unproven`; a `0 failed` artifact does not satisfy; rc=0 so the lane is never trapped) are
genuinely covered at the library level. The wiring is not, because there is none.

---

## Mechanism 1 — BROKEN

### The lib logic is real

In-body mutation on the production file:

```
M2: leadv2_writeset_missing — replaced `[[ ${hit} -eq 0 ]] && printf '%s\n' "${path}"` with `:`
SUMMARY: pass=11 fail=3                       <-- RED
restore -> SUMMARY: pass=14 fail=0            <-- GREEN
```

The suite's own C1/C2 controls also survive the "sed a scratch copy" trap the brief warned about:
both mutations `sys.exit(2)` when the anchor is absent and the suite treats that as `fail`
(`test-mission-writeset.sh:126-127, 152-153`), so a zero-match is a hard failure, not a skip. That
part is honest work — and I confirmed it fires: mutation M3 above shifted the red-proof lib enough
that its own C1 anchor vanished and the suite printed
`FAIL: control C1: mutation source pattern not found (lib drifted, update mutation)`.

### Everything around it is broken

#### C1 (Critical) — the dispatcher wiring is invisible to the suite

`leadv2-dispatch-code.sh:4105, 4121, 4334` — the three `_mission_writeset_guard` call sites. I
deleted all three (keeping the function definition) and re-ran the suite:

```
############ M1: delete ALL _mission_writeset_guard CALL SITES (keep definition) ############
call sites removed: 3
PASS: control C2: mutated lib always reports covered -> caught (would be red)
SUMMARY: pass=14 fail=0
M1 suite rc=0
```

**Green.** The suite tests the lib functions and the standalone `mission-writeset-check`
subcommand — neither of which is the live path. Remove the guard from `architect_prepass` and every
assertion still passes. This is finding #1 from the brief in its purest form: the load-bearing
control is not the one under test.

**Required fix:** a behavioural assertion that drives `architect_prepass` (or a harness that calls
it) with a non-covering mission and asserts the prepass returns 1 / emits
`mission_writeset_refused`. Then mutate the call site out and show that assertion RED.

#### C2 (Critical) — false positive on a real, already-corrected mission

`docs/handoff/ANTI-SILENCE-STATUSLINE-01/fix-round-4.md` is the *corrected* round-4 brief. Its
`LANE_WRITES` (line 5) already contains `docs/handoff/ANTI-SILENCE-STATUSLINE-01/round4-red/` and
`…/render-proof.md`. The checker refuses it:

```
$ leadv2-dispatch-code.sh mission-writeset-check docs/handoff/ANTI-SILENCE-STATUSLINE-01/fix-round-4.md
rc=1
mission_writeset_refused missing=round4-red/
round4-red/
LANE_WRITES: round4-red/
```

Cause: `fix-round-4.md:95` says "logs under \`round4-red/\`" — a bare relative fragment. `path_re`
(`lib/leadv2-mission-writeset.sh:41`) matches any backticked token containing a `/`, so
`round4-red/` becomes a "required path", and no absolute `LANE_WRITES` entry covers it.

Had Mechanism 1 been live today it would have blocked the corrected round-4 dispatch. The brief's
own words: *"a false positive here blocks good dispatches and the mechanism will be turned off."*
Same defect on this lane's own mission (`lane-mission.md:100`, "logs in \`red/\`") — the fragment
`red/` is reported missing even against a fully correct write set.

**Required fix:** ignore extracted tokens that are not repo-rooted (fewer than two path segments,
or a first segment that is not a top-level dir), or resolve a fragment against the handoff dir
before comparing.

#### C3 (Critical) — misses the specimen the brief named

`docs/handoff/DISPATCH-PIN-CLUSTER-01/fix-round-5.md`, the second specimen the brief pointed at:

```
$ leadv2-dispatch-code.sh mission-writeset-check docs/handoff/DISPATCH-PIN-CLUSTER-01/fix-round-5.md
rc=0
mission_writeset_ok
```

Zero required paths extracted. Two reasons, both structural:

1. Its real miss was **source** files (`lib/leadv2-lane-guard.sh` + four test harnesses named in
   the body, per its own write-set note), which the extractor never looks at — it only scans
   `## Done means` and two instruction phrasings.
2. `instr_re` (`lib/leadv2-mission-writeset.sh:62-66`) matches the literal `leave the logs in`.
   Every real mission in this repo — including `fix-round-5.md`, `fix-round-4.md`, and
   `lane-mission.md:87` — writes **"Leave the RED logs in"**. The word `RED` between "the" and
   "logs" defeats the regex. Proof, on this lane's own reconstructed pre-correction mission
   (round-1 `LANE_WRITES`: handoff dir and product-close removed, round-2 note stripped):

```
$ mission-writeset-check <lane-mission, pre-correction>
rc=1
mission_writeset_refused missing=red/,docs/handoff/DISPATCH-CLOSE-GATE-01/report.md
red/
docs/handoff/DISPATCH-CLOSE-GATE-01/report.md
LANE_WRITES: red/,docs/handoff/DISPATCH-CLOSE-GATE-01/report.md
```

   `docs/handoff/DISPATCH-CLOSE-GATE-01/red/` — the path from the "Leave the RED logs in" line at
   `lane-mission.md:87`, the single most important required artifact path in the brief — **is not
   in the missing list**. What was caught was the bare `red/` fragment from a different line, by
   accident, and `report.md` from the Done-means backtick scan. So the refusal on this specimen is
   right for the wrong reason and its suggested correction is wrong.

   The `test-mission-writeset.sh:71-75` assertion for this rule passes only because its fixture
   (`MISSION_INSTR`, line 54) uses the synthetic phrasing "Also leave the logs in" that no mission
   in this repo uses. The fixture was written to fit the regex.

**Required fix:** loosen to `leave .*logs? in` / `leave the .* in`, and replace the synthetic
fixture with the two on-disk specimens.

#### C4 (Critical) — `--scope changed` selects neither new suite from a dirty tree

The brief required this and it is not met. Run against the actual lane worktree (9 dirty
control-plane files, as every lane always has):

```
$ git diff --name-only HEAD
docs/leadv2/.bus-offsets
docs/leadv2/.bus.lock
docs/leadv2/.merge.lock
docs/leadv2/active.yaml
docs/leadv2/active.yaml.lock
docs/leadv2/bus.jsonl
docs/leadv2/merge-queue.jsonl
docs/leadv2/open-threads.md
docs/leadv2/questions

$ bash tests/run-all.sh --scope changed
[RUN] …/plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] running 83 suites across 4 shards
```

Neither `test-mission-writeset.sh` nor `test-red-proof-gate.sh` is selected. `tests/run-all.sh:133`
computes `changed` from `git diff --name-only HEAD`, which on a dirty lane is non-empty and
contains only `docs/leadv2/*` — so the `HEAD~1..HEAD` fallback at line 134 never runs and the
lane's own committed files are invisible. The `EXTRA_SUITE_MAP` rows added at lines 121-124 are
never consulted.

Nor does the unconditional fallback save it — `run-core-offline.sh` drives a hand-kept
`SUITE_DEFS` array:

```
$ grep -c "mission-writeset\|red-proof-gate" plugins/leadv2/scripts/tests/run-core-offline.sh
0
```

Only `--scope all` (the `find -maxdepth 1 -name 'test-*.sh'` at `tests/run-all.sh:130`) ever runs
them. A green suite CI never selects is worth nothing — this is the exact `EXTRA_SUITE_MAP` lesson
the brief cited.

---

## Findings

### Critical

**C1 — `plugins/leadv2/scripts/leadv2-dispatch-code.sh:4105,4121,4334` — test coverage**
Deleting all three `_mission_writeset_guard` call sites leaves `test-mission-writeset.sh` at
`pass=14 fail=0`. The suite proves the lib, never the wiring.
*Fix:* add an assertion that drives `architect_prepass` end-to-end (or a thin harness around it)
and asserts refusal + the `mission_writeset_refused` decision line; mutate the call site out and
paste the RED.

**C2 — `plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh:41` — correctness (false positive)**
`path_re` accepts bare relative fragments (`red/`, `round4-red/`). `fix-round-4.md`, a correct
mission, is refused rc=1. *Fix:* require ≥2 path segments and a repo-rooted first segment, or
resolve fragments against the handoff dir before the coverage test. Add `fix-round-4.md` as a
must-pass fixture.

**C3 — `plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh:62-66` — correctness (miss)**
`instr_re` requires the literal `leave the logs in`; every real mission writes `Leave the RED logs
in`, so the instruction scan is dead on the whole corpus. `fix-round-5.md` returns
`mission_writeset_ok`; this lane's own pre-correction mission does not name
`docs/handoff/DISPATCH-CLOSE-GATE-01/red/`. `test-mission-writeset.sh:54` uses a fixture written to
fit the regex rather than a real specimen. *Fix:* loosen the pattern and use the on-disk specimens.

**C4 — `tests/run-all.sh:133-144` — CI selection**
`--scope changed` on a dirty lane tree selects neither new suite; `run-core-offline.sh` does not
contain them either. *Fix:* union `git diff --name-only HEAD` with `git diff --name-only
<merge-base>..HEAD` (do not treat non-empty dirty output as "the changed set"), then paste the
`--scope changed` output showing both suites.

**C5 — `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` (untouched) — mechanism not wired**
Mechanism 2 has no caller on the live close path. The file is in `LANE_WRITES` and the mission's
round-2 note names it as the only live close gate. *Fix:* call `leadv2_red_proof_unproven` in
product-close, print each `unproven: <name>` into the close verdict, and downgrade the close
outcome (never block, per D3). Then add a control that removes that call and shows the suite RED.

### High

**H1 — `plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh:101,104,111` — bash 3.2 fail-open**
`local -a decls=()` + `for decl in "${decls[@]}"` is an unbound array under `set -u` on bash
3.2.57. `leadv2-dispatch-code.sh:277` is `set -uo pipefail`. When `writes_csv` ends up empty (no
CSV arg **and** no `LANE_WRITES:` line in the mission — the documented fallback branch at lines
95-99), the function aborts and the caller's command substitution swallows it:

```
$ /bin/bash --version | head -1
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)

$ mission-writeset-check <mission requiring docs/handoff/X/round4-red/, no LANE_WRITES line>
…/lib/leadv2-mission-writeset.sh: line 87: decls[@]: unbound variable
mission_writeset_ok
rc=0
```

`_mission_writeset_guard` (`leadv2-dispatch-code.sh:3466-3477`) reaches the same state — it passes
`${writes}`, and `_lane_writes_guard` returns 0 with **empty** writes on three live paths
(report-lane deliverable, prepass writes, existing lane worktree —
`leadv2-dispatch-code.sh:3449-3462`). Empty `missing` -> `return 0` -> dispatch proceeds. The gate
fails **open**, silently, and the mission explicitly banned this construct
(`lane-mission.md:91-92`). *Fix:* `${decls[@]+"${decls[@]}"}` or seed with a sentinel; and make an
empty write set with required paths a refusal, not a pass.

**H2 — `plugins/leadv2/scripts/leadv2-dispatch-code.sh:5900` and `:3471` — the corrected line
destroys the write set**
`leadv2_writeset_suggest_line` is given the caller's `writes_csv`, which is empty whenever the lib
fell back to parsing the mission's own `LANE_WRITES:` line. Result on both real specimens:

```
mission_writeset_refused missing=round4-red/
LANE_WRITES: round4-red/          <-- the other 7 declared entries are gone
```

The entire purpose of that line is to be pasted. Pasting it deletes the lane's write set.
*Fix:* have `leadv2_writeset_missing` export the resolved csv (or re-run the same fallback inside
`suggest_line`) so the suggestion is existing + missing. `test-mission-writeset.sh:99-101` only
covers the case where the csv is passed explicitly, which is why this survived.

**H3 — `plugins/leadv2/scripts/tests/test-mission-writeset.sh` / `test-red-proof-gate.sh` —
no negative control for either mechanism's wiring**
Neither suite has an assertion that goes RED when the mechanism is disconnected from its host
(C1, C5). Both suites are unit tests of two libs, presented as mechanism proofs. Every `PASS:` line
in `red/mission-writeset-green.log` and `red/red-proof-green.log` is about the lib.

### Medium

**M1 — `tests/run-all.sh:139-144` — false comment, no-op change**
The comment claims "a bare `scripts/*.sh` glob never matches a subdirectory". In bash `[[ == ]]`
pattern matching, `*` matches `/`:

```
$ cf=plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh
$ [[ "$cf" == plugins/leadv2/scripts/*.sh ]] && echo MATCHES
MATCHES
```

The `case` widening changes nothing and the stated rationale is wrong. *Fix:* revert the hunk or
correct the comment; do not leave a false rationale the next reader will trust.

**M2 — `plugins/leadv2/scripts/tests/test-red-proof-gate.sh:22` — non-hermetic suite**
`FIXTURE_DIR="${LANE_ROOT}/docs/handoff/DISPATCH-CLOSE-GATE-01/redproof-fixture-$$"` writes into
the real repo. A killed run leaves `redproof-fixture-<pid>/` behind in a shared checkout, and
`cmd_close_gate` then reports it. *Fix:* make `cmd_close_gate` accept an absolute dir (or a
`LEADV2_HANDOFF_ROOT` override) and point the fixture at `mktemp -d`.

**M3 — Done-means not met**
`docs/handoff/DISPATCH-CLOSE-GATE-01/report.md` does not exist (required by `lane-mission.md:102`),
and no `--scope changed` output was captured. `red/` contains only 4 lib-level logs.

**M4 — `plugins/leadv2/scripts/lib/leadv2-red-proof.sh:51` — untested requirement**
The `grep -qiE 'mutation'` condition has no coverage: removing it changes no fixture outcome. Add a
fixture whose artifact shows `3 failed` but names no mutation.

**M5 — `plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh:121` — SC2254**
```
In plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh line 121:
        *'*'*) case "${path}" in ${decl}) hit=1 ;; esac ;;
                                 ^-----^ SC2254 (warning): Quote expansions in case patterns to match literally rather than as a glob.
```
Intentional here (glob coverage), but suppress it explicitly with `# shellcheck disable=SC2254` so
a later shellcheck sweep does not "fix" it.

### Low

**L1 — `plugins/leadv2/scripts/leadv2-dispatch-code.sh:5918`** — `cmd_close_gate` concatenates an
unvalidated `task_id` onto `PROJECT_ROOT/docs/handoff/`. The suite relies on a `/` in the id
(`test-red-proof-gate.sh:97`). Reject `..` and a leading `/` at minimum.

**L2 — `tests/run-all.sh:121-124`** — four rows where two suffice; the map already accepts both the
bare stem and `<stem>.sh` (`tests/run-all.sh:157`).

---

## Type/lint output (verbatim)

`mypy --strict` / `tsc --noEmit` are not applicable — the diff is bash only. Substituted:

```
$ bash -n plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh \
          plugins/leadv2/scripts/lib/leadv2-red-proof.sh \
          plugins/leadv2/scripts/tests/test-mission-writeset.sh \
          plugins/leadv2/scripts/tests/test-red-proof-gate.sh
(clean)

$ shellcheck -S warning plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh \
    plugins/leadv2/scripts/lib/leadv2-red-proof.sh \
    plugins/leadv2/scripts/tests/test-mission-writeset.sh \
    plugins/leadv2/scripts/tests/test-red-proof-gate.sh

In plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh line 121:
        *'*'*) case "${path}" in ${decl}) hit=1 ;; esac ;;
                                 ^-----^ SC2254 (warning): Quote expansions in case patterns to match literally rather than as a glob.

For more information:
  https://www.shellcheck.net/wiki/SC2254 -- Quote expansions in case patterns...
```

Baseline suite runs (macOS `/bin/bash` 3.2.57, unmutated):
```
$ /bin/bash plugins/leadv2/scripts/tests/test-mission-writeset.sh
SUMMARY: pass=14 fail=0   rc=0
$ /bin/bash plugins/leadv2/scripts/tests/test-red-proof-gate.sh
SUMMARY: pass=10 fail=0   rc=0
```

Mutation matrix — all mutations applied INSIDE the function body, on the production file, in a
scratch copy of the lane tree (the lane itself was never edited):

| # | Mutation | Suite | Result |
|---|---|---|---|
| M1 | delete all 3 `_mission_writeset_guard` call sites (definition kept) | test-mission-writeset | **GREEN 14/0 — control does not exist** |
| M2 | `leadv2_writeset_missing`: `[[ ${hit} -eq 0 ]] && printf …` -> `:` | test-mission-writeset | RED 11/3 |
| M3 | `leadv2_red_proof_has_red`: nonzero-count grep -> `return 0` | test-red-proof-gate | RED 8/2 |
| M4 | `leadv2_red_proof_unproven`: cross-check -> `:` | test-red-proof-gate | RED 7/3 |
| — | restore | both | GREEN 14/0, 10/0 |

The worker's own `red/mission-writeset-red-C1.log` (3 FAIL) and `red/red-proof-red-C1.log`
(2 FAIL) reproduce; they are genuine lib-level mutations, not staged output. They simply do not
cover either mechanism's wiring.

---

## Contradiction scan

- `LEADV2_REQUIRE_MISSION_WRITESET` -> `REQUIRE_MISSION_WRITESET` (`leadv2-dispatch-code.sh:646`):
  consistent, default `1`, no drift against any other usage. **OK**
- `EXTRA_SUITE_MAP` key form: both `<stem>` and `<stem>.sh` rows are valid at the lookup
  (`tests/run-all.sh:157`). **OK** (redundant, see L2)
- **CONTRADICTION** — `tests/run-all.sh:139-141` comment vs bash `[[ == ]]` semantics (M1 above);
  the stated reason for the change is false and the change is inert.
- **CONTRADICTION** — `lane-mission.md:5` `LANE_WRITES` and `:107-111` both name
  `leadv2-dispatch-product-close.sh` as the live close gate; the diff never touches it (C5).
- **CONTRADICTION** — `lane-mission.md:91-92` bans unbound arrays under `set -u`;
  `lib/leadv2-mission-writeset.sh:101-111` ships one (H1).
- **CONTRADICTION** — `lane-mission.md:102` requires
  `docs/handoff/DISPATCH-CLOSE-GATE-01/report.md`; it does not exist (M3).
- Path existence: `lib/` is an established sourced-lib directory (`lib/leadv2-lane-guard.sh`
  predates this lane), and `source "${SCRIPT_DIR}/lib/…"` mirrors the working
  `source "${SCRIPT_DIR}/leadv2-portable-lock.sh"` at `:456`. **OK**

---

## What round 2 must do

1. Wire `leadv2_red_proof_unproven` into `leadv2-dispatch-product-close.sh` and downgrade the close
   verdict on any `unproven:` line. Control: remove the call, suite goes RED.
2. Add a wiring control for `_mission_writeset_guard` in `architect_prepass`. Control: remove the
   call site, suite goes RED. (Today it stays green — M1.)
3. Make `fix-round-4.md` a must-pass (`ok`) fixture and the reconstructed pre-correction
   `fix-round-5.md` / `lane-mission.md` must-refuse fixtures. Every fixture a real on-disk
   specimen, not a hand-fitted string.
4. Fix the unbound-array fail-open and make an empty write set with required paths a refusal.
5. Fix `suggest_line` so the pasted line preserves the existing write set.
6. Fix `--scope changed` selection on a dirty tree and paste the output showing both suites.
7. Write `report.md` with the actual refusal message and the actual `unproven:` line.

DELIVERABLE_COMPLETE
