# ROTTED-NEGATIVE-CONTROLS-CENSUS-01

Assigned after my own aside during ACTIVE-REGISTRY-FIVE-EPERM-COLLAPSING-PID-ALIVE-01:
`test-phase-refusal-lane-release.sh`'s M3 mutation control targets a code
pattern (`if _prlr_alive(rpid) and _prlr_kind(rpid) == "worker":`) that no
longer exists in `leadv2-dispatch-code.sh` (the function it mutates was
refactored to delegate to `leadv2_active_release_verified` in
`leadv2-active-registry.sh` instead). Leadmain escalated this to priority 1,
framed as a possibly-systemic "lying-green negative control" risk across the
~92 suites in `plugins/leadv2/scripts/tests/` that declare a mutation or
negative control, since `E2E-KILLRATE-01`'s kill-rate doctrine treats these
controls as its main evidence.

**Headline correction, verified, not assumed: the specific danger described
— a mutation that changes nothing, a suite that runs untouched, a control
that reports green — was NOT found anywhere in this census, including in the
cited example.** What IS real: M3 is drifted and currently produces a
confusing failure, not a silent pass. The distinction matters because it
changes the shape of the fix from "build new infrastructure to catch a
class of silent failures" to "refresh a small number of stale assertions
that are already failing loudly."

## Methodology

Two independent, complementary scans across all 455 `.sh` files in
`plugins/leadv2/scripts/tests/`:

1. **Idiom-matching**: regex-detect the known mutation idioms (`sed
   's|X|Y|' ... > $VAR`, a local `mutate()` bash/perl helper call, a Python
   `target = "..."` used with `.replace(target` / `count(target)`, and any
   call to the already-vetted shared tool `leadv2-mutation-control.sh`).
   Resolved each hit's target file (tracing the bash variable's own
   assignment inside the same file) and ran `grep -cF` for the **correctly
   unescaped literal text** (sed/perl regex escaping — `\[`, `\$`, `\{`,
   `\&` — was translated to the literal characters before matching; two of
   my own first-pass automated results were false positives caused by
   skipping this step, caught by re-deriving the literal text by hand and
   re-checking — see "False leads" below).
2. **No-guard sweep**: independently regex-scan for the *shape* of the
   danger itself — a `sed`/`perl` mutation writing to a `*mutant*`/`*mut*`
   variable with **no** `cmp -s` / `diff -q` / `assert ... in ...` /
   `count(target)` guard within 300 characters after the write. This is
   the pattern-agnostic net: it doesn't care what idiom produced the
   mutant, only whether anything checks that the mutant actually differs
   from the source.

## Results

**Idiom-matching scan**: 29 files matched a known mutation-declaring idiom
(30 hits — one file declares two). Of these, 13 use the shared
`leadv2-mutation-control.sh` tool, which is self-checking by construction
(`control_not_applied` / `anchor_count` on a no-op patch — confirmed by
reading its own source, not assumed). Of the remaining 16 directly
resolvable to a target+pattern pair: **all 16 are ALIVE** (pattern present,
`grep -cF` count > 0) after correcting the escaping bug in my first pass.

**No-guard sweep** (the pattern-agnostic net, independent of idiom):
**exactly one hit across all 455 files** — `test-arm-admission.sh`. Traced
it: the "mutated" file is `${FIXTURE}/routing.yaml`, a fixture the SAME
test script writes moments earlier in its own run (not a production
source file). The pattern is guaranteed present because the test controls
both sides. This is a same-file, same-run coupling, not the
cross-file "production code drifted out from under a stale test" scenario
the task is about — low risk, not counted as a finding.

**Conclusion: zero confirmed instances of a mutation control silently
reporting green against an unchanged mutant**, across both scans.

## False leads (worth recording — this is exactly the class of mistake the
task exists to catch, and I made it twice before verifying)

1. **`test-t13-slice1.sh`**: my first-pass script flagged its `mutate()`
   call (perl `s/if \[\[ "\$\{path\}" == "docs\/tasks\.yaml" \]\]; then/.../`)
   against `lib/leadv2-lane-guard.sh` as ROTTED, because my automated
   `grep -cF` used the raw regex-escaped capture group. Manually
   translating the perl escaping to the literal text
   (`if [[ "${path}" == "docs/tasks.yaml" ]]; then`) and re-checking:
   present, count=1. **False positive**, caused by my own tooling, not a
   real defect.
