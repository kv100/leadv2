verdict: APPROVE
next_action: deploy

# dispatch-9e1f4297 — critic.full.md — LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01

## Method

Read developer.full.md / .summary.md, `git diff main...HEAD` (4 tracked files:
`leadv2-lane-outcome.sh`, `tests/test-lane-outcome-reads-state.sh`, both
handoff docs). `bash -n` clean, `shellcheck -S warning` clean (0 findings).
Re-derived every claim from source, not from the developer's prose:
- Extracted `main`'s pre-fix `leadv2-lane-outcome.sh` **in place** (not copied
  to `/tmp`, which silently breaks the relative `lib/leadv2-parked-detect.sh`
  source and gives false negatives) and ran both the old and new binaries
  against each new test fixture to get a real differential, not just the
  "PASS" reported by the new suite.
- Read all 4 mutation-control artifacts under
  `docs/handoff/LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01/mutation-control/`
  (gitignored, correctly not committed — `.gitignore:49` matches
  `docs/handoff/*/*`).
- Read `tests/run-all.sh`'s selection logic directly (stem-comparison loop,
  `EXTRA_SUITE_MAP`) instead of trusting the "self-selects" claim.

## 1. Mutation controls — REAL, verified independently

All three reddened as claimed, exactly one FAIL each, matching the named
branch:
- Control A (`185s/.*/VERDICT=""/`) → `case_verdict_outranks_bound` only.
- Control B (`217s/&& "${WORK}" != "yes" //`) → `case_work_yes_never_downgraded_by_wording` only.
- Control C (`139s/echo unknown/echo no/;143s/…/`) → `case_undetermined_work_is_unknown_not_died_clean` only (the two-red note for `case_unknown_work_never_auto_respawns` is accurately disclosed as the same product branch, not a second defect).

All 4 artifact files present, `baseline_rc=0`/`mutated_rc=1` consistent, line
anchors match the live file at the stated line numbers (checked directly:
139/143 `echo unknown`, 185 `VERDICT=`, 217 the `PARKED` outcome-table guard).

## 2. Verdict-first / wording-subordinate logic — correctly implemented, but one test in the suite is vacuous

The decision table (`leadv2-lane-outcome.sh:208-234`) is verdict → bound+work
(unknown-aware) → wording (gated `VERDICT==""  && WORK!="unknown"` at the
`PARKED=1` assignment, line 197, **and** `WORK!="yes"` at the outcome-table
consult, line 217) → `.no-deliverable` → clean exit → fallback, matching the
mission's stated priority order. Verified with a real differential, not just
reading the diff:

```
# case_work_yes_never_downgraded_by_wording fixture, run against the
# UNPATCHED main-branch classifier (relative sourcing intact):
outcome=parked      # <- the actual bug: wording overrode WORK=yes
# same fixture, patched classifier:
outcome=died-with-work
```
This is a real, demonstrated fix — not just a passing assertion.

**Finding (Medium) — `case_e2e_real_work_never_died_clean` does not test what it claims.**
`plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh:148-165`, labelled
"MANDATORY end-to-end control (brief §3)... Disk must win: outcome must never
be died-clean." I ran the identical fixture against the **unpatched**
main-branch classifier:
```
$ /tmp/…lane-outcome-old.sh "$d2" 1 yes   # EXIT_CODE=1, WORK_DELTA=yes (explicit)
outcome=died-with-work   # <- same as the patched result
```
It passes identically on pre-fix and post-fix code. The reason: `PARKED` can
only be set when `EXIT_CODE=="0"` (line 198, unchanged by this fix), and this
fixture uses `EXIT_CODE=1`, so the wording probe was structurally unreachable
in **both** old and new code — the "disk beats prose" claim was never at risk
here regardless of the fix. The developer's own report (§5) states "Disk
wins, PASS" as if this proves the regression is closed; it proves nothing
about this fix specifically. The real regression coverage for "wording never
overrides real work" is `case_work_yes_never_downgraded_by_wording` (which
*does* discriminate old vs. new, see above) — that one should be the one
labelled as satisfying brief §3's mandatory control, not this one. Not
blocking (the actual property is covered elsewhere), but the deliverable
overclaims test coverage for a "MANDATORY" brief requirement — reclassify or
add a second e2e fixture with `EXIT_CODE=0` + probe-derived `WORK` so the
mandatory control is real.

## 3. `case_6` regression claim — CONFIRMED accurate, not a sign of broken logic

