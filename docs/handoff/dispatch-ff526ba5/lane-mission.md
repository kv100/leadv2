Product implementation task dispatch-ff526ba5. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# Architect prepass — WHEN-TO-FORK-01 fix round 1

Target file (single): `plugins/leadv2/docs/work-placement.md` (worktree `e7d05157`).
This is a documentation-rule change. No script, hook, or schema is touched.

---

## 1. Diagnosis — why the two highs are one defect

Both findings come from the same modelling error: the doc treats three *different kinds of
question* as three comparable branches on one ordered list.

| Test | What it actually asks | Kind |
|---|---|---|
| Test 1 (diff test) | does the work leave something durable behind? | **output shape** — a property of the deliverable |
| Test 2 ("only this session knows") | can a no-history agent even do this work? | **feasibility precondition** — a property of the *inputs* |
| Test 3 (otherwise) | fallback | residual |

A feasibility precondition and an output-shape question are not peers, so ordering them
against each other is arbitrary — and the arbitrary choice made was the unsafe one. H1 is
what that costs: durable work that depends on an unrecorded founder decision matches Test 1
first and goes to a lane whose worker never saw the decision.

H2 is the same error at the edge cases: "verification" was classified by output shape
("nothing is produced") when Phase 7 verification does produce — a verdict that gates
deploy and rollback.

## 2. H1 fix — chosen approach and why

**Chosen: both remedies the review offered, because either alone is insufficient.**

Reordering alone (context test first) is *wrong on the overlap*. Work that needs unrecorded
session context **and** produces a diff exists and is common (e.g. "write up the decision we
just made, as a doc another lane will cite"). A pure reorder sends it to a fork — and a fork
has no worktree, no review gate, no close record. That trades H1's failure (worker starts
blind) for its mirror (durable output ships unreviewed). The correct fix must not force a
choice between inheriting context and being reviewed.

So the rule is restructured into **one precondition + two mutually exclusive branches**:

### Step 0 — precondition (asked first, always, and it is not a branch)

> *Does doing this work require something that exists only in this conversation — a decision
> made earlier in this session, text this session authored, a founder statement not written
> to disk?*
>
> If **yes**, you must do one of two things before dispatching anywhere:
> 1. **Materialize it** — write the decision/statement verbatim into the mission text or
>    `context.yaml` `decisions[]`. It is now on disk, the precondition is discharged, and the
>    work proceeds to the branch test below like any other work.
> 2. **Fork** — when the dependency is the session's *whole* reasoning trail and not a
>    quotable fact or two, so materializing it means transcribing the session.
>
> Materializing is the default; forking is the escape hatch for when materializing is not
> tractable. Never dispatch context-dependent work without discharging this step — that is
> the exact failure the rule exists to prevent.

This makes ordering *inert* rather than merely correct: Step 0 is not competing with the
branch test, it gates entry to it. Even a reader who skims out of order cannot route around
it, because Step 0's two outcomes are "fork" or "you are now not context-dependent".

### The branch test (after Step 0, exactly one matches)

> *Does this work leave a durable artifact behind — a committed diff, or a file another
> session will cite after this one ends?*
>
> - **Yes → dispatch lane.** A lane buys an isolated worktree, a review gate, and a close
>   that records what landed. Durable output needs all three.
> - **No → fresh agent.** One spawn, one summary back to chat, no file.

Two outcomes on a single yes/no over an observable property: mutually exclusive and
exhaustive by construction, so "first match wins" no longer carries any weight. The ordering
language ("three tests, ordered, first match wins") is removed from the header — it is what
encoded the bug.

Fork ceases to be a peer branch and becomes what it actually is: an outcome of Step 0.

### Cost asymmetry — retained, re-anchored

The §"Cost asymmetry" paragraph stays (it is the reason the default stopped being "lane")
but is re-anchored to the branch test, not to the three-way ordering. Add one sentence: a
fork is not a cheaper lane — it is the *only* way to carry un-materializable context, and it
buys no review gate, which is why Step 0 prefers materializing.

## 3. H2 fix — reclassification

Edge case (b) currently says verification is "always a fresh agent, never a lane" on the
grounds that "nothing is produced". That is true of one kind of verification and false of
the other. Split it:

### (b1) Read-only fact check → fresh agent

