# REVIEW-GATE-SHOWS-FINDINGS-01 — report

Date: 2026-08-14 · Lane: dispatch-4c9ddb05 · Repo: `~/Projects/leadv2` (plugin source)

## What landed

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-review-findings.sh` | **New.** The one shared findings renderer, dual-mode (sourceable library + standalone CLI). rc ALWAYS 0, stdout-only, never writes `review-gate.md`. |
| `plugins/leadv2/scripts/leadv2-review-run.sh` | Appends the renderer's block at the fail and pass gate exits. Head lines byte-identical and first; guarded source + no-op stub (design R3). |
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | Same at its fail and pass exits — **the lane path that wrote every real gate to date** (design §0: all three real gates came from here, not from `review-run.sh`). Its two direct `>` gate writes became `.tmp` + `mv -f` (design R7). |
| `plugins/leadv2/scripts/tests/test-review-gate-shows-findings.sh` | **New.** 42 assertions: renderer CLI (all three real report shapes, structured `FINDING:`/json paths, do-not-merge advisory incl. Cyrillic, parse-fail degrade, rc-0 contract, Medium cap) + both REAL writers end-to-end with stubbed resolver/launchers. |

Verdict semantics are untouched: no `status:`, exit-code, or ledger-decision change. A
`PASS_WITH_NITS` + do-not-merge report still writes `status: pass` and exits 0 — with
`reviewer_says: do_not_merge` and the blocking Medium now on the face of the gate. The
ledger gains one additive token `do_not_merge=1` when the advisory fires. Making the
advisory BLOCKING is a decision change and stays in its own lane (design §3, §7).

## Evidence — the three real persona-engine gates, re-rendered (read-only)

Renderer invoked as the CLI exactly as the writers invoke it, against the real
`review-glm.md` of each lane; head lines are that lane's real `review-gate.md` head,
unchanged. These files are read-only evidence; persona-engine was not mutated.

### dispatch-9573bd97 (mission case 1 — PASS_WITH_NITS, three Mediums)

```
status: pass
reviewer: glm
diff: ac209434
findings_source: markdown_sections
findings:
- [Medium] client.sh — Stale/misleading stop_reason on request-failure paths — client.sh new code: the mirror file is written only after a successful _llm_request. If curl/HTTP fails, llm_run returns e…
- [Medium] grounding-gate.sh:960 — Grounding-gate calls got the token fix but no latency bound — the probe's own data shows the fix's operating point at 39–50 s per call (grounding_llm_check after@1024 = 50000 m…
- [Medium] docs/bench/glm-thinking-budget-2026-08-14.raw.jsonl — Cited evidence is not in the diff — the ENGINE-REFERENCE row cites docs/bench/glm-thinking-budget-2026-08-14.raw.jsonl and the safety-ranker comment cites docs/handoff/GLM53-TOKE…
omitted: low=5
report: docs/handoff/dispatch-9573bd97/review-glm.md
```

All three Mediums visible, including the stale `stop_reason` mirror finding (item 1) —
the observability seam that could lie in exactly the failure case it was built to
diagnose. Today's gate for this lane shows only `status: pass`.

### dispatch-95eb1cb9 (mission case 2 — "pass" on a do-not-merge report)

```
status: pass
reviewer: glm
diff: 8805d6d7
reviewer_says: do_not_merge
findings_source: markdown_sections
findings:
- [Medium] scripts/vps-release-deploy.sh — wire_shared_links затирает git-трекнутые файлы симлинками на пустые shared-листья (scripts/vps-release-deploy.sh в диффе,…
omitted: low=5
report: docs/handoff/dispatch-95eb1cb9/review-glm.md
```

`reviewer_says: do_not_merge` is now machine-visible (the reviewer's «Код не мержить
как есть» in the Вердикт section), the symlink-over-tracked-files Medium is on the
face of the gate, and `status: pass` is byte-identical to today — the advisory changes
what the gate SHOWS, not what it DECIDES.

### dispatch-82e1056d (mission case 3 — fail with two invisible Highs)

```
status: fail
critical: 0
high: 2
medium: 1
low: 6
findings_source: markdown_sections
findings:
- [High] scripts/gate-cost-report.sh — the only anchor proven present in the prod journal is computed and then silently discarded — the report can never produce output on live data.
- [High] scripts/gate-cost-report.sh — ^-anchored anchor regexes can never match the actual journal MESSAGE format.
- [Medium] new PE_ flag has no ENGINE-REFERENCE.md row (repo hard rule: "New PE_ flag ⇒ new row, same commit").
omitted: low=6
report: docs/handoff/dispatch-82e1056d/review-glm.md
```

Both Highs are named, both anchor to `scripts/gate-cost-report.sh`, and the
ENGINE-REFERENCE drift Medium renders too (its item carries no backticked path token,
so the anchor field is omitted per design §2.1 — the finding itself is kept).

### Parse-failure degrade (acceptance 3)

A report whose `REVIEW_FINDINGS:` claims `high=1 medium=1` but whose body has no
shape the extractor knows (e.g. a table-only arm) now yields:

```
findings_source: none
findings: unavailable
findings_reason: parse_failed
report: docs/handoff/dispatch-XXXX/review-glm.md
```

— an explicit unavailability with a pointer to the report, never a silent pass. The
block is written on every pass/fail exit of both writers, so a gate WITHOUT a findings
block can only be an old build; a gate WITH `findings: unavailable` is visibly broken,
not visibly clean. Missing report file degrades identically with
`findings_reason: report_missing`.

## Test results (honest)

New suite `tests/test-review-gate-shows-findings.sh`: **42 passed, 0 failed** —
renderer CLI (A1–A8) plus the REAL `leadv2-dispatch-product-close.sh` (B1–B3: fail
exit 7 with the High rendered and the `do_not_merge=1` ledger token; do-not-merge
PASS_WITH_NITS still exit 0 / `status: pass` with the advisory + Medium; clean pass →
`findings: none`) and the REAL `leadv2-review-run.sh` (C1: `arms:` still line 1,
High + Medium rendered, additive decision token).

Neighbouring suites that assert gate shape (design R2), post-change:

| Suite | Result |
|---|---|
| test-leadv2-review-routing | PASS=3 FAIL=0 |
| test-review-engine-fanout-multiprovider | PASS=1 FAIL=0 |
| test-review-engine-pool-degrades | PASS=2 FAIL=0 |
| test-review-arm-no-verdict | 15 passed, 0 failed |
| test-review-body-persist | 13 passed, 0 failed |
| test-review-silence-gate | 15 passed, 0 failed |
| test-dispatch-silent-arm | 12 passed, 0 failed |
| test-no-work-terminal | 43 passed, 0 failed |
| test-workflow-bypass-guard-lane | PASS=4 FAIL=0 |
| test-dispatch-product-close-exit-trap | 8 passed, 0 failed |
| test-landing-diff-scoping | 10 passed, **1 failed (Q3-pair)** |
| test-review-pool-never-empty | **fails (3 FAIL lines, quota/epoch-dependent)** |
| test-lane-writes-scoping | **times out (>4 min)** |

The three non-green rows were re-run against a pristine `git archive HEAD` copy of the
pre-change tree and fail/hang IDENTICALLY there — pre-existing, environment-dependent
(quota-lockout epoch arithmetic, a lane-diff scoping case, a long-hanging scoping
suite), not caused by this change.

## Deviations from the design text (minor, reported)

- Design §2.1 predicted anchor `grounding-gate.sh:973` for 9573bd97; the implemented
  rule (first backticked path token) yields `client.sh` for that item — the design's
  own rule text and its example disagree; the rule was implemented as written. All
  three acceptance-criteria anchors (`scripts/gate-cost-report.sh` ×2,
  `scripts/vps-release-deploy.sh`) are exact.
- `review-run.sh`'s emit lines and `product-close`'s fail emit carry the
  `do_not_merge=1` token; `product-close`'s pass path has no `emit decision` line, so
  its token rides the `_dl_note landed` ledger note instead (asserted in test B2).
- Renderer internal TSV uses the ASCII unit separator `\037` (not TAB): TAB is IFS
  whitespace, so `read` collapses the empty verdict field and shifts desc into the
  verdict slot. Caught by the new suite, fixed, regression-tested.

## Non-goals honored

No verdict/exit-code/ledger-decision change · no reviewer-prompt or `review_contract`
change · `blocked`/`unreviewed`/`review_body_lost`/`no_verdict_marker` writers
untouched · `review-findings.json` schema and the verify/dedup synthesis untouched ·
nothing written under any consuming project (persona-engine read only) · no new
dependency · no `docs/leadv2/**` or `docs/handoff/**` writes from the lane.

DELIVERABLE_COMPLETE
