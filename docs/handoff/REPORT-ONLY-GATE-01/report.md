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

One further blocked shape exists after the cross-provider review round (below):
`status: blocked` · `reason: harvest_failed` · `kind: report` · `declared: <rel path>` —
the report was located and substantive but could not be materialised ROOT-side, so the
lane fails closed rather than pass while advertising a deliverable that is not there.

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

## Cross-provider review round (Codex adversarial, 2026-08-16)

`codex-task.sh adversarial-review --base <pre-fix ref>` over the whole task diff returned
`REVIEW_VERDICT: fail` with 5 high findings (saved as
`docs/handoff/dispatch-5e57c5ff/review-codex.md`). Four were fixed in the same lane:

1. **Symlink exfiltration** — `lv2_report_locate` now refuses a symlinked report file and
   verifies the file's *physical* directory stays beneath the lane worktree / main
   checkout (`pwd -P` containment), so a declaration can never harvest a host file into
   the handoff and external review. Regression: test C7.
2. **Harvest unverified** — the gate fails closed on harvest failure with a new blocked
   cause `harvest_failed`, and `lv2_report_harvest` refuses a non-regular destination
   (an existing directory at `report.md` used to make `mv` file the tmp inside it and
   return success). Regression: test C8.
3. **Reviewed bytes ≠ durable deliverable** — the review body is now read from the
   *harvested* `docs/handoff/dispatch-<TASK>/report.md`, not the mutable worktree
   source: review approves exactly the file a human later opens.
4. **Review-engine mode dropped report semantics** — with `LEADV2_REVIEW_ENGINE=1`
   (non-default, not production), a report lane now skips the engine loudly
   (`review_engine … status=skipped reason=report_lane`) and falls through to the inline
   review body, which carries the kind/deliverable/prose-rubric contract.

The fifth — *a pre-existing file at the declared path satisfies the declaration without
lane-attributable change* — is **accepted by design**: the mission (founder-authored)
declares the deliverable path, the gate is deliberately dumb (§2.3: "non-trivial must be
a fact a human can re-check by eye"), and the prose review judges the content. A
pre-dispatch digest comparison would be a design change (new spawn-time state plumbing)
and re-introduces exactly the both-directions misfiring the mission rejected in a
heuristic. If a lane ever needs it, that is a follow-up task, not this one.

## Cross-provider review round 2 (Codex adversarial, 2026-08-16)

`review-codex-r2.md` returned fail with 6 highs. Five fixed, one held by design:

1. **Arm recovery dropped the declaration** — `advance-arm` re-spawned the close gate
   without `LEADV2_DISPATCH_LANE_DELIVERABLE`, so a recovered report lane was re-judged
   as a diff lane (`no_work` despite its report). Fixed: `cmd_advance_arm` re-harvests
   the declaration from the same persisted `lane-mission.md` the replacement worker
   gets, and threads it as `spawn_product_close`'s 8th arg.
2. **Hardlinks bypass containment** — `lv2_report_locate` refuses `st_nlink > 1`
   (BSD `stat -f %l` / GNU `stat -c %h`): a worker-written report is link-count 1.
   Regression: test C9.
3. **Symlink at the destination satisfied harvest** — `-f`/`-ef` follow links, so a
   `report.md` symlink to the worktree source skipped the copy and dangled after the
   sweep. Harvest refuses a symlink destination outright. Regression: test C10.
4. **Non-product classes never enforce a declaration** — unchanged behaviour (they never
   ran the close gate), but now surfaced loudly:
   `lane_deliverable … status=unenforced reason=non_product_class` instead of silence.
5. **Reviewer never saw the mission** — the review body now embeds a bounded mission
   excerpt (`LEADV2_REPORT_MISSION_MAX_BYTES`, default 4000) and the prose rubric gained
   (e): an internally coherent but unrelated report FAILs.
6. **Only a 60k prefix is reviewed** — **held by design**: `LEADV2_REPORT_REVIEW_MAX_BYTES`
   head-truncation with an in-body notice naming the full harvested file is the scoped
   design (§2.4). Full-report mandatory review is a follow-up if report sizes grow.

The advance-arm threading (fix 1) is verified by inspection + syntax + the unchanged
6b/6c dispatch-harness cases; a full offline advance-arm fixture would need the close
gate's silent-arm probe machinery and is not in this suite.

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

DELIVERABLE_COMPLETE