*"Is this ledger row still true?"* The answer is one of a small closed set (true/false, a
number, a path), it is checkable against disk or prod without editing anything, nothing is
written, and no gated lifecycle step branches on it. Nothing to isolate, nothing to review.

### (b2) Phase 7 live verification → stays in the task-owning lane

**Its output, stated explicitly** (this is what the review asked for):

| Output | Where it lands | Why it is not "output-free" |
|---|---|---|
| The pass/fail verdict itself | verify/close state written by the lane's close path | A later session reads it as the record of whether the change actually worked |
| Probe evidence (the live signal, re-probed on every 0/null) | task journal / handoff artifacts | It is the evidence backing the completion claim |
| The deploy/rollback decision | acted on, not just reported | Phase 7 failing routes to Recovery — the verifier owns that handoff |

Phase 7 verification is a **gated lifecycle step of the owning lane**, not a question the
lane asks someone else. It is not dispatched anywhere; it runs where the task's ownership,
worktree, and rollback authority already live. Routing it to a fresh agent would hand a
deploy/rollback gate to an agent with no worktree, no ownership, and nothing to roll back
with — the weakest accountability surface in the system.

### The discriminator (mechanical, one look)

> *Does anything downstream branch on this answer, or does the answer get written somewhere
> a later session reads?*
> Either yes → it is not a fact check. It belongs to the lane that owns the thing being
> verified. Both no → fresh agent.

## 4. Re-checking the doc's own examples against the corrected rule

The mission asks whether any example now lands in a different branch than the section it was
written under. Three do:

**(i) Edge case (a), report-only work — now redundant, fold it in.**
Its test is *"will anything read this file after this session ends?"* — which is verbatim the
second clause of the branch test. Under the corrected rule it is not an edge case at all;
it is the branch test applied to a file-shaped deliverable. Keep the `REPORT-ONLY-GATE-01`
cross-reference (it is real and load-bearing: the close gate is what makes the report
citable) but demote (a) from "edge case" to a two-line clarification under the branch test.
An "edge case" that restates the main rule is the example doing the rule's arguing.

**(ii) Edge case (b) — was one example, is two.** Covered in §3.

**(iii) The `PreToolUse` advisory spec in "If this needs teeth" — its heuristic is wrong.**
Line 87 greps for an `acceptance:` surface of `rendered_line|prod_db_row|http_response` as
the signal of durable intent, omitting `file_artifact`. Under the corrected branch test a
`file_artifact` acceptance surface is *precisely* a durable deliverable and belongs in a
lane — so the advisory as specced would fire "this produces no diff, use a fresh agent" at
exactly the report-only lanes that `REPORT-ONLY-GATE-01` was built to legitimize. Add
`file_artifact` to the list. Same correction applies to the sentence below it: a
`LANE_WRITES` that is *docs-only* is **not** by itself a fresh-agent candidate — empty is;
docs-only is a durable deliverable. Both lines currently argue for a conclusion the corrected
rule rejects.

## 5. Change plan — exact edits

Single file, `plugins/leadv2/docs/work-placement.md`:

1. **`:3-4` header** — replace "Three branches, three tests, ordered — first match wins" with
   a precondition-then-branch framing.
2. **`:15-39`** — replace the `## The three tests, ordered` block with `## Step 0 —
   precondition` (§2) followed by `## The branch test` (§2). Test 3's warning about session
   context being *noise* for on-disk questions is preserved inside the fresh-agent branch.
3. **`:41-45` "Not tests"** — unchanged, retarget wording from "the three tests" to "Step 0
   and the branch test".
4. **`:47-52` cost asymmetry** — retained, plus the one sentence on fork-buys-no-review-gate.
5. **`:56-67` edge case (a)** — demoted to a clarification under the branch test; the
   `REPORT-ONLY-GATE-01` reference and its script line-anchor survive verbatim.
6. **`:69-76` edge case (b)** — split into (b1) fact check → fresh agent and (b2) Phase 7 →
   owning lane, with the output table and the discriminator.
7. **`:84-93` "If this needs teeth"** — add `file_artifact` to the acceptance-surface list;
   correct "empty or docs-only" to "empty".
8. **`:95-98` non-goals** — unchanged; still true.

Header date line updated to note the fix round.

## 6. Risks

