verdict: APPROVE-with-finding
next_action: review_round_3

# D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01 — finisher round (dispatch-57a94876)

## Scope confirmed

git diff main...HEAD -- plugins/ (three dots) is empty. The C8a/C8b work (b6d1ecbd,
484dd7a2, prior proof commits) already landed and is an ancestor of main in this worktree
-- main currently points at f1afd147, and git merge-base main HEAD resolves to c60cf2f8,
itself one of this lane's own commits. No source function was added or changed by this
round; the only lane-owned file is the test suite
plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh, and its own diff versus the
pre-C8 commit (3a4ec991) is confined to the C8 test cases, not _dl_derive_lane_state
itself. _dl_derive_lane_state (plugins/leadv2/scripts/leadv2-dispatch-ledger.sh:906) is the
one function under test; it was written by a sibling lane
(D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF), not this one, so there is no second changed function
needing its own mutation -- the enumeration is: one function, one control (C8a), already
covering the dirty-or-landed regression this lane exists to prevent.

## 1. Measured return codes (not inferred from a tool's exit code)

Ran suite -> mutate -> suite -> restore -> suite directly, capturing each $? by hand -- no
reliance on leadv2-mutation-control.sh's own verdict string, and no diff_hash cited
anywhere below.

    function: _dl_derive_lane_state (plugins/leadv2/scripts/leadv2-dispatch-ledger.sh:968)
    mutation: [[ "${commit_sha}" != "none" ]]; then  ->  [[ "${commit_sha}" != "none" || ${dirty} -eq 1 ]]; then
              (re-introduces the 2026-08-04 incident shape: dirty-tree bytes alone stamp landed)

    baseline_rc=0    ([TEST] 21 passed, 0 failed)
    mutated_rc=1     ([TEST] FAIL: C8a: expected dead_with_unlanded_work (never landed), got: landednoneunknown)
    restored_rc=0    ([TEST] 21 passed, 0 failed)
    red line: [TEST] FAIL: C8a: expected dead_with_unlanded_work (never landed), got: landednoneunknown

Post-restore diff is clean: git diff --stat -- plugins/leadv2/scripts/leadv2-dispatch-ledger.sh
prints nothing; bash -n on the file is OK. The mutation was applied and reverted with sed
directly on the working file, in-process, not via the mutation-control tool -- so
mutated_rc=1 and restored_rc=0 above are both directly observed exit codes of
`bash test-reap-funnel-death-proof.sh`, not a restatement of any tool's verdict.

## 2. One control per changed function

Only one function is in scope (see Scope confirmed above): _dl_derive_lane_state. Its one
load-bearing branch -- positive commit evidence stamps landed, dirty alone must not -- is
exactly what the mutation above targets, and it is the only branch this lane's C8a/C8b
tests exist to pin. No coverage hole to report for a second function, because there is no
second changed function on this diff.

## 3. Ten consecutive runs -- real disagreement found

Three independent ten/twelve-run batches, same machine, same tree, no mutation applied:

    batch A (10 runs): 1 1 0 0 0 0 0 0 0 1        -> 3 failures, all "C8b: ... got: deadnoneunknown"
    batch B (12 runs): 0 0 1 0 0 0 1 0 0 0 0 0    -> 2 failures, same C8b symptom
    batch C (10 runs): 0 0 0 0 0 0 0 0 0 0        -> 0 failures

This disagreement is the finding and outranks the clean batch C above. C8a never once
failed across all 32 runs; only C8b flips, always with the same symptom:
_dl_derive_lane_state returns commit_sha=none for a fixture that just froze a real,
path-scoped commit.

### Root cause, isolated and proven (not "load average" -- a prior round's wrong attribution)

_dl_derive_lane_state builds since_arg="--since=@${spawn_epoch}" and C8b calls it with
spawn_epoch="0", intending "no lower time bound, include everything." Git 2.50.1 (Apple
Git) does NOT treat --since=@0 as absolute epoch 0 (1970-01-01) when combined with a
pathspec-scoped log. Direct proof, no load involved, no test harness involved -- a fresh
repo, one commit, queried twice:

    $ git log --since=@0 --pretty=%H -n1 -- g.txt      # queried in the same second as the commit
    ede6b4b695937e56a06f4b28e008a1fa67b88500            # FOUND

    $ sleep 2
    $ git log --since=@0 --pretty=%H -n1 -- g.txt      # queried 2s later, same repo, same commit
                                                         # EMPTY

--since=@1 and --since=1970-01-01 do not exhibit this -- they always find the commit,
immediately or after a wait. Only the literal @0 misbehaves, and it misbehaves in a way
that depends on wall-clock proximity between the commit and the query, i.e. it is being
evaluated as something closer to "now" than "the beginning of time." This is a genuine
defect in _dl_derive_lane_state's epoch-0 convention, reachable any time a lane's real
spawn_epoch is recorded as 0 -- not a fixture bug, not a load artifact, and not something
this round is scoped to fix (leadv2-dispatch-ledger.sh is off-limits this round). C8b's
intermittent FAIL is therefore correct, honest test behavior, catching a real product race
-- it should not be "fixed" by weakening the assertion, per this round's own instructions.
Flagging as a follow-up against _dl_derive_lane_state's use of --since=@0.

## Bounds respected

- No edits to tests/run-all.sh, docs/leadv2/, leadv2-dispatch-code.sh,
  leadv2-claude-profile-select.sh, lib/leadv2-route-arbiter.sh.
- No new test-*.sh suite added this round (only pre-existing C8a/C8b cases inside an
  already-registered suite), so no EXTRA_SUITE_MAP row is needed or proposed.
- main and docs/leadv2/ were not touched by this session; git status --short -- plugins/
  docs/handoff/dispatch-57a94876/ is clean of any stray file.
- Commit-message accuracy: this session made no new commit for source/tests (no edit was
  required -- see Scope confirmed); this file's own commit message describes exactly this
  diff (report content only).

## Falsification set

    $ bash -n plugins/leadv2/scripts/leadv2-dispatch-ledger.sh && echo OK
    OK
    $ bash -n plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh && echo OK
    OK

No Python files touched. Suite runner: `bash test-reap-funnel-death-proof.sh` (the repo's
own entrypoint for this file) -- baseline/mutated/restored rc's above are its directly
observed exit codes.

DELIVERABLE_COMPLETE
