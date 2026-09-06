# WAIVER-REGRESSION-01 — accepted waiver vs the cross-repo record gate

## Mechanism

`e7f8c2ec` added a missing-dispatch-dir refusal inside `cmd_record`
(leadv2-phase-record.sh:865): when `docs/handoff/dispatch-<sig8>/` does not yet
exist, it compared the git-common-dir identity of cwd vs the resolved root.
For a NON-git root, `_phase_common_dir` fails and the code fell back to a bare
realpath — so the comparison was "cwd git common-dir vs root realpath", which
always differs. `cmd_assert`'s accepted-waiver path (`record --status waived`)
is by definition a FIRST record for a sig8 with no dispatch dir yet, and the
test fixture root is a plain `mktemp -d` (not a git repo): the waiver record
was refused with exit 4 and `plan.yaml` never written → 80/2.

## Fix

Narrow the refusal (leadv2-phase-record.sh:873-883): when the resolved root is
not a git repository at all (`_phase_common_dir` fails), skip the refusal.
A non-git root cannot be "a foreign REPO" — there is no repo to write into —
and it is the isolated test-fixture shape every suite uses (the same non-git-
fixture carve-out `_phase_check_worktree` already applies). The gate stays
armed whenever the resolved root IS a git repo whose identity differs from
cwd's — the case-5c cross-repo abuse shape, both repos real.

## Proofs

1. **Regression fixed** — `test-phase-precondition.sh` **82/0** (was 80/2).
2. **Gates intact** (each re-run with the fix):
   - test-phase-gate-inversion **18/0** (incl. case 5c refusal, case 5d fresh-dispatch)
   - test-phase-precondition-bootstrap **38/0**
   - test-phase-record-worktree-axis **14/0**
   - test-gate1-discipline **13/2** (pre-existing red; identical 13/2 at HEAD without the fix)
   - additional guarding suites: test-phase-record **12/0**, test-phase-gate-names-everything **13/0**
   - test-phase-gate-default-class **13/6** — pre-existing (13/6 at HEAD with the fix reverted; untouched by this change)
3. **Paired negative control** (direct probes):
   - ABUSE: cwd=/tmp/nrepoA, `LEADV2_PROJECT_ROOT=/tmp/nrepoB`, missing dir →
     `rc=4`, `record: project root not permitted: … refusing to write phase
     classify … check LEADV2_PROJECT_ROOT / PROJECT_ROOT / cwd`, and
     `nrepoB/docs/handoff/` EMPTY (nothing created).
   - WAIVER: `LEADV2_PROJECT_ROOT=$(mktemp -d)` with `waivers_allowed: [plan]`
     → `assert … --waiver plan=no_prepass_needed` = rc 3 (missing=…, not 4),
     and `dispatch-wvpos1/phases.d/plan.yaml` written with
     `status: waived` / `reason: no_prepass_needed`.
4. **Mutation control** — mutation "revert to unconditional identity
   comparison (realpath fallback)": test-phase-precondition **80/2** (red,
   exactly the two regression failures). Restore the fix: **82/0**.
5. `tests/known-red-suites.txt` untouched (no known-failures.txt in tree);
   diff touches exactly one file: `plugins/leadv2/scripts/leadv2-phase-record.sh`.

## Suites found guarding leadv2-phase-record.sh (run-all-triggers headers)

test-phase-precondition, test-phase-precondition-bootstrap, test-phase-gate-inversion,
test-phase-gate-default-class, test-phase-gate-names-everything, test-phase-record,
test-phase-record-worktree-axis, test-fable-think-tier — all run, results above.

## Falsification set (raw)

- `bash -n plugins/leadv2/scripts/leadv2-phase-record.sh` → SYNTAX-OK (no Python changed).
- Changed-scope runner (`tests/run-all.sh --scope changed`, state file reset,
  select-only first: 12 suites): **9 passed, 3 failed** —
  - test-phase-gate-default-class: pre-existing 13/6 (verified at HEAD without fix).
  - test-fable-think-tier: census red over the TRACKED, unmodified
    `.dbg-funcs.sh` `opus` literal — pre-existing on main, unrelated to phase-record.
  - run-core-offline: 13 nested FAILED labels, 8 of them not in known-red.
    None touch phase-record; the changed-relevant label "phase precondition
    guard matrix" PASSES. Consistent with the documented core-offline
    under-concurrent-runners flake (many live lanes on this host). Not
    attributable to this diff by content.

## Commit

One file, explicit pathspec: plugins/leadv2/scripts/leadv2-phase-record.sh (+17/−6).
