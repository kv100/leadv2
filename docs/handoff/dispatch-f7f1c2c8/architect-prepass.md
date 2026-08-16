# architect — REPORT-ONLY-GATE-01 conflict resolution design

## Verdict

The two sides **can coexist**. This is a pure textual conflict in one hunk: they touch the same
region (the review-gate PASS exit) for orthogonal reasons.

| Side | Commit | What it contributes to the PASS exit |
|---|---|---|
| `HEAD` (main, `bb400e9`) | REVIEW-GATE-SHOWS-FINDINGS-01 | Appends the rendered findings block after the head lines; switches the write to `tmp` + `mv -f` (torn-read-safe for multi-line); computes `_rgf_rel` / `_rgf_dnm` and stamps `do_not_merge=1` into the terminal evidence |
| incoming (`b1c9bd3d`) | REPORT-ONLY-GATE-01 | Branches on `_pc_kind`: the report lane emits `kind: report` / `deliverable:` / `bytes:` / `review:` instead of `diff:`, and passes the harvested deliverable path as `_dl_note`'s 5th arg (write-terminal arg 9) |

Nothing about them is mutually exclusive: one decides **what the head lines are**, the other decides
**what is appended and how the file is written**. The resolution is the cross product — the report /
diff branch structure from the incoming side, with the head-line-writing mechanics of both branches
upgraded to HEAD's append + `tmp`/`mv` discipline.

## Scope of change

Exactly one hunk, lines 2152–2179 of `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`
(conflict markers removed). No other file changes. Everything else in the change set is already
staged and clean.

## Resolved shape (design, not a patch)

Replace the conflicted region with, in order:

1. `_rgf_rel` computation, hoisted **above** the `if` (identical in both branches, so it must not be
   duplicated inside them):
   - `_rgf_rel="docs/handoff/dispatch-${TASK}/review-${reviewer}.md"`
   - overridden by `${REVIEW_SOURCE#artifact:}` when `REVIEW_SOURCE` is set.
2. `if [[ "${_pc_kind}" == "report" ]]; then` — report branch:
   - head lines: `status: pass`, `reviewer:`, `kind: report`, `deliverable: ${_pc_report_deliverable}`,
     `bytes: ${_pc_report_bytes}`, `review: ${verdict}` — byte-identical to the incoming side, same
     order, still first in the file.
   - then `render_gate_findings "${review_file}" "" "${reviewer}" "${_rgf_rel}" || true` inside the
     same `{ ... }` group, redirected to `review-gate.md.tmp`, then `mv -f` into place.
   - `_dl_note landed review_verdict_pass "diff=${diff_hash:0:8} deliverable=${_pc_report_deliverable}${_rgf_dnm}" "" "${_pc_report_deliverable}"`
     — keeps the 5-arg form so write-terminal arg 9 still carries the deliverable.
3. `else` — diff branch: exactly HEAD's body (`status: pass` / `reviewer:` / `diff:` head lines,
   `render_gate_findings`, `tmp` + `mv -f`, `_dl_note landed review_verdict_pass "diff=${diff_hash:0:8}${_rgf_dnm}"`).
   This branch must stay **byte-identical in output** to current `HEAD`.
4. `_rgf_dnm` computed once before the `if` (it is a pure read of `RGF_DO_NOT_MERGE`), used by both
   branches' `_dl_note`.
5. `fi`, then the untouched `_stamp_review_terminal pass` and the phase-record call that follow.

## Why the diff branch MUST keep `render_gate_findings`

`tests/test-report-only-gate.sh` case 4 (`case_4_diff_golden`, lines 216–244) builds its baseline
with `git -C "${LEADV2_REPO}" archive HEAD plugins/leadv2/scripts` and requires `cmp -s` equality
between the live gate output and the baseline's. `HEAD` already contains
REVIEW-GATE-SHOWS-FINDINGS-01, so the baseline `review-gate.md` for a diff lane **includes** the
findings block. Dropping HEAD's side in the `else` branch (the naive "take incoming") would fail
case 4 as a golden mismatch. This is the mechanical proof that "keep both" is not merely tidy — it
is the only resolution the suite accepts.

