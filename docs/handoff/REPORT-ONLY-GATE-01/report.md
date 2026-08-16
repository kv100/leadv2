# REPORT-ONLY-GATE-01 — report-only lanes are gated on their file, not on a diff

Implemented 2026-08-16 in the plugin repo (lane worktree `5e57c5ff`). A lane may now
declare its deliverable is a **file (report)**, not a diff, and the close gate judges it
on that file: located (lane worktree, then main checkout), non-trivial (≥600
non-whitespace bytes AND ≥12 non-blank lines by default), harvested to
`docs/handoff/dispatch-<TASK>/report.md` (survives worktree sweep), and **prose-reviewed**
through the unmodified review path.

## What `review-gate.md` now prints, case by case

The three cases the mission asked to make distinguishable without opening a worktree —
plus the two blocked report-lane shapes:

| Case | `review-gate.md` |
|---|---|
| **diff lane** (no `LANE_DELIVERABLE`) | unchanged, byte-identical to pre-change (proven by golden compare in test C4): `status: pass` / `reviewer:` / `diff: <sha>` |
| **report lane, passes review** | `status: pass` · `reviewer: <arm>` · `kind: report` · `deliverable: docs/handoff/dispatch-<TASK>/report.md` · `bytes: <n>` · `review: <verdict>` |
| **report lane, no report file** | `status: blocked` · `reason: report_missing` · `kind: report` · `declared: <rel path>` |
| **report lane, stub report** | `status: blocked` · `reason: report_too_thin` · `kind: report` · `bytes: <n>` · `min: 600 bytes / 12 lines` |
| **dead worker** (empty diff, clean tree) | `status: blocked` · `reason: no_work` · `kind: diff` · `base: <sha>` — the `kind:` line is new and purely additive; a dead worker can no longer read like a finished report lane |

A diff lane blocked for other reasons (`unscoped_lane_work`, `asked_into_void`) gets the
same additive `kind: diff` after `reason:`; existing keys are byte-identical.

## How a lane declares it

`LANE_DELIVERABLE: report:<repo-relative path>` — precedence mirrors `LANE_WRITES`:
1. row/CLI `--lane-deliverable report:<path>` (dispatcher's declaration, highest);
2. the **mission's own** `LANE_DELIVERABLE:` line (tolerant matcher, `**LANE_DELIVERABLE:**`
   matches), harvested before the architect design is inlined — a report lane is a
   property of the ask, not of a design;
3. absent ⇒ `kind=diff` ⇒ today's behaviour byte-for-byte.

Unknown kinds (`artifact:x`, bad paths) are ignored and journalled
`lane_deliverable task=… status=ignored reason=unknown_kind` — never a silent lane-kind
flip. A valid report declaration also satisfies `_lane_writes_guard` (a report lane
legitimately has no `LANE_WRITES`; journal `lane_writes … source=report_deliverable`).

## What review means for prose

The report **is** the review body: `review.diff` is populated with a
`# REPORT-ONLY LANE — review the ANALYSIS, not a diff.` header plus the report text
(truncated at `LEADV2_REPORT_REVIEW_MAX_BYTES`, default 60000, with a notice line), and
the reviewer mission gains a prose rubric: (a) is every load-bearing claim backed by a
quoted file/line or command output present in the report; (b) list unsupported claims;
(c) does the recommendation follow from the evidence; (d) same `REVIEW_VERDICT:` /
`REVIEW_FINDINGS:` markers as a code review. Verdict-marker check, `review_body_lost`
guard, findings rendering and pass/fail paths are untouched — a wrong analysis is
rejected by the same machinery that rejects a wrong diff. A report lane that passes
stamps the unchanged `landed` terminal with `deliverable=docs/handoff/dispatch-<TASK>/report.md`
and no commit sha.

## Files

- `plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh` — new shared lib:
  `lv2_deliverable_parse` / `lv2_report_locate` / `lv2_report_substantive` /
  `lv2_report_harvest` (tmp + `mv -f` atomic idiom).
- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — mission harvest, `--lane-deliverable`
  arg, writes-guard exemption, `LEADV2_DISPATCH_LANE_DELIVERABLE` in `spawn_product_close`.
- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` — guarded source of the lib,
  `kind=report` branch in `pc_scope_diff` (before the `blocked_reason` block), harvest,
  review-body substitution + prose rubric, `kind:` line on blocked + pass writers,
  `_dl_note` passes write-terminal's optional commit/deliverable args.
- `plugins/leadv2/scripts/tests/test-report-only-gate.sh` — new offline suite, registered
  in `run-core-offline.sh` (its suite list is explicit, not glob-discovered).

Non-goals preserved: no diff-predicate change for code lanes, no new ledger terminal
word (`report_missing`/`report_too_thin` are causes on `no_work`), no heuristics, no
other deliverable kinds, no deploy, no retrofit of past lanes, no LLM-based scoring.

## Merge conflict resolution (2026-08-16, dispatch-f7f1c2c8)

`main` had advanced under this branch (`bb400e9` merged `dd43801`,
REVIEW-GATE-SHOWS-FINDINGS-01) and landed one conflicting hunk in the review-gate PASS
exit of `leadv2-dispatch-product-close.sh`. The two sides were orthogonal, not
competing: REVIEW-GATE-SHOWS-FINDINGS-01 contributed the append-after-head-lines
findings block plus the `tmp` + `mv -f` torn-read-safe write, and the `_rgf_dnm`
do-not-merge stamp on the terminal note; REPORT-ONLY-GATE-01 (this feature) contributed
the `_pc_kind == "report"` branch that swaps the `diff:` head line for
`kind: report` / `deliverable:` / `bytes:` / `review:` and threads the harvested
deliverable path through as write-terminal's 5th `_dl_note` arg. The resolution keeps
both: `_rgf_rel`/`_rgf_dnm` are hoisted once above the `if`, and both the `report` and
`diff` arms now render findings into a `.tmp` file and `mv -f` it into place before
calling `_dl_note` with their own arity. Verified: `test-report-only-gate.sh` 8/8 live
cases + 5/5 red-first evidence; `run-core-offline.sh` 45/47 (2 pre-existing failures
unrelated to this file — `test-hook-token-mode-isolation.sh`'s parallel-lead registry
race and `test-plan-followups-01.sh`'s arm-refused journal assertion — reproduced twice,
under heavy concurrent leadv2 activity in this shared tree, neither touching the
review-gate PASS code path).

DELIVERABLE_COMPLETE