2. **`test-orphan-reaper-and-singleflight-01.sh` Case E**: the sed target
   symbol `PULSE_OWNER_IDLE_MIN` genuinely does not exist anywhere in
   persona-engine's `anti-silence-pulse.sh` (confirmed, zero occurrences).
   But the WHOLE Case E block is gated by an outer
   `if grep -q "_owner_belt_should_exit" "$PE_PULSE"` check that is ALSO
   false today — so the mutation is never even attempted. Running the
   suite confirms an explicit, honest `SKIP: E: ... has no owner belt
   (pre-belt checkout)` line, not a silent pass. **Correctly self-gating,
   not rotted-and-lying.**
3. **`test-phase-refusal-lane-release.sh` M3** (the case that started this
   task): its own `mutate()` helper already has
   `assert old in t, "mutation anchor not found: " + old[:60]` (line 186)
   — the exact guard mechanism this task was going to build from scratch.
   Because the anchor is genuinely gone, the assert fires, `mutate()`
   raises, the mutant file `dc.m3.sh` is never created, and the suite's
   own downstream `run_release` call visibly fails
   (`awk: can't open file .../dc.m3.sh`, then `FAIL: M3 unexpected rc pair
   base=3 mut=1`). **This already fails loudly. It has never been silently
   green.** Confirmed the suite's other three controls in the same file
   (M1, M2, M4) all currently "bite" correctly — only M3 is stale.

## What this means for E2E-KILLRATE-01 and the fix scope

The doctrine's worry — that a rotted control inflates kill-rate the safest-
looking way, silently — is a real *class* of risk worth guarding against,
but **the codebase's own authors already converged on the guard,
independently, in the two dominant idioms**: the bash `cmp -s "$SRC" "$MUT"
... echo NC-SETUP-FAIL` pattern (used by every `nc-*.sh` file I checked)
and the Python `assert old in t` pattern (used by
`test-phase-refusal-lane-release.sh`'s `mutate()`). Both die loudly on a
no-op patch. No new shared mechanism is needed to close a class of failure
this census could not find a live instance of.

**Requirement 2 ("fix the mechanism, not 92 suites") is satisfied by there
being no mechanism to fix** — the one candidate outside these two idioms
(the no-guard sweep's single hit) turned out to be a same-file fixture
mutation with no drift exposure. I am not proposing new infrastructure
against a risk I verified is not materializing here; that would be
solving a problem the evidence says does not exist, at the cost of a
change nobody asked for.

**Requirement 4 ("if many are rotted, list them by name, don't fix in
bulk")**: exactly three suites carry a demonstrably stale (not silently
green — loudly failing) assertion, named here:
- `test-mission-writeset.sh` — the "control USAGE" mutation (usage heredoc
  drifted); its three sibling controls (CITE, COVERAGE, WIRING) are fine.
- `test-liveness-tristate-01.sh` — "T1-NC: mutation pattern not found ...
  the source line changed" (self-reported by the suite itself).
- `test-phase-refusal-lane-release.sh` — M3 only (M1/M2/M4 all bite
  correctly), targeting `leadv2-dispatch-code.sh`'s now-absent
  `_prlr_alive(rpid) and _prlr_kind(rpid) == "worker"` line — the check
  moved to `leadv2_active_release_verified` in
  `leadv2-active-registry.sh` (already covered, independently, by the
  D1/D2 pair I added there in ACTIVE-REGISTRY-FIVE-EPERM-COLLAPSING-PID-ALIVE-01).

Not fixed here — each is a small, independent, low-risk maintenance item
(refresh a stale string constant against its current target), not part of
this census's scope, and not urgent: all three fail loudly today, so
nothing is lying green while they wait.

## Scope and limits of this census

Idiom-matching covered 29/455 files (files matching a KNOWN mutation
idiom). The no-guard sweep is idiom-agnostic and covered all 455, which is
the stronger claim for the specific "silently reports green" risk — but it
is still a regex heuristic (300-char proximity window for a guard), not a
proof for every possible shape of self-check. I am confident in "zero
found" as a measurement, not certain as an absolute; a residual risk is an
NC whose guard sits further than 300 characters from the mutation write,
or one written in a form neither regex recognizes. Given the sweep's zero
hits and the two idioms' evident dominance, I judged further exhaustive
manual reading of all 455 files not to be a good use of effort without a
concrete lead pointing at a specific file.