## Why the report branch is safe to extend with the findings block

Cases 1–3 assert with `grep -q '^kind: report'`, `grep -q '^deliverable: …'`, `grep -q '^bytes: '`
on the whole file — line-anchored greps, not a whole-file `cmp`. Appending after the head lines
cannot break them. The report lane has no golden comparison (it does not exist at `HEAD`, so
`case_4`-style archiving is inapplicable).

## Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | Naive resolution (take one side) silently drops a shipped behaviour | Both suites must be run **after** the resolution; case 4 catches a dropped HEAD side, cases 1–3 catch a dropped incoming side |
| R2 | Duplicating `_rgf_rel` / `_rgf_dnm` inside both branches — drift risk on the next edit | Hoist both above the `if`; each is a pure computation with no branch dependency |
| R3 | `render_gate_findings` missing at runtime | Already handled at line 77 — a no-op stub is defined when the renderer cannot be sourced; the `|| true` keeps a broken renderer non-fatal |
| R4 | Report branch keeps the old direct `>` write while the diff branch uses `tmp`/`mv` — a torn multi-line read on the report path only | Apply `tmp` + `mv -f` on **both** branches |
| R5 | Concurrent sessions rewrite the file between resolve and stage (shared tree, three live repos) | `git diff plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` immediately before `git add`; never `reset --hard` / `clean` / `stash` in this tree |
| R6 | `_dl_note` arity: the report branch needs 5 args, the diff branch 3 | Preserve each branch's existing arity exactly; the 4th arg stays `""` so write-terminal's own commit default (`none`) applies |

## Non-goals

- No change to gate *decision* semantics — `status:` stays `pass` on both paths; the findings block
  and `do_not_merge` remain advisory.
- No change to any other file in the change set (`leadv2-dispatch-code.sh`,
  `lib/leadv2-report-deliverable.sh`, the two test files) — they are already staged and clean.
- No touch of `docs/leadv2/open-threads.md`.
- No de-duplication of `.claude/scripts/tests/` copies (separate open thread).
- No refactor of `render_gate_findings`, `_dl_note`, or the FAIL exit above.

## Verification plan for the implementer

1. Resolve the hunk as above; confirm `grep -c '^<<<<<<<\|^=======\|^>>>>>>>'` returns 0 and
   `bash -n` parses.
2. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` → 8/8.
3. `bash plugins/leadv2/scripts/tests/test-report-only-gate.sh` → 5/5, **after** the resolution.
4. `git diff` the file, then `git add` it, then commit on `main` in `~/Projects/leadv2`.
5. Append the one-paragraph "what each side contributed" note to
   `docs/handoff/REPORT-ONLY-GATE-01/report.md`.

acceptance:
  - surface: file_artifact
    observable: "Opening plugins/leadv2/scripts/leadv2-dispatch-product-close.sh in the committed tree on main shows no <<<<<<< / ======= / >>>>>>> lines anywhere, and the review-gate PASS section reads as one if/else on the report kind where both arms end by moving a .tmp file into place."
    authored_at: 2026-08-16T00:00:00Z
  - surface: rendered_line
    observable: "The final line printed by the report-only gate suite reads that all 5 cases passed, and the core offline suite prints 8 passed / 0 failed, both in a run started after the conflict was resolved."
    authored_at: 2026-08-16T00:00:00Z
  - surface: file_artifact
    observable: "docs/handoff/REPORT-ONLY-GATE-01/report.md contains a paragraph naming what the findings-rendering side and what the report-deliverable side each contributed to the merged PASS exit."
    authored_at: 2026-08-16T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh

DELIVERABLE_COMPLETE
