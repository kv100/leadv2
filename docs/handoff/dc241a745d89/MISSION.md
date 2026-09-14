# CODEX-REVIEWS-LOSE-THEIR-FINDINGS-TEXT-01

A review gate can report correct counts and throw the findings text away. Live case, 2026-09-14:
lane `dispatch-199f5d8e` died on `high=2` with `findings: unavailable`, `findings_reason:
parse_failed`, `findings_source: none` — while the reviewer's report
(`docs/handoff/dispatch-199f5d8e/review-codex.md`) carried both findings in full at lines 12 and 15:

```
- [high] Migration requires unavailable cluster-role privilege (engine/db/migrations/0001_...:7-19)
- [high] Changed-scope CI silently omits the migration acceptance test (tests/v5/...:1)
```

The counts parsed (a sed over `REVIEW_FINDINGS: critical=… high=…`,
`leadv2-dispatch-product-close.sh:914`); only the per-finding list extraction failed. The reader is
told "the reviewer said nothing useful" where the reviewer answered completely. That is a silent
failure, and it is worse than a red.

## CORRECTION — read this before you start; the row title is misleading

The row is named for codex because that is where we hit it. **It is not a codex problem.** Measured
across every `review-gate.md` on this machine from the last three days:

```
codex   findings_source=markdown_sections   x2
codex   findings_source=finding_lines       x2   (one of them high=2)
glm     findings_source=finding_lines       x1
```

**Codex reviews are not uniformly broken — two of them extracted fine.** So the discriminator is the
REPORT LAYOUT, not the arm. There are (at least) two extractors, `markdown_sections` (walks `###
High` / `### Medium` headings) and `finding_lines` (a flat `- [high] Title (path:lines)` list), and a
report that matches neither loses its text. Any arm can emit either layout, so claude and glm
reviewers fall into the same hole — just less often, because we route fewer reviews to them.

**Do not write a codex-specific branch.** A fix keyed on the reviewer's name would leave the actual
hole open and would pass a codex-only test.

## Second finding, free — decide whether it is a bug and say which

`DEFAULT_REVIEW_EXCLUSIONS = ["glm", "glm-flash", "freepool"]`
(`scripts/lib/leadv2-glm-policy-resolve.py:77`) says glm never reviews. The measurement above shows
a glm review-gate that exists. Exactly one of these is true: the exclusion list is not enforced on
some path, or that gate was produced by a path the list deliberately does not cover. Name which,
with the line. Do not change the list in this lane — just establish the fact.

## What to build

1. **One extraction contract, layout-driven, not arm-driven.** Whatever the reviewer emits, either
   the findings render on the gate or the gate says — in a distinguishable way — which layout it
   failed to match. `parse_failed` today cannot be told apart from "the reviewer produced nothing".
2. **A silence must be distinguishable from a verdict.** `findings: unavailable` must not be the
   same string for "reviewer returned an empty report", "reviewer returned a layout we cannot read",
   and "the report file was missing". Three causes, three names.

## Acceptance

1. A suite with **at least three** report fixtures: a `### High` sections report, a flat
   `- [high] …` list report, and a deliberately malformed one. The first two both yield
   `findings_source != none` AND render the finding titles into `review-gate.md`.
2. **Negative control, run it:** the malformed fixture still fails to extract, and its gate names a
   reason distinct from the other two. A parser that swallows everything is worse than the bug.
3. The glm-exclusion contradiction named with its line and a verdict (enforced / not enforced /
   different path).
4. New suite registered so `tests/run-all.sh --scope changed` SELECTS it.

## Method — binding

- Report the gate text verbatim for every claim; name the surface of every count.
- Any journal/quota number must be scoped to ONE repo directory — `~/.claude/leadv2-state/*/` spans
  repos running under different account slots, and mixing them produced a wrong number for the lead
  earlier today.

## Off limits

- `capability` numbers, `router_v2.cost`, the class→arm think tiering.
- The reviewer-SELECTION policy — a sibling row (`03a5bd7cccea`) owns who gets picked; you own what
  happens to the report after they answer.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