| Risk | Mitigation |
|---|---|
| Step 0's "materialize it" becomes a ritual nobody performs, silently reintroducing H1 | Materialization has an existing home — `context.yaml` `decisions[]`, already read by every subagent per the subagent protocol. Step 0 names that destination explicitly rather than inventing one. |
| Removing "fork" as a peer branch reads as "forking is discouraged" | Step 0 states forking is the correct outcome when the dependency is the session's whole reasoning trail, not a quotable fact. |
| (b2) is read as "Phase 7 needs a new lane" | Wording is "stays in the task-owning lane" — it is not dispatched at all. No new placement is created. |
| Doc drifts from `leadv2-verify` skill behaviour | (b2) describes Phase 7 as it already runs; this is a doc correcting itself toward the runtime, not a runtime change. Verified against the Phase 7 description in the leadv2 skill surface (anti-lying-green gate, re-probe every 0/null, failure → Recovery). |

## 7. Non-goals (explicit — for the implementing agent)

- No hook, script, gate, or test is added or edited. The `PreToolUse` advisory stays a
  written spec; item 7 above corrects the spec's text only.
- No change to `leadv2-dispatch-product-close.sh`, `leadv2-routing-guard.sh`, or any Phase 7
  runtime behaviour.
- No change to `docs/model-effort-matrix.md` or `docs/routing-enforcement.md`.
- `docs/leadv2/open-threads.md` is not touched (hard constraint).
- No `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- No new doc file. The correction lands in the existing one.

## 8. Constraint checklist

1. **Env var naming** — n/a, no env var introduced or referenced.
2. **File paths** — `plugins/leadv2/docs/work-placement.md` exists in worktree `e7d05157`
   (read, 99 lines). Referenced-only paths (`docs/model-effort-matrix.md`,
   `docs/routing-enforcement.md`, `leadv2-dispatch-product-close.sh`) are cited in prose
   already present in the file and are not edited; no new path is introduced.
3. **`claude -p` commands** — n/a, none.
4. **Concurrent access** — single file, single lane, resumed worktree. No parallel writer.
   The shared-tree hazard is the *repo*, addressed by the no-reset/no-clean constraint.
5. **Config contradiction** — the one contradiction found is documented as item (iii) in §4:
   the advisory spec's acceptance-surface list contradicts `REPORT-ONLY-GATE-01`. Fix is in
   the change plan (item 7).

---

acceptance:
  surface: file_artifact
  observable: |
    A reader opening plugins/leadv2/docs/work-placement.md sees, before any branch is
    offered, a "Step 0" precondition asking whether the work needs something that exists
    only in this conversation, with materialize-or-fork as its two outcomes; the phrase
    "three tests, ordered — first match wins" is gone from the header; and the verification
    section names Phase 7 verification as staying in the task-owning lane, listing the
    verdict, probe evidence, and deploy/rollback decision as its outputs, separate from a
    read-only fact check which goes to a fresh agent.
  authored_at: 2026-08-17T00:00:00Z

LANE_WRITES: plugins/leadv2/docs/work-placement.md

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# MISSION — WHEN-TO-FORK-01, fix round 1

Resume the same worktree (`e7d05157`). Review: `docs/handoff/dispatch-e7d05157/review-codex.md`,
status **fail**, 0 critical, 2 high. Both are in `plugins/leadv2/docs/work-placement.md`, and both
say the rule as written would send work to the wrong place.

## H1 — first-match ordering discards required session context (`:16-20`)

The rule is evaluated top-down and the first match wins, so work that genuinely needs the session's
history can be captured by an earlier branch and sent to a fresh agent, which starts blind. That is
the exact failure the rule exists to prevent, encoded into its own ordering.

Fix the ordering so the "needs this session's history" test is asked **before** the cheaper branches,
or make the branches mutually exclusive so order cannot decide it. State which you chose and why.

## H2 — Phase 7 verification is misclassified as output-free (`:70-76`)

Live verification produces a verdict that gates deploy and rollback — treating it as output-free
routes it to the branch with the weakest accountability. Reclassify it and say what its output is.

## While you are there

Re-read your own worked examples against the corrected rule. If an example now lands in a different
branch than the one you wrote it under, the example was doing the arguing instead of the rule — fix
the rule, then the example.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.

## Deliverable
The corrected rule, the reclassification, and the examples re-checked against it.
End with DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-ff526ba5" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.