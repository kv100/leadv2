# LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-outcome.sh, plugins/leadv2/scripts/lib/leadv2-parked-detect.sh, plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh, docs/handoff/LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01/

## 0. The defect — measured, not argued

`leadv2-lane-outcome.sh` (218 lines) decides a lane's fate: it prints exactly one of
`completed | died-with-work | died-clean | parked`, and the close gate acts on that token.

**It never reads a gate verdict.** Measured 2026-09-04:

```
grep -c 'review_gate\|verdict\|gate_result\|dod_gate\|e2e_gate' leadv2-lane-outcome.sh   → 0
grep -c '…same pattern…'          leadv2-dispatch-product-close.sh                       → 104
```

The second number is the instrument's positive control: the probe can find these words, so the zero
is a real zero and not a blind grep.

What it reads instead:

| line | signal | kind |
|---|---|---|
| 82-84 | `terminal_reason == "max_turns"`, `subtype == "error_max_turns"` | runner metadata |
| 164/168/172 | a work-delta in the worktree (`WORK == yes`) | **state — the one honest input** |
| 156-157 | `lv2_parked_text_file "${RUN_DIR}/result.md"` → `lib/leadv2-parked-detect.sh`, 22 lines | **the wording of the worker's last message** |

So in the place where the system decides whether work is kept or thrown away, the deciding input is
partly **what the worker wrote in prose**. A worker that phrases its ending differently gets a
different fate for the same state on disk. This is the night's dominant disease — a claim believed
instead of a state — sitting in the worst possible place.

## 1. The question you must answer, because it is not yet explained

The rule `died-with-work → continue` exists (`leadv2-lane-outcome.sh:176`) and it **has a reader**:
`leadv2-dispatch-product-close.sh:667` — `GLM-DIED-WITH-WORK-RESUME-01`, which relaunches the same
provider on the same worktree, **exactly once**, guarded by a per-lane marker file, kill-switch
`LEADV2_PC_DWR_RESUME=0`.

And yet: **five lanes died on 2026-09-03 with real work in their worktrees, and all five closed.**
Rule present, reader present, outcome wrong. There is a third defect between the classifier and the
resume, and finding it is half this lane's value. Candidates to check by measurement, not by reading:

- the classifier returned something other than `died-with-work` for those lanes (wording probe won,
  or the work-delta probe missed the work);
- `_pc_lane_outcome` (`:745`) returned `""` because the run-dir could not be resolved for that
  author/handle (`_pc_run_dir_for`, `:677`);
- the per-lane marker was already present, so "exactly once" had already been spent;
- `LEADV2_PC_DWR_RESUME` was 0 in the live environment;
- the resume launched and its own death was classified as clean.

Name which one it was, with the evidence line. If it is none of them, say so — that is a finding.

## 2. What to build

1. **The classifier reads verdict and state first.** A recorded gate verdict (review/dod/e2e) and
   the worktree's own state must decide the token. Where a verdict exists, it outranks everything
   else.
2. **The wording probe stops being an input, or becomes the last resort after state** — explicitly
   marked as such, and never able to override a verdict or a work-delta. If you keep it, its
   subordination must be provable by mutation: a mutant that lets wording win must redden a case.
3. **A state that cannot be determined is `unknown`, never a default.** Do not resolve ambiguity by
   picking the safer-sounding token; `died-clean` on an undetermined lane is how work is thrown
   away.

## 3. Acceptance — it bites

- **A negative control per changed function body**, via `plugins/leadv2/scripts/leadv2-mutation-control.sh`,
  mutation INSIDE the body. Report `baseline_rc` / `mutated_rc` / `restored_rc`.
- **Under each mutation, exactly ONE assertion may go red, and it must be the one the control's name
  claims.** If an earlier assertion is the red, the mutation removed a precondition and your named
  branch is still undefended — report that rather than accepting the red. Two reds are legitimate
  ONLY when one product line genuinely serves two call sites and each has its own case; say which
  applies.
- **A mutant that does not bite is a claim about your anchor, not about the branch.** Twice today a
  green suite under mutation turned out to be a mutation anchored on a site the fixture never
  reaches. Before reporting "undefended", prove the mutated line is on the executed path.
- **Read the mutated line back** before trusting the run: a mutation can change the file's sha256 and
  still be inert (a `perl` replacement interpolated `$link_name` as its own undefined variable today
  and inserted `[[ -L "" ]] && return 0`).
- **Before believing any zero, show the same probe returning non-zero** on a case known to be
  positive. The measurement in §0 is done exactly this way — copy the shape.
- **Ten consecutive runs**, all exit codes pasted. A disagreement between runs IS the finding.
- Mandatory end-to-end control: **a lane whose worktree contains real work must never classify as
  `died-clean`, whatever the worker's last message says.** Build the fixture so the prose says one
  thing and the disk says another, and assert the disk wins.

## 4. Bounds

- Do NOT edit `leadv2-dispatch-code.sh`, `leadv2-dispatch-product-close.sh` (read them freely — if
  the fix belongs in the close gate, put the exact replacement text in your report and say plainly
  that it is not landed), `tests/run-all.sh` (declare triggers with a `# run-all-triggers:` line in
  your suite; note the walker for those declarations is **not on main yet**, it lands with the
  suite-map branch), `tests/known-red-suites.txt`, `main`, or `docs/leadv2/`.
- Scratch worktrees go under `/private/tmp`, never `/tmp`: on macOS `/tmp` is a symlink to
  `/private/tmp` and `run-all.sh`'s `root_escape` guard kills the run with `rc=2` before selecting
  anything, which reads exactly like "the suite was not selected".
- Never `reset --hard`, `clean`, `stash`, or `worktree prune` — the tree is shared and live lanes
  stand next to yours. Remove scratch worktrees with `git worktree remove`.
- Commit incrementally: the e2e gate times out at 900s and has already parked one lane today on the
  threshold between finished and committed.
- If any instruction here rests on a false premise, stop and say so with the measurement. That is a
  complete and welcome answer.
- Do not merge to main. Leave the branch green with a report.

## 5. Report

The answer to §1 with its evidence line, each control's triple with the full list of red lines under
it, the ten count lines, the final `git diff --name-only main...HEAD`, and the commit shas.
