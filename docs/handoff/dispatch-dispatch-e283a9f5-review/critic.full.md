# critic.full.md — dispatch-e283a9f5 (WHEN-TO-FORK-01 round 2 docs)

REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=3 low=2

Scope: `docs/handoff/dispatch-e283a9f5/diff.patch` — 2 files, both markdown
(`plugins/leadv2/docs/phases.md` §Spawn-hygiene, `plugins/leadv2/docs/work-placement.md`
round-2 rewrite). No Python/TypeScript/SQL changed.

Type checks: **N/A** — the diff contains no `.py`/`.ts` files; `mypy --strict` /
`tsc --noEmit` have nothing to check. Evidence below is grep/Read against the live
post-diff files and the scripts the docs cite.

---

## Medium

**M1. work-placement.md:26 — stale "branch test" reference inside the rewritten Step 0.**
Step 0, item 1: "the work proceeds to **the branch test** below like any other work."
The diff renamed the decision procedure from "branch test" to "must-not-fork
gate/check" everywhere else (title line 4, §Ordering, §Not-tests, the teeth bullet at
:155) but missed this occurrence — and it sits in the precondition text that is quoted
most often. A reader following the doc linearly now hits a section name that no longer
exists.
Fix: "…the work proceeds to the must-not-fork check below like any other work."

**M2. work-placement.md:98 and :126 — §Verification (b1) contradicts the round-2 fork default.**
(b1) header: "Read-only fact check → **fresh agent**"; discriminator (:126): "Both no →
**fresh agent**." Round 2's stated default (:47-54) is that work leaning on session
context goes to a **fork**, and the phases.md index line added in this very diff
(phases.md:477) says "Read-only fact checks land on a fork/plain agent." The canonical
doc and its index now give divergent routing for the same class of work — the worked
example (:137) even lists "fork (or plain agent when checkable from disk alone)" for
the ledger-row case. §Verification was not updated to the new vocabulary.
Fix: change (b1) header to "→ fork or plain agent" and the discriminator tail to
"Both no → fork (or plain agent when checkable from repo/prod/logs alone with no
session dependency)."

**M3. work-placement.md:152 — teeth-hook spec message still carries round-1 wording.**
The proposed advisory's stderr text: "…the **branch test** says **fresh agent**; see
docs/work-placement.md". The adjacent bullet (:154-158) was rewritten to must-not-fork /
fork-candidate language, but the message a future implementer would copy verbatim was
not. If built as written, the hook would emit guidance this doc no longer contains.
Fix: "…names no durable deliverable — the must-not-fork check says fork/plain agent;
see docs/work-placement.md".

## Low

**L1. work-placement.md:47-67 — section order inverts the stated evaluation order.**
§The default appears before §Must-not-fork, whose own header says "checked **before**
the default" (:56), and §Ordering (:69) confirms default is step 3. A tired reader
applying reading order meets the fork-favouring default before the gate that bounds
it — precisely the failure mode the doc's own preamble (:10-12) targets.
Fix: move §Must-not-fork above §The default, or drop the duplicated ordering rationale
(now stated three times: :43, :56, :69-77).

**L2. work-placement.md:83 — dangling script citation.**
"`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1987` (prose rubric:
REPORT-ONLY-GATE-01)". Line 1987 of the live script is review-verdict parsing
(`if [[ -n "${_pc_no_verdict_reason}" ]]`), and `grep -rn REPORT-ONLY-GATE-01` across
`plugins/leadv2/` hits only this doc — the rubric string does not exist in the script.
Carried verbatim from round 1, but re-stated in this diff's moved text.
Fix: cite the actual location of the report-only handling, or drop the line-number pin
and reference the gate by task ID only.

## Checks performed (no Critical/High found)

- Cross-references verified against live files: `docs/model-effort-matrix.md` naming
  consistent; phases.md §Spawn-hygiene accurately indexes work-placement.md (no second
  copy drift — items 1-3 match Step 0 / must-not-fork / default, Phase 7 carve-out
  matches §Verification (b2)).
- Report-only routing is internally consistent under the new model: no-diff work routes
  via must-not-fork #3 ("outlives the session"), and the report-only paragraph (:79-86)
  says exactly that.
- `LANE_WRITES` claims in the teeth section match reality: the dispatch door does
  require it (`leadv2-dispatch-code.sh:425-433`, harvest at :1659-1674).
- New-logic test coverage: N/A — the diff adds no executable logic; the teeth section
  explicitly ships "a rule, not machinery."
- The three stale-text findings are advisory-doc defects (misrouting risk at most, and
  the lead reads the whole doc), hence Medium, not High.

## Raw evidence

```
$ grep -rn "branch test" plugins/leadv2/docs/
work-placement.md:26:   the work proceeds to the branch test below like any other work.
work-placement.md:152:  branch test says fresh agent; see docs/work-placement.md".

$ grep -rn "REPORT-ONLY-GATE-01" -r plugins/leadv2/
plugins/leadv2/docs/work-placement.md:82  (only hit — no script occurrence)

$ sed -n '1985,1989p' plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
  fi

  if [[ -n "${_pc_no_verdict_reason}" ]]; then
    _pc_tried_csv="$(IFS=,; echo "${PC_TRIED[*]:-}")"
    _pc_remaining="$(_pc_remaining_ok_after "${reviewer}")"
```

mypy/tsc: not run — no source files in the diff (docs-only).

DELIVERABLE_COMPLETE