Read `test-lane-outcome.sh:159-166`: `case_6_no_meta_no_throw` builds a
`run_dir` via bare `mktemp -d` (skipping `_new_run_dir`, so **no** `meta.yaml`
at all — no `cwd` key can exist), calls the classifier with a nonzero exit,
and asserts `outcome=died-clean, next=respawn`. That is textually the exact
defect the mission named: an undeterminable work-probe state (no `cwd` on
record → `_resolve_work` can't run `git`) silently encoded as "no work, throw
it away, respawn." Ran it directly:
```
$ bash plugins/leadv2/scripts/tests/test-lane-outcome.sh
... 7 passed ...
FAIL: case_6_no_meta_no_throw -- outcome=unknown, expected died-clean
```
Matches the developer's report exactly. This is an old test asserting the
bug, not new logic breaking something else — confirmed independently, not
just accepted from the write-up.

## 4. Bounds — respected

`git diff --name-only main...HEAD` = `docs/handoff/dispatch-9e1f4297/{developer.full.md,developer.summary.md}`,
`plugins/leadv2/scripts/leadv2-lane-outcome.sh`,
`plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh`. No match for
`dispatch-code|dispatch-product-close|run-all.sh|known-red-suites|docs/leadv2/`.
`lib/leadv2-parked-detect.sh` is declared in `LANE_WRITES` but carries no
diff, as stated — confirmed (`git diff` shows zero hunks for it).

## 5. Self-selection — CONFIRMED, but flag an adjacent gap (not this diff's to fix)

`tests/run-all.sh:452-459`: on `--scope changed`, any `cf` matching
`plugins/leadv2/scripts/tests/test-*.sh` (etc.) in the diff range
(`_range_start..HEAD`, falling back to `merge-base HEAD main`) is added via
`add_suite` regardless of stem match — the new suite is a changed file itself
under that glob, so it self-selects correctly.

**Adjacent gap, not blocking, informational:** the *production* file
`leadv2-lane-outcome.sh` does NOT auto-select `test-lane-outcome.sh` (the
suite carrying the disclosed `case_6` regression). The stem-comparison at
`run-all.sh:551-552` builds candidate `test-leadv2-lane-outcome.sh` (no such
file — the real file drops the `leadv2-` prefix), and the only
`EXTRA_SUITE_MAP` row keyed on `leadv2-lane-outcome.sh` points at
`test-worker-dod-gate.sh` (`run-all.sh:371`), not `test-lane-outcome.sh`
(that suite is only reachable via the `glm-coder.sh` key, `run-all.sh:364`).
Net effect: this lane's own `--scope changed` gate will likely **not**
surface the `case_6` regression automatically — the developer only found it
by running the suite by hand. That's good for not blocking this lane's
close, but it also means the disclosed defect has no tracking mechanism once
this task closes. Recommend a follow-up: either an `EXTRA_SUITE_MAP` row
`leadv2-lane-outcome.sh:plugins/leadv2/scripts/tests/test-lane-outcome.sh`,
or a `known-red-suites.txt` entry, or (preferably) updating `case_6`'s
expectation to `unknown`/`none` in a task that owns that file. This is
correctly out of `LANE_WRITES` for this task — surfacing it here so it isn't
lost.

## 6. Other checks

- `bash -n` clean on all 3 changed shell files (self-reported and
  independently reconfirmed).
- `shellcheck -S warning` on `leadv2-lane-outcome.sh`: 0 findings.
- No `except Exception`-equivalent silent-swallow pattern introduced; the new
  `_resolve_verdict` allowlists outcome tokens
  (`completed|died-with-work|died-clean|parked|unknown`) before trusting the
  file content — good defensive parsing of an external/future input, not
  bloat.
- `VERDICT="$(_resolve_verdict || true)"` — `_resolve_verdict` always
  `return 0`, so the `|| true` is dead code. Cosmetic only, Low, not worth a
  round-trip.
- 10/10 identical run claim reproduced or spot-checked: ran the new suite
  directly, 7/7 pass, consistent with the report.

## Contradiction scan

- Env vars / flags: none introduced by this diff (`.gate-verdict` is a file
  path, not an env var; no new flag semantics).
- Path existence: `${RUN_DIR}/.gate-verdict` — confirmed no shipped writer
  exists (`grep -rn gate-verdict plugins/leadv2/scripts/` shows only this
  file's own read and the new test's fixture write) — matches the honesty
  note in the diff's own comment, not a false claim.
- `LANE_WRITES` vs actual diff: consistent (§4 above).
- No contradictions found beyond the Medium/informational items above.

## Verdict

**APPROVE WITH NOTES** (Medium + Low only, nothing Critical/High):
- Medium: `case_e2e_real_work_never_died_clean` doesn't discriminate pre/post
  fix behavior — mislabeled as satisfying the brief's mandatory e2e control;
  the real coverage for that property is `case_work_yes_never_downgraded_by_wording`.
  Non-blocking (property is genuinely covered by another case), but the
  deliverable's claim should be corrected in a follow-up commit or the next
  round's note.
- Low: dead `|| true` on `VERDICT=` assignment.
- Informational (not this task's scope): `test-lane-outcome.sh`'s `case_6`
  regression is real, confirmed intentional, and correctly disclosed — but
  has no automatic CI tracking once this lane closes (§5). Someone should
  own a follow-up to fix `case_6`'s expectation or register the suite as
  known-red.

DELIVERABLE_COMPLETE
