verdict: APPROVE
next_action: review_round_2

# STATE-LAYER-CANNOT-SAY-IT-FAILED-01 — developer deliverable

## Scope and bounds respected

No fixes made. No edits to `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`,
`lib/leadv2-route-arbiter.sh`, `tests/run-all.sh`, `tests/known-red-suites.txt`, or
`docs/leadv2/`. Diff is one new file: `plugins/leadv2/scripts/tests/test-state-layer-silent-write.sh`.
Verified via `git status --short` in the worktree (clean except that one untracked/added file)
and `git diff --diff-filter=D --name-only main...HEAD` (empty — no deletions).

## Method

Three parallel behavioural sweeps (Explore subagents), each instructed to search by BEHAVIOUR
(source the file, invoke the function under conditions that should trigger the silent path,
observe rc + missing artifact) rather than grep for `return 0` literally:

1. `leadv2-active-registry.sh` + `leadv2-journal.sh` — 8 findings
2. `leadv2-phase-record.sh` + `leadv2-lanes-snapshot.sh` + `leadv2-status-snapshot.sh` (no findings, no writes) — 4 findings
3. `plugins/leadv2/scripts/lib/*.sh` (37 files) — 7 findings

19 total candidates, consolidated and ranked in
`docs/handoff/STATE-LAYER-CANNOT-SAY-IT-FAILED-01/census.md` by how far the lie travels
(state other surfaces read and trust), not by fix difficulty.

## Acceptance bar: rediscovery of known instances

All three documented instances from the brief map onto the census:
- Registration (`active_register_miss task=07401216 rc=0`) → census row 3/6 mechanism
  (`leadv2_active_update_phase` / `leadv2_active_update_pulse`, missing-file guard + no-`else`
  unmatched-`task_id` python pattern).
- Deregistration (`leadv2_active_unregister`) → census row 2, exact match.
- Phase records (`leadv2-phase-record.sh:164`, wrong-repo write) → census row 1, exact match.

Each was rediscovered by sourcing the real file and invoking the function under the triggering
condition, not assumed from the brief text — see census.md for the measured command+output per
row (reproduced from the three subagent transcripts).

## Detector suite

`plugins/leadv2/scripts/tests/test-state-layer-silent-write.sh` (self-selects: lives at
`plugins/leadv2/scripts/tests/test-*.sh`, matching both `tests/run-all.sh`'s own "a changed test
suite selects itself" rule at `tests/run-all.sh:452-460` and `leadv2-dod-gate.sh::_dod_check_c`'s
self-selecting-conventional-dirs list — no `tests/run-all.sh` edit, no `EXTRA_SUITE_MAP` row).

