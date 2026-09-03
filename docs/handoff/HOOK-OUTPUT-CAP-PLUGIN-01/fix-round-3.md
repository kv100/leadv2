# HOOK-OUTPUT-CAP-PLUGIN-01 — round 3: one item left, and it is the CI selection

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HOOK-OUTPUT-CAP-PLUGIN-01`

LANE_WRITES: plugins/leadv2/hooks/leadv2-one-copy-drift.sh,plugins/leadv2/hooks/leadv2-truth-card-inject.sh,plugins/leadv2/scripts/tests/test-hook-output-cap.sh,tests/run-all.sh,docs/handoff/HOOK-OUTPUT-CAP-PLUGIN-01/

Full report: `docs/handoff/HOOK-OUTPUT-CAP-PLUGIN-01/review-r2.md`. HEAD is `b885e0d`.

**Two of three jobs are done and independently reproduced — keep them, do not redo them.**

- The crash-shaped failure is no longer swallowed, and the control is real: 7/7 green, mutate
  `if false; then` into the production body → T5 RED → revert → 7/7 green.
- The byte win is confirmed by a second measurement in the MAIN checkouts:
  `~/Projects/leadv2` **45,705 B → 277 B** (exact match to the claim), `~/Projects/persona-engine`
  **7,758 B → 243 B**. `report.md` honestly marks the runtime numbers UNVERIFIED rather than
  over-claiming, which is the right call.

## [High] `--scope changed` still does not select the suite at the real HEAD

The round-2 proof was captured at `41256ac`. The lane's own next commit `b885e0d` is docs-only and
is now HEAD, and the fallback is a single-parent hop `HEAD~1..HEAD` — so it sees only the report
commit, never the functional fix. Reproduced live at the actual current state (nine dirty
`docs/leadv2/*` coordination files, HEAD `b885e0d`): the union contains zero `plugins/leadv2/*.sh`
paths and `test-hook-output-cap.sh` is not selected.

This is the same defect class as round 1, one commit later — and it will recur every time a lane
ends with a docs commit, which is most of the time. So do not re-capture the proof at a convenient
commit; **fix the range**.

`tests/run-all.sh` is in your write set. Make the fallback cover the lane's whole range rather than
one hop — the merge-base against the lane's base branch is the natural anchor (`git merge-base` then
`<base>..HEAD`), so every commit the lane made is considered, not just the last one. Keep the
existing behaviour when there genuinely is dirt that matters.

Prove it in the state CI will actually be in:

1. commit something docs-only so HEAD is a docs commit,
2. leave the nine `docs/leadv2/*` coordination files dirty,
3. run `tests/run-all.sh --scope changed` and show `test-hook-output-cap.sh` selected and passing.

Then mutate the range fix out and show the suite is no longer selected — that is the control.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image.
- Do not reorder, add or remove entries in `hooks.json`; it is not in LANE_WRITES.
- Never make a hook quieter about a real problem to improve a byte count.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- Commit artifacts with `git add -f <file>`, one file at a time; do not edit `.gitignore`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

`--scope changed` selecting and passing `test-hook-output-cap.sh` at a HEAD whose last commit is
docs-only and with unrelated dirt present, proven by a pasted run, and held by a control that fails
when the range fix is reverted.