**Shape, not a list.** `_ssw_classify_body()` classifies a function body (as printed by
`declare -f` after sourcing the real file into an isolated tmp-git sandbox) as `FLAGGED` if:
- an early `... || return 0` guard is textually followed by more effective work in the same
  function (the guard was not the function's last statement), OR
- a statement's own failure is swallowed via `|| true` / `|| :`.

No function names are hardcoded into the detection rule itself (only the *targets scanned*, i.e.
which file/function pairs the suite happens to check, are named — the rule that decides FLAGGED
vs CLEAN has no knowledge of which functions exist). This is a heuristic, not a proof — it will
have false positives on legitimate idempotency fast-paths and false negatives on writes hidden
behind a call to another function (e.g. `lane_deregister` in `lib/leadv2-lane-state.sh` delegates
its write to a python heredoc inside `_lv2_lane_state_mutate`, invisible to a bash-text scanner —
documented as an explicit gap in the test file's Part-1 comment).

**16/16 assertions pass:**
```
PASS: known instance: leadv2_active_unregister (deregistration) flagged
PASS: known instance: phase-record _emit (journal fire-and-forget) flagged
PASS: census row 17: arm_cooldown_record flagged
PASS: census row 14: leadv2_brain_write_yaml flagged
PASS: negative control: clean function not flagged
PASS: mutation A: mutant differs from original
mutation A (synthetic safe_write): baseline=CLEAN mutated=FLAGGED restored=CLEAN
PASS: mutation A: baseline is CLEAN
PASS: mutation A: injecting a swallowed-write turns it FLAGGED
PASS: mutation A: restoring the original text returns it to CLEAN
PASS: mutation B: located the guard line in leadv2_active_unregister (line 974)
PASS: mutation B: mutant line differs from original
PASS: mutation B: mutated copy still parses (bash -n)
mutation B (leadv2_active_unregister, copied file): baseline=FLAGGED mutated=CLEAN restored=FLAGGED
PASS: mutation B: restored line matches original byte-for-byte
PASS: mutation B: baseline (real defect) is FLAGGED
PASS: mutation B: fixing the guard (return 0 -> return 1) turns it CLEAN
PASS: mutation B: restoring the original guard returns it to FLAGGED
---
16 passed, 0 failed
```

**Mutation controls, byte-for-byte diff asserted before running:**
- **Mutation A (synthetic):** `_ssw_safe_write()` (a clean, correctly-erroring function defined
  inline in the test) — baseline `CLEAN` → inject a swallowed-write (`2>/dev/null || true`) on a
  temp-file line-numbered sed pass → `FLAGGED` → restore original text → `CLEAN` again. The
  mutant-vs-original diff is asserted non-empty before classifying.
- **Mutation B (real defect, on a copy):** `leadv2_active_unregister` from a *copy* of
  `leadv2-active-registry.sh` (never the real file) — baseline `FLAGGED` (the real, documented
  defect) → locate the guard line dynamically via awk (no hardcoded line number) → mutate
  `return 0` → `return 1` → `bash -n` confirms the mutated copy still parses → `CLEAN` → restore
  via the `sed -i.bak` backup → `FLAGGED` again, with the restored line asserted byte-identical to
  the original.

Under each mutation, only the assertions for that fixture flip; the other fixture's PASS/FAIL
lines are unaffected in the same run (see the interleaved but independently-asserted output
above — one bad prior state, before the `_emit` sourcing fix and the mutation-A sed rewrite, is
recorded below for transparency).

**Ten consecutive runs, all exit codes:**
```
run=1..10 rc=0 (all ten identical: "16 passed, 0 failed")
```
No disagreement between runs.

**Self-check:**
```
$ bash -n plugins/leadv2/scripts/tests/test-state-layer-silent-write.sh   -> OK
$ zsh -n plugins/leadv2/scripts/tests/test-state-layer-silent-write.sh    -> OK
```
No Python files changed. No changed-scope test runner invoked beyond this suite itself (the
suite is the only diff).

### One debugging note kept for the record (not a defect in the deliverable, a build-time fix)

First draft had two failures, both fixed before commit:
1. `_emit` (in `leadv2-phase-record.sh`) came back `MISSING` because that file is a CLI script
   with an unconditional `[[ $# -eq 0 ]] && { usage; exit 4; }` at file scope — sourcing it with
   no args hit that `exit 4` inside the sourcing subshell before `declare -f` ran. Fixed by
   retrying the source with a harmless, argument-complete subcommand
   (`is-bootstrap deadbeef00`) when the plain-source attempt yields an empty body.
2. Mutation A's first attempt used bash `${VAR/pattern/replacement}` parameter substitution
   against text containing `${dir}` — bash's glob-pattern parser misread the nested `${...}`
   inside the pattern and silently produced a mismatched/garbled string. Fixed by writing the
   body to a temp file and mutating via `sed` on a located line number instead (same approach
   already used for mutation B).

## Backlog

19 rows added via `~/Projects/persona-engine/scripts/task-add.sh --group state-layer-silent-write-01
--no-probe-yet`, one per census finding, each `intent` naming the file:line, function, and
mechanism. Confirmed via the tool's own JSON echo (19 successful `"task created"` responses, no
errors) — group_key `state-layer-silent-write-01` throughout.

## What was deliberately left alone

- No fixes to any of the 19 findings — that's the lane's own bound.
- `leadv2-lanes-snapshot.sh`'s primary mutation logic (active.yaml/tombstones.yaml core writes)
  was checked and excluded from the census: it's fail-closed by design (`emit_fatal` →
  `sys.exit(1)` on `OSError`), already hardened against this exact failure class.
- `lib/leadv2-watch-lifecycle.sh`'s `wl_event` has the identical guard shape as census row 17 but
  is documented as an intentional "soft-fail, never kills a watcher" contract — noted in census.md
  as excluded-by-design rather than counted as a 20th finding.
- The scanner does not follow calls into other functions (e.g. python heredocs, or
  `lane_deregister`'s delegation to `_lv2_lane_state_mutate`) — documented gap, not silently
  dropped; `lane_deregister` itself is still recorded as census row 13 by direct measurement
  (sourcing + invoking), just not by the automated scanner.

DELIVERABLE_COMPLETE
